(** Parse ocamlobjinfo output *)
open Stdune

type t = Module.Name.Set.t Ml_kind.Dict.t

val pp : t Fmt.t

val rules
  :  dir:Path.t
  -> ctx:Context.t
  -> unit:Path.t
  -> Action.t Build.s * t Build.s

(** For testing only *)
val parse : string -> t
