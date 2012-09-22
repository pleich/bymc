open Printf

open SpinTypes
open Spin
open SpinIr
open SpinIrImp
open Debug

exception Ltl_error of string
exception Fairness_error of string
exception Prop_error of string

let rec is_propositional = function
    | Var v -> v#get_type = TPROPOSITION
    | BinEx(GT, _, _)
    | BinEx(GE, _, _)
    | BinEx(LT, _, _)
    | BinEx(LE, _, _)
    | BinEx(EQ, _, _)
    | BinEx(NE, _, _) -> true
    | BinEx(AND, l, r) -> (is_propositional l) && (is_propositional r)
    | BinEx(OR, l, r) -> (is_propositional l) && (is_propositional r)
    | BinEx(IMPLIES, l, r) -> (is_propositional l) && (is_propositional r)
    | BinEx(EQUIV, l, r) -> (is_propositional l) && (is_propositional r)
    | BinEx(UNTIL, _, _) -> false
    | BinEx(RELEASE, _, _) -> false
    | BinEx(WEAK_UNTIL, _, _) -> false
    | UnEx(NEG, a) -> is_propositional a
    | UnEx(ALWAYS, _) -> false
    | UnEx(EVENTUALLY, _) -> false
    | UnEx(NEXT, _) -> false
    | _ as e -> raise (Ltl_error ("Not an LTL formula: " ^ (expr_s e)))
;;

let normalize_form form =
    let rec norm neg = function
        | Var _ as f -> if neg then UnEx(NEG, f) else f
        | Const _ as f -> f
        | BinEx(GT, l, r) as f -> if neg then BinEx(LE, l, r) else f
        | BinEx(GE, l, r) as f -> if neg then BinEx(LT, l, r) else f
        | BinEx(LT, l, r) as f -> if neg then BinEx(GE, l, r) else f
        | BinEx(LE, l, r) as f -> if neg then BinEx(GT, l, r) else f
        | BinEx(EQ, l, r) as f -> if neg then BinEx(NE, l, r) else f
        | BinEx(NE, l, r) as f -> if neg then BinEx(EQ, l, r) else f
        | BinEx(AND, l, r) as f ->
                if neg
                then BinEx(OR, (norm true l), (norm true r))
                else (norm false f)

        | BinEx(OR, l, r) as f ->
                if neg
                then BinEx(AND, (norm true l), (norm true r))
                else (norm false f)

        | UnEx(NEG, a) as f -> if neg then (norm true a) else f

        | BinEx(IMPLIES, l, r) ->
                if neg
                then BinEx(AND, norm false l, norm true r)
                else BinEx(IMPLIES, norm false l, norm false r)

        | BinEx(EQUIV, l, r) ->
                BinEx(EQUIV, norm neg l, norm neg r)
        
        | _ as f ->
                let m = (sprintf "Not a propositional formula: %s" (expr_s f))
                in
                raise (Ltl_error m)
    in
    norm false form
;;


let embed_atomics aprops form =
    let get_atomic name =
        try
            match Hashtbl.find aprops name with
            | PropGlob e -> e
            | _ -> raise (Fairness_error ("Incorrect atomic expr: " ^ name))
        with Not_found ->
            raise (Fairness_error ("Atomic expr not found: " ^ name))
    in
    let rec embed = function
        | BinEx(op, l, r) -> BinEx(op, embed l, embed r)
        | UnEx(op, r) -> UnEx(op, embed r)
        | Var v as e ->
            if v#get_type = SpinTypes.TPROPOSITION
            then embed (get_atomic v#get_name)
            else e
        | _ as e -> e
    in
    embed form
;;


let find_fairness_assertion aprops ltl_forms =
    let fairness =
        try Hashtbl.find ltl_forms "fairness"
        with Not_found ->
            raise (Fairness_error "No LTL formula called \"fairness\" found!")
    in
    let strange_fairness () =
        let m = "Don't know how to handle fairness: " ^ (expr_s fairness) in
        raise (Fairness_error m)
    in
    let proposition = 
        match fairness with
        | UnEx(ALWAYS, UnEx(EVENTUALLY, f)) ->
            if is_propositional f
            then normalize_form (embed_atomics aprops f)
            else strange_fairness ()
        | UnEx(EVENTUALLY, UnEx(ALWAYS, f)) ->
            if is_propositional f
            then normalize_form (embed_atomics aprops f)
            else strange_fairness ()
        | _ -> strange_fairness ()
    in
    printf "fairness proposition: %s\n" (expr_s proposition);
    proposition
;;


let find_invariants aprops =
    let re = Str.regexp ".*_inv" in
    let collect_invariants name prop inv_props =
        let form = match prop with
        | PropGlob e -> e
        | _ ->
            let m = "An invariant must be a glob property: " ^ name in
            raise (Prop_error m)
        in
        if Str.string_match re name 0
        then begin
            log INFO ("    adding invariant: " ^ name);
            form :: inv_props
        end else inv_props
    in
    Hashtbl.fold collect_invariants aprops []
;;

