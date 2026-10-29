open Jasmin
open Prog
open Apron
open Wsize
open Utils

type v_scope = Expr.v_scope
                 
open SafetyUtils
    
(* Memory locations: the region an export argument [x] points to
   ([MemLoc x]), and the region that the pointer held, at entry, in cell [k]
   of an export array argument [x] of pointer-width cells points to
   ([MemCell (x, k)]). *)
type mem_loc = MemLoc of var | MemCell of var * int

(* (v,ws,i) is the slice [8*i; 8*i + ws[ of v. 
     Note that the slice offset is not scaled on the word-size. *)
type slice = var * wsize * int
             
type atype =
  | Avar of var                     (* Variable *)
  | Aarray of var                   (* Array *)
  | AarraySlice of slice

type mvar =
  | Temp of string * int * ty   (* Temporary variable *)
  | WTemp of string * int * ty  (* Temporary variable (weak updates) *)
  | Mglobal of atype            (* Global variable *)
  | Mlocal of atype             (* Local variable value *)
  | MinLocal of var             (* Local variable initial value *)
  | MvarOffset of var           (* Local variable offset *)
  | MNumInv of L.i_loc          (* Numerical Invariants *)
  | MmemRange of mem_loc        (* Memory location range *)
  | MinitPrefix of var * int    (* Initialised prefix of an array: the
                                   number of initialised bytes of [x] from
                                   the byte base [c]. *)

(*---------------------------------------------------------------*)
(* Must the variable [v] be handled as a weak variable. *)
let weak_update v = 
  let weak_update_kind = function
    | Const -> assert false     (* should not happen *)
    | Stack _
    | Reg _
    | Inline
    | Global -> false in

  match v with
  | Mglobal _ -> false (* global variable are read-only. *)
  | Temp _
  | MNumInv _ -> false

  | Mlocal at -> begin match at with
      | Avar gv | Aarray gv | AarraySlice (gv,_,_) ->
        weak_update_kind gv.v_kind
    end

  | MinLocal gv
  | MvarOffset gv ->  weak_update_kind gv.v_kind 

  | MmemRange _ -> true
  | MinitPrefix _ -> false
  | WTemp _ -> true

(*---------------------------------------------------------------*)
(* An export array argument gets one region per pointer-width cell
   ([MemCell]), at most [max_table_cells] of them. An array that is not of
   this shape gets no cell region, which only means that a pointer read
   from it points to anything: losing regions is always sound. *)
let max_table_cells = 64

let is_table_arg pd x = match x.v_ty with
  | Arr (ws, n) -> ws = pd && 0 <= n && n <= max_table_cells
  | Bty _ -> false

(* The name of a region is a dimension name of the numerical domains. Export
   arguments are never renamed ([MkUniq] processes the export first and
   keeps the first variable of each name, see [SafetyInterpreter.AbsMake]),
   and a Jasmin identifier has no '.', so [x] and [x.k] and [x'.k'] are
   pairwise distinct. [export_mem_locs] checks the uniqueness of the list it
   builds. *)
let string_of_mloc = function
  | MemLoc s -> s.v_name
  | MemCell (s, k) -> s.v_name ^ "." ^ string_of_int k

let string_of_atype = function
  | Avar s -> "v_" ^ s.v_name
  | Aarray t -> "a_" ^ t.v_name
  | AarraySlice (t,ws,int) ->
    "ael_" ^ t.v_name ^ "_" ^ string_of_int (int_of_ws ws)
    ^ "_" ^ string_of_int int

let string_of_mvar = function
  | Temp (s, i, _) -> "tmp_" ^ s ^ "_" ^ string_of_int i
  | WTemp (s, i, _) -> "wtmp_" ^ s ^ "_" ^ string_of_int i
  | Mglobal at -> "g_" ^ string_of_atype at
  | MinLocal s -> "inv_" ^ s.v_name
  | Mlocal at -> string_of_atype at
  | MvarOffset s -> "o_" ^ s.v_name
  | MNumInv lt -> "ni_" ^ string_of_int (fst lt.base_loc.loc_start)
  | MmemRange loc -> "mem_" ^ string_of_mloc loc
  | MinitPrefix (v, c) -> "g_" ^ v.v_name ^ "_" ^ string_of_int c

let pp_mvar fmt v = Format.fprintf fmt "%s" (string_of_mvar v)

(*---------------------------------------------------------------*)
let dummy_mvar = Mlocal (Avar (V.mk "__absint_empty_env"
                                 (Reg(Normal, Direct)) (Bty (U U8)) (L._dummy) []))

(*---------------------------------------------------------------*)
let svariables_ignore vs =
  match String.split_on_char '_' vs with
  | [] -> assert false
  | vs' :: _ -> match String.split_on_char '@' vs' with
    | "inv" :: _ -> true
    | "ael" :: _  -> Config.sc_arr_no_print ()
    | "g" :: _  -> Config.sc_glob_no_print ()
    | _ -> false

let variables_ignore v =
  let vs = Var.to_string v in
  svariables_ignore vs

let mvar_ignore = function
  | MinLocal _ -> true
  | Mlocal (AarraySlice _) -> Config.sc_arr_no_print ()
  | Mglobal _ -> Config.sc_glob_no_print ()
  | _ -> false
    
(*---------------------------------------------------------------*)
let arr_range (v : var) : int = match v.v_ty with
  | Arr (_,i) -> i
  | _ -> assert false

let arr_size v = match v.v_ty with
  | Arr (ws,_) -> ws
  | _ -> assert false

let untracked_cell = function
  | Mlocal (AarraySlice (v,_,_)) | Mglobal (AarraySlice (v,_,_)) ->
    let m = Config.sc_array_track_max_bytes () in
    m >= 0 && arr_range v * size_of_ws (arr_size v) > m
  | _ -> false

let ty_atype = function
  | Avar s -> s.v_ty
  | Aarray t -> t.v_ty
  | AarraySlice (_,ws,_) -> Bty (U ws)

let ty_mvar = function
  | Temp (_,_,ty) -> ty
  | WTemp (_,_,ty) -> ty
  | MinLocal s -> s.v_ty
  | Mglobal at | Mlocal at -> ty_atype at
  | MvarOffset _ -> Bty Int
  | MNumInv _ -> Bty Int
  | MmemRange _ -> Bty Int
  | MinitPrefix _ -> Bty Int

(*---------------------------------------------------------------*)
let of_scope scope at = match scope with
  | Expr.Slocal -> Mlocal  at
  | Expr.Sglob  -> Mglobal at

(* Ignore the [MinLocal _] case. *)
let get_scope = function  
  | Mlocal  _ ->  Expr.Slocal
  | Mglobal _ -> Expr.Sglob
  | _ -> assert false

(* Ignore the [MinLocal _] case. *)
let get_at = function  
  | Mlocal at | Mglobal at -> at
  | _ -> assert false

(*---------------------------------------------------------------*)
(* We log the result to be able to inverse it. *)
let log_var = Hashtbl.create 16

(* APRON variables by name: an APRON variable is an immutable value, and
   building one allocates; the analysis converts the same variables over and
   over. *)
let avar_cache : (string, Var.t) Hashtbl.t = Hashtbl.create 4096

(* Bases of the initialised-prefix ghosts, per array: recorded when a
   ghost dimension is first created (base 0 at entry, a sub-array's byte
   offset at a call or a copy), cleared with [reset]. *)
let init_bases : (Prog.var, int list ref) Hashtbl.t = Hashtbl.create 16

let note_base x c =
  let l = match Hashtbl.find_opt init_bases x with
    | Some l -> l
    | None -> let l = ref [ 0 ] in Hashtbl.add init_bases x l; l in
  if not (List.mem c !l) then l := c :: !l

let bases_of_var x = match Hashtbl.find_opt init_bases x with
  | Some l -> !l
  | None -> [ 0 ]

let reset () =
  Hashtbl.reset log_var;
  Hashtbl.reset avar_cache;
  Hashtbl.reset init_bases

let avar_of_mvar a =
  let s = string_of_mvar a in
  match Hashtbl.find_opt avar_cache s with
  | Some v -> v
  | None ->
    if not(Hashtbl.mem log_var s) then
      Hashtbl.add log_var s a;
    let v = Var.of_string s in
    Hashtbl.add avar_cache s v;
    v

let mvar_of_svar s =
  try Hashtbl.find log_var s with
  | Not_found ->
    Format.eprintf "mvar_of_svar: unknown variable %s@." s;
    assert false

let mvar_of_avar v =
  let s = Var.to_string v in
  mvar_of_svar s

let mvar_of_scoped_var (s : Expr.v_scope) (uv : var) =
  let at = match uv.v_ty with
    | Bty _ -> Avar uv
    | Arr _ -> Aarray uv in

  of_scope s at

let mvar_of_var (v : int Prog.ggvar) =
  mvar_of_scoped_var v.gs (L.unloc v.gv)

(*---------------------------------------------------------------*)
(* Blasts array elements and arrays. *)
let u8_blast_at ~blast_arrays scope at =
  let ats = match at with
    | Aarray v ->
      if blast_arrays then
        let iws = size_of_ws (arr_size v) in
        let r = max 0 (arr_range v) in
        let vi i = AarraySlice (v,U8,i) in
        List.init (r * iws) vi
      else [at]

    | AarraySlice (v,ws,j) ->
      let iws = size_of_ws ws in
      let vi i = AarraySlice (v,U8,i + j) in
      List.init iws vi
    | _ -> [at]
  in
  List.map (of_scope scope) ats

let u8_blast_var ~blast_arrays v = match v with
  | Mlocal at  -> u8_blast_at ~blast_arrays Expr.Slocal at
  | Mglobal at -> u8_blast_at ~blast_arrays Expr.Sglob  at
  | _ -> [v]

let u8_blast_ats ~blast_arrays scope ats =
  List.concat (List.map (u8_blast_at ~blast_arrays scope) ats)

let u8_blast_vars ~blast_arrays vs =
  List.concat (List.map (u8_blast_var ~blast_arrays) vs)

let rec expand_arr_vars = function
  | [] -> []
  | (Mlocal (Aarray v) as head) :: t | (Mglobal (Aarray v) as head) :: t ->
    begin
      let scope = get_scope head in
      match v.v_ty with
      | Bty _ -> assert false
      | Arr (ws, n) ->
        let wsz = size_of_ws ws in
        List.init (max 0 n) (fun i -> of_scope scope (AarraySlice (v,ws,wsz * i)))
        @ expand_arr_vars t
    end
  | v :: t -> v :: expand_arr_vars t

(*------------------------------------------------------------*)
let is_local_var = function
  | Mlocal (Avar _) -> true
  | _ -> false

let is_offset = function
  | MvarOffset _ -> true
  | _ -> false

let ty_gvar_of_mvar = function
  | Mlocal (Avar v) -> Some v
  | _ -> None

(*------------------------------------------------------------*)
module Mmv = struct
  type t = mvar

  let compare v v' = Stdlib.compare (avar_of_mvar v) (avar_of_mvar v')
  let equal v v' = avar_of_mvar v = avar_of_mvar v'
end

module Mm = Map.Make(Mmv)
module Sm = Set.Make(Mmv)

(*------------------------------------------------------------*)
module Mmlv = struct
  type t = mem_loc

  (* A total order on regions, so that [Mml] and [Sml] are ordered
     maps and sets whatever the mixture of cells and arguments. *)
  let compare m m' = match m, m' with
    | MemLoc v, MemLoc v' -> Prog.V.compare v v'
    | MemLoc _, MemCell _ -> -1
    | MemCell _, MemLoc _ -> 1
    | MemCell (v, k), MemCell (v', k') ->
      let c = Prog.V.compare v v' in
      if c <> 0 then c else Stdlib.compare k k'

  let equal m m' = compare m m' = 0
end

module Mml = Map.Make(Mmlv)
module Sml = Set.Make(Mmlv)



(*********************)
(* Boolean Variables *)
(*********************)

(* A boolean variable is a positive of negative variable (of type [mvar]). *)
module Bvar : sig
  type t
  val compare : t -> t -> int
  val equal : t -> t -> bool

  (* the boolean is true if t is positive. *)
  val make : mvar -> bool -> t

  val not : t -> t

  val is_neg : t -> bool

  val var_name : t -> string

  val get_mv : t -> mvar

  (* Force the boolean variable to be positive *)
  val positive : t -> t

  val print : Format.formatter -> t -> unit
end = struct
  type t = mvar * bool          (* the boolean is true if t is positive. *)

  let compare (bv,b) (bv',b') = 
    match Stdlib.compare b b' with
    | 0 -> Stdlib.compare (avar_of_mvar bv) (avar_of_mvar bv')
    | _ as r -> r

  let equal (bv,b) (bv',b') = 
    avar_of_mvar bv = avar_of_mvar bv' && b = b'

  let make bv b = (bv,b)

  let is_neg (_,b) = not b
      
  let not (bv,b) = (bv,not b)                  
    
  let positive (bv,_) = (bv,true)

  let get_mv (bv,_) = bv
                  
  let var_name (bv,_) = Var.to_string (avar_of_mvar bv)

  let print fmt (bv,b) =
    let v = Var.to_string (avar_of_mvar bv) in
    if b then Format.fprintf fmt "%s" v
    else Format.fprintf fmt "NOT %s" v
end

module Mbv = Map.Make(Bvar)


