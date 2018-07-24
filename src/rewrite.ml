(** Implementation of the REWRITE tactic. *)

open Timed
open Terms
open Print
open Console
open Proofs

(****************************************************************************)
(* Error function. *)
let fail_to_match = fun n ->
  match n with
  | 0 -> fatal_no_pos "Can only use rewrite with equalities."
  | 1 -> fatal_no_pos "Cannot rewrite under products."
  | 2 -> fatal_no_pos "Cannot rewrite under abstractions."
  | 3 -> fatal_no_pos "Cannot rewrite  meta variables."
  | 4 -> fatal_no_pos "Should not get here, match_subst."
  | _ -> fatal_no_pos "Incorrect error code."

(* Minimal unwrapper. *)
let get : 'a option -> 'a = fun t ->
  match t with
  | Some x -> x
  | None   -> fail_to_match 0

(****************************************************************************)

(** [break_prod] is a less safe version of Handle.env_of_prod. It is given the
    type of the term passed to #REWRITE which is assumed to be of the form
                    !x1 : A1 ... ! xn : An U
    and it returns an environment [x1 : A1, ... xn : An] and U. *)
(* TODO: Replace this by Handle.env_of_prod if it is possible to get the
 * number of products in a term. *)
let break_prod : term -> Env.t * term = fun t ->
   let rec aux t acc =
     match t with
     | Prod(a,b) ->
        let (v,b) = Bindlib.unbind b in
        aux b ((Bindlib.name_of v,(v,lift a))::acc)
     | _ -> acc, t
   in aux t []

(** [break_eq] is given the type of the term passed as an argument to #REWRITE
    and checks that it is an equality type. That is, it checks that t matches
    with:
                          "P" ("eq" a l r)
    That is:
      Appl((Symb "P") , (Appl(Appl(Appl((Symb "eq") , (Symb a )) , l) , r ))
    If the argument does match a term of the shape l = r then it returns the
    triple (a, l, r) otherwise it throws a fatal error. *)
let break_eq : term -> term * term * term = fun t ->
  let check_symb : term -> string -> unit = fun t n ->
    match unfold t with
    | Symb s when s.sym_name = n -> ()
    | _ -> fail_to_match 0
  in
  match get_args t with
  | (p, [eq]) ->
      begin
        check_symb p "P" ;
        match get_args eq with
        | (e, [a ; l ; r]) -> check_symb e "eq" ; (a, l, r)
        | _                -> fail_to_match 0
      end
  | _ -> fail_to_match 0

(** [term_match] is given two terms (for now) and determines if they match.
    at this stage this is just done by using the syntactic equality function
    from Terms, but it will change. *)
let term_match : term -> term -> bool = fun t1 t2 -> eq t1 t2

(** [match_subst] is given the type of the current goal, the left hand side of
    the lemma rewrite was called on and some term it returns the type of the
    new goal, where all occurrences of left are replaced by the new term.
    Use: This will be called with a fresh Vari term to build a product term,
    using the bindlib lilfting functions. *)
let match_subst : term -> term -> term -> term = fun g_type l t ->
  let rec matching_aux : term -> term = fun cur ->
    if term_match (unfold cur) l then t else match unfold cur with
    | Vari _ | Type | Kind | Symb _ -> cur
    | Appl(t1, t2) ->
        let t1' = matching_aux t1 and t2' = matching_aux t2 in Appl(t1', t2')
    | Prod _  -> fail_to_match 1     (* For now we do not "mess" with any  *)
    | Abst _  -> fail_to_match 2     (* terms conaining Prodi, Abst, Meta. *)
    | Meta _  -> fail_to_match 3
    | _       -> fail_to_match 4
  in matching_aux g_type

(****************************************************************************)

(** [handle_rewrite] is given a term which must be of the form l = r (for now
    with no quantifiers) and replaces the first instance of l in g with the
    corresponding instance of r. *)
let handle_rewrite : term -> unit = fun t ->
  (* Get current theorem, focus goal and the metavariable representing it. *)
  let thm = current_theorem() in
  let (currentGoal, otherGoals) =
    match thm.t_goals with
    | []    -> fatal_no_pos "No remaining goals..."
    | g::gs -> (g, gs)
  in
  let metaCurrentGoal = currentGoal.g_meta in
  let t_type =
    match Solve.infer (Ctxt.of_env currentGoal.g_hyps) t with
    | Some a -> a
    | None   -> fatal_no_pos "Cannot infer type of argument passed to rewrite."
  in
  (* Check that the term passed as an argument to rewrite has the correct
   * type, i.e. represents an equaltiy and get the subterms l,r from l = r
   * as well as their type a. *)
  (* let (env, t_type)  = break_prod t_type        in *)
  let (a, l, r)      = break_eq t_type          in

  (* Make a new free variable X and pass it in match_subst using bindlib *)
  let x         = Bindlib.new_var mkfree "X"    in
  let t' = (match_subst currentGoal.g_type l (Vari x)) in
  let (_, ar::rest) = get_args t' in
  let t'' = add_args ar rest in

  (* We build the predicate Pred := Lambda y. (match_subst ...)
     and the product Prod := Forall X. Pred X
     by computing immediately the product Prod := Forall X. (match_subst...)  *)
  let pred_0    = lift t'' in
  let pred_1    = Bindlib.unbox (Bindlib.bind_var x pred_0) in
  let pred    = Abst (a, pred_1) in

  let all_symb  = Symb (Sign.find (Sign.current_sign()) "all") in
  let formulae_0  = Appl (all_symb, a) in
  let formulae_1 = Appl (formulae_0, pred) in

  let p_symb    = Symb (Sign.find (Sign.current_sign()) "P") in

  (* Here we build P (all a pred) *)
  let formulae  = Appl (p_symb, formulae_1) in
  (* see at the end of proof.dk for the explanation *)

  (*
  let prod_type =
    match Solve.infer (Ctxt.of_env currentGoal.g_hyps) prod with
    | Some a -> a
    | None   -> fatal_no_pos "Cannot infer type of the product built."
     in
  *)

  (* Construct the type of the new goal, which is obtained by performing the
     the subsitution by r, and adding the P symbol on top *)
  let new_type_0  = Bindlib.subst pred_1 r   in
  let new_type    = Appl (p_symb, new_type_0) in

  (* let (new_type_type, _) = Typing.infer (Ctxt.of_env currentGoal.g_hyps) new_type in
     wrn "The type of new_type is [%a]\n" pp new_type_type; *)

  let meta_env  = Array.map Bindlib.unbox (Env.vars_of_env currentGoal.g_hyps)   in
  let new_m     = fresh_meta new_type (metaCurrentGoal.meta_arity) in
  let new_meta  = Meta(new_m, meta_env) in
  (* Get the inductive assumption of Leibniz equality to transform a proof of
   * the new goal to a proof of the previous goal. *)
  (* FIXME: When a Logic module with a notion of equality is defined get this
  from that module. *)
  let eq_ind    = Symb(Sign.find (Sign.current_sign()) "eqind")        in
  (* Build the term tht will be used in the instantiation of the new meta. *)
  let g_m       = add_args eq_ind [a ; l ; r ; t_type ; pred ; new_meta]    in
  let b = Bindlib.bind_mvar (to_tvars meta_env) (lift g_m) in
  let b = Bindlib.unbox b in
  (* FIXME: Type check the term used to instantiate the old meta. *)
  (* if not (Solve.check (Ctxt.of_env currentGoal.g_hyps) g_m !(metaCurrentGoal.meta_type)) then
     fatal_no_pos "Typing error."; *)

  metaCurrentGoal.meta_value := Some b ;
  let thm =
    {thm with t_goals = {currentGoal with g_meta = new_m ; g_type = new_type }::otherGoals} in
  theorem := Some thm ;
  begin
    wrn "Goal : [%a]\n" pp currentGoal.g_type ;
    wrn "Tactic rewrite used on the term: [%a]\n" pp t        ;
    wrn "LHS of the rewrite hypothesis: [%a]\n" pp l        ;
    wrn "RHS of the rewrite hypothesis: [%a]\n" pp r        ;
    wrn "t' [%a]\n" pp t';
    wrn "t'' [%a]\n" pp t'';
    (* wrn "Type of pred:  [%a]\n" pp pred_type     ; *)
    wrn "Pred:  [%a]\n" pp pred ;
    wrn "New type to prove obtained by subst [%a]\n" pp new_type ;
    wrn "Term produced by the tactic:   [%a]\n" pp g_m      ;
  end


(* --------------- TODO (From the meetings on 16/07/2018) ------------------ *)

(*****************************************************************************
 *  1) Take G build G[x].
 *               --> Started doing that in match_subst.
 *  2) Make a new variable X
 *  3) Compute G[X], this is simply the application of match_subst with X as
 *     the term to substitute in.
 *  4) Build Prod(X, G[X]) using bindlib.
 *****************************************************************************
 * Once the above is done we will be close to finishing the simple rewrite
 * tactic, by using:
 *      eqind T l r (lemma) (Pi X. G[X]) G'
 * or something along these lines, but we will see.
 *)
