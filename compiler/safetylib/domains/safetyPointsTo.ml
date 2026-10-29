open Jasmin
open Utils
open Prog
    
open SafetyUtils
open SafetyVar
open SafetyInterfaces

(*****************************)
(* Points-to Abstract Domain *)
(*****************************)

let pp_memloc fmt = function
  | MemLoc v -> Format.fprintf fmt "%s" v.v_name
  | MemCell (v, k) -> Format.fprintf fmt "%s.%d" v.v_name k

let pp_memlocs fmt l =
  pp_list ~sep:(fun fmt () -> Format.fprintf fmt "@ ") pp_memloc fmt l

let pp_ptr fmt = function
  | Ptrs m -> Format.fprintf fmt "%a" pp_memlocs m
  | TopPtr -> Format.fprintf fmt "#TopPtr"


module PointsToImpl : PointsTo = struct
  (* Points-to abstract value.
     - [pts] associates a pointer variable with the regions it may point
       to; a variable absent from the map points to anything ([TopPtr]).
     - [prov] is the provenance of arrays: [prov(y) = (x, c)] states that,
       in every concrete state, the array [y] is defined, [c + size(y)]
       does not exceed [size(x)], and every byte [i] of [y] equals byte
       [c + i] of the entry value of the export argument [x]. A variable
       absent from the map has no known provenance, which is the sound
       default: a read from an array without provenance points to anything
       ([TopPtr]), as it did before regions for table cells existed.
       Losing a binding only loses regions, hence only adds alarms. *)
  type t = { pts : mem_loc list Mm.t;
             prov : (var * int) Mv.t }
             (* top : mem_loc list } *)

  (* A cell region of an export argument [x] states that [x]'s own entry
     value is the array whose cells are the regions; no pointer holds a
     cell's value until the cell is read ([SafetyAbsExpr.table_cell]). *)
  let make mls =
    let make_var v = Mlocal (Avar v) in

    let pts = List.fold_left (fun pts x -> match x with
        | MemLoc v -> Mm.add (make_var v) [x] pts
        | MemCell _ -> pts)
        Mm.empty mls in
    let prov = List.fold_left (fun prov x -> match x with
        | MemCell (v, _) -> Mv.add v (v, 0) prov
        | MemLoc _ -> prov)
        Mv.empty mls in
    { pts = pts; prov = prov }

  let same_prov (x, c) (x', c') = V.equal x x' && c = c'

  let meet : t -> t -> t = fun t t' ->
    let pts'' =
      Mm.merge (fun _ aop bop -> match aop,bop with
          | None, x | x, None -> x (* None corresponds to TopPtr *)

          | Some l, Some l' ->
            let l_inter = List.filter (fun x -> List.mem x l') l in
            Some (List.sort_uniq Stdlib.compare l_inter )
        ) t.pts t'.pts in

    (* Both facts hold in the intersection, so one of them may be kept. Two
       different bindings of one array cannot both hold of a reachable
       state; keeping none is sound. *)
    let prov'' =
      Mv.merge (fun _ a b -> match a, b with
          | None, x | x, None -> x
          | Some p, Some p' -> if same_prov p p' then a else None)
        t.prov t'.prov in

    { pts = pts''; prov = prov'' }

  (* A binding holds after a join only if it holds on both sides. *)
  let join_prov p p' =
    Mv.merge (fun _ a b -> match a, b with
        | Some p, Some p' when same_prov p p' -> a
        | _ -> None) p p'

  let join : t -> t -> t = fun t t' ->
    let pts'' =
      Mm.merge (fun _ aop bop -> match aop,bop with
          | None, _ | _, None -> None (* None corresponds to TopPtr *)

          | Some l, Some l' ->
            Some (List.sort_uniq Stdlib.compare (l @ l'))
        ) t.pts t'.pts in

    { pts = pts''; prov = join_prov t.prov t'.prov }

  (* An array has at most one binding, which this join keeps or drops: the
     map has height one per array, so it is a widening. *)
  let widening t t' = join t t'

  let svar_points_to : t -> mvar -> ptrs = fun t s_var ->
    if Mm.mem s_var t.pts then Ptrs (Mm.find s_var t.pts)
    else TopPtr

  let var_points_to : t -> mvar -> ptrs = fun t var ->
    (* We correctly tracked points-to information only for 
       variables (e.g. array elements are not properly handled, and
       consequently can point to anybody.). *)
    match var with
    | Mlocal (Avar _) -> svar_points_to t var
    | _ -> TopPtr

  (* An array loses its provenance when it, or any of its cells, is
     forgotten. The test is on the base variable, before and after the list
     is blasted to cells: the callers blast too ([remove_vars],
     [SafetyBoolean.remove_vars]). *)
  let forget_list : t -> mvar list -> t = fun t l_rem ->
    let l_blast = u8_blast_vars ~blast_arrays:true l_rem in
    let arrays =
      List.fold_left (fun s v -> match v with
          | Mlocal (Aarray y) | Mlocal (AarraySlice (y, _, _)) -> Sv.add y s
          | _ -> s)
        Sv.empty (l_rem @ l_blast) in
    { pts = Mm.filter (fun v _ -> not (List.mem v l_blast)) t.pts;
      prov = Mv.filter (fun y _ -> not (Sv.mem y arrays)) t.prov }

  (* [t] is included in [t'] when every variable points, in [t], into a
     subset of what it points to in [t']. A variable absent from a map
     points to anything (TopPtr), so every binding of [t'] must have a
     binding in [t] with fewer regions, and a variable absent from [t']
     accepts anything. The loop fixpoint test asks this inclusion: testing
     it over the bindings of [t] instead would let a loop stop while a
     pointer of the last iteration has lost its region. The provenance map
     is compared in the same direction: every binding of [t'] must hold in
     [t]. A binding is monotone (it is set and dropped, never widened), so
     a loop whose body drops one is not stable. *)
  let is_included : t -> t -> bool = fun t t' ->
    Mm.for_all (fun v l' ->
        match Mm.find_opt v t.pts with
        | None -> false
        | Some l -> List.for_all (fun x -> List.mem x l') l
      ) t'.pts
    && Mv.for_all (fun y p' ->
        match Mv.find_opt y t.prov with
        | None -> false
        | Some p -> same_prov p p')
      t'.prov

  (* let top_mem_loc : t -> mem_loc list = fun t -> t.top *)

  let join_ptrs_list ptrss =
    let rec aux acc = function
      | [] -> Ptrs (List.sort_uniq Stdlib.compare acc)
      | TopPtr :: _ -> TopPtr
      | Ptrs l :: tail -> aux (l @ acc) tail in

    aux [] ptrss

  let pt_assign : t -> mvar -> ptrs -> t = fun t v ptrs -> match ptrs with
    | Ptrs vpts -> { t with pts = Mm.add v vpts t.pts }
    | TopPtr -> { t with pts = Mm.remove v t.pts }

  let assign_ptr_expr : t -> mvar -> ptr_expr -> t = fun t v e -> match e with
    | PtTopExpr -> { t with pts = Mm.remove v t.pts }
    | PtVars el ->
      let v_pts =
        List.fold_left (fun acc var ->
            var_points_to t var :: acc) [] el
        |> join_ptrs_list in

      pt_assign t v v_pts

  (* [v] points to the single region [m]. *)
  let assign_region : t -> mvar -> mem_loc -> t = fun t v m ->
    { t with pts = Mm.add v [m] t.pts }

  let array_prov : t -> var -> (var * int) option = fun t y ->
    Mv.find_opt y t.prov

  let set_prov : t -> var -> (var * int) option -> t = fun t y o ->
    match o with
    | None -> { t with prov = Mv.remove y t.prov }
    | Some p -> { t with prov = Mv.add y p t.prov }

  let print ppf t =
    Format.fprintf ppf "@[<hov 4>* Points-to:@ %a@]@;"
      (pp_list ~sep:(fun _ _ -> ()) (fun ppf (k,l) ->
           if l <> [] then
             Format.fprintf ppf "(%a → %a);@,"
               pp_mvar k pp_memlocs l;))
      (List.filter (fun (x,_) -> not (mvar_ignore x)) (Mm.bindings t.pts));
    if not (Mv.is_empty t.prov) then
      Format.fprintf ppf "@[<hov 4>* Provenance:@ %a@]@;"
        (pp_list ~sep:(fun _ _ -> ()) (fun ppf (y, (x, c)) ->
             Format.fprintf ppf "(%s ← %s + %d);@,"
               y.v_name x.v_name c))
        (Mv.bindings t.prov)

end
