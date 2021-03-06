(**************************************************************************)
(*  Copyright (c) 2012, 2013,                                             *)
(*                           Sebastien Mondet <seb@mondet.org>,           *)
(*                           Ashish Agarwal <agarwal1975@gmail.com>.      *)
(*                                                                        *)
(*  Permission to use, copy, modify, and/or distribute this software for  *)
(*  any purpose with or without fee is hereby granted, provided that the  *)
(*  above  copyright notice  and this  permission notice  appear  in all  *)
(*  copies.                                                               *)
(*                                                                        *)
(*  THE  SOFTWARE IS  PROVIDED  "AS  IS" AND  THE  AUTHOR DISCLAIMS  ALL  *)
(*  WARRANTIES  WITH  REGARD  TO  THIS SOFTWARE  INCLUDING  ALL  IMPLIED  *)
(*  WARRANTIES  OF MERCHANTABILITY AND  FITNESS. IN  NO EVENT  SHALL THE  *)
(*  AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL  *)
(*  DAMAGES OR ANY  DAMAGES WHATSOEVER RESULTING FROM LOSS  OF USE, DATA  *)
(*  OR PROFITS,  WHETHER IN AN  ACTION OF CONTRACT, NEGLIGENCE  OR OTHER  *)
(*  TORTIOUS ACTION,  ARISING OUT  OF OR IN  CONNECTION WITH THE  USE OR  *)
(*  PERFORMANCE OF THIS SOFTWARE.                                         *)
(**************************************************************************)

(** The Flow-monad core module. *)

open Core.Std

(** The flow-monad “embeds” {i Core}'s [Result]s into [Lwt] threads. *)
type ('good, 'bad) t = ('good, 'bad) Result.t Lwt.t

val bind : ('a, 'd) t -> ('a -> ('b, 'd) t) -> ('b, 'd) t

val return : 'a -> ('a, _) t

val (>>=) : ('a, 'd) t -> ('a -> ('b, 'd) t) -> ('b, 'd) t

(** The monadic [map] function. *)
val (>>|) : ('a, 'd) t -> ('a -> 'b) -> ('b, 'd) t

(** Bind on the I/O part, i.e. get a [Result.t] and continue with a
    [Flow.t]. Example:
    [return () >>< (function Ok () -> return () | Error _ -> return ())] *)
val (>><): ('a, 'b) t -> (('a, 'b) Result.t -> ('c, 'd) t) -> ('c, 'd) t

(** Use anything as an Error thread.  *)
val error: 'a -> ('any, 'a) t

(** Do something on errors (generally in order to augment them). *)
val bind_on_error: ('a, 'err) t -> f:('err -> ('a, 'b) t) -> ('a, 'b) t

(** Do something on both sides. *)
val double_bind: ('a, 'b) t ->
  ok:('a -> ('c, 'd) t) ->
  error:('b -> ('c, 'd) t) -> ('c, 'd) t

(** [catch_deferred f x] uses [Lwt.catch] to catch all the
    lwt-exceptions in the result. *)
val catch_deferred : (unit -> 'a Lwt.t) -> ('a, exn) t

(** Put any Lwt.t in a flow-monad like [catch_deferred] but put the exception
    in a polymorphic variant (the default being [`io_exn e]).  *)
val wrap_deferred: on_exn:(exn -> 'c) -> (unit -> 'b Lwt.t) -> ('b, 'c) t

(** Put any non-I/O function
    in a flow-monad and do “something” on the error.  *)
val wrap: on_exn:(exn -> 'c) -> (unit -> 'b) -> ('b, 'c) t

(** [map_option] allows to put options {i inside} the t. *)
val map_option: 'a option -> f:('a -> ('c, 'b) t) -> ('c option, 'b) t

(** [of_result] adds threading to a [Result.t]. *)
val of_result: ('a, 'b) Result.t -> ('a, 'b) t

