(* Single static assignment form.
 *
 * This module is written in Dubrovnik next to Adriatic sea.
 * So it may have more bugs than the other modules!
 *
 * Igor Konnov, July 2012.
 *)

open Printf

open Graph.Pack.Graph

open Cfg
open Analysis
open Spin
open SpinIr
open SpinIrImp
open Debug

exception Var_not_found of string

let comp_dom_frontiers cfg =
    let df = Hashtbl.create (Hashtbl.length cfg#blocks) in
    let idom_tbl = comp_idoms cfg in
    let idom_tree = comp_idom_tree idom_tbl in
    let visit_node n =
        let visit_y s df_n =
            if n <> (Hashtbl.find idom_tbl s)
            then IntSet.add s df_n
            else df_n in
        let df_n = List.fold_right visit_y (cfg#find n)#succ_labs IntSet.empty 
        in
        let propagate_up df_n z =
            IntSet.fold visit_y (Hashtbl.find df z) df_n in
        let children = Hashtbl.find idom_tree n in
        let df_n = List.fold_left propagate_up df_n children in
        Hashtbl.add df n df_n
    in
    let rec bottom_up node =
        try
            let children = Hashtbl.find idom_tree node in
            List.iter bottom_up children;
            visit_node node
        with Not_found ->
            raise (Failure (sprintf "idom children of %d not found" node))
    in
    bottom_up 0;
    df


(* Ron Cytron et al. Efficiently Computing Static Single Assignment Form and
   the Control Dependence Graph, ACM Transactions on PLS, Vol. 13, No. 4, 1991,
   pp. 451-490.

   Figure 11.
 *)
let place_phi (vars: var list) (cfg: 't control_flow_graph) =
    let df = comp_dom_frontiers cfg in
    let iter_cnt = ref 0 in
    let has_already = Hashtbl.create (Hashtbl.length cfg#blocks) in
    let work = Hashtbl.create (Hashtbl.length cfg#blocks) in
    let init_node n =
        Hashtbl.add has_already n 0; Hashtbl.add work n 0 in
    List.iter init_node cfg#block_labs;

    let for_var v =
        let does_stmt_uses_var = function
            | Expr (_, BinEx (ASGN, Var ov, _)) ->
                    ov#qual_name = v#qual_name
            | Expr (_, BinEx (ASGN, BinEx (ARR_ACCESS, Var ov, _), _)) ->
                    ov#qual_name = v#qual_name
            | Havoc (_, ov) ->
                    ov#qual_name = v#qual_name
            | _ -> false in
        let does_blk_uses_var bb =
            List.exists does_stmt_uses_var bb#get_seq in
        let blks_using_v =
            List.map bb_lab (List.filter does_blk_uses_var cfg#block_list) in
        iter_cnt := !iter_cnt + 1;
        List.iter (fun bb -> Hashtbl.replace work bb !iter_cnt) blks_using_v;
        let work_list = ref blks_using_v in
        let one_step x =
            let do_y y = 
                if (Hashtbl.find has_already y) < !iter_cnt
                then begin
                    let bb = cfg#find y in
                    let num_preds = (List.length bb#get_pred) in
                    let phi = Expr (fresh_id (),
                                    Phi (v, Accums.n_copies num_preds v))
                    in
                    let seq = bb#get_seq in
                    bb#set_seq ((List.hd seq) :: phi :: (List.tl seq));
                    Hashtbl.replace has_already y !iter_cnt;
                    if (Hashtbl.find work y) < !iter_cnt
                    then begin
                        Hashtbl.replace work y !iter_cnt;
                        work_list := y :: !work_list
                    end
                end
            in
            IntSet.iter do_y (Hashtbl.find df x)
        in
        let rec many_steps () =
            match !work_list with
            | hd :: tl -> work_list := tl; one_step hd; many_steps ()
            | [] -> ()
        in
        work_list := blks_using_v;
        many_steps ()
    in
    List.iter for_var vars;
    cfg


let map_rvalues map_fun ex =
    let rec sub = function
    | Var v -> map_fun v
    | UnEx (t, l) ->
            UnEx (t, sub l)
    | BinEx (ASGN, BinEx (ARR_ACCESS, arr, idx), r) ->
            BinEx (ASGN, BinEx (ARR_ACCESS, arr, sub idx), sub r)
    | BinEx (ASGN, l, r) ->
            BinEx (ASGN, l, sub r)
    | BinEx (t, l, r) ->
            BinEx (t, sub l, sub r)
    | _ as e -> e
    in
    sub ex


(*
 It appears that the Cytron's algorithm can produce redundant phi functions like
 x_2 = phi(x_1, x_1, x_1). Here we remove them.
 *)
let optimize_ssa cfg =
    let sub_tbl = Hashtbl.create 10 in
    let changed = ref true in
    let collect_replace bb =
        let on_stmt = function
            | Expr (id, Phi (lhs, rhs)) as s ->
                    let fst = List.hd rhs in
                    if List.for_all (fun o -> o#qual_name = fst#qual_name) rhs
                    then begin
                        Hashtbl.add sub_tbl lhs#qual_name fst;
                        changed := true;
                        Skip id 
                    end else s
            | Expr (id, e) ->
                    let sub v =
                        if Hashtbl.mem sub_tbl v#qual_name
                        then Var (Hashtbl.find sub_tbl v#qual_name)
                        else Var v in
                    let ne = map_rvalues sub e in
                    Expr (id, ne)
            | _ as s -> s
        in
        bb#set_seq (List.map on_stmt bb#get_seq);
    in
    while !changed do
        changed := false;
        List.iter collect_replace cfg#block_list;
    done;
    cfg


(* for every basic block, find the starting indices of the variables,
   i.e., such indices that have not been used in immediate dominators.
 *)
let reduce_indices cfg var =
    (* create dependencies between different copies of the variable *)
    let add_copy lst = function
        | Decl (_, v, _) ->
            v#color :: lst          
        | Expr (_, Phi (v, _)) ->
            v#color :: lst          
        | Expr (_, BinEx (ASGN, Var v, _)) ->
            v#color :: lst          
        | Expr (_, BinEx (ASGN, BinEx (ARR_ACCESS, Var v, _), _)) ->
            v#color :: lst          
        | Havoc (_, v) ->
            v#color :: lst          
        | _ -> lst
    in
    let get_bb_copies bb =
        List.fold_left add_copy [] bb#get_seq in
    let vertices = Hashtbl.create 10 in
    let depg = create () in
    let create_vertex id =
        let v = V.create id in
        add_vertex depg v;
        Hashtbl.add vertices id v
    in
    List.iter (fun bb -> List.iter create_vertex get_bb_copies bb) cfg#block_list;
    (* add dependencies *)
    let add_dep v1 v2 =
        if v1#color <> v2#color
        then add_edge depg
            (Hashtbl.find vertices v1#color)
            (Hashtbl.find vertices v2#color)
    in
    let add_bb_deps bb =
        let copies = get_bb_copies bb in
        (* all copies are dependent in the block *)
        List.iter (fun v -> List.iter (add_dep v) copies) copies;
        let add_succ succ =
            let scopies = get_bb_copies succ in
            List.iter (fun v -> List.iter (add_dep v) scopies) copies
        in
        List.iter add_succ bb#succ
    in
    List.iter add_bb_deps cfg#block_list;
    ()


(* Ron Cytron et al. Efficiently Computing Static Single Assignment Form and
   the Control Dependence Graph, ACM Transactions on PLS, Vol. 13, No. 4, 1991,
   pp. 451-490.

   Figure 12.
   
   NOTE: we do not need unique versions on parallel blocks.
   Here we are trying to minimize the number of different versions
   (as it defines the number of variables in an SMT problem),
   thus, blocks corresponding to different options introduce copies
   with the same indices.
 *)
let mk_ssa tolerate_undeclared_vars extern_vars intern_vars cfg =
    let vars = extern_vars @ intern_vars in
    if may_log DEBUG then print_detailed_cfg "CFG before SSA" cfg;
    let cfg = place_phi vars cfg in
    if may_log DEBUG then print_detailed_cfg "CFG after place_phi" cfg;
    let idom_tbl = comp_idoms cfg in
    let idom_tree = comp_idom_tree idom_tbl in

    let counters = Hashtbl.create (List.length vars) in
    let stacks = Hashtbl.create (List.length vars) in
    let nm v = v#id in (* TODO: use v#id instead *)
    let s_push v i =
        Hashtbl.replace stacks (nm v) (i :: (Hashtbl.find stacks (nm v))) in
    let s_pop var_nm = 
        Hashtbl.replace stacks var_nm (List.tl (Hashtbl.find stacks var_nm)) in
    let s_top v =
        let stack =
            try Hashtbl.find stacks (nm v)
            with Not_found ->
                raise (Var_not_found ("No stack for " ^ (nm v)))
        in
        if stack <> []
        then List.hd stack
        else if tolerate_undeclared_vars
        then begin
            let i = Hashtbl.find counters (nm v) in
            Hashtbl.replace counters (nm v) (i + 1);
            i
            end else
                let m = (sprintf "Use of %s before declaration?" v#qual_name) in
                raise (Failure m)
    in
    let intro_var v =
        (* EXPERIMENTAL: as opposite to Cytron et al., we assign
           the *same* variable versions on parallel branches.  Thus, SSA
           deals only with sequential copies of the same variable.
           This works for us, because we introduce variables at_i in CFG,
           to distinguish the control. The present optimization allows us
           to decrease the number of variables copies, which are integer
           variables, and to decrease the size of the problem!
         *)
        try let stack = Hashtbl.find stacks (nm v) in
            let num = if stack <> [] then List.hd stack else 0 in
            s_push v (num + 1);
            v#copy (sprintf "%s_Y%d" v#get_name (num + 1))
        with Not_found ->
            raise (Var_not_found ("No stack for " ^ (nm v)))

        (* ORIGINAL:
        try
            let i = Hashtbl.find counters (nm v) in
            let new_v = v#copy (sprintf "%s_Y%d" v#get_name i) in
            s_push v i;
            Hashtbl.replace counters (nm v) (i + 1);
            new_v
        with Not_found ->
            raise (Var_not_found ("Var not found: " ^ v#qual_name))
        *)
    in
    (* initialize local variables: start with 1 as 0 is reserved for input *)
    (* ORIGINAL:
    List.iter (fun v -> Hashtbl.add counters (nm v) 1) intern_vars;
    *)
    List.iter (fun v -> Hashtbl.add stacks (nm v) []) intern_vars;
    (* global vars are different,
       each global variable x has a version x_0 referring
       to the variable on the input
     *)
    (* ORIGINAL:
    List.iter (fun v -> Hashtbl.add counters (nm v) 1) extern_vars;
    *)
    List.iter (fun v -> Hashtbl.add stacks (nm v) [0]) extern_vars;

    let sub_var v =
        if v#is_symbolic
        (* do not touch symbolic variables, they are parameters! *)
        then v                (* TODO: what about atomic propositions? *)
        else 
            let i = s_top v in
            let suf = (if i = 0 then "IN" else sprintf "Y%d" i) in
            v#copy (sprintf "%s_%s" v#get_name suf) (* not a qualified name! *)
    in
    let sub_var_as_var e v =
        try Var (sub_var v)
        with Var_not_found m ->
            raise (Var_not_found (m ^ " in " ^ (expr_s e)))
    in
    let rec search x =
        let bb = cfg#find x in
        let bb_old_seq = bb#get_seq in
        let replace_rhs = function
            | Decl (id, v, e) ->
                    Decl (id, v, map_rvalues (sub_var_as_var e) e)
            | Expr (id, e) ->
                    Expr (id, map_rvalues (sub_var_as_var e) e)
            | Assume (id, e) ->
                    Assume (id, map_rvalues (sub_var_as_var e) e)
            | Assert (id, e) ->
                    Assert (id, map_rvalues (sub_var_as_var e) e)
            | _ as s -> s
        in
        let replace_lhs = function
            | Decl (id, v, e) -> Decl (id, (intro_var v), e)
            | Expr (id, BinEx (ASGN, Var v, rhs)) ->
                    Expr (id, BinEx (ASGN, Var (intro_var v), rhs))
            | Expr (id, (BinEx (ASGN, BinEx (ARR_ACCESS, Var v, idx), rhs) as e)) ->
                    (* A_i <- Update(A_j, k, e) *)
                    let old_arr =
                        try Var (sub_var v)
                        with Var_not_found m ->
                            raise (Var_not_found (m ^ " in " ^ (expr_s e)))
                    in
                    let upd = BinEx (ARR_UPDATE,
                        BinEx (ARR_ACCESS, old_arr, idx), rhs) in
                    Expr (id, BinEx (ASGN, Var (intro_var v), upd))
            | Expr (id, Phi (v, rhs)) ->
                    Expr (id, Phi (intro_var v, rhs))
            | Havoc (id, v) ->
                    (* just introduce a fresh one *)
                    let _ = intro_var v in
                    Skip id
            | _ as s -> s
        in
        let on_stmt lst s = (replace_lhs (replace_rhs s)) :: lst in
        bb#set_seq (List.rev (List.fold_left on_stmt [] bb#get_seq));
        (* put the variables in the successors *)
        let sub_phi_arg y =
            let succ_bb = cfg#find y in
            let j = Accums.list_find_pos x succ_bb#pred_labs in
            let on_phi = function
            | Expr (id, Phi (v, rhs)) ->
                let (before, e, after) = Accums.list_nth_slice rhs j in
                let new_e =
                    try sub_var e
                    with Var_not_found s ->
                        let m =
                            (sprintf "sub_phi_arg(x = %d, y = %d): %s" x y s) in
                        raise (Var_not_found m)
                in
                Expr (id, Phi (v, before @ (new_e :: after)))
            | _ as s -> s
            in
            succ_bb#set_seq (List.map on_phi succ_bb#get_seq)
        in
        List.iter sub_phi_arg bb#succ_labs;
        (* visit children in the dominator tree *)
        List.iter search (Hashtbl.find idom_tree x);
        (* our extension: if we are at the exit block,
           then add x_OUT for each shared variable x *)
        if bb#get_succ = []
        then begin
            let bind_out v =
                let out_v = v#copy (v#get_name ^ "_OUT") in
                Expr (fresh_id (), BinEx (ASGN, Var out_v,
                    sub_var_as_var (Nop "bind_out") v)) in
            let out_assignments = List.map bind_out extern_vars in
            bb#set_seq (bb#get_seq @ out_assignments);
        end;
        let pop_v v = s_pop v#qual_name in
        let pop_stmt = function
            | Decl (_, v, _) -> pop_v v
            | Expr (_, Phi (v, _)) -> pop_v v
            | Expr (_, BinEx (ASGN, Var v, _)) -> pop_v v
            | Expr (_, BinEx (ASGN, BinEx (ARR_ACCESS, Var v, _), _)) ->
                    pop_v v
            | Havoc (_, v) -> pop_v v
            | _ -> ()
        in
        List.iter pop_stmt bb_old_seq
    in
    search 0;
    List.iter (reduce_indices cfg) vars;
    optimize_ssa cfg (* optimize it after all *)


(* move explicit statements x_1 = phi(x_2, x_3) to basic blocks (see bddPass) *)
let move_phis_to_blocks cfg =
    let move_in_bb bb =
        let on_stmt lst = function
        | Expr (_, Phi (lhs, rhs)) ->
                bb#set_phis ((Phi (lhs, rhs)) :: bb#get_phis);
                lst
        | _ as s ->
                s :: lst
        in
        bb#set_seq (List.fold_left on_stmt [] (List.rev bb#get_seq))
    in
    List.iter move_in_bb cfg#block_list;
    cfg

