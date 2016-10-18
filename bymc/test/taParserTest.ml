open Batteries
open OUnit

open TaIr

let expect_ta skel text =
    let out = TaParser.parse_input "<string>" (IO.input_string text) in
    (*print_skel IO.stdout out;*)
    assert_equal skel out


let expect_exception text =
    try
        ignore (TaParser.parse_input "<string>" (IO.input_string text));
        assert_failure "expected ParseErr"
    with TaParser.ParseErr _ -> ()


let test_header _ =
    let text = "\
skel foo {
    assumptions (0) { }
    locations (0) { }
    inits (0) { }
    rules (0) { }
}"
    in
    expect_ta (mk_ta "foo" [] [] [] [] []) text


let test_header_skel_wrong _ =
    let text = "\
skelzz foo {}"
    in
    expect_exception text


let test_header_no_name _ =
    let text = "\
skel {}"
    in
    expect_exception text


let test_header_paren_wrong _ =
    let text = "\
skel foo ()"
    in
    expect_exception text


let test_decl_local _ =
    let text = "\
skel foo {
    local x, y;
    assumptions (0) { }
    locations (0) { }
    inits (0) { }
    rules (0) { }
}"
    in
    expect_ta (TaIr.mk_ta "foo" [ Local "x"; Local "y" ] [] [] [] []) text


let test_decl_local_many _ =
    let text = "\
skel foo {
    local x, y; local z;
    assumptions (0) { }
    locations (0) { }
    inits (0) { }
    rules (0) { }
}"
    in
    expect_ta (TaIr.mk_ta "foo" [ Local "x"; Local "y"; Local "z" ] [] [] [] []) text


let test_decl_local_empty _ =
    let text = "\
skel foo { local; }"
    in
    expect_exception text


let test_decl_shared _ =
    let text = "\
skel foo {
    shared x, y;
    assumptions (0) { }
    locations (0) { }
    inits (0) { }
    rules (0) { }
}"
    in
    expect_ta (TaIr.mk_ta "foo" [ Shared "x"; Shared "y" ] [] [] [] []) text


let test_decl_shared_many _ =
    let text = "\
skel foo {
    shared x, y; shared z;
    assumptions (0) { }
    locations (0) { }
    inits (0) { }
    rules (0) { }
}"
    in
    expect_ta (TaIr.mk_ta "foo" [ Shared "x"; Shared "y"; Shared "z" ] [] [] [][]) text


let test_decl_shared_empty _ =
    let text = "\
skel foo { shared; }"
    in
    expect_exception text


let test_decl_params _ =
    let text = "\
skel foo {
    parameters x, y;
    assumptions (0) { }
    locations (0) { }
    inits (0) { }
    rules (0) { }
}"
    in
    expect_ta (TaIr.mk_ta "foo" [ Param "x"; Param "y" ] [] [] [] []) text


let test_decl_params_many _ =
    let text = "\
skel foo {
    parameters x, y; parameters z;
    assumptions (0) { }
    locations (0) { }
    inits (0) { }
    rules (0) { }
}"
    in
    expect_ta (TaIr.mk_ta "foo" [ Param "x"; Param "y"; Param "z" ] [] [] [] []) text


let test_decl_params_empty _ =
    let text = "\
skel foo { parameters; }"
    in
    expect_exception text


let test_assumptions_one _ =
    let text = "\
skel foo {
    local x; shared g; parameters n, t;
    assumptions (1) {
        n > 3 * t;
    }
    locations (0) { }
    inits (0) { }
    rules (0) { }
}"
    in
    let ds = [ Local "x"; Shared "g"; Param "n"; Param "t" ] in
    let ass = [ Gt (Var "n", Mul (Int 3, Var "t")) ] in
    expect_ta (TaIr.mk_ta "foo" ds ass [] [] []) text

    
let test_assumptions_many _ =
    let text = "\
skel foo {
    local x; shared g; parameters n, t;
    assumptions (1) {
        n > 3 * t;
        ((t) <= (0));
    }
    locations (0) { }
    inits (0) { }
    rules (0) { }
}"
    in
    let ds = [ Local "x"; Shared "g"; Param "n"; Param "t" ] in
    let ass = [
        Gt (Var "n", Mul (Int 3, Var "t"));
        Leq (Var "t", Int 0);

    ] in
    expect_ta (TaIr.mk_ta "foo" ds ass [] [] []) text

    
let test_locations _ =
    let text = "\
skel foo {
    local x, y; shared g; parameters n, t;
    assumptions (0) {
    }
    locations (3) {
        loc_a: [0; 0];
        loc_b: [0; 1];
        loc_c: [1; 1];
    }
    inits (0) { }
    rules (0) { }
}"
    in
    let ds = [ Local "x"; Local "y"; Shared "g"; Param "n"; Param "t" ] in
    let locs = [ ("loc_a", [0; 0]); ("loc_b", [0; 1]); ("loc_c", [1; 1]) ] in
    expect_ta (TaIr.mk_ta "foo" ds [] locs [] []) text

    
let test_locations_wrong _ =
    let text = "\
skel foo {
    local x, y; shared g; parameters n, t;
    assumptions (0) {
    }
    locations (3) {
        loc_a: [0];
        loc_b: [0; 1];
        loc_c: [1; 1; 1];
    }
    inits (0) { }
    rules (0) { }
}"
    in
    expect_exception text

    
let test_inits _ =
    let text = "\
skel foo {
    local x, y; shared g; parameters n, t;
    assumptions (0) {
    }
    locations (0) {
        loc_a: [0; 0];
        loc_b: [0; 1];
    }
    inits (2) {
        loc_a == n - t;
        loc_b == t;
    }
    rules (0) { }
}"
    in
    let ds = [ Local "x"; Local "y"; Shared "g"; Param "n"; Param "t" ] in
    let locs = [ ("loc_a", [0; 0]); ("loc_b", [0; 1]) ] in
    let inits = [
        Eq (Var "loc_a", Sub (Var "n", Var "t"));
        Eq (Var "loc_b", Var "t");

    ] in
    expect_ta (TaIr.mk_ta "foo" ds [] locs inits []) text

    
let test_rules _ =
    let text = "\
skel foo {
    local x, y; shared g; parameters n, t;
    assumptions (0) {
    }
    locations (0) {
        loc_a: [0; 0];
        loc_b: [0; 1];
    }
    inits (0) {
    }
    rules (1) {
    0:  loc_a -> loc_b
        when (g >= t + 1)
        do { g' == (g + 1) };
    }
}"
    in
    let ds = [ Local "x"; Local "y"; Shared "g"; Param "n"; Param "t" ] in
    let locs = [ ("loc_a", [0; 0]); ("loc_b", [0; 1]) ] in
    let rules = [
        { Ta.src_loc = 0; Ta.dst_loc = 1;
          guard = Cmp (Geq (Var "g", Add (Var "t", Int 1)));
          action = Cmp (Eq (NextVar "g", Add (Var "g", Int 1)))
        }
    ] in
    expect_ta (TaIr.mk_ta "foo" ds [] locs [] rules) text

    
let test_rules_two _ =
    let text = "\
skel foo {
    local x, y; shared g; parameters n, t;
    assumptions (0) {
    }
    locations (0) {
        loc_a: [0; 0];
        loc_b: [0; 1];
    }
    inits (0) {
    }
    rules (2) {
    0:  loc_a -> loc_b
        when (g >= t + 1)
        do { g' == g + 1 };
    1:  loc_b -> loc_a
        when (g >= n - t)
        do { g' == g + 1 };
    }
}"
    in
    let ds = [ Local "x"; Local "y"; Shared "g"; Param "n"; Param "t" ] in
    let locs = [ ("loc_a", [0; 0]); ("loc_b", [0; 1]) ] in
    let rules = [
        { Ta.src_loc = 0; Ta.dst_loc = 1;
          guard = Cmp (Geq (Var "g", Add (Var "t", Int 1)));
          action = Cmp (Eq (NextVar "g", Add (Var "g", Int 1)));
        };
        { Ta.src_loc = 1; Ta.dst_loc = 0;
          guard = Cmp (Geq (Var "g", Sub (Var "n", Var "t")));
          action = Cmp (Eq (NextVar "g", Add (Var "g", Int 1)));
        };
    ] in
    expect_ta (TaIr.mk_ta "foo" ds [] locs [] rules) text

    
let test_rules_bool _ =
    let text = "\
skel foo {
    local x, y; shared g; parameters n, t;
    assumptions (0) {
    }
    locations (0) {
        loc_a: [0; 0];
        loc_b: [0; 1];
    }
    inits (0) {
    }
    rules (2) {
    0:  loc_a -> loc_b
        when (g >= t + 1)
        do { g' == g + 1 };
    1:  loc_b -> loc_a
        when ((g >= n - t) && ((g < 1) || (g >= n)))
        do { g' == g + 1 };
    }
}"
    in
    let ds = [ Local "x"; Local "y"; Shared "g"; Param "n"; Param "t" ] in
    let locs = [ ("loc_a", [0; 0]); ("loc_b", [0; 1]) ] in
    let rules = [
        { Ta.src_loc = 0; Ta.dst_loc = 1;
          guard = Cmp (Geq (Var "g", Add (Var "t", Int 1)));
          action = Cmp (Eq (NextVar "g", Add (Var "g", Int 1)))
        };
        { Ta.src_loc = 1; Ta.dst_loc = 0;
          guard = And (Cmp (Geq (Var "g", Add (Var "t", Int 1))),
                       Not (Or (Cmp (Lt (Var "g", Int 1)),
                           Cmp (Geq (Var "g", Var "n")))));
          action = Cmp (Eq (NextVar "g", Add (Var "g", Int 1)));
        };
    ] in
    expect_ta (TaIr.mk_ta "foo" ds [] locs [] rules) text


let suite = "taParser-suite" >:::
    [
        "test_header" >:: test_header;
        "test_header_skel_wrong" >:: test_header_skel_wrong;
        "test_header_no_name" >:: test_header_no_name;
        "test_header_paren_wrong" >:: test_header_paren_wrong;
        "test_decl_local" >:: test_decl_local;
        "test_decl_local_many" >:: test_decl_local_many;
        "test_decl_local_empty" >:: test_decl_local_empty;
        "test_decl_shared" >:: test_decl_shared;
        "test_decl_shared_many" >:: test_decl_shared_many;
        "test_decl_shared_empty" >:: test_decl_shared_empty;
        "test_decl_params" >:: test_decl_params;
        "test_decl_params_many" >:: test_decl_params_many;
        "test_decl_params_empty" >:: test_decl_params_empty;
        "test_assumptions_one" >:: test_assumptions_one;
        "test_assumptions_many" >:: test_assumptions_many;
        "test_locations" >:: test_locations;
        "test_locations_wrong" >:: test_locations_wrong;
        "test_inits" >:: test_inits;
        "test_rules" >:: test_rules;
        (*
        "test_rules_two" >:: test_rules_two;
        "test_rules_bool" >:: test_rules_bool;
        *)
    ]

