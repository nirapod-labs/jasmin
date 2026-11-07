open Jasmin
open Cmdliner
open CommonCLI
open Utils

(* The name of the EasyCrypt theory of the extracted model, from its file. *)
let theory_name outfile =
  match outfile with
  | None -> ""
  | Some f ->
      let basename = Filename.basename f in
      let basename =
        try Filename.chop_extension basename with Invalid_argument _ -> basename
      in
      String.capitalize_ascii basename

let format_to_file outfile action =
  let fmt, close =
    match outfile with
    | None -> (Format.std_formatter, fun () -> ())
    | Some f ->
        let out = open_out f in
        let fmt = Format.formatter_of_out_channel out in
        (fmt, fun () -> close_out out)
  in
  try BatPervasives.finally (fun () -> close ()) (fun () -> action fmt) ()
  with e ->
    BatPervasives.ignore_exceptions
      (fun () -> Option.map Unix.unlink outfile)
      ();
    raise e

(* In the safety model the extracted program and the file of its safety
   lemmas are written separately: either one, or both when both files are
   given. *)
let extract_to_file prog arch pd msfsz asmOp model amodel global_options
    fnames array_dir outfile prooffile =
  let array_dir =
    if array_dir = None then Option.map Filename.dirname outfile else array_dir
  in
  let extract () =
    format_to_file outfile (fun fmt ->
        ToEC.extract prog arch pd msfsz asmOp model amodel global_options
          fnames array_dir fmt)
  in
  let extract_proof () =
    format_to_file prooffile (fun fmt ->
        ToEC.generate_safety_lemmas (theory_name outfile) prog arch pd msfsz
          asmOp model amodel global_options fnames array_dir fmt)
  in
  match (model, outfile, prooffile) with
  | SafetyAnnotations, None, Some _ -> extract_proof ()
  | SafetyAnnotations, Some _, Some _ -> extract (); extract_proof ()
  | _ -> extract ()

let parse_and_extract arch call_conv idirs =
  let module A = (val CoreArchFactory.get_arch_module arch call_conv) in
  let extract model amodel global_options functions array_dir output
      output_proof pass file =
    (* The safety conditions are stated on the program as written, then the
       loops are put in the form the extraction expects. *)
    let prog = parse_and_compile (module A) ~wi2i:true pass file idirs in
    let prog =
      if model = SafetyAnnotations then Compile.do_safety (module A) prog
      else prog
    in
    let prog = Compile.do_toec (module A) prog in
    try
      extract_to_file prog arch A.reg_size A.msf_size A.asmOp model amodel
        global_options functions array_dir output output_proof
    with Annot.AnnotationError (loc, code) ->
      hierror ~loc:(Lone loc) ~kind:"annotation error" "%t" code
  in
  fun model amodel global_options functions array_dir output output_proof pass
      file warn ->
    if not warn then nowarning ();
    match
      extract model amodel global_options functions array_dir output
        output_proof pass file
    with
    | () -> ()
    | exception HiError e ->
        Format.eprintf "%a@." pp_hierror e;
        exit 1

let model =
  let alts =
    [
      ("normal", Normal);
      ("CT", ConstantTime);
      ("CTG", ConstantTimeGlobal);
      ("safety", SafetyAnnotations);
    ]
  in
  let doc =
    "Extraction model.
    $(b,normal): plain extraction.
    $(b,CT): Functions additionally return timing-observable leakage for
    'cryptographic constant time' (if/while conditions, memory access
    addresses, array indices, for loop bounds).
    $(b,safety): the safety conditions of the program as assertions, collected
    in a trace that each function returns; see $(b,--output-proof).
    (Deprecated) $(b,CTG): Cryptographic constant time leakage is added to a
    global variable."
  in
  Arg.(value & opt (Arg.enum alts) Normal & info [ "m"; "model" ] ~doc)

let array_model =
  let alts =
    [ ("old", ToEC.ArrayOld); ("warray", ToEC.WArray); ("barray", ToEC.BArray) ]
  in

  let doc =
    "Array model.
     $(b,warray): use polymorphic arrays and warrays (functions predefined in eclib).
     $(b,barray): use byte arrays (functions predefined in eclib).
     (Deprecated) $(b,old): old representation for array operations (anonymous functions instead of eclib functions)."
  in
  Arg.(value & opt (Arg.enum alts) ToEC.BArray & info [ "array-model" ] ~doc)

(* The extraction of global variables is configured by the repeatable
   --global-model option, whose value selects either the kind of the EasyCrypt
   declaration (abbrev, op, op=OPTIONS) or how the machine words are printed
   (sign=signed, sign=unsigned). *)
let global_model =
  (* Each occurrence of the option is a “key” or a “key = value”; the spaces
     around the “=” are ignored. *)
  let alts = [ "abbrev"; "op"; "op=OPTIONS"; "sign=signed"; "sign=unsigned" ] in
  let sign =
    Arg.enum [ ("signed", ToEC.GlobSigned); ("unsigned", ToEC.GlobUnsigned) ]
  in
  (* the shell usually removes the quotes of “op="opaque smt_opaque"”, but they
     reach us when written as --global-model='op="opaque smt_opaque"' *)
  let unquote s =
    let n = String.length s in
    if n >= 2 && s.[0] = '"' && s.[n - 1] = '"' then
      String.trim (String.lchop (String.rchop s))
    else s
  in
  let parse s =
    let key, value =
      match String.split s ~by:"=" with
      | key, value -> (String.trim key, Some (String.trim value))
      | exception Not_found -> (String.trim s, None)
    in
    match (key, value) with
    | "abbrev", None -> Ok (`Model ToEC.GlobAbbrev)
    | "op", None -> Ok (`Model (ToEC.GlobOp ""))
    | "op", Some opts -> Ok (`Model (ToEC.GlobOp (unquote opts)))
    | "sign", Some v -> (
        match Arg.conv_parser sign v with
        | Ok s -> Ok (`Sign s)
        | Error (`Msg e) -> Error (`Msg e))
    | _ ->
        Error
          (`Msg
            (Format.sprintf "invalid value “%s”, must be %s" s
               (Arg.doc_alts ~quoted:true alts)))
  in
  let pp fmt = function
    | `Model g -> Format.pp_print_string fmt (ToEC.string_of_gmodel g)
    | `Sign g -> Format.fprintf fmt "sign=%s" (ToEC.string_of_gsign g)
  in
  let doc =
    "How global variables are extracted; this option may be repeated, the last
     value of each kind wins (the spaces around the '=' are optional).
     $(b,abbrev) (the default): as EasyCrypt abbreviations.
     $(b,op): as EasyCrypt operators.
     $(b,op)=$(i,OPTIONS): as EasyCrypt operators declared with the given
     options, e.g. $(b,op=\"opaque smt_opaque\"); the options are passed to
     EasyCrypt as such.
     These defaults can be overridden for each global variable using the
     $(b,#[abbrev]) and $(b,#[op]) annotations.
     $(b,sign=signed) (the default): the machine words are printed as integers
     in [-2^(n-1), 2^(n-1)), e.g. $(b,W64.of_int (-1)).
     $(b,sign=unsigned): they are printed as integers in [0, 2^n), e.g.
     $(b,W64.of_int 18446744073709551615).
     Both denote the same words, but the unsigned form avoids the unary minus,
     which is cheaper to handle in EasyCrypt."
  in
  let global_options =
    List.fold_left
      (fun (global_options : ToEC.global_options) -> function
        | `Sign gsign -> { global_options with gsign }
        | `Model gmodel -> { global_options with gmodel })
      ToEC.default_global_options
  in
  Term.(
    const global_options
    $ Arg.(
        value
        & opt_all (conv (parse, pp)) []
        & info [ "global-model" ] ~docv:"MODEL" ~doc))

let functions =
  let doc =
    "Only extract the given function (and its dependencies). This argument may \
     be extract to check many functions. If not given, all functions will be \
     extracted."
  in
  Arg.(value & opt_all string [] & info [ "f"; "function" ] ~doc)

let output =
  let doc = "Output file. If not given, output will be printed on stdout." in
  Arg.(
    value
    & opt (some string) None
    & info [ "o"; "output" ] ~docv:"OUTPUT FILE" ~doc)

let output_proof =
  let doc =
    "With the safety model: the file of the safety lemmas, one per function \
     from its contract, with proof skeletons."
  in
  Arg.(
    value
    & opt (some string) None
    & info [ "output-proof" ] ~docv:"OUTPUT PROOF FILE" ~doc)

let array_dir =
  let doc =
    "Directory for generation of easycrypt array theories. \
     If not given, the theories be in the same directory as the output \
     (they will not be generated if the output is stdout)."
  in
  Arg.(
    value
    & opt (some dir) None
    & info [ "oa"; "output-array" ] ~docv:"OUTPUT DIR" ~doc)

let file =
  let doc = "The Jasmin source file to extract" in
  Arg.(required & pos 0 (some non_dir_file) None & info [] ~docv:"JAZZ" ~doc)

let () =
  let doc = "Extract Jasmin program to easycrypt" in
  let man =
    [
      `S Manpage.s_environment;
      Manpage.s_environment_intro;
      `I ("OCAMLRUNPARAM", "This is an OCaml program");
      `I ("JASMINPATH", "To resolve $(i,require) directives");
    ]
  in
  let info =
    Cmd.info "jasmin2ec" ~version:Glob_options.version_string ~doc ~man
  in
  Cmd.v info
    Term.(
      const parse_and_extract $ arch $ call_conv $ idirs $ model $ array_model
      $ global_model $ functions $ array_dir $ output $ output_proof $ after_pass
      $ file $ warn)
  |> Cmd.eval |> exit
