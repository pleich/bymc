open Printf;;

open Parse;;
open Abstract;;
open Writer;;
open Debug;;

type options =
    {
        abstract: bool; refine: bool; check_inv: bool;
        trail_name: string; filename: string; 
        inv_name: string;
        verbose: bool
    }

let parse_options =
    let opts = ref {
        abstract = false; refine = false; check_inv = false;
        trail_name = ""; filename = ""; inv_name = "";
        verbose = false
    } in
    (Arg.parse
        [
            ("-a", Arg.Unit (fun () -> opts := {!opts with abstract = true}),
             "Produce abstraction of a Promela program.");
            ("-t", Arg.String
             (fun s -> opts := {!opts with refine = true; trail_name = s}),
             "Check feasibility of a counterexample produced by spin -t (not a *.trail!).");
            ("-i", Arg.String
             (fun s -> opts := {!opts with check_inv = true; inv_name = s}),
             "Check if an atomic proposition is an invariant!.");
            ("-v", Arg.Unit (fun () -> opts := {!opts with verbose = true}),
             "Produce lots of verbose output (you are warned).");
        ]
        (fun s ->
            if !opts.filename = "" then opts := {!opts with filename = s})
        "Use: run [-a] [-i invariant] [-c spin_sim_out] promela_file");

    !opts
;;

let write_to_file name units =
    let fo = open_out name in
    List.iter (write_unit fo 0) units;
    close_out fo
;;

let _ =
    try
        let opts = parse_options in
        current_verbosity_level := if opts.verbose then DEBUG else INFO;
        let filename, basename, dirname =
            if Array.length Sys.argv > 1
            then opts.filename,
                Filename.basename opts.filename, Filename.dirname opts.filename
            else raise (Failure (sprintf "File not found: %s" opts.filename))
        in
        log INFO (sprintf "> Parsing %s..." basename);
        let units = parse_promela filename basename dirname in
        write_to_file "original.prm" units;
        log INFO "  [DONE]";
        log DEBUG (sprintf "#units: %d" (List.length units));
        if opts.abstract
        then let _ = do_abstraction true units in ()
        else if opts.refine
        then let _ = do_refinement opts.trail_name units in ()
        else if opts.check_inv
        then let _ = check_invariant opts.inv_name units in ()
        else printf "No options given. Bye.\n"
    with End_of_file ->
        log ERROR "Premature end of file";
        exit 1

