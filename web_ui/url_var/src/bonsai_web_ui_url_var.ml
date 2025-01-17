open! Core
open! Bonsai_web
module History = Html5_history.Opinionated

let get_uri () =
  let open Js_of_ocaml in
  Dom_html.window##.location##.href |> Js.to_string |> Uri.of_string
;;

module Components = struct
  type t =
    { path : string
    ; query : string list String.Map.t
    ; fragment : string option
    }
  [@@deriving sexp, equal]

  let create ?(path = "") ?(query = String.Map.empty) ?(fragment = None) () =
    { path; query; fragment }
  ;;

  let empty = create ()

  let to_path_and_query { path; query; fragment } =
    let uri = get_uri () in
    uri
    |> Fn.flip Uri.with_path path
    |> Fn.flip Uri.with_query (Map.to_alist query)
    |> Fn.flip Uri.with_fragment fragment
  ;;

  let of_uri uri =
    let path = Uri.path uri |> String.chop_prefix_if_exists ~prefix:"/" in
    let query =
      uri
      |> Uri.query
      |> String.Map.of_alist_multi
      |> Map.filter_map ~f:(function
        | [ value ] -> Some value
        | _ -> None)
    in
    let fragment = Uri.fragment uri in
    { path; query; fragment }
  ;;
end

module type T = sig
  type t [@@deriving sexp, equal]
end

module type S = sig
  include T

  val parse_exn : Components.t -> t
  val unparse : t -> Components.t
end

module type S_via_sexp = sig
  type t [@@deriving sexp, equal]
end

module Literally_just_a_gigantic_sexp (M : S_via_sexp) : S with type t = M.t = struct
  include M

  let query_param_name = "query"

  let parse_exn { Components.query; _ } =
    Map.find_exn query query_param_name |> List.hd_exn |> Sexp.of_string |> [%of_sexp: t]
  ;;

  let unparse t =
    let uri = get_uri () in
    let param = Sexp.to_string ([%sexp_of: t] t) in
    { Components.path = Uri.path uri
    ; query = String.Map.singleton query_param_name [ param ]
    ; fragment = Uri.fragment uri
    }
  ;;
end

module Original_components = Components

type 'a t =
  { var : 'a Bonsai.Var.t
  ; setter : 'a -> unit
  ; effect : 'a -> unit Effect.t
  }

let create_exn' (type a) (module S : S with type t = a) ~on_bad_uri =
  let module Uri_routing = struct
    include S

    let parse uri =
      let components = Components.of_uri uri in
      match parse_exn components with
      | a -> Ok a
      | exception e ->
        eprint_s [%message "couldn't parse uri" (components : Components.t) (e : exn)];
        Error `Not_found
    ;;

    let to_path_and_query uri = Components.to_path_and_query (unparse uri)
  end
  in
  let module History_state = struct
    type uri_routing = a

    include S

    include Binable.Of_sexpable_with_uuid (struct
        include S

        let caller_identity =
          Bin_prot.Shape.Uuid.of_string "918e794b-02c3-4f27-ad86-3f406a41fc4b"
        ;;
      end)

    let to_uri_routing = Fn.id
    let of_uri_routing = Fn.id
  end
  in
  let t =
    History.init_exn
      ~log_s:(ignore : Sexp.t -> unit)
      (module History_state)
      (module Uri_routing)
      ~on_bad_uri
  in
  let value = History.current t in
  let var = Bonsai.Var.create value in
  let setter = History.update t in
  let effect =
    Effect.of_sync_fun (fun a ->
      setter a;
      Bonsai.Var.set var a)
  in
  Bus.iter_exn (History.changes_bus t) [%here] ~f:(Bonsai.Var.set var);
  { var; setter; effect }
;;

let create_exn (type a) (module S : S with type t = a) ~fallback =
  create_exn' (module S) ~on_bad_uri:(`Default_state fallback)
;;

let set { var; setter; effect = _ } a =
  setter a;
  Bonsai.Var.set var a
;;

let value { var; setter = _; effect = _ } = Bonsai.Var.value var

let update { var; setter; effect = _ } ~f =
  Bonsai.Var.update var ~f:(fun old ->
    let new_ = f old in
    setter new_;
    new_)
;;

let get { var; _ } = Bonsai.Var.get var
let set_effect { effect; _ } = effect

type 'a url_var = 'a t

module Typed = struct
  module Components = struct
    include Uri_parsing.Components

    let slash_regexp = Re.Str.regexp "/"
    let unicode_slash_regexp = Re.Str.regexp "%2F"

    let sanitize_slashes s =
      let url_unicode_slash = "%2F" in
      Re.Str.global_replace slash_regexp url_unicode_slash s
    ;;

    let parse_unicode_slashes s = Re.Str.global_replace unicode_slash_regexp "/" s

    let of_original_components (original : Components.t) =
      let split_path =
        match original.path with
        | "" -> []
        | path -> String.split ~on:'/' path |> List.map ~f:parse_unicode_slashes
      in
      { Uri_parsing.Components.path = split_path; query = original.query }
    ;;

    let to_original_components (typed_components : t) =
      { Components.path =
          String.concat ~sep:"/" (List.map typed_components.path ~f:sanitize_slashes)
      ; query = typed_components.query
      ; fragment = None
      }
    ;;
  end

  module Projection = Uri_parsing.Projection
  module Parser = Uri_parsing.Parser

  module Versioned_parser = struct
    include Uri_parsing.Versioned_parser

    let of_non_typed_parser
          ~(parse_exn : Original_components.t -> 'a)
          ~(unparse : 'a -> Original_components.t)
      =
      let projection =
        let parse_exn components =
          parse_exn (Components.to_original_components components)
        in
        let unparse result = Components.of_original_components (unparse result) in
        { Projection.parse_exn; unparse }
      in
      Uri_parsing.Versioned_parser.of_non_typed_parser projection
    ;;
  end

  let make'
        (type a)
        (parser : a Uri_parsing.Versioned_parser.t)
        ~(fallback : Exn.t -> Original_components.t -> a)
        ~on_fallback_raises
    =
    let projection = Uri_parsing.Versioned_parser.eval parser in
    let try_with_backup ~f =
      try f () with
      | e -> Option.value_or_thunk on_fallback_raises ~default:(fun () -> raise e)
    in
    let parse_exn (components : Original_components.t) =
      try
        let typed_components = Components.of_original_components components in
        let result : a Uri_parsing.Parse_result.t =
          projection.parse_exn typed_components
        in
        match result.remaining.path with
        | [] -> result.result
        | unparsed_path ->
          raise_s
            [%message "Part of the path was left unparsed!" (unparsed_path : string list)]
      with
      | e -> try_with_backup ~f:(fun () -> fallback e components)
    in
    let unparse (t : a) =
      let typed_components =
        projection.unparse
          { Uri_parsing.Parse_result.result = t
          ; remaining = Uri_parsing.Components.empty
          }
      in
      Components.to_original_components typed_components
    in
    { Projection.parse_exn; unparse }
  ;;

  let make
        (type a)
        ?on_fallback_raises
        (module T : T with type t = a)
        (parser : a Uri_parsing.Versioned_parser.t)
        ~(fallback : Exn.t -> Original_components.t -> a)
    : a url_var
    =
    let projection = make' parser ~fallback ~on_fallback_raises in
    let module S = struct
      include T

      let parse_exn = projection.parse_exn
      let unparse = projection.unparse
    end
    in
    create_exn' (module S) ~on_bad_uri:`Raise
  ;;

  let make_projection
        (type a)
        ?on_fallback_raises
        (parser : a Uri_parsing.Versioned_parser.t)
        ~(fallback : Exn.t -> Original_components.t -> a)
    =
    make' parser ~fallback ~on_fallback_raises
  ;;

  module Value_parser = Uri_parsing.Value_parser

  let to_url_string (type a) (parser : a Parser.t) a =
    let projection = Parser.eval parser in
    let components =
      projection.unparse
        { Uri_parsing.Parse_result.result = a; remaining = Components.empty }
    in
    let with_query = Uri.add_query_params Uri.empty (Map.to_alist components.query) in
    let with_path = Uri.with_path with_query (String.concat ~sep:"/" components.path) in
    Uri.to_string with_path
  ;;
end

module For_testing = struct
  module Parse_result = Uri_parsing.Parse_result

  module Projection = struct
    type 'a t = (Typed.Components.t, 'a Parse_result.t) Uri_parsing.Projection.t

    let slash_regexp = Re.Str.regexp "/"
    let unicode_slash_regexp = Re.Str.regexp "%2F"

    let sanitize_slashes s =
      let url_unicode_slash = "%2F" in
      Re.Str.global_replace slash_regexp url_unicode_slash s
    ;;

    let parse_unicode_slashes s = Re.Str.global_replace unicode_slash_regexp "/" s

    let make (parser : 'a Typed.Parser.t) =
      let projection = Typed.Parser.eval parser in
      let parse_exn (components : Typed.Components.t) =
        projection.parse_exn
          { components with path = List.map ~f:parse_unicode_slashes components.path }
      in
      let unparse (result : 'a Parse_result.t) =
        let components = projection.unparse result in
        { components with path = List.map ~f:sanitize_slashes components.path }
      in
      { Uri_parsing.Projection.parse_exn; unparse }
    ;;

    let make_of_versioned_parser (versioned_parser : 'a Typed.Versioned_parser.t) =
      Uri_parsing.Versioned_parser.eval versioned_parser
    ;;

    let parse_exn (projection : 'a t) = projection.parse_exn
    let unparse (projection : 'a t) = projection.unparse
  end
end
