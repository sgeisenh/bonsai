open! Core
open! Bonsai_web
open! Bonsai_web_test
open Bonsai.Let_syntax
open Shared

module Test = struct
  include Shared.Test

  let create
        (type a)
        ?(visible_range = 0, 100)
        ?(map = small_map)
        ?(should_print_styles = false)
        ?(should_set_bounds = true)
        component
    : a t
    =
    let min_vis, max_vis = visible_range in
    let input_var = Bonsai.Var.create map in
    let filter_var = Bonsai.Var.create (fun ~key:_ ~data:_ -> true) in
    let { Component.component; get_vdom; get_testing = _; get_focus; get_inject } =
      component (Bonsai.Var.value input_var) (Bonsai.Var.value filter_var)
    in
    let handle =
      Handle.create
        (module struct
          type t = a

          let view result =
            result
            |> get_vdom
            |> Virtual_dom_test_helpers.Node_helpers.unsafe_convert_exn
            |> Virtual_dom_test_helpers.Node_helpers.to_string_html
                 ~filter_printed_attributes:(fun key _data ->
                   should_print_styles || not (String.is_prefix ~prefix:"style." key))
          ;;

          type incoming = Action.t

          let incoming = get_inject
        end)
        component
    in
    let t = { handle; get_vdom; get_focus; input_var; filter_var } in
    if should_set_bounds then set_bounds t ~low:min_vis ~high:max_vis;
    t
  ;;

  let print_message_on_result_recomputation t =
    let result = Incr.map (Handle.result_incr t.handle) ~f:t.get_vdom in
    Incr.Observer.on_update_exn (Incr.observe result) ~f:(function
      | Initialized _ -> print_endline "Initialized"
      | Changed _ -> print_endline "Changed"
      | Invalidated -> assert false)
  ;;
end

let sexp_of_computation (type result) (t : result Bonsai.Private.Computation.t) =
  Bonsai.Private.Skeleton.Computation.of_computation t
  |> Bonsai.Private.Skeleton.Computation.minimal_sexp_of_t
;;

let print_assocs component =
  let rec count needle = function
    | Sexp.Atom s when String.equal needle s -> 1
    | Atom _ -> 0
    | List l -> List.sum (module Int) l ~f:(count needle)
  in
  let structure =
    component
    |> Bonsai.Private.reveal_computation
    |> Bonsai.Private.pre_process
    |> sexp_of_computation
  in
  let assoc_count = count "Assoc" structure in
  let assoc_simple_count = count "Assoc_simpl" structure in
  let assoc_on_count = count "Assoc_on" structure in
  print_s [%message (assoc_count : int) (assoc_simple_count : int) (assoc_on_count : int)]
;;

let%expect_test "simplified_assocs" =
  let { Test.Component.component; _ } =
    Test.Component.default
      ()
      (Bonsai.Value.return Int.Map.empty)
      (Bonsai.Value.return (fun ~key:_ ~data:_ -> true))
  in
  print_assocs component;
  (* there's only one assoc because all the columns are inside of an assoc
     per-row instead of it being the other way around as you might have
     expected. *)
  [%expect {| ((assoc_count 1) (assoc_simple_count 2) (assoc_on_count 1)) |}]
;;

let%expect_test "simplified_assocs on the dynamic columns" =
  let { Test.Component.component; _ } =
    Test.Component.default'
      ()
      (Bonsai.Value.return Int.Map.empty)
      (Bonsai.Value.return (fun ~key:_ ~data:_ -> true))
  in
  print_assocs component;
  (* No assocs here because it just uses the Incr_map function directly *)
  [%expect {| ((assoc_count 1) (assoc_simple_count 0) (assoc_on_count 0)) |}]
;;

let%expect_test "column visibility" =
  let is_column_b_visible_var = Bonsai.Var.create true in
  let is_column_b_visible = Bonsai.Var.value is_column_b_visible_var in
  let test =
    Test.create ~should_print_styles:true (Test.Component.default ~is_column_b_visible ())
  in
  Handle.recompute_view_until_stable test.handle;
  Handle.store_view test.handle;
  Bonsai.Var.set is_column_b_visible_var false;
  Handle.recompute_view_until_stable test.handle;
  Handle.show_diff test.handle;
  [%expect
    {|
          </td>
          <td colspan="1"
              class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
              freeze_width=((set <fun>)(reset <fun>))
              size_tracker=<fun>
              style={
                width: 50px;
              }>
            <div> a </div>
          </td>
          <td colspan="1"
              class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
              freeze_width=((set <fun>)(reset <fun>))
              size_tracker=<fun>
              style={
                width: 50px;
+|              display: none;
              }>
            <div class="column_header_hash_replaced_in_test" onclick>
              <span> ◇  b </span>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    <div class="partial_render_table_body_hash_replaced_in_test"
         bounds-change=<opaque>
         style={
           height: 3px;
         }>
      <div style={ padding-top: 0px; padding-bottom: 0px; }>
        <div>
          <div class="prt-table-row" onclick style={ height: 1px; width: 0.00px; }>

                   max-height: 1px;
                   width: 0.00px;
                   min-width: 0.00px;
                   max-width: 0.00px;
                 }>
              <input oninput> </input>
              hello
            </div>
            <div class="cell_hash_replaced_in_test prt-table-cell"
                 style={
                   height: 1px;
                   min-height: 1px;
                   max-height: 1px;
                   width: 0.00px;
                   min-width: 0.00px;
                   max-width: 0.00px;
-|               }> 1.000000 </div>
+|                 display: none;
+|               }> </div>
          </div>
          <div class="prt-table-row" onclick style={ height: 1px; width: 0.00px; }>
            <div class="cell_hash_replaced_in_test prt-table-cell"
                 style={
                   height: 1px;
                   min-height: 1px;
                   max-height: 1px;
                   width: 0.00px;
                   min-width: 0.00px;
                   max-width: 0.00px;
                 }> 1 </div>
            <div class="cell_hash_replaced_in_test prt-table-cell"
                 style={
                   height: 1px;
                   min-height: 1px;
                   max-height: 1px;
                   width: 0.00px;
                   min-width: 0.00px;
                   max-width: 0.00px;
                 }>
              <input oninput> </input>
              there
            </div>
            <div class="cell_hash_replaced_in_test prt-table-cell"
                 style={
                   height: 1px;
                   min-height: 1px;
                   max-height: 1px;
                   width: 0.00px;
                   min-width: 0.00px;
                   max-width: 0.00px;
-|               }> 2.000000 </div>
+|                 display: none;
+|               }> </div>
          </div>
          <div class="prt-table-row" onclick style={ height: 1px; width: 0.00px; }>
            <div class="cell_hash_replaced_in_test prt-table-cell"
                 style={
                   height: 1px;
                   min-height: 1px;
                   max-height: 1px;
                   width: 0.00px;
                   min-width: 0.00px;
                   max-width: 0.00px;
                 }> 4 </div>
            <div class="cell_hash_replaced_in_test prt-table-cell"
                 style={
                   height: 1px;
                   min-height: 1px;
                   max-height: 1px;
                   width: 0.00px;
                   min-width: 0.00px;
                   max-width: 0.00px;
                 }>
              <input oninput> </input>
              world
            </div>
            <div class="cell_hash_replaced_in_test prt-table-cell"
                 style={
                   height: 1px;
                   min-height: 1px;
                   max-height: 1px;
                   width: 0.00px;
                   min-width: 0.00px;
                   max-width: 0.00px;
-|               }> 2.000000 </div>
+|                 display: none;
+|               }> </div>
          </div>
        </div>
      </div>
    </div>
  </div> |}]
;;

let%expect_test "stabilization of view range" =
  let test =
    Test.create (Test.Component.default ()) ~visible_range:(0, 2) ~should_set_bounds:false
  in
  Handle.recompute_view_until_stable test.handle;
  Handle.show test.handle;
  [%expect
    {|
<div class="partial-render-table-bonsai_path_replaced_in_test partial_render_table_container_hash_replaced_in_test">
  <table class="partial_render_table_header_hash_replaced_in_test prt-table-header"
         bounds-change=<opaque>>
    <tbody>
      <tr>
        <td colspan="1"
            class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
            freeze_width=((set <fun>)(reset <fun>))
            size_tracker=<fun>>
          <div class="column_header_hash_replaced_in_test" onclick>
            <span> ◇  key </span>
          </div>
        </td>
        <td colspan="1"
            class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
            freeze_width=((set <fun>)(reset <fun>))
            size_tracker=<fun>>
          <div> a </div>
        </td>
        <td colspan="1"
            class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
            freeze_width=((set <fun>)(reset <fun>))
            size_tracker=<fun>>
          <div class="column_header_hash_replaced_in_test" onclick>
            <span> ◇  b </span>
          </div>
        </td>
      </tr>
    </tbody>
  </table>
  <div class="partial_render_table_body_hash_replaced_in_test" bounds-change=<opaque>>
    <div>
      <div>
        <div class="prt-table-row" onclick>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 0 </div>
          <div class="cell_hash_replaced_in_test prt-table-cell">
            <input oninput> </input>
            hello
          </div>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 1.000000 </div>
        </div>
        <div class="prt-table-row" onclick>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 1 </div>
          <div class="cell_hash_replaced_in_test prt-table-cell">
            <input oninput> </input>
            there
          </div>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 2.000000 </div>
        </div>
      </div>
    </div>
  </div>
</div> |}];
  (* Change the visibility to show the rest of the nodes *)
  Handle.show_diff test.handle;
  [%expect {||}];
  Handle.recompute_view_until_stable test.handle;
  Handle.show_diff test.handle;
  [%expect {||}];
  Test.set_bounds test ~low:0 ~high:100;
  Handle.recompute_view_until_stable test.handle;
  Handle.show_diff test.handle;
  [%expect
    {|
              <div class="prt-table-row" onclick>
                <div class="cell_hash_replaced_in_test prt-table-cell"> 0 </div>
                <div class="cell_hash_replaced_in_test prt-table-cell">
                  <input oninput> </input>
                  hello
                </div>
                <div class="cell_hash_replaced_in_test prt-table-cell"> 1.000000 </div>
              </div>
              <div class="prt-table-row" onclick>
                <div class="cell_hash_replaced_in_test prt-table-cell"> 1 </div>
                <div class="cell_hash_replaced_in_test prt-table-cell">
                  <input oninput> </input>
                  there
                </div>
                <div class="cell_hash_replaced_in_test prt-table-cell"> 2.000000 </div>
              </div>
    +|        <div class="prt-table-row" onclick>
    +|          <div class="cell_hash_replaced_in_test prt-table-cell"> 4 </div>
    +|          <div class="cell_hash_replaced_in_test prt-table-cell">
    +|            <input oninput> </input>
    +|            world
    +|          </div>
    +|          <div class="cell_hash_replaced_in_test prt-table-cell"> 2.000000 </div>
    +|        </div>
            </div>
          </div>
        </div>
      </div> |}]
;;

let%expect_test "resize-column" =
  let test = Test.create ~should_print_styles:true (Test.Component.default ()) in
  Handle.recompute_view_until_stable test.handle;
  Handle.store_view test.handle;
  Test.resize_column test ~idx:0 ~width:10.0;
  Handle.recompute_view_until_stable test.handle;
  Handle.show_diff test.handle;
  [%expect
    {|
  <div class="partial-render-table-bonsai_path_replaced_in_test partial_render_table_container_hash_replaced_in_test">
    <table class="partial_render_table_header_hash_replaced_in_test prt-table-header"
           bounds-change=<opaque>>
      <tbody>
        <tr>
          <td colspan="1"
              class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
              freeze_width=((set <fun>)(reset <fun>))
              size_tracker=<fun>
              style={
-|              width: 50px;
+|              width: 10.00px;
              }>
            <div class="column_header_hash_replaced_in_test" onclick>
              <span> ◇  key </span>
            </div>
          </td>
          <td colspan="1"
              class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
              freeze_width=((set <fun>)(reset <fun>))
              size_tracker=<fun>
              style={
                width: 50px;
              }>
            <div> a </div>
          </td>
          <td colspan="1"
              class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"

                width: 50px;
              }>
            <div class="column_header_hash_replaced_in_test" onclick>
              <span> ◇  b </span>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    <div class="partial_render_table_body_hash_replaced_in_test"
         bounds-change=<opaque>
         style={
           height: 3px;
         }>
      <div style={ padding-top: 0px; padding-bottom: 0px; }>
        <div>
-|        <div class="prt-table-row" onclick style={ height: 1px; width: 0.00px; }>
+|        <div class="prt-table-row" onclick style={ height: 1px; width: 10.00px; }>
            <div class="cell_hash_replaced_in_test prt-table-cell"
                 style={
                   height: 1px;
                   min-height: 1px;
                   max-height: 1px;
-|                 width: 0.00px;
+|                 width: 10.00px;
-|                 min-width: 0.00px;
+|                 min-width: 10.00px;
-|                 max-width: 0.00px;
+|                 max-width: 10.00px;
                 }> 0 </div>
            <div class="cell_hash_replaced_in_test prt-table-cell"
                 style={
                   height: 1px;
                   min-height: 1px;
                   max-height: 1px;
                   width: 0.00px;
                   min-width: 0.00px;
                   max-width: 0.00px;
                 }>
              <input oninput> </input>
              hello
            </div>
            <div class="cell_hash_replaced_in_test prt-table-cell"
                 style={
                   height: 1px;
                   min-height: 1px;
                   max-height: 1px;
                   width: 0.00px;
                   min-width: 0.00px;
                   max-width: 0.00px;
                 }> 1.000000 </div>
          </div>
-|        <div class="prt-table-row" onclick style={ height: 1px; width: 0.00px; }>
+|        <div class="prt-table-row" onclick style={ height: 1px; width: 10.00px; }>
            <div class="cell_hash_replaced_in_test prt-table-cell"
                 style={
                   height: 1px;
                   min-height: 1px;
                   max-height: 1px;
-|                 width: 0.00px;
+|                 width: 10.00px;
-|                 min-width: 0.00px;
+|                 min-width: 10.00px;
-|                 max-width: 0.00px;
+|                 max-width: 10.00px;
                 }> 1 </div>
            <div class="cell_hash_replaced_in_test prt-table-cell"
                 style={
                   height: 1px;
                   min-height: 1px;
                   max-height: 1px;
                   width: 0.00px;
                   min-width: 0.00px;
                   max-width: 0.00px;
                 }>
              <input oninput> </input>
              there
            </div>
            <div class="cell_hash_replaced_in_test prt-table-cell"
                 style={
                   height: 1px;
                   min-height: 1px;
                   max-height: 1px;
                   width: 0.00px;
                   min-width: 0.00px;
                   max-width: 0.00px;
                 }> 2.000000 </div>
          </div>
-|        <div class="prt-table-row" onclick style={ height: 1px; width: 0.00px; }>
+|        <div class="prt-table-row" onclick style={ height: 1px; width: 10.00px; }>
            <div class="cell_hash_replaced_in_test prt-table-cell"
                 style={
                   height: 1px;
                   min-height: 1px;
                   max-height: 1px;
-|                 width: 0.00px;
+|                 width: 10.00px;
-|                 min-width: 0.00px;
+|                 min-width: 10.00px;
-|                 max-width: 0.00px;
+|                 max-width: 10.00px;
                 }> 4 </div>
            <div class="cell_hash_replaced_in_test prt-table-cell"
                 style={
                   height: 1px;
                   min-height: 1px;
                   max-height: 1px;
                   width: 0.00px;
                   min-width: 0.00px;
                   max-width: 0.00px;
                 }>
              <input oninput> </input>
              world
            </div>
            <div class="cell_hash_replaced_in_test prt-table-cell"
                 style={
                   height: 1px; |}]
;;

let%expect_test "big table" =
  (* The PRT always renders [low-25, high+25], so 50,50 will render a big chunk
     centered at 50 *)
  let test =
    Test.create ~map:big_map ~visible_range:(50, 50) (Test.Component.default ())
  in
  Handle.recompute_view_until_stable test.handle;
  Handle.show test.handle;
  [%expect
    {|
<div class="partial-render-table-bonsai_path_replaced_in_test partial_render_table_container_hash_replaced_in_test">
  <table class="partial_render_table_header_hash_replaced_in_test prt-table-header"
         bounds-change=<opaque>>
    <tbody>
      <tr>
        <td colspan="1"
            class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
            freeze_width=((set <fun>)(reset <fun>))
            size_tracker=<fun>>
          <div class="column_header_hash_replaced_in_test" onclick>
            <span> ◇  key </span>
          </div>
        </td>
        <td colspan="1"
            class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
            freeze_width=((set <fun>)(reset <fun>))
            size_tracker=<fun>>
          <div> a </div>
        </td>
        <td colspan="1"
            class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
            freeze_width=((set <fun>)(reset <fun>))
            size_tracker=<fun>>
          <div class="column_header_hash_replaced_in_test" onclick>
            <span> ◇  b </span>
          </div>
        </td>
      </tr>
    </tbody>
  </table>
  <div class="partial_render_table_body_hash_replaced_in_test" bounds-change=<opaque>>
    <div>
      <div>
        <div class="prt-table-row" onclick>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 51 </div>
          <div class="cell_hash_replaced_in_test prt-table-cell">
            <input oninput> </input>
            hi
          </div>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 25.000000 </div>
        </div>
        <div class="prt-table-row" onclick>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 52 </div>
          <div class="cell_hash_replaced_in_test prt-table-cell">
            <input oninput> </input>
            hi
          </div>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 26.000000 </div>
        </div>
      </div>
    </div>
  </div>
</div> |}];
  (* extending the range upwards should only add to the end *)
  Test.set_bounds test ~low:55 ~high:60;
  Handle.recompute_view_until_stable test.handle;
  Handle.show_diff test.handle;
  [%expect
    {|
          </td>
          <td colspan="1"
              class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
              freeze_width=((set <fun>)(reset <fun>))
              size_tracker=<fun>>
            <div class="column_header_hash_replaced_in_test" onclick>
              <span> ◇  b </span>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    <div class="partial_render_table_body_hash_replaced_in_test" bounds-change=<opaque>>
      <div>
        <div>
          <div class="prt-table-row" onclick>
-|          <div class="cell_hash_replaced_in_test prt-table-cell"> 51 </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 55 </div>
            <div class="cell_hash_replaced_in_test prt-table-cell">
              <input oninput> </input>
              hi
            </div>
-|          <div class="cell_hash_replaced_in_test prt-table-cell"> 25.000000 </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 27.000000 </div>
          </div>
          <div class="prt-table-row" onclick>
-|          <div class="cell_hash_replaced_in_test prt-table-cell"> 52 </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 56 </div>
            <div class="cell_hash_replaced_in_test prt-table-cell">
              <input oninput> </input>
              hi
            </div>
-|          <div class="cell_hash_replaced_in_test prt-table-cell"> 26.000000 </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 28.000000 </div>
+|        </div>
+|        <div class="prt-table-row" onclick>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 57 </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell">
+|            <input oninput> </input>
+|            hi
+|          </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 28.000000 </div>
+|        </div>
+|        <div class="prt-table-row" onclick>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 58 </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell">
+|            <input oninput> </input>
+|            hi
+|          </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 29.000000 </div>
+|        </div>
+|        <div class="prt-table-row" onclick>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 59 </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell">
+|            <input oninput> </input>
+|            hi
+|          </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 29.000000 </div>
+|        </div>
+|        <div class="prt-table-row" onclick>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 60 </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell">
+|            <input oninput> </input>
+|            hi
+|          </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 30.000000 </div>
+|        </div>
+|        <div class="prt-table-row" onclick>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 61 </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell">
+|            <input oninput> </input>
+|            hi
+|          </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 30.000000 </div>
+|        </div>
+|        <div class="prt-table-row" onclick>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 62 </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell">
+|            <input oninput> </input>
+|            hi
+|          </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 31.000000 </div>
          </div>
        </div>
      </div>
    </div>
  </div> |}]
;;

let%expect_test "typing into a column, leaving that column, and then coming back. " =
  let test =
    Test.create ~map:big_map ~visible_range:(50, 50) (Test.Component.default ())
  in
  Handle.recompute_view_until_stable test.handle;
  Handle.store_view test.handle;
  Handle.input_text
    test.handle
    ~get_vdom:Table.Result.view
    ~selector:".prt-table-cell:nth-child(2) input"
    ~text:"hello world";
  Handle.recompute_view_until_stable test.handle;
  Handle.show_diff test.handle;
  [%expect
    {|
              freeze_width=((set <fun>)(reset <fun>))
              size_tracker=<fun>>
            <div class="column_header_hash_replaced_in_test" onclick>
              <span> ◇  b </span>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    <div class="partial_render_table_body_hash_replaced_in_test" bounds-change=<opaque>>
      <div>
        <div>
          <div class="prt-table-row" onclick>
            <div class="cell_hash_replaced_in_test prt-table-cell"> 51 </div>
            <div class="cell_hash_replaced_in_test prt-table-cell">
              <input oninput> </input>
-|            hi
+|            hi hello world
            </div>
            <div class="cell_hash_replaced_in_test prt-table-cell"> 25.000000 </div>
          </div>
          <div class="prt-table-row" onclick>
            <div class="cell_hash_replaced_in_test prt-table-cell"> 52 </div>
            <div class="cell_hash_replaced_in_test prt-table-cell">
              <input oninput> </input>
              hi
            </div>
            <div class="cell_hash_replaced_in_test prt-table-cell"> 26.000000 </div>
          </div>
        </div>
      </div>
    </div>
  </div> |}];
  (* move out of bounds (really 99-25 through 100) *)
  Test.set_bounds test ~low:99 ~high:99;
  Handle.recompute_view_until_stable test.handle;
  Handle.store_view test.handle;
  (* move back into bounds *)
  Test.set_bounds test ~low:50 ~high:50;
  Handle.recompute_view_until_stable test.handle;
  Handle.show test.handle;
  [%expect
    {|
<div class="partial-render-table-bonsai_path_replaced_in_test partial_render_table_container_hash_replaced_in_test">
  <table class="partial_render_table_header_hash_replaced_in_test prt-table-header"
         bounds-change=<opaque>>
    <tbody>
      <tr>
        <td colspan="1"
            class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
            freeze_width=((set <fun>)(reset <fun>))
            size_tracker=<fun>>
          <div class="column_header_hash_replaced_in_test" onclick>
            <span> ◇  key </span>
          </div>
        </td>
        <td colspan="1"
            class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
            freeze_width=((set <fun>)(reset <fun>))
            size_tracker=<fun>>
          <div> a </div>
        </td>
        <td colspan="1"
            class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
            freeze_width=((set <fun>)(reset <fun>))
            size_tracker=<fun>>
          <div class="column_header_hash_replaced_in_test" onclick>
            <span> ◇  b </span>
          </div>
        </td>
      </tr>
    </tbody>
  </table>
  <div class="partial_render_table_body_hash_replaced_in_test" bounds-change=<opaque>>
    <div>
      <div>
        <div class="prt-table-row" onclick>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 51 </div>
          <div class="cell_hash_replaced_in_test prt-table-cell">
            <input oninput> </input>
            hi hello world
          </div>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 25.000000 </div>
        </div>
        <div class="prt-table-row" onclick>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 52 </div>
          <div class="cell_hash_replaced_in_test prt-table-cell">
            <input oninput> </input>
            hi
          </div>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 26.000000 </div>
        </div>
      </div>
    </div>
  </div>
</div> |}]
;;

let%expect_test "table body is not recomputed more often than necessary" =
  (* The size_tracker and visibility hooks that PRT uses can be called by the browser more
     often than one would expect. For instance, if one places an element over the table,
     it causes the size_tracker hook on every column to fire. If you have a large table
     with lots of columns and lots of rows, it can be expensive to recompute the table
     body n times, once for each column. *)
  let test = Test.create (Test.Component.default ()) in
  Test.print_message_on_result_recomputation test;
  Test.resize_column test ~idx:0 ~width:1.;
  Test.set_bounds test ~low:0 ~high:300;
  Handle.flush test.handle;
  [%expect {|
    Initialized
    Changed |}];
  (* Sanity check: re-stabilizing after doing no actions does not cause recomputation *)
  Handle.flush test.handle;
  [%expect {||}];
  (* Re-setting a column to its existing width should not cause a re-fire *)
  Test.resize_column test ~idx:0 ~width:1.;
  Handle.flush test.handle;
  [%expect {| |}];
  (* Re-setting the bounds to the same value should not cause a re-fire *)
  Test.set_bounds test ~low:0 ~high:300;
  Handle.flush test.handle;
  [%expect {||}]
;;

let%expect_test "table body is not recomputed more often than necessary" =
  let test =
    Test.create (fun input _filter_var ->
      let component =
        let%sub collation =
          Table_expert.collate
            ~filter_equal:[%compare.equal: unit]
            ~order_equal:[%compare.equal: unit]
            ~filter_to_predicate:(fun () -> None)
            ~order_to_compare:(fun () -> Unchanged)
            input
            (Value.return
               { Incr_map_collate.Collate.filter = ()
               ; order = ()
               ; key_range = All_rows
               ; rank_range = All_rows
               })
        in
        let columns =
          [ Table_expert.Columns.Dynamic_cells.column
              ~label:(Value.return (Vdom.Node.text "key"))
              ~cell:(fun ~key ~data:_ ->
                let%arr key = key in
                Vdom.Node.textf "%d" key)
              ()
          ]
          |> Table_expert.Columns.Dynamic_cells.lift
        in
        Table_expert.component
          (module Int)
          ~focus:
            (By_row
               { on_change = Value.return (Fn.const Effect.Ignore)
               ; compute_presence = (fun focus -> return focus)
               })
          ~row_height:(`Px 10)
          ~columns
          collation
      in
      { Test.Component.component
      ; get_vdom = Table_expert.Result.view
      ; get_testing = Table_expert.Result.for_testing
      ; get_inject = Shared.Test.Component.get_inject_expert
      ; get_focus = Table_expert.Result.focus
      })
  in
  Test.print_message_on_result_recomputation test;
  Test.resize_column test ~idx:0 ~width:1.;
  Test.set_bounds test ~low:0 ~high:300;
  Handle.flush test.handle;
  [%expect {|
    Initialized
    Changed |}];
  (* Sanity check: re-stabilizing after doing no actions does not cause recomputation *)
  Handle.flush test.handle;
  [%expect {||}];
  (* Changing the bounds should not cause a re-fire because we are doing our own collation
     and don't rely on result.bounds. *)
  Test.set_bounds test ~low:100 ~high:300;
  Handle.flush test.handle;
  [%expect {||}]
;;

let%expect_test "test is browser" =
  let open Js_of_ocaml in
  Dom_html.document |> Obj.magic |> Js_of_ocaml.Js.Optdef.test |> printf "%b";
  [%expect {| false |}]
;;

let%expect_test "sorting" =
  let test = Test.create (Test.Component.default ()) in
  Handle.recompute_view_until_stable test.handle;
  Handle.show test.handle;
  [%expect
    {|
<div class="partial-render-table-bonsai_path_replaced_in_test partial_render_table_container_hash_replaced_in_test">
  <table class="partial_render_table_header_hash_replaced_in_test prt-table-header"
         bounds-change=<opaque>>
    <tbody>
      <tr>
        <td colspan="1"
            class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
            freeze_width=((set <fun>)(reset <fun>))
            size_tracker=<fun>>
          <div class="column_header_hash_replaced_in_test" onclick>
            <span> ◇  key </span>
          </div>
        </td>
        <td colspan="1"
            class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
            freeze_width=((set <fun>)(reset <fun>))
            size_tracker=<fun>>
          <div> a </div>
        </td>
        <td colspan="1"
            class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
            freeze_width=((set <fun>)(reset <fun>))
            size_tracker=<fun>>
          <div class="column_header_hash_replaced_in_test" onclick>
            <span> ◇  b </span>
          </div>
        </td>
      </tr>
    </tbody>
  </table>
  <div class="partial_render_table_body_hash_replaced_in_test" bounds-change=<opaque>>
    <div>
      <div>
        <div class="prt-table-row" onclick>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 0 </div>
          <div class="cell_hash_replaced_in_test prt-table-cell">
            <input oninput> </input>
            hello
          </div>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 1.000000 </div>
        </div>
        <div class="prt-table-row" onclick>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 1 </div>
          <div class="cell_hash_replaced_in_test prt-table-cell">
            <input oninput> </input>
            there
          </div>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 2.000000 </div>
        </div>
        <div class="prt-table-row" onclick>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 4 </div>
          <div class="cell_hash_replaced_in_test prt-table-cell">
            <input oninput> </input>
            world
          </div>
          <div class="cell_hash_replaced_in_test prt-table-cell"> 2.000000 </div>
        </div>
      </div>
    </div>
  </div>
</div> |}];
  (* this one is the key, clicking on it does nothing (it's already sorted by the key) *)
  Handle.click_on test.handle ~selector:"td:nth-child(1) > div" ~get_vdom:test.get_vdom;
  Handle.show_diff test.handle;
  [%expect
    {|
      <div class="partial-render-table-bonsai_path_replaced_in_test partial_render_table_container_hash_replaced_in_test">
        <table class="partial_render_table_header_hash_replaced_in_test prt-table-header"
               bounds-change=<opaque>>
          <tbody>
            <tr>
              <td colspan="1"
                  class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
                  freeze_width=((set <fun>)(reset <fun>))
                  size_tracker=<fun>>
                <div class="column_header_hash_replaced_in_test" onclick>
    -|            <span> ◇  key </span>
    +|            <span> ⬘  key </span>
                </div>
              </td>
              <td colspan="1"
                  class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
                  freeze_width=((set <fun>)(reset <fun>))
                  size_tracker=<fun>>
                <div> a </div>
              </td>
              <td colspan="1"
                  class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
                  freeze_width=((set <fun>)(reset <fun>))
                  size_tracker=<fun>>
                <div class="column_header_hash_replaced_in_test" onclick>
                  <span> ◇  b </span>
                </div>
              </td> |}];
  (* this one actually does stuff, click on it twice for a reverse sort *)
  Handle.click_on test.handle ~selector:"td:nth-child(3) > div" ~get_vdom:test.get_vdom;
  Handle.click_on test.handle ~selector:"td:nth-child(3) > div" ~get_vdom:test.get_vdom;
  Handle.show_diff test.handle;
  [%expect
    {|
  <div class="partial-render-table-bonsai_path_replaced_in_test partial_render_table_container_hash_replaced_in_test">
    <table class="partial_render_table_header_hash_replaced_in_test prt-table-header"
           bounds-change=<opaque>>
      <tbody>
        <tr>
          <td colspan="1"
              class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
              freeze_width=((set <fun>)(reset <fun>))
              size_tracker=<fun>>
            <div class="column_header_hash_replaced_in_test" onclick>
-|            <span> ⬘  key </span>
+|            <span> ◇  key </span>
            </div>
          </td>
          <td colspan="1"
              class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
              freeze_width=((set <fun>)(reset <fun>))
              size_tracker=<fun>>
            <div> a </div>
          </td>
          <td colspan="1"
              class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
              freeze_width=((set <fun>)(reset <fun>))
              size_tracker=<fun>>
            <div class="column_header_hash_replaced_in_test" onclick>
-|            <span> ◇  b </span>
+|            <span> ⬙  b </span>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    <div class="partial_render_table_body_hash_replaced_in_test" bounds-change=<opaque>>
      <div>
        <div>
-|        <div class="prt-table-row" onclick>
-|          <div class="cell_hash_replaced_in_test prt-table-cell"> 0 </div>
-|          <div class="cell_hash_replaced_in_test prt-table-cell">
-|            <input oninput> </input>
-|            hello
-|          </div>
-|          <div class="cell_hash_replaced_in_test prt-table-cell"> 1.000000 </div>
-|        </div>
          <div class="prt-table-row" onclick>
            <div class="cell_hash_replaced_in_test prt-table-cell"> 1 </div>
            <div class="cell_hash_replaced_in_test prt-table-cell">
              <input oninput> </input>
              there
            </div>
            <div class="cell_hash_replaced_in_test prt-table-cell"> 2.000000 </div>
          </div>
          <div class="prt-table-row" onclick>
            <div class="cell_hash_replaced_in_test prt-table-cell"> 4 </div>
            <div class="cell_hash_replaced_in_test prt-table-cell">
              <input oninput> </input>
              world
            </div>
            <div class="cell_hash_replaced_in_test prt-table-cell"> 2.000000 </div>
          </div>
+|        <div class="prt-table-row" onclick>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 0 </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell">
+|            <input oninput> </input>
+|            hello
+|          </div>
+|          <div class="cell_hash_replaced_in_test prt-table-cell"> 1.000000 </div>
+|        </div>
        </div>
      </div>
    </div>
  </div> |}];
  Handle.click_on test.handle ~selector:"td:nth-child(3) > div" ~get_vdom:test.get_vdom;
  Handle.show_diff test.handle;
  [%expect
    {|
                  size_tracker=<fun>>
                <div class="column_header_hash_replaced_in_test" onclick>
                  <span> ◇  key </span>
                </div>
              </td>
              <td colspan="1"
                  class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
                  freeze_width=((set <fun>)(reset <fun>))
                  size_tracker=<fun>>
                <div> a </div>
              </td>
              <td colspan="1"
                  class="header_label_hash_replaced_in_test leaf_header_hash_replaced_in_test"
                  freeze_width=((set <fun>)(reset <fun>))
                  size_tracker=<fun>>
                <div class="column_header_hash_replaced_in_test" onclick>
    -|            <span> ⬙  b </span>
    +|            <span> ◇  b </span>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
        <div class="partial_render_table_body_hash_replaced_in_test" bounds-change=<opaque>>
          <div>
            <div>
    +|        <div class="prt-table-row" onclick>
    +|          <div class="cell_hash_replaced_in_test prt-table-cell"> 0 </div>
    +|          <div class="cell_hash_replaced_in_test prt-table-cell">
    +|            <input oninput> </input>
    +|            hello
    +|          </div>
    +|          <div class="cell_hash_replaced_in_test prt-table-cell"> 1.000000 </div>
    +|        </div>
              <div class="prt-table-row" onclick>
                <div class="cell_hash_replaced_in_test prt-table-cell"> 1 </div>
                <div class="cell_hash_replaced_in_test prt-table-cell">
                  <input oninput> </input>
                  there
                </div>
                <div class="cell_hash_replaced_in_test prt-table-cell"> 2.000000 </div>
              </div>
              <div class="prt-table-row" onclick>
                <div class="cell_hash_replaced_in_test prt-table-cell"> 4 </div>
                <div class="cell_hash_replaced_in_test prt-table-cell">
                  <input oninput> </input>
                  world
                </div>
                <div class="cell_hash_replaced_in_test prt-table-cell"> 2.000000 </div>
              </div>
    -|        <div class="prt-table-row" onclick>
    -|          <div class="cell_hash_replaced_in_test prt-table-cell"> 0 </div>
    -|          <div class="cell_hash_replaced_in_test prt-table-cell">
    -|            <input oninput> </input>
    -|            hello
    -|          </div>
    -|          <div class="cell_hash_replaced_in_test prt-table-cell"> 1.000000 </div>
    -|        </div>
            </div>
          </div>
        </div>
      </div> |}]
;;
