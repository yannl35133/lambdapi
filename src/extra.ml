(** Standard library extension (mostly). *)

(** Short name for the type of a pretty-printing function. *)
type 'a pp = Format.formatter -> 'a -> unit

(** Short name for the type of an equality function. *)
type 'a eq = 'a -> 'a -> bool

module Int =
  struct
    type t = int
    let compare = (-)
  end

module Option =
  struct
    type 'a t = 'a option

    let map : ('a -> 'b) -> 'a t -> 'b t = fun f o ->
      match o with
      | None    -> None
      | Some(e) -> Some(f e)

    let iter : ('a -> unit) -> 'a t -> unit = fun f o ->
      match o with
      | None    -> ()
      | Some(e) -> f e
  end

module List =
  struct
    include List

    (** [pp pp_e sep oc l] prints the list [l] on the channel [oc] using [sep]
        as separator, and [pp_e] for printing the elements. *)
    let pp : 'a pp -> string -> 'a list pp = fun pp_elt sep oc l ->
      match l with
      | []    -> ()
      | e::es -> let fn e = Format.fprintf oc "%s%a" sep pp_elt e in
                 pp_elt oc e; iter fn es

    (** [map_find f l] applies [f] to the elements of list [l] (in order), and
        returns the result of the first application of [f] which result is not
        [None]. If none is found, [None] is returned. *)
    let rec map_find : ('a -> 'b option) -> 'a list -> 'b option = fun f l ->
      match l with
      | []    -> None
      | e::es -> match f e with None -> map_find f es | res -> res

    (** [cut l k] returns a pair of lists [(l1,l2)] such that [l1] has length
        [max (List.length l) k] and [l1 @ l2] is equal to [l]. *)
    let cut : 'a list -> int -> 'a list * 'a list = fun l k ->
      let rec cut acc l k =
        if k <= 0 then (List.rev acc, l) else
        match l with
        | []   -> (List.rev acc, l)
        | x::l -> cut (x::acc) l (k-1)
      in
      if k <= 0 then ([], l) else cut [] l k

    (** [add_array a l] returns a list containing the elements of [l]
        and [a]. *)
    let add_array : 'a array -> 'a list -> 'a list = fun a l ->
      let res = ref l in
      Array.iter (fun x -> res := x::!res) a;
      !res

    (** [add_array a l] returns a list containing the elements of [l]
        and [a]. *)
    let add_array2 : 'a array -> 'b array -> ('a * 'b) list -> ('a * 'b) list =
      fun a1 a2 l ->
        let res = ref l in
        Array.iter2 (fun x1 x2 -> res := (x1,x2)::!res) a1 a2;
        !res

  end

module Array =
  struct
    include Array

    (** [for_all2 p a1 a2] checks if the corresponding elements of arrays [a1]
        and [a2] satisfy the predicate [p].  The [Invalid_argument]  exception
        is raised if the arrays do not have the same size. *)
    let for_all2 : ('a -> 'b -> bool) -> 'a array -> 'b array -> bool =
      fun f a1 a2 ->
        let exception Done in
        let f x y = if not (f x y) then raise Done in
        try iter2 f a1 a2; true with Done -> false

    (** [pp pp_e sep oc a] prints the array list [a] on the channel [oc] using
        [sep] as separator, and [pp_e] for printing the elements. *)
    let pp : 'a pp -> string -> 'a array pp = fun pp_elt sep oc a ->
      List.pp pp_elt sep oc (to_list a)
  end

module Stack =
  struct
    include Stack

    (** [mem e s] checks whether the element [e] occurs in the stack [s]. *)
    let mem : 'a -> 'a t -> bool = fun e s ->
      let test x = if x = e then raise Exit in
      try iter test s; false with Exit -> true
  end

(** [time f x] times the application of [f] to [x], and returns the evaluation
    time in seconds together with the result of the application. *)
let time : ('a -> 'b) -> 'a -> float * 'b = fun f x ->
  let t = Sys.time () in
  let r = f x in (Sys.time () -. t, r)

(* Functional maps with [int] keys. *)
module IntMap = Map.Make(Int)

(* Functional maps with [string] keys. *)
module StrMap = Map.Make(String)
