(** A collection of rules for one or multiple directories. *)

open! Stdune

type 'rules t =
  (** [Empty] is a scheme that has no rules *)
  | Empty

  (** [Union (a, b)] produces all the rules produced by a and b *)
  | Union of 'rules t * 'rules t

  (** [Approximation (dirs, x)] produces the same rules as [x] in [dirs] and
      produces no rules outside of [dirs].

      It is an error if [x] produces any rules outside of [dirs].
      This error is not always going to be detected, especially if it's hidden
      by an occurrence of [Thunk]. If the error is undetected, the violating
      rules are just silently ignored. *)
  | Approximation of Dir_set.t * 'rules t

  (** [Finite rules] just produces a fixed set of rules known in advance.
      The keys in the map are the directory paths. *)
  | Finite of 'rules Path.Build.Map.t

  (** [Thunk f] is a "lazy" collection of rules. This is normally used with
      [Approximation (dirs, Thunk f)] such that the work of [f] can be delayed
      (or avoided entirely) until (or unless) the rules for [dirs] become
      necessary.

      The thunk will be called at most once per [evaluate]. *)
  | Thunk of (unit -> 'rules t)

module Evaluated : sig
  type 'a t

  val get_rules : 'a t -> dir:Path.Build.t -> 'a option
end

(** [Evaluated.t] shares the work of scheme evaluation between multiple
    [get_rules] requests.

    This consists of:

    - Sharing the work of scheme data structure traversal. For example, if a
      scheme consists of a many nested [Union]s, a naive scheme lookup would
      have to look at them all at every [get_rules] query.
      [evaluate] will collapse them to a directory-keyed trie for faster lookup.
    - Sharing the work done by user thunks. Every thunk will only be called
      at most once per [evaluate].
*)
val evaluate : 'a t -> union:('a -> 'a -> 'a) -> 'a Evaluated.t

val all : 'a t list -> 'a t
