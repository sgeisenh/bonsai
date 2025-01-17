open! Core
open! Import
open Bonsai.For_open
open Bonsai.Let_syntax
open Proc

(* A big focus of the tests in this file is about making sure that there are no
   "in-transit" frames - frames during which the result has some intermediate
   value because lifecycle events haven't yet run. To accomplish this goal, all
   the tests have been written in a [Common] functor, which accepts a module
   that specifies what [Handle.show] should do. We supply three different
   answers to that question:

   - it should do what it normally does.
   - it should recompute_view an extra time prior to calling Handle.show.
   - it should recompute_view_until_stable prior to calling Handle.show.

   We do this to ensure that all the functions being tested behave the same no
   matter which one of those options is chosen. *)

let advance_by_sec handle seconds =
  Handle.advance_clock_by handle (Time_ns.Span.of_sec seconds)
;;

let%test_module "Bonsai_extra.with_last_modified_time" =
  (module struct
    module Common (M : sig
        val with_last_modified_time
          :  equal:('a -> 'a -> bool)
          -> 'a Value.t
          -> ('a * Time_ns.t) Computation.t

        val show_handle : ('a, 'b) Handle.t -> unit
      end) =
    struct
      let show = M.show_handle

      let%expect_test _ =
        let v' = Bonsai.Var.create 1 in
        let v = Bonsai.Var.value v' in
        let c = M.with_last_modified_time ~equal:Int.equal v in
        let handle =
          Handle.create
            (Result_spec.sexp
               (module struct
                 type t = int * Time_ns.Alternate_sexp.t [@@deriving sexp]
               end))
            c
        in
        show handle;
        [%expect {| (1 "1970-01-01 00:00:00Z") |}];
        advance_by_sec handle 1.0;
        show handle;
        [%expect {| (1 "1970-01-01 00:00:00Z") |}];
        Bonsai.Var.set v' 2;
        show handle;
        [%expect {| (2 "1970-01-01 00:00:01Z") |}];
        Bonsai.Var.set v' 3;
        advance_by_sec handle 1.0;
        show handle;
        [%expect {| (3 "1970-01-01 00:00:02Z") |}];
        show handle;
        [%expect {| (3 "1970-01-01 00:00:02Z") |}]
      ;;

      let%expect_test _ =
        let v' = Bonsai.Var.create 1 in
        let on' = Bonsai.Var.create true in
        let v = Bonsai.Var.value v' in
        let on = Bonsai.Var.value on' in
        let c =
          match%sub on with
          | true ->
            let%sub x = M.with_last_modified_time ~equal:Int.equal v in
            let%arr x = x in
            Some x
          | false -> Bonsai.const None
        in
        let handle =
          Handle.create
            (Result_spec.sexp
               (module struct
                 type t = (int * Time_ns.Alternate_sexp.t) option [@@deriving sexp]
               end))
            c
        in
        show handle;
        [%expect {| ((1 "1970-01-01 00:00:00Z")) |}];
        advance_by_sec handle 1.0;
        show handle;
        [%expect {| ((1 "1970-01-01 00:00:00Z")) |}];
        Bonsai.Var.set on' false;
        show handle;
        [%expect {| () |}];
        Bonsai.Var.set on' true;
        show handle;
        [%expect {| ((1 "1970-01-01 00:00:01Z")) |}];
        Bonsai.Var.set on' false;
        show handle;
        [%expect {| () |}];
        advance_by_sec handle 1.0;
        show handle;
        [%expect {| () |}];
        Bonsai.Var.set on' true;
        show handle;
        [%expect {| ((1 "1970-01-01 00:00:02Z")) |}];
        advance_by_sec handle 1.0;
        show handle;
        [%expect {| ((1 "1970-01-01 00:00:02Z")) |}];
        Bonsai.Var.set v' 2;
        show handle;
        [%expect {| ((2 "1970-01-01 00:00:03Z")) |}]
      ;;
    end

    module _ = Common (struct
        let with_last_modified_time = Bonsai_extra.with_last_modified_time
        let show_handle = Handle.show
      end)

    module _ = Common (struct
        let with_last_modified_time = Bonsai_extra.with_last_modified_time

        let show_handle handle =
          Handle.recompute_view handle;
          Handle.show handle
        ;;
      end)

    module _ = Common (struct
        let with_last_modified_time = Bonsai_extra.with_last_modified_time

        let show_handle handle =
          Handle.recompute_view_until_stable handle;
          Handle.show handle
        ;;
      end)
  end)
;;

let%test_module "Bonsai_extra.is_stable" =
  (module struct
    module Common (M : sig
        val is_stable
          :  equal:('a -> 'a -> bool)
          -> 'a Value.t
          -> time_to_stable:Time_ns.Span.t
          -> bool Computation.t

        val show_handle : ('a, 'b) Handle.t -> unit
      end) =
    struct
      let show = M.show_handle

      let%expect_test _ =
        let v' = Bonsai.Var.create 1 in
        let v = Bonsai.Var.value v' in
        let c =
          let%sub is_stable =
            M.is_stable ~equal:Int.equal v ~time_to_stable:(Time_ns.Span.of_sec 1.0)
          in
          return (Value.both v is_stable)
        in
        let handle =
          Handle.create
            (Result_spec.sexp
               (module struct
                 type t = int * bool [@@deriving sexp]
               end))
            c
        in
        show handle;
        [%expect {| (1 false) |}];
        advance_by_sec handle 1.0;
        show handle;
        [%expect {| (1 true) |}];
        Bonsai.Var.set v' 2;
        show handle;
        [%expect {| (2 false) |}];
        advance_by_sec handle 0.5;
        show handle;
        [%expect {| (2 false) |}];
        Bonsai.Var.set v' 3;
        show handle;
        [%expect {| (3 false) |}];
        advance_by_sec handle 0.5;
        show handle;
        [%expect {| (3 false) |}];
        advance_by_sec handle 0.5;
        show handle;
        [%expect {| (3 true) |}];
        Bonsai.Var.set v' 4;
        show handle;
        [%expect {| (4 false) |}];
        advance_by_sec handle 1.0;
        Bonsai.Var.set v' 5;
        show handle;
        [%expect {| (5 false) |}];
        advance_by_sec handle 1.0;
        show handle;
        [%expect {| (5 true) |}];
        advance_by_sec handle 0.5;
        Bonsai.Var.set v' 4;
        show handle;
        [%expect {| (4 false) |}];
        advance_by_sec handle 0.5;
        Bonsai.Var.set v' 5;
        show handle;
        [%expect {| (5 false) |}]
      ;;

      let%expect_test _ =
        let v' = Bonsai.Var.create 1 in
        let on' = Bonsai.Var.create true in
        let v = Bonsai.Var.value v' in
        let on = Bonsai.Var.value on' in
        let c =
          match%sub on with
          | true ->
            let%sub x =
              M.is_stable ~equal:Int.equal v ~time_to_stable:(Time_ns.Span.of_sec 1.0)
            in
            let%arr x = x
            and v = v in
            Some (x, v)
          | false -> Bonsai.const None
        in
        let handle =
          Handle.create
            (Result_spec.sexp
               (module struct
                 type t = (bool * int) option [@@deriving sexp]
               end))
            c
        in
        show handle;
        [%expect {| ((false 1)) |}];
        advance_by_sec handle 1.0;
        show handle;
        [%expect {| ((true 1)) |}];
        Bonsai.Var.set on' false;
        show handle;
        [%expect {| () |}];
        Bonsai.Var.set on' true;
        show handle;
        [%expect {| ((false 1)) |}]
      ;;

      let%expect_test {|zero values for the timespan should be permitted (but issue a warning) and always return false |}
        =
        let v' = Bonsai.Var.create 1 in
        let on' = Bonsai.Var.create true in
        let v = Bonsai.Var.value v' in
        let on = Bonsai.Var.value on' in
        let c =
          match%sub on with
          | true ->
            let%sub x =
              M.is_stable ~equal:Int.equal v ~time_to_stable:(Time_ns.Span.of_sec 0.0)
            in
            let%arr x = x
            and v = v in
            Some (x, v)
          | false -> Bonsai.const None
        in
        let handle =
          Handle.create
            (Result_spec.sexp
               (module struct
                 type t = (bool * int) option [@@deriving sexp]
               end))
            c
        in
        [%expect {| "Bonsai_extra.is_stable: [time_to_stable] should be positive" |}];
        show handle;
        [%expect {| ((false 1)) |}];
        advance_by_sec handle 1.0;
        show handle;
        [%expect {| ((false 1)) |}];
        Bonsai.Var.set on' false;
        show handle;
        [%expect {| () |}];
        Bonsai.Var.set on' true;
        show handle;
        [%expect {| ((false 1)) |}]
      ;;

      let%expect_test {|negative values for the timespan should be permitted (but issue a warning) and always return false |}
        =
        let v' = Bonsai.Var.create 1 in
        let v = Bonsai.Var.value v' in
        let c =
          M.is_stable ~equal:Int.equal v ~time_to_stable:(Time_ns.Span.of_sec (-1.0))
        in
        [%expect {| "Bonsai_extra.is_stable: [time_to_stable] should be positive" |}];
        let handle = Handle.create (Result_spec.sexp (module Bool)) c in
        show handle;
        [%expect {| false |}]
      ;;
    end

    module _ = Common (struct
        let is_stable = Bonsai_extra.is_stable
        let show_handle = Handle.show
      end)

    module _ = Common (struct
        let is_stable = Bonsai_extra.is_stable

        let show_handle handle =
          Handle.recompute_view handle;
          Handle.show handle
        ;;
      end)

    module _ = Common (struct
        let is_stable = Bonsai_extra.is_stable

        let show_handle handle =
          Handle.recompute_view_until_stable handle;
          Handle.show handle
        ;;
      end)
  end)
;;

let%test_module "Bonsai.most_recent_value_satisfying" =
  (module struct
    module Common (M : sig
        val most_recent_value_satisfying
          :  (module Bonsai.Model with type t = 'a)
          -> 'a Value.t
          -> condition:('a -> bool)
          -> 'a option Computation.t

        val show_handle : ('a, 'b) Handle.t -> unit
      end) =
    struct
      let show = M.show_handle

      let%expect_test _ =
        let v' = Bonsai.Var.create 1 in
        let v = Bonsai.Var.value v' in
        let c =
          M.most_recent_value_satisfying (module Int) v ~condition:(fun x -> x % 2 = 0)
        in
        let handle =
          Handle.create
            (Result_spec.sexp
               (module struct
                 type t = int option [@@deriving sexp]
               end))
            c
        in
        show handle;
        [%expect {| () |}];
        Bonsai.Var.set v' 2;
        show handle;
        [%expect {| (2) |}];
        Bonsai.Var.set v' 3;
        show handle;
        [%expect {| (2) |}];
        Bonsai.Var.set v' 4;
        show handle;
        [%expect {| (4) |}]
      ;;

      let%expect_test _ =
        let v' = Bonsai.Var.create 1 in
        let on' = Bonsai.Var.create true in
        let v = Bonsai.Var.value v' in
        let on = Bonsai.Var.value on' in
        let c =
          match%sub on with
          | true ->
            let%sub x =
              M.most_recent_value_satisfying
                (module Int)
                v
                ~condition:(fun x -> x % 2 = 0)
            in
            let%arr x = x in
            Some x
          | false -> Bonsai.const None
        in
        let handle =
          Handle.create
            (Result_spec.sexp
               (module struct
                 type t = int option option [@@deriving sexp]
               end))
            c
        in
        show handle;
        [%expect {| (()) |}];
        Bonsai.Var.set v' 2;
        show handle;
        [%expect {| ((2)) |}];
        Bonsai.Var.set on' false;
        show handle;
        [%expect {| () |}];
        Bonsai.Var.set v' 3;
        show handle;
        [%expect {| () |}];
        Bonsai.Var.set on' true;
        show handle;
        [%expect {| ((2)) |}]
      ;;
    end

    module _ = Common (struct
        let most_recent_value_satisfying = Bonsai.most_recent_value_satisfying
        let show_handle = Handle.show
      end)

    module _ = Common (struct
        let most_recent_value_satisfying = Bonsai.most_recent_value_satisfying

        let show_handle handle =
          Handle.recompute_view handle;
          Handle.show handle
        ;;
      end)

    module _ = Common (struct
        let most_recent_value_satisfying = Bonsai.most_recent_value_satisfying

        let show_handle handle =
          Handle.recompute_view_until_stable handle;
          Handle.show handle
        ;;
      end)
  end)
;;

let%test_module "Bonsai_extra.value_stability" =
  (module struct
    let alternate_value_stability_implementation
          (type a)
          (module M : Bonsai.Model with type t = a)
          input
          ~time_to_stable
      =
      let%sub input =
        (* apply cutoff as an optimistic performance improvement *)
        Bonsai.Incr.value_cutoff input ~equal:M.equal
      in
      let module T = struct
        module Model = struct
          type stability =
            | Inactive of { previously_stable : M.t option }
            | Unstable of
                { previously_stable : M.t option
                ; unstable_value : M.t
                }
            | Stable of M.t
          [@@deriving sexp, equal]

          let set_value new_value = function
            | Inactive { previously_stable } ->
              Unstable { previously_stable; unstable_value = new_value }
            | Stable stable ->
              Unstable { previously_stable = Some stable; unstable_value = new_value }
            | Unstable { previously_stable; unstable_value = _ } ->
              Unstable { previously_stable; unstable_value = new_value }
          ;;

          type t =
            { stability : stability
            ; time_to_next_stable : Time_ns.Alternate_sexp.t option
            }
          [@@deriving sexp, equal]

          let default =
            { stability = Inactive { previously_stable = None }
            ; time_to_next_stable = None
            }
          ;;
        end

        module Action = struct
          type t =
            | Deactivate
            | Bounce of M.t * Time_ns.Alternate_sexp.t
            | Set_stable of M.t * Time_ns.Alternate_sexp.t
          [@@deriving sexp_of]
        end
      end
      in
      let open T in
      let%sub { stability; time_to_next_stable }, inject =
        Bonsai.state_machine0
          (module Model)
          (module Action)
          ~default_model:Model.default
          ~apply_action:(fun ~inject:_ ~schedule_event:_ model action ->
            match action, model with
            | Deactivate, { stability; _ } ->
              let stability =
                match stability with
                | Inactive _ -> stability
                | Unstable { previously_stable; _ } -> Inactive { previously_stable }
                | Stable stable -> Inactive { previously_stable = Some stable }
              in
              (* Deactivating this component will automatically cause the value to be
                 considered unstable.  This is because we have no way to tell what is
                 happening to the value when this component is inactive, and I consider
                 it safer to assume instability than to assume stability. *)
              { stability; time_to_next_stable = None }
            | Bounce (new_value, now), { stability; _ } ->
              (* Bouncing will cause the value to become unstable, and set the
                 time-to-next-stable to the provided value. *)
              let stability = Model.set_value new_value stability in
              let time_to_next_stable = Some (Time_ns.add now time_to_stable) in
              { stability; time_to_next_stable }
            | Set_stable (stable, now), { stability; time_to_next_stable } ->
              (* Sets the value which is considered to be stable and resets
                 the time until next stability. *)
              (match stability with
               | Inactive { previously_stable } ->
                 { stability = Unstable { previously_stable; unstable_value = stable }
                 ; time_to_next_stable = Some (Time_ns.add now time_to_stable)
                 }
               | Stable previously_stable ->
                 if M.equal previously_stable stable
                 then { stability = Stable stable; time_to_next_stable = None }
                 else
                   { stability =
                       Unstable
                         { unstable_value = stable
                         ; previously_stable = Some previously_stable
                         }
                   ; time_to_next_stable = Some (Time_ns.add now time_to_stable)
                   }
               | Unstable { unstable_value; previously_stable } ->
                 let candidate_time_to_next_stable = Time_ns.add now time_to_stable in
                 (match M.equal unstable_value stable, time_to_next_stable with
                  | true, Some time_to_next_stable
                    when Time_ns.( >= ) now time_to_next_stable ->
                    { stability = Stable stable; time_to_next_stable = None }
                  | _ ->
                    { stability = Unstable { unstable_value = stable; previously_stable }
                    ; time_to_next_stable = Some candidate_time_to_next_stable
                    })))
      in
      let%sub get_current_time = Bonsai.Clock.get_current_time in
      let%sub bounce =
        (* [bounce] is an effect which, when scheduled, will bounce the
           state-machine and set the time-until-stable to the current wallclock
           time plus the provided offset *)
        let%arr get_current_time = get_current_time
        and inject = inject
        and input = input in
        let%bind.Effect now = get_current_time in
        inject (Bounce (input, now))
      in
      let%sub () =
        (* the input value changing triggers a bounce *)
        let%sub callback =
          let%arr bounce = bounce in
          fun _ -> bounce
        in
        Bonsai.Edge.on_change (module M) input ~callback
      in
      let%sub () =
        let%sub on_deactivate =
          let%arr inject = inject in
          inject Deactivate
        in
        (* activating the component bounces it to reset the timer *)
        Bonsai.Edge.lifecycle ~on_deactivate ~on_activate:bounce ()
      in
      let%sub () =
        match%sub time_to_next_stable with
        | None -> Bonsai.const ()
        | Some next_stable ->
          let%sub callback =
            let%arr inject = inject
            and input = input
            and get_current_time = get_current_time
            and bounce = bounce in
            fun (prev : Bonsai.Clock.Before_or_after.t option)
              (cur : Bonsai.Clock.Before_or_after.t) ->
              match prev, cur with
              | Some Before, After ->
                let%bind.Effect now = get_current_time in
                inject (Set_stable (input, now))
              | None, After ->
                print_s [%message "BUG" [%here] "clock moves straight to 'after'"];
                bounce
              | _ -> Effect.Ignore
          in
          let%sub before_or_after = Bonsai.Clock.at next_stable in
          Bonsai.Edge.on_change'
            (module Bonsai.Clock.Before_or_after)
            before_or_after
            ~callback
      in
      let%arr stability = stability
      and input = input in
      match stability with
      | Stable input' when M.equal input' input -> Bonsai_extra.Stability.Stable input
      | Stable previously_stable ->
        (* Even if the state-machine claims that the value is stable, we can still witness
           instability one frame before the lifecycle events run. *)
        Unstable { previously_stable = Some previously_stable; unstable_value = input }
      | Unstable { previously_stable; unstable_value = _ } ->
        Unstable { previously_stable; unstable_value = input }
      | Inactive { previously_stable } ->
        Unstable { previously_stable; unstable_value = input }
    ;;

    module Common (M : sig
        val value_stability
          :  (module Bonsai.Model with type t = 'a)
          -> 'a Value.t
          -> time_to_stable:Time_ns.Span.t
          -> 'a Bonsai_extra.Stability.t Computation.t

        val show_handle : ('a, 'b) Handle.t -> unit
      end) =
    struct
      let show = M.show_handle

      let%expect_test _ =
        let v' = Bonsai.Var.create 1 in
        let v = Bonsai.Var.value v' in
        let c =
          M.value_stability (module Int) v ~time_to_stable:(Time_ns.Span.of_sec 1.0)
        in
        let handle =
          Handle.create
            (Result_spec.sexp
               (module struct
                 type t = int Bonsai_extra.Stability.t [@@deriving sexp]
               end))
            c
        in
        show handle;
        [%expect {| (Unstable (previously_stable ()) (unstable_value 1)) |}];
        advance_by_sec handle 1.0;
        show handle;
        [%expect {| (Stable 1) |}];
        Bonsai.Var.set v' 2;
        show handle;
        [%expect {| (Unstable (previously_stable (1)) (unstable_value 2)) |}];
        advance_by_sec handle 0.5;
        show handle;
        [%expect {| (Unstable (previously_stable (1)) (unstable_value 2)) |}];
        Bonsai.Var.set v' 3;
        show handle;
        [%expect {| (Unstable (previously_stable (1)) (unstable_value 3)) |}];
        advance_by_sec handle 0.5;
        show handle;
        [%expect {| (Unstable (previously_stable (1)) (unstable_value 3)) |}];
        advance_by_sec handle 0.5;
        show handle;
        [%expect {| (Stable 3) |}];
        Bonsai.Var.set v' 4;
        show handle;
        [%expect {| (Unstable (previously_stable (3)) (unstable_value 4)) |}];
        advance_by_sec handle 1.0;
        Bonsai.Var.set v' 5;
        show handle;
        [%expect {| (Unstable (previously_stable (3)) (unstable_value 5)) |}];
        advance_by_sec handle 1.0;
        show handle;
        [%expect {| (Stable 5) |}];
        advance_by_sec handle 0.5;
        Bonsai.Var.set v' 4;
        show handle;
        [%expect {| (Unstable (previously_stable (5)) (unstable_value 4)) |}];
        advance_by_sec handle 0.5;
        Bonsai.Var.set v' 5;
        show handle;
        [%expect {| (Unstable (previously_stable (5)) (unstable_value 5)) |}]
      ;;

      let%expect_test _ =
        let v' = Bonsai.Var.create 1 in
        let on' = Bonsai.Var.create true in
        let v = Bonsai.Var.value v' in
        let on = Bonsai.Var.value on' in
        let c =
          match%sub on with
          | true ->
            let%sub x =
              M.value_stability (module Int) v ~time_to_stable:(Time_ns.Span.of_sec 1.0)
            in
            let%arr x = x in
            Some x
          | false -> Bonsai.const None
        in
        let handle =
          Handle.create
            (Result_spec.sexp
               (module struct
                 type t = int Bonsai_extra.Stability.t option [@@deriving sexp]
               end))
            c
        in
        show handle;
        [%expect {| ((Unstable (previously_stable ()) (unstable_value 1))) |}];
        advance_by_sec handle 1.0;
        show handle;
        [%expect {| ((Stable 1)) |}];
        Bonsai.Var.set on' false;
        show handle;
        [%expect {| () |}];
        Bonsai.Var.set on' true;
        show handle;
        [%expect {| ((Unstable (previously_stable (1)) (unstable_value 1))) |}]
      ;;
    end

    module _ = Common (struct
        (* The function reference below is an implementation that exists purely
           as a sanity check for the real implementation. If two vastly
           different implemenations always yield the same result, that's an
           encouraging sign. Sadly, this implementation relies on having a
           frame between certain real-world events, so we only run the tests
           with [recompute_view_until_stable] being called before Handle.show.
           (This downside is one reason why this is not the real
           implementation.) *)

        let value_stability = alternate_value_stability_implementation

        let show_handle handle =
          Handle.recompute_view_until_stable handle;
          Handle.show handle
        ;;
      end)

    module _ = Common (struct
        let value_stability = Bonsai_extra.value_stability
        let show_handle = Handle.show
      end)

    module _ = Common (struct
        let value_stability = Bonsai_extra.value_stability

        let show_handle handle =
          Handle.recompute_view handle;
          Handle.show handle
        ;;
      end)

    module _ = Common (struct
        let value_stability = Bonsai_extra.value_stability

        let show_handle handle =
          Handle.recompute_view_until_stable handle;
          Handle.show handle
        ;;
      end)
  end)
;;
