open! Core
open! Bonsai_web
module Form = Bonsai_web_ui_form

module type S = sig
  type t [@@deriving sexp, sexp_grammar]
end

type form_transformer =
  Sexp_grammar.grammar Sexp_grammar.with_tag Value.t
  -> recurse:(Sexp_grammar.grammar Value.t -> Sexp.t Form.t Computation.t)
  -> Sexp.t Form.t Computation.t

(** Customizations allow you to use custom logic for leaves of your view/form generation.
    When a tagged sexp_grammar is encountered, [apply_to_tag] will be invoked on the tag's
    key and value. If [apply_to_tag] returns true, then the custom logic will be used in
    place of the default auto-generated logic.

    Customizations based on individual fields within a record are not yet supported, only
    tags applied to entire types will match.

    WARNING: Customization of auto-generated UIs/Forms is currently under development.
    Please do not take a dependency on customization logic if you are not ok with the API
    changing under your feet. *)
module Customization : sig
  type 'a t

  module Defaults : sig
    module Form : sig
      val all : form_transformer t list
    end
  end

  (** [create_for_view] allows you to specify a custom rendering function for a sexp value
      whose grammar includes the provided tag name. *)
  val create_for_view
    :  apply_to_tag:(key:string -> value:Sexp.t -> bool)
    -> (Sexp.t Value.t -> Vdom.Node.t Computation.t)
    -> (Sexp.t Value.t -> Vdom.Node.t Computation.t) t

  (** [constant] allows you to specify a form for the ['a] that you're providing
      custom logic for. This form will be projected to [Sexp.t], so that it can be used in
      the logic for form generation. *)
  val constant_form
    :  (module Sexpable with type t = 'a)
    -> apply_to_tag:(key:string -> value:Sexp.t -> bool)
    -> 'a Form.t Computation.t
    -> form_transformer t

  val transform_form
    :  apply_to_tag:(key:string -> value:Sexp.t -> bool)
    -> form_transformer
    -> form_transformer t

  val transform_form'
    :  (module Sexpable with type t = 'a)
    -> apply_to_tag:(key:string -> value:Sexp.t -> bool)
    -> (Sexp_grammar.grammar Sexp_grammar.with_tag Value.t
        -> recurse:(Sexp_grammar.grammar Value.t -> Sexp.t Form.t Computation.t)
        -> 'a Form.t Computation.t)
    -> form_transformer t
end

(** WARNING: This function produces output which is auto-generated and is subject to
    large layout changes without notice while the API is being developed. You should not
    rely on this function if your users will be sad when the output changes.

    [view] produces a [Vdom.Node.t] representing a given ['a Value.t], based on the
    sexp grammar for ['a].

    [customizations] is a list of customizations to use while generating the view (see
    above). Customizations are tried in the provided order, using the result of the first
    matching customization. *)
val view
  :  (module S with type t = 'a)
  -> ?customizations:(Sexp.t Value.t -> Vdom.Node.t Computation.t) Customization.t list
  -> 'a Value.t
  -> [ `This_view_may_change_without_notice ]
  -> Vdom.Node.t Computation.t

(** [form] takes a type ['a] and its sexp grammar and produces a ['a Form.t].

    [on_set_error] defaults to [Effect.print_s] and allows customization of what happens
    if [Form.set] produces an error while operating on the sexp representation of the
    type. For types which derive sexp and sexp_grammar, [on_set_error] should not be
    called, but it may for types with hand-rolled grammars or sexp functions.

    [customizations] is a list of customizations to use while generating the form (see
    above). Customizations are tried in the provided order, using the result of the first
    matching customization.

    Grammar fields tagged with key [Ppx_sexp_conv_lib.Sexp_grammar.doc_comment_tag] will
    be converted into tooltips. This tag is added automatically to doc comments on types
    which derive [sexp_grammar] with the [~tags_of_doc_comments] option.

    If [textbox_for_string] is supplied, string inputs will be textboxes rather than
    textareas (meaning the form can be submitted with Enter when those fields are active,
    but users will not be able to input multiline strings).
*)
val form
  :  (module S with type t = 'a)
  -> ?on_set_error:(Sexp.t -> unit Effect.t)
  -> ?customizations:form_transformer Customization.t list
  -> ?textbox_for_string:unit
  -> unit
  -> 'a Form.t Computation.t

(** [form'] is similar to [form], but takes an untyped sexp grammar as a value, and
    produces a [Sexp.t Form.t]. This allows you to create a form that depends on a dynamic
    sexp grammar. *)
val form'
  :  ?on_set_error:(Sexp.t -> unit Effect.t)
  -> ?customizations:form_transformer Customization.t list
  -> ?textbox_for_string:unit
  -> Sexp_grammar.grammar Value.t
  -> Sexp.t Form.t Computation.t

(** [view_as_vdom] provides a custom rendering function for the form generated by [form],
    which is optimized to look good, even with many levels of nesting. *)
val view_as_vdom
  :  ?on_submit:'a Bonsai_web_ui_form.Submit.t
  -> ?editable:[ `Yes_always | `Currently_yes | `Currently_no ]
  -> 'a Form.t
  -> Vdom.Node.t
