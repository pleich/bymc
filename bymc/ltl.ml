open Printf

open SpinTypes
open Spin
open SpinIr
open SpinIrImp
open Debug

exception Ltl_error of string
exception Fairness_error of string
exception Prop_error of string

let is_propositional type_tab e =
    let rec isp = function
    | Var v ->
            (type_tab#get_type v)#basetype = TPROPOSITION
    | BinEx(GT, _, _)
    | BinEx(GE, _, _)
    | BinEx(LT, _, _)
    | BinEx(LE, _, _)
    | BinEx(EQ, _, _)
    | BinEx(NE, _, _) -> true
    | BinEx(AND, l, r) -> (isp l) && (isp r)
    | BinEx(OR, l, r) -> (isp l) && (isp r)
    | BinEx(IMPLIES, l, r) -> (isp l) && (isp r)
    | BinEx(EQUIV, l, r) -> (isp l) && (isp r)
    | BinEx(UNTIL, _, _) -> false
    | BinEx(RELEASE, _, _) -> false
    | BinEx(WEAK_UNTIL, _, _) -> false
    | UnEx(NEG, a) -> isp a
    | UnEx(ALWAYS, _) -> false
    | UnEx(EVENTUALLY, _) -> false
    | UnEx(NEXT, _) -> false
    | _ as e -> raise (Ltl_error ("Not an LTL formula: " ^ (expr_s e)))
    in
    isp e
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
        | BinEx(AND, l, r) ->
                if neg
                then BinEx(OR, (norm neg l), (norm neg r))
                else BinEx(AND, (norm neg l), (norm neg r))

        | BinEx(OR, l, r) ->
                if neg
                then BinEx(AND, (norm neg l), (norm neg r))
                else BinEx(OR, (norm neg l), (norm neg r))

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


let embed_atomics type_tab aprops form =
    let get_atomic name =
        try
            match Program.StringMap.find name aprops with
            | PropGlob e -> e
            | _ -> raise (Ltl_error ("Incorrect atomic expr: " ^ name))
        with Not_found ->
            raise (Ltl_error ("Atomic expr not found: " ^ name))
    in
    let rec embed = function
        | BinEx(op, l, r) -> BinEx(op, embed l, embed r)
        | UnEx(op, r) -> UnEx(op, embed r)
        | Var v as e ->
            if (type_tab#get_type v)#basetype = SpinTypes.TPROPOSITION
            then embed (get_atomic v#get_name)
            else e
        | _ as e -> e
    in
    embed form
;;

let find_fair_atoms error_fun type_tab aprops = function
    | UnEx(ALWAYS, UnEx(EVENTUALLY, f)) as ff ->
        if is_propositional type_tab f
        then normalize_form (embed_atomics type_tab aprops f)
        else error_fun ff
    | UnEx(EVENTUALLY, UnEx(ALWAYS, f)) as ff ->
        if is_propositional type_tab f
        then normalize_form (embed_atomics type_tab aprops f)
        else error_fun ff
    | _ as ff -> error_fun ff
;;

let collect_fairness_forms ltl_forms =
    let fairness =
        try Hashtbl.find ltl_forms "fairness"
        with Not_found ->
            raise (Fairness_error "No LTL formula called \"fairness\" found!")
    in
    (* break down boolean combinations of formulas into a list *)
    let rec collect = function
    | BinEx (AND, l, r) ->
            List.append (collect l) (collect r)
    | BinEx (OR, _, _) as f ->
            let m = ("f||g is not supported in fairness: " ^ (expr_s f)) in
            raise (Fairness_error m)
    | BinEx (IMPLIES, _, _) as f ->
            let m = ("f->g is not supported in fairness: " ^ (expr_s f)) in
            raise (Fairness_error m)
    | BinEx (EQUIV, _, _) as f ->
            let m = ("f<->g is not supported in fairness: " ^ (expr_s f)) in
            raise (Fairness_error m)
    | UnEx (NEG, _) as f -> 
            let m = ("!f is not supported in fairness (please normalize): "
                ^ (expr_s f)) in
            raise (Fairness_error m)
    | _ as f -> [f]
    in
    collect fairness
;;

let is_invariant_atomic name =
    Str.string_match (Str.regexp ".*_inv") name 0
;;

let find_invariants (aprops: Spin.token atomic_expr Program.StringMap.t):
        Spin.token expr list =
    let collect_invariants name prop inv_props =
        let form = match prop with
        | PropGlob e -> e
        | _ ->
            let m = "An invariant must be a glob property: " ^ name in
            raise (Prop_error m)
        in
        if is_invariant_atomic name then form :: inv_props else inv_props
    in
    Program.StringMap.fold collect_invariants aprops []
;;

