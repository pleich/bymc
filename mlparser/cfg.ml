open Printf;;

open Spin_ir;;
open Spin_ir_imp;;
open Debug;;

module IntSet = Set.Make (struct
 type t = int
 let compare a b = a - b
end);;

class ['t] basic_block =
    object(self)
        val mutable seq: 't stmt list = []
        val mutable succ: 't basic_block list = []
        val mutable pred: 't basic_block list = []
        (* this flag can be used to traverse along basic blocks *)
        val mutable visit_flag = false

        method set_seq s = seq <- s
        method get_seq = seq

        method set_succ s = succ <- s
        method get_succ = succ

        method set_pred p = pred <- p
        method get_pred = pred

        method set_visit_flag f = visit_flag <- f
        method get_visit_flag = visit_flag

        method get_exit_labs =
            match List.hd (List.rev seq) with
                | Goto i -> [i]
                | If (is, _) -> is
                | _ -> [] (* an exit block *)

        method get_lead_lab =
            match List.hd seq with
                | Label i -> i
                | _ -> raise (Failure "Corrupted basic block, no leading label")

        method str =
            let exit_s = List.fold_left
                (fun a i ->
                    sprintf "%s%s%d" a (if a <> "" then ", " else "") i) 
                "" self#get_exit_labs in
            (sprintf "Basic block %d [succs: %s]:\n" self#get_lead_lab exit_s) ^
            (List.fold_left (fun a s -> sprintf "%s%s\n" a (stmt_s s)) "" seq)
    end
;;

class ['t, 'attr] attr_basic_block a =
    object(self)
        inherit ['t] basic_block as super

        val mutable attr: 'attr = a

        method as_basic_block = (self :> ('t) basic_block)

        method set_attr a = attr <- a
        
        method get_attr = attr
    end
;;

(* collect labels standing one next to each other *)
let replace_neighb_labels stmts =
    let neighb = Hashtbl.create 10
    in
    List.iter2
        (fun s1 s2 ->
            match s1, s2 with
            | Label i, Label j ->
                if Hashtbl.mem neighb i
                (* add the neighbor of i *)
                then Hashtbl.add neighb j (Hashtbl.find neighb i)
                (* add i itself *)
                else Hashtbl.add neighb j i
            | _ -> ()
        )
        (List.rev (List.tl (List.rev stmts))) (List.tl stmts);
    let sub_lab i = if (Hashtbl.mem neighb i) then Hashtbl.find neighb i else i
    in
    List.map
        (fun s ->
            match s with
            | Goto i -> Goto (sub_lab i)
            | If (targs, exit) -> If ((List.map sub_lab targs), (sub_lab exit))
            | _ -> s
        ) stmts
;;

let collect_jump_targets stmts =
    List.fold_left
        (fun targs stmt ->
            match stmt with
                | Goto i -> IntSet.add i targs
                | If (is, _)  -> List.fold_right IntSet.add is targs
                | _      -> targs
        )
        IntSet.empty
        stmts
;;

(* split a list into a list of list each terminating with an element
   recognized by is_sep
 *)
let separate is_sep list_i =
    let rec sep_rec lst =
        match lst with
            | [] -> []
            | hd :: tl ->
                let res = sep_rec tl in
                match res with
                    | [] ->
                        if is_sep hd then [[]; [hd]] else [[hd]]
                    | hdl :: tll ->
                        if is_sep hd
                        then [] :: (hd :: hdl) :: tll
                        else (hd :: hdl) :: tll
    in (* clean hanging empty sets *)
    List.filter (fun l -> l <> []) (sep_rec list_i)
;;

let basic_block_tbl_s bbs =
    Hashtbl.iter
        (fun i bb -> printf "\nBasic block %d:\n" i;
            List.iter (fun s -> printf "%s\n" (stmt_s s)) bb#get_seq)
        bbs
;;

let mk_cfg stmts =
    let stmts_r = replace_neighb_labels stmts in
    let seq_heads = collect_jump_targets stmts_r in
    let cleaned = List.filter (* remove hanging unreferenced labels *)
        (fun s ->
            match s with
                | Label i -> IntSet.mem i seq_heads
                | _ -> true)
        stmts_r in
    let seq_list = separate
            (fun s ->
                match s with (* separate by jump targets *)
                    | Label i -> IntSet.mem i seq_heads
                    | _ -> false)
            (* add 0 in front to denote the entry label *)
            ((Label 0):: cleaned) in
    let blocks = Hashtbl.create (List.length seq_list) in
    (* create basic blocks *)
    List.iter
        (fun seq ->
            match seq with
            | (Label i) :: tl ->
                let b = new basic_block in
                b#set_seq seq; Hashtbl.add blocks i b
            | _ -> raise (Failure "Broken head: expected (Label i) :: tl"))
        seq_list;
    (* set successors *)
    Hashtbl.iter
        (fun _ bb -> bb#set_succ
            (List.map (Hashtbl.find blocks) bb#get_exit_labs))
        blocks;
    (* set predecessors *)
    Hashtbl.iter
        (fun _ bb ->
            List.iter (fun s -> s#set_pred (bb :: s#get_pred)) bb#get_succ)
        blocks;
    (* return the hash table: heading_label: int -> basic_block *)
    blocks
