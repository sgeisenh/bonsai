open! Core
open! Bonsai_web
open! Bonsai_web_test
open! Incr_map_collate
open! Bonsai.Let_syntax
open Shared
module Table = Bonsai_web_ui_partial_render_table

let table_to_string
      ~include_stats
      ~include_focus
      (res : _ Table.Focus_by_row.t)
      (for_testing : Table.For_testing.t)
  =
  let open Ascii_table_kernel in
  let module Node_h = Virtual_dom_test_helpers.Node_helpers in
  let stats =
    Ascii_table_kernel.draw
      ~limit_width_to:200
      ~prefer_split_on_spaces:false
      [ Column.create "metric" (fun (k, _) -> k)
      ; Column.create "value" (fun (_, v) -> v)
      ]
      [ "rows-before", sprintf "%d" for_testing.body.rows_before
      ; "rows-after", sprintf "%d" for_testing.body.rows_after
      ; "num-filtered", sprintf "%d" for_testing.body.num_filtered
      ; "num-unfiltered", sprintf "%d" for_testing.body.num_unfiltered
      ]
    |> Option.value_exn
    |> Ascii_table_kernel.Screen.to_string
         ~bars:`Unicode
         ~string_with_attr:(fun _attr str -> str)
  in
  let contents =
    let selected =
      Column.create ">" (fun { Table.For_testing.Table_body.selected; _ } ->
        if selected then "*" else "")
    in
    let num_column =
      Column.create "#" (fun { Table.For_testing.Table_body.id; _ } ->
        Map_list.Key.to_string id)
    in
    let ascii_column_of_leaf i header =
      let header = Node_h.unsafe_convert_exn header |> Node_h.inner_text in
      Column.create header (fun { Table.For_testing.Table_body.view; _ } ->
        List.nth_exn view i |> Node_h.unsafe_convert_exn |> Node_h.inner_text)
    in
    let columns =
      selected
      :: num_column
      :: (for_testing.body.column_names |> List.mapi ~f:ascii_column_of_leaf)
    in
    Ascii_table_kernel.draw
      columns
      for_testing.body.cells
      ~limit_width_to:200
      ~prefer_split_on_spaces:false
    |> Option.value_exn
    |> Ascii_table_kernel.Screen.to_string
         ~bars:`Unicode
         ~string_with_attr:(fun _attr str -> str)
  in
  let focus =
    [%message "" ~focused:(res.focused : int option)]
    |> Sexp.to_string_hum
    |> fun s -> s ^ "\n"
  in
  let result = if include_stats then stats ^ contents else contents in
  if include_focus then focus ^ result else result
;;

module Test = struct
  include Shared.Test

  let create_with_var
        (type a)
        ?(stabilize_height = true)
        ?(visible_range = 0, 100)
        ?(map = Bonsai.Var.create small_map)
        ?(should_set_bounds = true)
        ~stats
        component
    =
    let min_vis, max_vis = visible_range in
    let filter_var = Bonsai.Var.create (fun ~key:_ ~data:_ -> true) in
    let { Component.component; get_vdom; get_focus; get_testing; get_inject } =
      component (Bonsai.Var.value map) (Bonsai.Var.value filter_var)
    in
    let handle =
      Handle.create
        (module struct
          type t = a

          let out a = Lazy.force (get_testing a)

          let view a =
            table_to_string (get_focus a) (out a) ~include_stats:stats ~include_focus:true
          ;;

          type incoming = Action.t

          let incoming = get_inject
        end)
        component
    in
    let t = { handle; get_vdom; get_focus; input_var = map; filter_var } in
    if should_set_bounds then set_bounds t ~low:min_vis ~high:max_vis;
    (* Because the component uses edge-triggering to propagate rank-range, we need to
       run the view-computers twice. *)
    if stabilize_height
    then (
      Handle.store_view handle;
      Handle.store_view handle);
    t
  ;;

  let create
        ?stabilize_height
        ?visible_range
        ?(map = small_map)
        ?should_set_bounds
        ~stats
        component
    =
    create_with_var
      ?stabilize_height
      ?visible_range
      ~map:(Bonsai.Var.create map)
      ?should_set_bounds
      ~stats
      component
  ;;
end

let%expect_test "basic table" =
  let test = Test.create ~stats:true (Test.Component.default ()) in
  Handle.show test.handle;
  [%expect
    {|
(focused ())
┌────────────────┬───────┐
│ metric         │ value │
├────────────────┼───────┤
│ rows-before    │ 0     │
│ rows-after     │ 0     │
│ num-filtered   │ 3     │
│ num-unfiltered │ 3     │
└────────────────┴───────┘
┌───┬─────┬───────┬───────┬──────────┐
│ > │ #   │ ◇ key │ a     │ ◇ b      │
├───┼─────┼───────┼───────┼──────────┤
│   │ 0   │ 0     │ hello │ 1.000000 │
│   │ 100 │ 1     │ there │ 2.000000 │
│   │ 200 │ 4     │ world │ 2.000000 │
└───┴─────┴───────┴───────┴──────────┘ |}]
;;

let%expect_test "basic table with default sort" =
  let test =
    Test.create
      ~stats:true
      (Test.Component.default
         ~default_sort:
           (Value.return (fun (_key, { a = a1; _ }) (_key, { a = a2; _ }) ->
              -String.compare a1 a2))
         ())
  in
  Handle.show test.handle;
  [%expect
    {|
    (focused ())
    ┌────────────────┬───────┐
    │ metric         │ value │
    ├────────────────┼───────┤
    │ rows-before    │ 0     │
    │ rows-after     │ 0     │
    │ num-filtered   │ 3     │
    │ num-unfiltered │ 3     │
    └────────────────┴───────┘
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 4     │ world │ 2.000000 │
    │   │ 100 │ 1     │ there │ 2.000000 │
    │   │ 200 │ 0     │ hello │ 1.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}]
;;

let%expect_test "big table" =
  let test =
    Test.create
      ~stats:true
      ~map:big_map
      ~visible_range:(0, 10)
      (Test.Component.default ())
  in
  Handle.show test.handle;
  [%expect
    {|
(focused ())
┌────────────────┬───────┐
│ metric         │ value │
├────────────────┼───────┤
│ rows-before    │ 0     │
│ rows-after     │ 87    │
│ num-filtered   │ 99    │
│ num-unfiltered │ 99    │
└────────────────┴───────┘
┌───┬──────┬───────┬────┬──────────┐
│ > │ #    │ ◇ key │ a  │ ◇ b      │
├───┼──────┼───────┼────┼──────────┤
│   │ 0    │ 1     │ hi │ 0.000000 │
│   │ 100  │ 2     │ hi │ 1.000000 │
│   │ 200  │ 3     │ hi │ 1.000000 │
│   │ 300  │ 4     │ hi │ 2.000000 │
│   │ 400  │ 5     │ hi │ 2.000000 │
│   │ 500  │ 6     │ hi │ 3.000000 │
│   │ 600  │ 7     │ hi │ 3.000000 │
│   │ 700  │ 8     │ hi │ 4.000000 │
│   │ 800  │ 9     │ hi │ 4.000000 │
│   │ 900  │ 10    │ hi │ 5.000000 │
│   │ 1000 │ 11    │ hi │ 5.000000 │
│   │ 1100 │ 12    │ hi │ 6.000000 │
└───┴──────┴───────┴────┴──────────┘ |}]
;;

let%expect_test "table with some preload" =
  let test =
    Test.create
      ~map:big_map
      ~visible_range:(5, 10)
      ~stats:true
      (Test.Component.default ~preload_rows:2 ())
  in
  Handle.show test.handle;
  [%expect
    {|
(focused ())
┌────────────────┬───────┐
│ metric         │ value │
├────────────────┼───────┤
│ rows-before    │ 2     │
│ rows-after     │ 85    │
│ num-filtered   │ 99    │
│ num-unfiltered │ 99    │
└────────────────┴───────┘
┌───┬──────┬───────┬────┬──────────┐
│ > │ #    │ ◇ key │ a  │ ◇ b      │
├───┼──────┼───────┼────┼──────────┤
│   │ 0    │ 3     │ hi │ 1.000000 │
│   │ 100  │ 4     │ hi │ 2.000000 │
│   │ 200  │ 5     │ hi │ 2.000000 │
│   │ 300  │ 6     │ hi │ 3.000000 │
│   │ 400  │ 7     │ hi │ 3.000000 │
│   │ 500  │ 8     │ hi │ 4.000000 │
│   │ 600  │ 9     │ hi │ 4.000000 │
│   │ 700  │ 10    │ hi │ 5.000000 │
│   │ 800  │ 11    │ hi │ 5.000000 │
│   │ 900  │ 12    │ hi │ 6.000000 │
│   │ 1000 │ 13    │ hi │ 6.000000 │
│   │ 1100 │ 14    │ hi │ 7.000000 │
└───┴──────┴───────┴────┴──────────┘ |}]
;;

let%expect_test "big table filtered" =
  let test =
    Test.create
      ~stats:true
      ~map:big_map
      ~visible_range:(0, 10)
      (Test.Component.default ())
  in
  Bonsai.Var.set test.filter_var (fun ~key ~data:_ -> key mod 2 = 0);
  Handle.show test.handle;
  [%expect
    {|
    (focused ())
    ┌────────────────┬───────┐
    │ metric         │ value │
    ├────────────────┼───────┤
    │ rows-before    │ 0     │
    │ rows-after     │ 37    │
    │ num-filtered   │ 49    │
    │ num-unfiltered │ 99    │
    └────────────────┴───────┘
    ┌───┬──────┬───────┬────┬───────────┐
    │ > │ #    │ ◇ key │ a  │ ◇ b       │
    ├───┼──────┼───────┼────┼───────────┤
    │   │ 0    │ 2     │ hi │ 1.000000  │
    │   │ 100  │ 4     │ hi │ 2.000000  │
    │   │ 200  │ 6     │ hi │ 3.000000  │
    │   │ 300  │ 8     │ hi │ 4.000000  │
    │   │ 400  │ 10    │ hi │ 5.000000  │
    │   │ 500  │ 12    │ hi │ 6.000000  │
    │   │ 600  │ 14    │ hi │ 7.000000  │
    │   │ 700  │ 16    │ hi │ 8.000000  │
    │   │ 800  │ 18    │ hi │ 9.000000  │
    │   │ 900  │ 20    │ hi │ 10.000000 │
    │   │ 1000 │ 22    │ hi │ 11.000000 │
    │   │ 1100 │ 24    │ hi │ 12.000000 │
    └───┴──────┴───────┴────┴───────────┘ |}]
;;

let%expect_test "focus down" =
  let test = Test.create ~stats:false (Test.Component.default ()) in
  Handle.show test.handle;
  [%expect
    {|
    (focused ())
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │   │ 100 │ 1     │ there │ 2.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}];
  Handle.do_actions test.handle [ Focus_down ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (0))
    (focused (0))
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │ * │ 0   │ 0     │ hello │ 1.000000 │
    │   │ 100 │ 1     │ there │ 2.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}];
  Handle.do_actions test.handle [ Focus_down ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (1))
    (focused (1))
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │ * │ 100 │ 1     │ there │ 2.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}]
;;

let%expect_test "focus up" =
  let test = Test.create ~stats:false (Test.Component.default ()) in
  Handle.show test.handle;
  [%expect
    {|
    (focused ())
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │   │ 100 │ 1     │ there │ 2.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}];
  Handle.do_actions test.handle [ Focus_up ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (4))
    (focused (4))
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │   │ 100 │ 1     │ there │ 2.000000 │
    │ * │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}];
  Handle.do_actions test.handle [ Focus_up ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (1))
    (focused (1))
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │ * │ 100 │ 1     │ there │ 2.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}]
;;

let%expect_test "unfocus" =
  let test = Test.create ~stats:false (Test.Component.default ()) in
  Handle.do_actions test.handle [ Focus_up ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (4))
    (focused (4))
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │   │ 100 │ 1     │ there │ 2.000000 │
    │ * │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}];
  Handle.do_actions test.handle [ Unfocus ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to ())
    (focused ())
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │   │ 100 │ 1     │ there │ 2.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}]
;;

let%expect_test "remove focused moves down if possible" =
  let test = Test.create ~stats:false (Test.Component.default ()) in
  Handle.do_actions test.handle [ Focus_down; Focus_down ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (0))
    (focus_changed_to (1))
    (focused (1))
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │ * │ 100 │ 1     │ there │ 2.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}];
  Bonsai.Var.update test.input_var ~f:(fun map -> Map.remove map 1);
  Handle.show test.handle;
  [%expect
    {|
    (focused ())
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}]
;;

let%expect_test "focus shadow (down)" =
  let test = Test.create ~stats:false (Test.Component.default ()) in
  Handle.do_actions test.handle [ Focus_down ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (0))
    (focused (0))
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │ * │ 0   │ 0     │ hello │ 1.000000 │
    │   │ 100 │ 1     │ there │ 2.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}];
  Handle.do_actions test.handle [ Focus_down ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (1))
    (focused (1))
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │ * │ 100 │ 1     │ there │ 2.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}];
  Handle.do_actions test.handle [ Unfocus ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to ())
    (focused ())
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │   │ 100 │ 1     │ there │ 2.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}];
  Handle.do_actions test.handle [ Focus_down ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (4))
    (focused (4))
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │   │ 100 │ 1     │ there │ 2.000000 │
    │ * │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}]
;;

let%expect_test "focus shadow (up)" =
  let test = Test.create ~stats:false (Test.Component.default ()) in
  Handle.do_actions test.handle [ Focus_up ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (4))
    (focused (4))
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │   │ 100 │ 1     │ there │ 2.000000 │
    │ * │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}];
  Handle.do_actions test.handle [ Focus_up ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (1))
    (focused (1))
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │ * │ 100 │ 1     │ there │ 2.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}];
  Handle.do_actions test.handle [ Unfocus ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to ())
    (focused ())
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │   │ 100 │ 1     │ there │ 2.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}];
  Handle.do_actions test.handle [ Focus_up ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (0))
    (focused (0))
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │ * │ 0   │ 0     │ hello │ 1.000000 │
    │   │ 100 │ 1     │ there │ 2.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}]
;;

let%expect_test "remove focused causes unfocus (down)" =
  let test = Test.create ~stats:false (Test.Component.default ()) in
  Handle.do_actions test.handle [ Focus_down; Focus_down ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (0))
    (focus_changed_to (1))
    (focused (1))
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │ * │ 100 │ 1     │ there │ 2.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}];
  Bonsai.Var.update test.input_var ~f:(fun map -> Map.remove map 1);
  Handle.recompute_view_until_stable test.handle;
  Handle.show test.handle;
  [%expect
    {|
    (focused ())
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}];
  Handle.do_actions test.handle [ Focus_down ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (4))
    (focused (4))
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │ * │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}]
;;

let%expect_test "remove focused causes unfocus (up)" =
  let test = Test.create ~stats:false (Test.Component.default ()) in
  Handle.do_actions test.handle [ Focus_down; Focus_down ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (0))
    (focus_changed_to (1))
    (focused (1))
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │ * │ 100 │ 1     │ there │ 2.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}];
  Bonsai.Var.update test.input_var ~f:(fun map -> Map.remove map 1);
  Handle.recompute_view_until_stable test.handle;
  Handle.show test.handle;
  [%expect
    {|
    (focused ())
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │   │ 0   │ 0     │ hello │ 1.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}];
  Handle.do_actions test.handle [ Focus_up ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (0))
    (focused (0))
    ┌───┬─────┬───────┬───────┬──────────┐
    │ > │ #   │ ◇ key │ a     │ ◇ b      │
    ├───┼─────┼───────┼───────┼──────────┤
    │ * │ 0   │ 0     │ hello │ 1.000000 │
    │   │ 200 │ 4     │ world │ 2.000000 │
    └───┴─────┴───────┴───────┴──────────┘ |}]
;;

let%expect_test "page up" =
  let test =
    Test.create
      ~map:big_map
      ~visible_range:(5, 10)
      ~stats:false
      (Test.Component.default ~preload_rows:2 ())
  in
  Handle.show test.handle;
  [%expect
    {|
    (focused ())
    ┌───┬──────┬───────┬────┬──────────┐
    │ > │ #    │ ◇ key │ a  │ ◇ b      │
    ├───┼──────┼───────┼────┼──────────┤
    │   │ 0    │ 3     │ hi │ 1.000000 │
    │   │ 100  │ 4     │ hi │ 2.000000 │
    │   │ 200  │ 5     │ hi │ 2.000000 │
    │   │ 300  │ 6     │ hi │ 3.000000 │
    │   │ 400  │ 7     │ hi │ 3.000000 │
    │   │ 500  │ 8     │ hi │ 4.000000 │
    │   │ 600  │ 9     │ hi │ 4.000000 │
    │   │ 700  │ 10    │ hi │ 5.000000 │
    │   │ 800  │ 11    │ hi │ 5.000000 │
    │   │ 900  │ 12    │ hi │ 6.000000 │
    │   │ 1000 │ 13    │ hi │ 6.000000 │
    │   │ 1100 │ 14    │ hi │ 7.000000 │
    └───┴──────┴───────┴────┴──────────┘ |}];
  Handle.do_actions test.handle [ Page_up ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (6))
    (focused (6))
    ┌───┬──────┬───────┬────┬──────────┐
    │ > │ #    │ ◇ key │ a  │ ◇ b      │
    ├───┼──────┼───────┼────┼──────────┤
    │   │ 0    │ 3     │ hi │ 1.000000 │
    │   │ 100  │ 4     │ hi │ 2.000000 │
    │   │ 200  │ 5     │ hi │ 2.000000 │
    │ * │ 300  │ 6     │ hi │ 3.000000 │
    │   │ 400  │ 7     │ hi │ 3.000000 │
    │   │ 500  │ 8     │ hi │ 4.000000 │
    │   │ 600  │ 9     │ hi │ 4.000000 │
    │   │ 700  │ 10    │ hi │ 5.000000 │
    │   │ 800  │ 11    │ hi │ 5.000000 │
    │   │ 900  │ 12    │ hi │ 6.000000 │
    │   │ 1000 │ 13    │ hi │ 6.000000 │
    │   │ 1100 │ 14    │ hi │ 7.000000 │
    └───┴──────┴───────┴────┴──────────┘ |}]
;;

let%expect_test "page down" =
  let test =
    Test.create
      ~map:big_map
      ~visible_range:(5, 10)
      ~stats:false
      (Test.Component.default ~preload_rows:2 ())
  in
  Handle.show test.handle;
  [%expect
    {|
    (focused ())
    ┌───┬──────┬───────┬────┬──────────┐
    │ > │ #    │ ◇ key │ a  │ ◇ b      │
    ├───┼──────┼───────┼────┼──────────┤
    │   │ 0    │ 3     │ hi │ 1.000000 │
    │   │ 100  │ 4     │ hi │ 2.000000 │
    │   │ 200  │ 5     │ hi │ 2.000000 │
    │   │ 300  │ 6     │ hi │ 3.000000 │
    │   │ 400  │ 7     │ hi │ 3.000000 │
    │   │ 500  │ 8     │ hi │ 4.000000 │
    │   │ 600  │ 9     │ hi │ 4.000000 │
    │   │ 700  │ 10    │ hi │ 5.000000 │
    │   │ 800  │ 11    │ hi │ 5.000000 │
    │   │ 900  │ 12    │ hi │ 6.000000 │
    │   │ 1000 │ 13    │ hi │ 6.000000 │
    │   │ 1100 │ 14    │ hi │ 7.000000 │
    └───┴──────┴───────┴────┴──────────┘ |}];
  Handle.do_actions test.handle [ Page_down ];
  Handle.show test.handle;
  [%expect
    {|
(focus_changed_to (12))
(focused (12))
┌───┬──────┬───────┬────┬──────────┐
│ > │ #    │ ◇ key │ a  │ ◇ b      │
├───┼──────┼───────┼────┼──────────┤
│   │ 0    │ 3     │ hi │ 1.000000 │
│   │ 100  │ 4     │ hi │ 2.000000 │
│   │ 200  │ 5     │ hi │ 2.000000 │
│   │ 300  │ 6     │ hi │ 3.000000 │
│   │ 400  │ 7     │ hi │ 3.000000 │
│   │ 500  │ 8     │ hi │ 4.000000 │
│   │ 600  │ 9     │ hi │ 4.000000 │
│   │ 700  │ 10    │ hi │ 5.000000 │
│   │ 800  │ 11    │ hi │ 5.000000 │
│ * │ 900  │ 12    │ hi │ 6.000000 │
│   │ 1000 │ 13    │ hi │ 6.000000 │
│   │ 1100 │ 14    │ hi │ 7.000000 │
└───┴──────┴───────┴────┴──────────┘ |}]
;;

let%expect_test "actions on empty table" =
  let test =
    Test.create
      ~map:(Map.empty (module Int))
      ~visible_range:(5, 10)
      ~stats:false
      (Test.Component.default ~preload_rows:2 ())
  in
  (* just make sure nothing weird happens *)
  Handle.do_actions test.handle [ Page_down; Page_up; Focus_down; Focus_up; Unfocus ];
  [%expect {| |}]
;;

let%expect_test "moving focus down should work even when the index changes" =
  let map =
    [ 1; 2; 3; 4 ]
    |> List.map ~f:(fun i -> i, { a = "hi"; b = Float.of_int (i / 2) })
    |> Int.Map.of_alist_exn
    |> Bonsai.Var.create
  in
  let test =
    Test.create_with_var
      ~map
      ~visible_range:(0, 5)
      ~stats:false
      (Test.Component.default ~preload_rows:2 ())
  in
  Handle.show test.handle;
  [%expect
    {|
    (focused ())
    ┌───┬─────┬───────┬────┬──────────┐
    │ > │ #   │ ◇ key │ a  │ ◇ b      │
    ├───┼─────┼───────┼────┼──────────┤
    │   │ 0   │ 1     │ hi │ 0.000000 │
    │   │ 100 │ 2     │ hi │ 1.000000 │
    │   │ 200 │ 3     │ hi │ 1.000000 │
    │   │ 300 │ 4     │ hi │ 2.000000 │
    └───┴─────┴───────┴────┴──────────┘ |}];
  Handle.do_actions test.handle [ Focus_down; Focus_down ];
  Handle.show test.handle;
  [%expect
    {|
(focus_changed_to (1))
(focus_changed_to (2))
(focused (2))
┌───┬─────┬───────┬────┬──────────┐
│ > │ #   │ ◇ key │ a  │ ◇ b      │
├───┼─────┼───────┼────┼──────────┤
│   │ 0   │ 1     │ hi │ 0.000000 │
│ * │ 100 │ 2     │ hi │ 1.000000 │
│   │ 200 │ 3     │ hi │ 1.000000 │
│   │ 300 │ 4     │ hi │ 2.000000 │
└───┴─────┴───────┴────┴──────────┘ |}];
  Bonsai.Var.update map ~f:(fun map -> Map.remove map 1);
  Handle.show test.handle;
  [%expect
    {|
    (focused (2))
    ┌───┬─────┬───────┬────┬──────────┐
    │ > │ #   │ ◇ key │ a  │ ◇ b      │
    ├───┼─────┼───────┼────┼──────────┤
    │ * │ 100 │ 2     │ hi │ 1.000000 │
    │   │ 200 │ 3     │ hi │ 1.000000 │
    │   │ 300 │ 4     │ hi │ 2.000000 │
    └───┴─────┴───────┴────┴──────────┘ |}];
  Handle.do_actions test.handle [ Focus_down ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (3))
    (focused (3))
    ┌───┬─────┬───────┬────┬──────────┐
    │ > │ #   │ ◇ key │ a  │ ◇ b      │
    ├───┼─────┼───────┼────┼──────────┤
    │   │ 100 │ 2     │ hi │ 1.000000 │
    │ * │ 200 │ 3     │ hi │ 1.000000 │
    │   │ 300 │ 4     │ hi │ 2.000000 │
    └───┴─────┴───────┴────┴──────────┘ |}]
;;

let%expect_test "moving focus up should work even when the index changes" =
  let map =
    [ 1; 2; 3; 4 ]
    |> List.map ~f:(fun i -> i, { a = "hi"; b = Float.of_int (i / 2) })
    |> Int.Map.of_alist_exn
    |> Bonsai.Var.create
  in
  let test =
    Test.create_with_var
      ~map
      ~visible_range:(0, 5)
      ~stats:false
      (Test.Component.default ~preload_rows:2 ())
  in
  Handle.show test.handle;
  [%expect
    {|
    (focused ())
    ┌───┬─────┬───────┬────┬──────────┐
    │ > │ #   │ ◇ key │ a  │ ◇ b      │
    ├───┼─────┼───────┼────┼──────────┤
    │   │ 0   │ 1     │ hi │ 0.000000 │
    │   │ 100 │ 2     │ hi │ 1.000000 │
    │   │ 200 │ 3     │ hi │ 1.000000 │
    │   │ 300 │ 4     │ hi │ 2.000000 │
    └───┴─────┴───────┴────┴──────────┘ |}];
  Handle.do_actions test.handle [ Focus_down; Focus_down; Focus_down ];
  Handle.show test.handle;
  [%expect
    {|
(focus_changed_to (1))
(focus_changed_to (2))
(focus_changed_to (3))
(focused (3))
┌───┬─────┬───────┬────┬──────────┐
│ > │ #   │ ◇ key │ a  │ ◇ b      │
├───┼─────┼───────┼────┼──────────┤
│   │ 0   │ 1     │ hi │ 0.000000 │
│   │ 100 │ 2     │ hi │ 1.000000 │
│ * │ 200 │ 3     │ hi │ 1.000000 │
│   │ 300 │ 4     │ hi │ 2.000000 │
└───┴─────┴───────┴────┴──────────┘ |}];
  Bonsai.Var.update map ~f:(fun map -> Map.add_exn map ~key:0 ~data:{ a = "hi"; b = 0.0 });
  Handle.show test.handle;
  [%expect
    {|
    (focused (3))
    ┌───┬──────┬───────┬────┬──────────┐
    │ > │ #    │ ◇ key │ a  │ ◇ b      │
    ├───┼──────┼───────┼────┼──────────┤
    │   │ -100 │ 0     │ hi │ 0.000000 │
    │   │ 0    │ 1     │ hi │ 0.000000 │
    │   │ 100  │ 2     │ hi │ 1.000000 │
    │ * │ 200  │ 3     │ hi │ 1.000000 │
    │   │ 300  │ 4     │ hi │ 2.000000 │
    └───┴──────┴───────┴────┴──────────┘ |}];
  Handle.do_actions test.handle [ Focus_up ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (2))
    (focused (2))
    ┌───┬──────┬───────┬────┬──────────┐
    │ > │ #    │ ◇ key │ a  │ ◇ b      │
    ├───┼──────┼───────┼────┼──────────┤
    │   │ -100 │ 0     │ hi │ 0.000000 │
    │   │ 0    │ 1     │ hi │ 0.000000 │
    │ * │ 100  │ 2     │ hi │ 1.000000 │
    │   │ 200  │ 3     │ hi │ 1.000000 │
    │   │ 300  │ 4     │ hi │ 2.000000 │
    └───┴──────┴───────┴────┴──────────┘ |}]
;;


let%expect_test "BUG: setting rank_range to not include the first element doesn't allow \
                 focus up/down events"
  =
  let module Action = struct
    type t = Focus_down
  end
  in
  let rank_range = Bonsai.Var.create (Collate.Which_range.To 2) in
  let map =
    [ 1; 2; 3; 4; 5; 6; 7 ]
    |> List.map ~f:(fun i -> i, { a = "hi"; b = Float.of_int i })
    |> Int.Map.of_alist_exn
    |> Value.return
  in
  let component =
    let%sub collate =
      let collate =
        let%map rank_range = Bonsai.Var.value rank_range in
        { Collate.filter = None
        ; order = Compare.Unchanged
        ; key_range = Collate.Which_range.All_rows
        ; rank_range
        }
      in
      Table_expert.collate
        ~filter_equal:phys_equal
        ~filter_to_predicate:Fn.id
        ~order_equal:phys_equal
        ~order_to_compare:Fn.id
        map
        collate
    in
    Table_expert.component
      (module Int)
      ~focus:
        (Table_expert.Focus.By_row
           { on_change = Test.focus_changed
           ; compute_presence =
               (fun focus ->
                  let%arr map = map
                  and focus = focus in
                  match focus with
                  | None -> None
                  | Some focus -> if Map.mem map focus then Some focus else None)
           })
      ~row_height:(`Px 20)
      ~columns:
        (Bonsai.Value.return
         @@ [ Table_expert.Columns.Dynamic_columns.column
                ~label:(Vdom.Node.text "a")
                ~cell:(fun ~key:_ ~data -> Vdom.Node.text data.a)
                ()
            ; Table_expert.Columns.Dynamic_columns.column
                ~label:(Vdom.Node.text "b")
                ~cell:(fun ~key:_ ~data -> Vdom.Node.text (Float.to_string data.b))
                ()
            ]
         |> Table_expert.Columns.Dynamic_columns.lift)
      collate
  in
  let handle =
    Handle.create
      (module struct
        type t = int Table_expert.Focus.By_row.optional Table_expert.Result.t
        type incoming = Action.t

        let view { Table_expert.Result.for_testing; focus; _ } =
          table_to_string
            focus
            (Lazy.force for_testing)
            ~include_stats:false
            ~include_focus:true
        ;;

        let incoming { Table_expert.Result.focus; _ } Action.Focus_down =
          focus.Table_expert.Focus.By_row.focus_down
        ;;
      end)
      component
  in
  Handle.show handle;
  [%expect
    {|
    (focused ())
    ┌───┬─────┬────┬────┐
    │ > │ #   │ a  │ b  │
    ├───┼─────┼────┼────┤
    │   │ 0   │ hi │ 1. │
    │   │ 100 │ hi │ 2. │
    │   │ 200 │ hi │ 3. │
    └───┴─────┴────┴────┘ |}];
  (* See that focus_down with the default rank_range works as intended *)
  Handle.do_actions handle [ Focus_down ];
  Handle.recompute_view_until_stable handle;
  Handle.show handle;
  [%expect
    {|
    (focus_changed_to (1))
    (focused (1))
    ┌───┬─────┬────┬────┐
    │ > │ #   │ a  │ b  │
    ├───┼─────┼────┼────┤
    │ * │ 0   │ hi │ 1. │
    │   │ 100 │ hi │ 2. │
    │   │ 200 │ hi │ 3. │
    └───┴─────┴────┴────┘ |}];
  Bonsai.Var.set rank_range (Collate.Which_range.Between (3, 5));
  Handle.recompute_view_until_stable handle;
  Handle.show handle;
  [%expect
    {|
    (focused (1))
    ┌───┬─────┬────┬────┐
    │ > │ #   │ a  │ b  │
    ├───┼─────┼────┼────┤
    │   │ 0   │ hi │ 4. │
    │   │ 100 │ hi │ 5. │
    │   │ 200 │ hi │ 6. │
    └───┴─────┴────┴────┘ |}];
  (* After setting the [rank_range], focus down no longer focuses an item *)
  Handle.do_actions handle [ Focus_down ];
  Handle.recompute_view_until_stable handle;
  Handle.show handle;
  [%expect
    {|
    (focus_changed_to ())
    (focused ())
    ┌───┬─────┬────┬────┐
    │ > │ #   │ a  │ b  │
    ├───┼─────┼────┼────┤
    │   │ 0   │ hi │ 4. │
    │   │ 100 │ hi │ 5. │
    │   │ 200 │ hi │ 6. │
    └───┴─────┴────┴────┘ |}];
  (* The focus didn't just stay on the element with b = 1., as demonstrated by performing
     3 more focus down events and viewing the table *)
  Handle.do_actions handle [ Focus_down; Focus_down; Focus_down ];
  Handle.recompute_view_until_stable handle;
  Handle.show handle;
  [%expect
    {|
    (focused ())
    ┌───┬─────┬────┬────┐
    │ > │ #   │ a  │ b  │
    ├───┼─────┼────┼────┤
    │   │ 0   │ hi │ 4. │
    │   │ 100 │ hi │ 5. │
    │   │ 200 │ hi │ 6. │
    └───┴─────┴────┴────┘ |}]
;;

let%expect_test "focus down when presence says that all responses are None" =
  let presence ~focus:_ ~collation:_ = Bonsai.const None in
  let collate =
    Value.return
      { Incr_map_collate.Collate.filter = ()
      ; order = ()
      ; key_range = All_rows
      ; rank_range = All_rows
      }
  in
  let test =
    Test.create
      ~stats:false
      (Test.Component.expert_for_testing_compute_presence ~collate ~presence ())
  in
  Handle.show test.handle;
  [%expect
    {|
    (focused ())
    ┌───┬─────┬─────┐
    │ > │ #   │ key │
    ├───┼─────┼─────┤
    │   │ 0   │ 0   │
    │   │ 100 │ 1   │
    │   │ 200 │ 4   │
    └───┴─────┴─────┘ |}];
  Handle.do_actions test.handle [ Focus_down ];
  Handle.show test.handle;
  (* notice that visual selection still works, but
     "focused" remains "()", aka 'none' *)
  [%expect
    {|
    (focused ())
    ┌───┬─────┬─────┐
    │ > │ #   │ key │
    ├───┼─────┼─────┤
    │ * │ 0   │ 0   │
    │   │ 100 │ 1   │
    │   │ 200 │ 4   │
    └───┴─────┴─────┘ |}];
  Handle.do_actions test.handle [ Focus_down ];
  Handle.show test.handle;
  [%expect
    {|
    (focused ())
    ┌───┬─────┬─────┐
    │ > │ #   │ key │
    ├───┼─────┼─────┤
    │   │ 0   │ 0   │
    │ * │ 100 │ 1   │
    │   │ 200 │ 4   │
    └───┴─────┴─────┘ |}]
;;

let%expect_test "show that scrolling out of a basic table will keep the focus" =
  let test =
    Test.create
      ~stats:true
      ~map:big_map
      ~should_set_bounds:false
      (Test.Component.default ())
  in
  Test.set_bounds test ~low:0 ~high:10;
  Handle.show test.handle;
  [%expect
    {|
(focused ())
┌────────────────┬───────┐
│ metric         │ value │
├────────────────┼───────┤
│ rows-before    │ 0     │
│ rows-after     │ 97    │
│ num-filtered   │ 99    │
│ num-unfiltered │ 99    │
└────────────────┴───────┘
┌───┬─────┬───────┬────┬──────────┐
│ > │ #   │ ◇ key │ a  │ ◇ b      │
├───┼─────┼───────┼────┼──────────┤
│   │ 0   │ 1     │ hi │ 0.000000 │
│   │ 100 │ 2     │ hi │ 1.000000 │
└───┴─────┴───────┴────┴──────────┘ |}];
  Handle.do_actions test.handle [ Focus_down ];
  Handle.show test.handle;
  [%expect
    {|
    (focus_changed_to (1))
    (focused (1))
    ┌────────────────┬───────┐
    │ metric         │ value │
    ├────────────────┼───────┤
    │ rows-before    │ 0     │
    │ rows-after     │ 87    │
    │ num-filtered   │ 99    │
    │ num-unfiltered │ 99    │
    └────────────────┴───────┘
    ┌───┬──────┬───────┬────┬──────────┐
    │ > │ #    │ ◇ key │ a  │ ◇ b      │
    ├───┼──────┼───────┼────┼──────────┤
    │ * │ 0    │ 1     │ hi │ 0.000000 │
    │   │ 100  │ 2     │ hi │ 1.000000 │
    │   │ 200  │ 3     │ hi │ 1.000000 │
    │   │ 300  │ 4     │ hi │ 2.000000 │
    │   │ 400  │ 5     │ hi │ 2.000000 │
    │   │ 500  │ 6     │ hi │ 3.000000 │
    │   │ 600  │ 7     │ hi │ 3.000000 │
    │   │ 700  │ 8     │ hi │ 4.000000 │
    │   │ 800  │ 9     │ hi │ 4.000000 │
    │   │ 900  │ 10    │ hi │ 5.000000 │
    │   │ 1000 │ 11    │ hi │ 5.000000 │
    │   │ 1100 │ 12    │ hi │ 6.000000 │
    └───┴──────┴───────┴────┴──────────┘ |}];
  Test.set_bounds test ~low:3 ~high:13;
  Handle.recompute_view_until_stable test.handle;
  Handle.show test.handle;
  [%expect
    {|
    (focused (1))
    ┌────────────────┬───────┐
    │ metric         │ value │
    ├────────────────┼───────┤
    │ rows-before    │ 2     │
    │ rows-after     │ 84    │
    │ num-filtered   │ 99    │
    │ num-unfiltered │ 99    │
    └────────────────┴───────┘
    ┌───┬──────┬───────┬────┬──────────┐
    │ > │ #    │ ◇ key │ a  │ ◇ b      │
    ├───┼──────┼───────┼────┼──────────┤
    │   │ 200  │ 3     │ hi │ 1.000000 │
    │   │ 300  │ 4     │ hi │ 2.000000 │
    │   │ 400  │ 5     │ hi │ 2.000000 │
    │   │ 500  │ 6     │ hi │ 3.000000 │
    │   │ 600  │ 7     │ hi │ 3.000000 │
    │   │ 700  │ 8     │ hi │ 4.000000 │
    │   │ 800  │ 9     │ hi │ 4.000000 │
    │   │ 900  │ 10    │ hi │ 5.000000 │
    │   │ 1000 │ 11    │ hi │ 5.000000 │
    │   │ 1100 │ 12    │ hi │ 6.000000 │
    │   │ 1200 │ 13    │ hi │ 6.000000 │
    │   │ 1300 │ 14    │ hi │ 7.000000 │
    │   │ 1400 │ 15    │ hi │ 7.000000 │
    └───┴──────┴───────┴────┴──────────┘ |}];
  Test.set_bounds test ~low:0 ~high:10;
  Handle.recompute_view_until_stable test.handle;
  Handle.show test.handle;
  [%expect
    {|
    (focused (1))
    ┌────────────────┬───────┐
    │ metric         │ value │
    ├────────────────┼───────┤
    │ rows-before    │ 0     │
    │ rows-after     │ 87    │
    │ num-filtered   │ 99    │
    │ num-unfiltered │ 99    │
    └────────────────┴───────┘
    ┌───┬──────┬───────┬────┬──────────┐
    │ > │ #    │ ◇ key │ a  │ ◇ b      │
    ├───┼──────┼───────┼────┼──────────┤
    │ * │ 100  │ 1     │ hi │ 0.000000 │
    │   │ 150  │ 2     │ hi │ 1.000000 │
    │   │ 200  │ 3     │ hi │ 1.000000 │
    │   │ 300  │ 4     │ hi │ 2.000000 │
    │   │ 400  │ 5     │ hi │ 2.000000 │
    │   │ 500  │ 6     │ hi │ 3.000000 │
    │   │ 600  │ 7     │ hi │ 3.000000 │
    │   │ 700  │ 8     │ hi │ 4.000000 │
    │   │ 800  │ 9     │ hi │ 4.000000 │
    │   │ 900  │ 10    │ hi │ 5.000000 │
    │   │ 1000 │ 11    │ hi │ 5.000000 │
    │   │ 1100 │ 12    │ hi │ 6.000000 │
    └───┴──────┴───────┴────┴──────────┘ |}]
;;

let%expect_test "show that scrolling out of a custom table will execute the presence \
                 component"
  =
  let open Incr_map_collate.Collate.Which_range in
  let presence ~focus ~collation =
    let%arr focus = focus
    and collation = collation in
    match focus with
    | None -> None
    | Some focus ->
      if Map.exists (Incr_map_collate.Collated.to_map_list collation) ~f:(fun (k, _v) ->
        focus = k)
      then Some focus
      else None
  in
  let rank = Bonsai.Var.create (Between (0, 10)) in
  let collate =
    let%map rank_range = Bonsai.Var.value rank in
    { Incr_map_collate.Collate.filter = (); order = (); key_range = All_rows; rank_range }
  in
  let test =
    Test.create
      ~map:big_map
      ~stats:false
      (Test.Component.expert_for_testing_compute_presence ~collate ~presence ())
  in
  Bonsai.Var.set rank (Between (0, 10));
  Handle.show test.handle;
  [%expect
    {|
(focused ())
┌───┬──────┬─────┐
│ > │ #    │ key │
├───┼──────┼─────┤
│   │ 0    │ 1   │
│   │ 100  │ 2   │
│   │ 200  │ 3   │
│   │ 300  │ 4   │
│   │ 400  │ 5   │
│   │ 500  │ 6   │
│   │ 600  │ 7   │
│   │ 700  │ 8   │
│   │ 800  │ 9   │
│   │ 900  │ 10  │
│   │ 1000 │ 11  │
└───┴──────┴─────┘ |}];
  Handle.do_actions test.handle [ Focus_down ];
  Handle.show test.handle;
  [%expect
    {|
    (focused (1))
    ┌───┬──────┬─────┐
    │ > │ #    │ key │
    ├───┼──────┼─────┤
    │ * │ 0    │ 1   │
    │   │ 100  │ 2   │
    │   │ 200  │ 3   │
    │   │ 300  │ 4   │
    │   │ 400  │ 5   │
    │   │ 500  │ 6   │
    │   │ 600  │ 7   │
    │   │ 700  │ 8   │
    │   │ 800  │ 9   │
    │   │ 900  │ 10  │
    │   │ 1000 │ 11  │
    └───┴──────┴─────┘ |}];
  Bonsai.Var.set rank (Between (3, 13));
  Handle.recompute_view_until_stable test.handle;
  Handle.show test.handle;
  (* notice that when we scrolled away, the "focused" value is set to None. *)
  [%expect
    {|
    (focused ())
    ┌───┬──────┬─────┐
    │ > │ #    │ key │
    ├───┼──────┼─────┤
    │   │ 300  │ 4   │
    │   │ 400  │ 5   │
    │   │ 500  │ 6   │
    │   │ 600  │ 7   │
    │   │ 700  │ 8   │
    │   │ 800  │ 9   │
    │   │ 900  │ 10  │
    │   │ 1000 │ 11  │
    │   │ 1100 │ 12  │
    │   │ 1200 │ 13  │
    │   │ 1300 │ 14  │
    └───┴──────┴─────┘ |}];
  Bonsai.Var.set rank (Between (0, 10));
  Handle.recompute_view_until_stable test.handle;
  Handle.show test.handle;
  [%expect
    {|
    (focused (1))
    ┌───┬──────┬─────┐
    │ > │ #    │ key │
    ├───┼──────┼─────┤
    │ * │ 200  │ 1   │
    │   │ 250  │ 2   │
    │   │ 275  │ 3   │
    │   │ 300  │ 4   │
    │   │ 400  │ 5   │
    │   │ 500  │ 6   │
    │   │ 600  │ 7   │
    │   │ 700  │ 8   │
    │   │ 800  │ 9   │
    │   │ 900  │ 10  │
    │   │ 1000 │ 11  │
    └───┴──────┴─────┘ |}]
;;
