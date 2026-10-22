open Jasmin
open SafetyArch

(** ARMv8-A architecture implementation.

    Same abstraction as ARMv7-M and RISC-V: the outputs of
    architecture-specific operators are unknown (Top), and no comparison or
    conditional-instruction heuristic is used. Memory accesses, array
    accesses, initialization and alignment are checked by the generic
    analysis, as for the other architectures. *)
module Armv8a_safety
  (A: Arch_full.Arch
      with type reg = Armv8a_decl.register
       and type regx = Arch_utils.empty
       and type xreg = Armv8a_decl.vregister
       and type rflag = Arm_common.rflag
       and type cond = Arm_common.condt
       and type asm_op = Armv8a_instr_decl.armv8a_asm_op
       and type extra_op = Armv8a_extra.armv8a_extra_op)
  : SafetyArch
    with type reg = Armv8a_decl.register
     and type regx = Arch_utils.empty
     and type xreg = Armv8a_decl.vregister
     and type rflag = Arm_common.rflag
     and type cond = Arm_common.condt
     and type asm_op = Armv8a_instr_decl.armv8a_asm_op
     and type extra_op = Armv8a_extra.armv8a_extra_op
  = struct

  include A

  let is_comparison _ = false

  let is_conditional _ _ _ _ = None

  let split_asm_opn n _opn _es =
    (* Default: all outputs are unknown (Top) *)
    List.init n (fun _ -> None)

  let post_opn _opn _lvs _es = []

  let opn_heur _opn _v _es = None
end
