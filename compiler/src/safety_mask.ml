(* Initialisation masks for the extraction of the safety model.

   [Safety.sc_prog] states the safety of a program with assertions, some of
   which observe the initialisation of variables: [Pis_var_init x] for a
   scalar and [Ois_arr_init] for the cells of an array. EasyCrypt has no
   notion of an uninitialised value, so this pass makes initialisation
   explicit, as the comment of [opN_safety] (operators.v) describes:
   - each scalar variable [x] gets a boolean [x_init], true once [x] is
     written;
   - each array variable [x] of [n] bytes gets a mask [x_init], an array of
     [n] bytes holding 0xFF where [x] is initialised ([WArray.is_initb]).
   The masks are updated along the writes, passed along with array arguments
   and returned with array results, and the assertions are rewritten to read
   them: [Pis_var_init x] becomes [x_init], and [Ois_arr_init] on [x] becomes
   [Ois_barr_init] on [x_init]. Contracts are rewritten in the same way, with
   one mask parameter (result) after the parameters (results) for each array
   parameter (result), in order.

   The pass is not proved: it is part of the extraction, which is trusted. *)

open Utils
open Prog

let hierror_no_loc fmt =
  hierror ~loc:Lnone ~kind:"safety masks" ~internal:true fmt

let mask_ty (ty : ty) : ty option =
  match ty with
  | Bty _ -> None
  | Arr (ws, n) -> Some (Arr (Wsize.U8, arr_size ws n))

let is_arr (ty : ty) = match ty with Arr _ -> true | Bty _ -> false

let bytes_of (ty : ty) =
  match ty with Arr (ws, n) -> arr_size ws n | Bty _ -> assert false

(* ------------------------------------------------------------------------ *)
(* The mask of each variable, created on first use.                         *)

type env = { masks : var Hv.t }

let mask_var env (x : var) : var =
  match Hv.find env.masks x with
  | m -> m
  | exception Not_found ->
      let ty = match mask_ty x.v_ty with Some t -> t | None -> tbool in
      let m = V.mk (x.v_name ^ "_init") (Reg (Normal, Direct)) ty x.v_dloc [] in
      Hv.add env.masks x m;
      m

let mk_vi loc x = L.mk_loc loc x

let mask_vi env (x : var_i) : var_i = mk_vi (L.loc x) (mask_var env (L.unloc x))

let ptrue = Pbool true

(* A byte array of [n] bytes, all equal to [b]. *)
let const_mask n b =
  let byte = Papp1 (Operators.Oword_of_int Wsize.U8, Pconst (Z.of_int b)) in
  PappN (Operators.Oarray (Conv.cz_of_int n), List.init n (fun _ -> byte))

let full_mask n = const_mask n 0xff

let empty_mask n = const_mask n 0

let word_ones ws =
  Papp1 (Operators.Oword_of_int ws, Pconst (Z.pred (Z.shift_left Z.one (8 * size_of_ws ws))))

(* The byte offset of index [e] for an access of size [ws] scaled by [aa]. *)
let byte_offset aa ws e =
  match aa with
  | Warray_.AAdirect -> e
  | Warray_.AAscale -> Papp2 (Operators.Omul Operators.Op_int, Pconst (Z.of_int (size_of_ws ws)), e)

(* ------------------------------------------------------------------------ *)
(* The mask of an array expression.                                         *)

let rec mask_of_expr env (e : expr) : expr =
  match e with
  | Pvar x ->
      let ty = (L.unloc x.gv).v_ty in
      if is_gkvar x then Pvar (gkvar (mask_vi env x.gv))
      else full_mask (bytes_of ty) (* global arrays are fully initialised *)
  | Parr_init (ws, n) -> empty_mask (arr_size ws n)
  | PappN (Operators.Oarray n, _) -> full_mask (Conv.int_of_cz n)
  | Psub (aa, ws, len, x, i) ->
      let m = mask_of_expr env (Pvar x) in
      begin match m with
      | Pvar mx ->
          Psub (Warray_.AAdirect, Wsize.U8, arr_size ws len, mx, byte_offset aa ws i)
      | _ -> full_mask (arr_size ws len)
      end
  | Pif (ty, c, e1, e2) ->
      let ty' = match mask_ty ty with Some t -> t | None -> assert false in
      Pif (ty', c, mask_of_expr env e1, mask_of_expr env e2)
  | _ -> hierror_no_loc "safety masks: unsupported array expression"

(* ------------------------------------------------------------------------ *)
(* Assertions                                                               *)

let rec mask_assert env (a : eassert) : eassert =
  match a with
  | Pexpr _ -> a
  | Pis_mem_init _ -> a
  | Pis_var_init x -> Pexpr (Pvar (gkvar (mask_vi env x)))
  | PappN_safety (Operators.Ois_arr_init len, [ t; s; n ]) ->
      PappN_safety (Operators.Ois_barr_init len, [ mask_of_expr env t; s; n ])
  | PappN_safety _ -> a
  | Pand (a1, a2) -> Pand (mask_assert env a1, mask_assert env a2)

let mask_assertion env ((k, a) : 'a * eassert) = (k, mask_assert env a)

(* ------------------------------------------------------------------------ *)
(* Writes                                                                   *)

let mk_instr i d = { i with i_desc = d }

let set_mask env i (x : var_i) (e : expr) =
  let m = mask_vi env x in
  mk_instr i (Cassgn (Lvar m, E.AT_none, (L.unloc m).v_ty, e))

(* The mask updates after a write to [lv] of the value [src], the mask of
   that value when it is an array ([None] when it is fully initialised). *)
let lval_mask env i (lv : lval) (src : expr option) : (_, _) instr list =
  match lv with
  | Lnone _ | Lmem _ -> []
  | Lvar x ->
      let ty = (L.unloc x).v_ty in
      if is_arr ty then
        let e = match src with Some e -> e | None -> full_mask (bytes_of ty) in
        [ set_mask env i x e ]
      else [ set_mask env i x ptrue ]
  | Laset (al, aa, ws, x, e) ->
      let m = mask_vi env x in
      [ mk_instr i (Cassgn (Laset (al, aa, ws, m, e), E.AT_none, Bty (U ws), word_ones ws)) ]
  | Lasub (aa, ws, len, x, e) ->
      let m = mask_vi env x in
      let n = arr_size ws len in
      let src = match src with Some s -> s | None -> full_mask n in
      [ mk_instr i
          (Cassgn (Lasub (Warray_.AAdirect, Wsize.U8, n, m, byte_offset aa ws e),
                   E.AT_none, Arr (Wsize.U8, n), src)) ]

(* The mask of the right-hand side of an assignment, for an array. *)
let rhs_mask env (ty : ty) (e : expr) =
  if is_arr ty then Some (mask_of_expr env e) else None

(* ------------------------------------------------------------------------ *)
(* Instructions                                                             *)

type sigs = (funname, (bool list * bool list)) Hashtbl.t
(* for each function: which parameters and which results are arrays *)

let rec mask_stmt env (sigs : sigs) (c : ('info, 'asm) stmt) : ('info, 'asm) stmt =
  List.concat_map (mask_instr env sigs) c

and mask_instr env sigs (i : ('info, 'asm) instr) : ('info, 'asm) stmt =
  match i.i_desc with
  | Cassert a -> [ mk_instr i (Cassert (mask_assertion env a)) ]
  | Cassgn (lv, _, ty, e) -> i :: lval_mask env i lv (rhs_mask env ty e)
  | Copn (lvs, _, o, es) ->
      let src =
        match o, es with
        | Sopn.Opseudo_op (Pseudo_operator.Ocopy _), [ e ] -> Some (mask_of_expr env e)
        | _ -> None
      in
      i :: List.concat_map (fun lv -> lval_mask env i lv src) lvs
  | Csyscall (lvs, _, _) -> i :: List.concat_map (fun lv -> lval_mask env i lv None) lvs
  | Cif (e, c1, c2) -> [ mk_instr i (Cif (e, mask_stmt env sigs c1, mask_stmt env sigs c2)) ]
  | Cfor (x, r, c) ->
      set_mask env i x ptrue :: [ mk_instr i (Cfor (x, r, mask_stmt env sigs c)) ]
  | Cwhile (al, c1, e, inf, c2) ->
      [ mk_instr i (Cwhile (al, mask_stmt env sigs c1, e, inf, mask_stmt env sigs c2)) ]
  | Ccall (lvs, f, es) ->
      let params, results =
        try Hashtbl.find sigs f
        with Not_found -> hierror_no_loc "safety masks: unknown function %s" f.fn_name
      in
      let extra_args =
        List.concat
          (List.map2 (fun isarr e -> if isarr then [ mask_of_expr env e ] else []) params es)
      in
      let extra_lvs =
        List.concat
          (List.map2
             (fun isarr lv ->
               if not isarr then []
               else
                 match lv with
                 | Lvar x -> [ Lvar (mask_vi env x) ]
                 | Lasub (aa, ws, len, x, e) ->
                     [ Lasub (Warray_.AAdirect, Wsize.U8, arr_size ws len,
                              mask_vi env x, byte_offset aa ws e) ]
                 | Lnone (loc, ty) ->
                     [ Lnone (loc, match mask_ty ty with Some t -> t | None -> tbool) ]
                 | _ -> hierror_no_loc "safety masks: an array result must go to a variable")
             results lvs)
      in
      let scalars =
        List.concat
          (List.map2
             (fun isarr lv -> if isarr then [] else lval_mask env i lv None)
             results lvs)
      in
      mk_instr i (Ccall (lvs @ extra_lvs, f, es @ extra_args)) :: scalars

(* ------------------------------------------------------------------------ *)
(* Functions                                                                *)

(* In a contract the scalar parameters and results are initialised: the
   parameters on entry, the results by the assertions of the body before the
   return. Only the masks of arrays are passed along. *)
let rec contract_assert env (a : eassert) : eassert =
  match a with
  | Pis_var_init x when not (is_arr (L.unloc x).v_ty) -> Pexpr ptrue
  | Pand (a1, a2) -> Pand (contract_assert env a1, contract_assert env a2)
  | _ -> mask_assert env a

let mask_contract env (c : int gfcontract) : int gfcontract =
  let extra xs =
    List.filter_map
      (fun x -> if is_arr (L.unloc x).v_ty then Some (mask_vi env x) else None)
      xs
  in
  {
    f_iparams = c.f_iparams @ extra c.f_iparams;
    f_ires = c.f_ires @ extra c.f_ires;
    f_pre = List.map (fun (k, a) -> (k, contract_assert env a)) c.f_pre;
    f_post = List.map (fun (k, a) -> (k, contract_assert env a)) c.f_post;
  }

let mask_func sigs (f : ('info, 'asm) func) : ('info, 'asm) func =
  let env = { masks = Hv.create 17 } in
  let loc = f.f_loc in
  let mk d =
    { i_desc = d; i_loc = L.i_loc0 loc; i_info = f.f_info; i_annot = [] }
  in
  (* masks of the array parameters are parameters; scalar parameters are
     initialised on entry *)
  let arr_args = List.filter (fun x -> is_arr x.v_ty) f.f_args in
  let mask_args = List.map (mask_var env) arr_args in
  let body = mask_stmt env sigs f.f_body in
  let arr_rets = List.filter (fun x -> is_arr (L.unloc x).v_ty) f.f_ret in
  let mask_rets = List.map (mask_vi env) arr_rets in
  let init_scalar x = mk (Cassgn (Lvar (mk_vi loc (mask_var env x)), E.AT_none, tbool, ptrue)) in
  let entry_scalars =
    List.map init_scalar (List.filter (fun x -> not (is_arr x.v_ty)) f.f_args)
  in
  (* every other variable starts uninitialised *)
  let params = Sv.of_list f.f_args in
  let locals =
    Hv.fold (fun x _ acc -> if Sv.mem x params then acc else x :: acc) env.masks []
    |> List.sort V.compare
  in
  let init_local x =
    let m = mask_var env x in
    let e = if is_arr x.v_ty then empty_mask (bytes_of x.v_ty) else Pbool false in
    mk (Cassgn (Lvar (mk_vi loc m), E.AT_none, m.v_ty, e))
  in
  let entry = entry_scalars @ List.map init_local locals in
  {
    f with
    f_contract = Option.map (mask_contract env) f.f_contract;
    f_tyin = f.f_tyin @ List.map (fun x -> x.v_ty) mask_args;
    f_args = f.f_args @ mask_args;
    f_body = entry @ body;
    f_tyout = f.f_tyout @ List.map (fun x -> (L.unloc x).v_ty) mask_rets;
    f_ret = f.f_ret @ mask_rets;
  }

let mask_prog ((globs, funcs) : ('info, 'asm) prog) : ('info, 'asm) prog =
  let sigs : sigs = Hashtbl.create 17 in
  List.iter
    (fun f ->
      Hashtbl.add sigs f.f_name
        (List.map (fun x -> is_arr x.v_ty) f.f_args,
         List.map (fun x -> is_arr (L.unloc x).v_ty) f.f_ret))
    funcs;
  (globs, List.map (mask_func sigs) funcs)
