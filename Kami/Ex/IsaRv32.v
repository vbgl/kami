Require Import Bool String List.
Require Import Lib.CommonTactics Lib.Word Lib.Struct.
Require Import Kami.Syntax Kami.Semantics Kami.Notations.
Require Import Ex.MemTypes Ex.SC.

(* Subset of RV32I instructions (24/47):
 * - Branch : JAL, JALR, BEQ, BNE, BLT, BGE, BLTU, BGEU
 * - Memory : LW, SW
 * - Arithmetic : LUI, ADD, ADDI, SUB, SLL, SLLI, SRL, OR, AND, XOR, ANDI, SLT, SLTU, SLTI, SLTIU
 * Some pseudo instructions of RV32I (9):
 * - LI, MV, BEQZ, BNEZ, BLEZ, BGEZ, BLTZ, BGTZ, J, NOP
 * Custom instructions (1):
 * - TOHOST
 * Just one RV32M instruction: MUL
 *)
Section RV32I.
  Definition rv32iAddrSize := 11. (* 2^11 memory cells *)
  Definition rv32iIAddrSize := 8. (* 2^8 = 256 program size *)
  Definition rv32iDataBytes := 4.
  Definition rv32iOpIdx := 7. (* always inst[6-0] *)
  Definition rv32iRfIdx := 5. (* 2^5 = 32 general purpose registers, x0 is hardcoded though *)

  Section Common.

    Definition getOpcodeE {ty}
               (inst : Expr ty (SyntaxKind (Data rv32iDataBytes))) :=
      (UniBit (Trunc 7 _) inst)%kami_expr.

    Definition getRs1E {ty}
               (inst : Expr ty (SyntaxKind (Data rv32iDataBytes))) :=
      (UniBit (ConstExtract 15 5 _) inst)%kami_expr.
    
    Definition getRs1ValueE {ty}
               (s : StateT rv32iDataBytes rv32iRfIdx ty)
               (inst : Expr ty (SyntaxKind (Data rv32iDataBytes))) :=
      (#s @[getRs1E inst])%kami_expr.

    Definition getRs2E {ty}
               (inst : Expr ty (SyntaxKind (Data rv32iDataBytes))) :=
      (UniBit (ConstExtract 20 5 _) inst)%kami_expr.

    Definition getRs2ValueE {ty}
               (s : StateT rv32iDataBytes rv32iRfIdx ty)
               (inst : Expr ty (SyntaxKind (Data rv32iDataBytes))) :=
      (#s @[getRs2E inst])%kami_expr.

    Definition getRdE {ty}
               (inst: Expr ty (SyntaxKind (Data rv32iDataBytes))) :=
      UniBit (ConstExtract 7 5 _) inst.

    Definition getFunct7E {ty}
               (inst : Expr ty (SyntaxKind (Data rv32iDataBytes))) :=
      (UniBit (TruncLsb 25 7) inst)%kami_expr.

    Definition getFunct3E {ty}
               (inst : Expr ty (SyntaxKind (Data rv32iDataBytes))) :=
      (UniBit (ConstExtract 12 3 _) inst)%kami_expr.

    Definition getOffsetIE {ty}
               (inst : Expr ty (SyntaxKind (Data rv32iDataBytes))) :=
      (UniBit (TruncLsb 20 12) inst)%kami_expr.

    Definition getOffsetShamtE {ty}
               (inst : Expr ty (SyntaxKind (Data rv32iDataBytes))) :=
      (UniBit (ConstExtract 20 5 _) inst)%kami_expr.

    Definition getOffsetSE {ty}
               (inst : Expr ty (SyntaxKind (Data rv32iDataBytes))) :=
      (BinBit (Concat _ _)
              (UniBit (TruncLsb 25 7) inst)
              (UniBit (ConstExtract 7 5 _) inst))%kami_expr.

    Definition getOffsetSBE {ty}
               (inst: Expr ty (SyntaxKind (Data rv32iDataBytes))) :=
      (BinBit (Concat _ _)
              (BinBit (Concat _ _)
                      (UniBit (TruncLsb 31 1) inst)
                      (UniBit (ConstExtract 7 1 _) inst))
              (BinBit (Concat _ _)
                      (UniBit (ConstExtract 25 6 _) inst)
                      (UniBit (ConstExtract 8 4 _) inst)))%kami_expr.

    Definition getOffsetUE {ty}
               (inst: Expr ty (SyntaxKind (Data rv32iDataBytes))) :=
      (UniBit (TruncLsb 12 20) inst)%kami_expr.

    Definition getOffsetUJE {ty}
               (inst: Expr ty (SyntaxKind (Data rv32iDataBytes))) :=
      (BinBit (Concat _ _)
              (BinBit (Concat _ _)
                      (UniBit (TruncLsb 31 1) inst)
                      (UniBit (ConstExtract 12 8 _) inst))
              (BinBit (Concat _ _)
                      (UniBit (ConstExtract 20 1 _) inst)
                      (UniBit (ConstExtract 21 10 _) inst))).
  End Common.

  Section Opcodes.

    Definition rv32iOpLUI     := WO~0~1~1~0~1~1~1. (* U-type, load upper immediate *)
    Definition rv32iOpJAL     := WO~1~1~0~1~1~1~1. (* UJ-type, jump and link *)
    Definition rv32iOpJALR    := WO~1~1~0~0~1~1~1. (* I-type, jump and link register *)
    Definition rv32iOpBRANCH  := WO~1~1~0~0~0~1~1. (* SB-type, branch *)
    Definition rv32iOpLOAD    := WO~0~0~0~0~0~1~1. (* I-type, load *)
    Definition rv32iOpSTORE   := WO~0~1~0~0~0~1~1. (* S-type, store *)
    Definition rv32iOpOPIMM   := WO~0~0~1~0~0~1~1. (* I-type, register-immediate *)
    Definition rv32iOpOP      := WO~0~1~1~0~0~1~1. (* R-type, register-register *)

    Definition rv32iOpTOHOST  := WO~0~0~0~1~0~0~0. (* custom-0 opcode *)

  End Opcodes.

  (* NOTE: decode functions simply separates memory operations and non-memory operations *)
  (* CAUTION: currently there are no distinctions among LW/LH/LB or SW/SH/SB.
   *          All loads (stores) are regarded as LW (SW).
   *)
  Section Decode.

    Definition rv32iGetOptype: OptypeT rv32iDataBytes.
      unfold OptypeT; intros ty inst.
      refine (IF (getOpcodeE #inst == $$ rv32iOpLOAD) then $$opLd else _)%kami_expr.
      refine (IF (getOpcodeE #inst == $$ rv32iOpSTORE) then $$opSt else _)%kami_expr.
      refine (IF (getOpcodeE #inst == $$ rv32iOpTOHOST) then $$opTh else $$opNm)%kami_expr.
    Defined.

    Definition rv32iGetLdDst: LdDstT rv32iDataBytes rv32iRfIdx.
      unfold LdDstT; intros ty inst.
      exact (getRdE #inst)%kami_expr.
    Defined.

    Definition rv32iGetLdAddr: LdAddrT rv32iAddrSize rv32iDataBytes.
      unfold LdAddrT; intros ty inst.
      exact (UniBit (SignExtendTrunc _ _) (getOffsetIE #inst))%kami_expr.
    Defined.

    Definition rv32iGetLdSrc: LdSrcT rv32iDataBytes rv32iRfIdx.
      unfold LdSrcT; intros ty inst.
      exact (getRs1E #inst)%kami_expr.
    Defined.

    Definition rv32iCalcLdAddr: LdAddrCalcT rv32iAddrSize rv32iDataBytes.
      unfold LdAddrCalcT; intros ty ofs base.
      exact ((UniBit (ZeroExtendTrunc _ _) #base)
             + (UniBit (SignExtendTrunc _ _) #ofs))%kami_expr.
    Defined.

    Definition rv32iGetStAddr: StAddrT rv32iAddrSize rv32iDataBytes.
      unfold StAddrT; intros ty inst.
      exact (UniBit (SignExtendTrunc _ _) (getOffsetSE #inst))%kami_expr.
    Defined.
      
    Definition rv32iGetStSrc: StSrcT rv32iDataBytes rv32iRfIdx.
      unfold StSrcT; intros ty inst.
      exact (getRs1E #inst)%kami_expr.
    Defined.
    
    Definition rv32iCalcStAddr: StAddrCalcT rv32iAddrSize rv32iDataBytes.
      unfold StAddrCalcT; intros ty ofs base.
      exact ((UniBit (ZeroExtendTrunc _ _) #base)
             + (UniBit (SignExtendTrunc _ _) #ofs))%kami_expr.
    Defined.

    Definition rv32iGetStVSrc: StVSrcT rv32iDataBytes rv32iRfIdx.
      unfold StVSrcT; intros ty inst.
      exact (getRs2E #inst)%kami_expr.
    Defined.

    Definition rv32iGetSrc1: Src1T rv32iDataBytes rv32iRfIdx.
      unfold Src1T; intros ty inst.
      exact (getRs1E #inst)%kami_expr.
    Defined.
    
    Definition rv32iGetSrc2: Src2T rv32iDataBytes rv32iRfIdx.
      unfold Src2T; intros ty inst.
      exact (getRs2E #inst)%kami_expr.
    Defined.

    Definition rv32iGetDst: DstT rv32iDataBytes rv32iRfIdx.
      unfold DstT; intros ty inst.
      refine (IF (getOpcodeE #inst == $$rv32iOpBRANCH) then _ else _)%kami_expr.
      - exact ($0)%kami_expr. (* Branch instructions should not write registers *)
      - exact (getRdE #inst)%kami_expr.
    Defined.

  End Decode.
    
  Section Funct7.

    Definition rv32iF7SLLI := WO~0~0~0~0~0~0~0.
    Definition rv32iF7SRLI := WO~0~0~0~0~0~0~0.
    Definition rv32iF7ADD := WO~0~0~0~0~0~0~0.
    Definition rv32iF7SUB := WO~0~1~0~0~0~0~0.
    Definition rv32iF7SLL := WO~0~0~0~0~0~0~0.
    Definition rv32iF7SLT := WO~0~0~0~0~0~0~0.
    Definition rv32iF7SLTU := WO~0~0~0~0~0~0~0.
    Definition rv32iF7XOR := WO~0~0~0~0~0~0~0.
    Definition rv32iF7SRL := WO~0~0~0~0~0~0~0.
    Definition rv32iF7OR := WO~0~0~0~0~0~0~0.
    Definition rv32iF7AND := WO~0~0~0~0~0~0~0.
    Definition rv32mF7MUL := WO~0~0~0~0~0~0~1.

  End Funct7.

  Section Funct3.

    Definition rv32iF3JALR := WO~0~0~0.
    Definition rv32iF3BEQ := WO~0~0~0.
    Definition rv32iF3BNE := WO~0~0~1.
    Definition rv32iF3BLT := WO~1~0~0.
    Definition rv32iF3BGE := WO~1~0~1.
    Definition rv32iF3BLTU := WO~1~1~0.
    Definition rv32iF3BGEU := WO~1~1~1.
    Definition rv32iF3LB := WO~0~0~0.
    Definition rv32iF3LH := WO~0~0~1.
    Definition rv32iF3LW := WO~0~1~0.
    Definition rv32iF3LBU := WO~1~0~0.
    Definition rv32iF3LHU := WO~1~0~1.
    Definition rv32iF3SB := WO~0~0~0.
    Definition rv32iF3SH := WO~0~0~1.
    Definition rv32iF3SW := WO~0~1~0.
    Definition rv32iF3ADDI := WO~0~0~0.
    Definition rv32iF3SLT := WO~0~1~0.
    Definition rv32iF3SLTU := WO~0~1~1.
    Definition rv32iF3SLTI := WO~0~1~0.
    Definition rv32iF3SLTIU := WO~0~1~1.
    Definition rv32iF3XORI := WO~1~0~0.
    Definition rv32iF3ORI := WO~1~1~0.
    Definition rv32iF3ANDI := WO~1~1~1.
    Definition rv32iF3SLLI := WO~0~0~1.
    Definition rv32iF3SRLI := WO~1~0~1.
    Definition rv32iF3ADD := WO~0~0~0.
    Definition rv32iF3SUB := WO~0~0~0.
    Definition rv32iF3SLL := WO~0~0~1.
    Definition rv32iF3XOR := WO~1~0~0.
    Definition rv32iF3SRL := WO~1~0~1.
    Definition rv32iF3OR := WO~1~1~0.
    Definition rv32iF3AND := WO~1~1~1.
    Definition rv32mF3MUL := WO~0~0~0.
  
  End Funct3.

  Ltac register_op_funct7 inst op expr :=
    refine (IF (getFunct7E #inst == $$op) then expr else _)%kami_expr.
  Ltac register_op_funct3 inst op expr :=
    refine (IF (getFunct3E #inst == $$op) then expr else _)%kami_expr.

  Definition rv32iExec: ExecT rv32iAddrSize rv32iDataBytes.
    unfold ExecT; intros ty val1 val2 pc inst.

    refine (IF (getOpcodeE #inst == $$rv32iOpJAL)
            then (UniBit (ZeroExtendTrunc _ _) (#pc + $4))
            else _)%kami_expr.
    refine (IF (getOpcodeE #inst == $$rv32iOpJALR)
            then (UniBit (ZeroExtendTrunc _ _) (#pc + $4))
            else _)%kami_expr.

    refine (IF (getOpcodeE #inst == $$rv32iOpOP) then _ else _)%kami_expr.

    - refine (IF (getFunct7E #inst == $$(WO~0~0~0~0~0~0~0)) then _ else _)%kami_expr.

      + register_op_funct3 inst rv32iF3ADD (#val1 + #val2)%kami_expr.
        register_op_funct3 inst rv32iF3SLL (#val1 << (UniBit (Trunc 5 _) #val2))%kami_expr.
        register_op_funct3 inst rv32iF3SRL (#val1 >> (UniBit (Trunc 5 _) #val2))%kami_expr.
        register_op_funct3 inst rv32iF3OR (#val1 ~| #val2)%kami_expr.
        register_op_funct3 inst rv32iF3AND (#val1 ~& #val2)%kami_expr.
        register_op_funct3 inst rv32iF3XOR (#val1 ~+ #val2)%kami_expr.
        register_op_funct3 inst rv32iF3SLT
                           (IF ((UniBit (TruncLsb 31 1) (#val1 - #val2)) == $1)
                            then $1 else $$(natToWord (rv32iDataBytes * 8) 0))%kami_expr.
        register_op_funct3 inst rv32iF3SLTU
                           (IF (#val1 < #val2)
                            then $1 else $$(natToWord (rv32iDataBytes * 8) 0))%kami_expr.
        exact ($$Default)%kami_expr. (* undefined semantics so far *)

      + refine (IF (getFunct7E #inst == $$(WO~0~0~0~0~0~0~1)) then _ else _)%kami_expr.

        * register_op_funct3 inst rv32mF3MUL (#val1 * #val2)%kami_expr.
          exact ($$Default)%kami_expr. (* undefined semantics so far *)

        * (* NOTE: now assume (getFunct7E #inst == $$(WO~0~1~0~0~0~0~0)) *)
          register_op_funct3 inst rv32iF3SUB (#val1 - #val2)%kami_expr.
          exact ($$Default)%kami_expr. (* undefined semantics so far *)
      
    - refine (IF (getOpcodeE #inst == $$rv32iOpOPIMM) then _ else _)%kami_expr.

      + register_op_funct3 inst rv32iF3ADDI
                           (#val1 + (UniBit (SignExtendTrunc _ _) (getOffsetIE #inst)))%kami_expr.
        register_op_funct3 inst rv32iF3SLLI
                           (#val1 << (getOffsetShamtE #inst))%kami_expr.
        register_op_funct3 inst rv32iF3SLTI
                           (IF (#val1 < (UniBit (SignExtendTrunc _ _) (getOffsetIE #inst)))
                            then $1 else $$(natToWord (rv32iDataBytes * 8) 0))%kami_expr.
        register_op_funct3 inst rv32iF3SLTIU
                           (IF (#val1 < (UniBit (ZeroExtendTrunc _ _) (getOffsetIE #inst)))
                            then $1 else $$(natToWord (rv32iDataBytes * 8) 0))%kami_expr.
        register_op_funct3 inst rv32iF3ANDI
                           (#val1 ~& (UniBit (SignExtendTrunc _ _) (getOffsetIE #inst)))%kami_expr.
        exact ($$Default)%kami_expr.

      + refine (IF (getOpcodeE #inst == $$rv32iOpLUI) then _ else $$Default)%kami_expr.
        exact (BinBit (Concat _ 12) (getOffsetUE #inst) $0)%kami_expr.

  Defined.

  Definition rv32iAlignPc: AlignPcT rv32iAddrSize rv32iIAddrSize.
    unfold AlignPcT; intros ty pc.
    exact (UniBit (ZeroExtendTrunc _ _) (#pc >> $$(natToWord 2 2)))%kami_expr.
  Defined.

  Definition rv32iAlignAddr: AlignAddrT rv32iAddrSize.
    unfold AlignPcT; intros ty addr.
    exact (#addr >> $$(natToWord 2 2))%kami_expr.
  Defined.

  (* NOTE: Because instructions are not on the memory, we give (pc + 1) for the next pc.
   * Branch offsets are not aligned, so the complete offset bits are used.
   *)

  Definition rv32iNextPc: NextPcT rv32iAddrSize rv32iDataBytes rv32iRfIdx.
    unfold NextPcT; intros ty st pc inst.

    (* NOTE: "rd" is updated by rv32iExecState *)
    refine (IF (getOpcodeE #inst == $$rv32iOpJAL)
            then #pc + (UniBit (SignExtendTrunc _ _)
                               ((getOffsetUJE #inst) << $$(natToWord 1 1))) else _)%kami_expr.
    refine (IF (getOpcodeE #inst == $$rv32iOpJALR)
            then (UniBit (SignExtendTrunc _ _) (getRs1ValueE st #inst))
                 + (UniBit (SignExtendTrunc _ _) (getOffsetIE #inst)) else _)%kami_expr.

    refine (IF (getOpcodeE #inst == $$rv32iOpBRANCH) then _ else #pc + $4)%kami_expr.
    (* branch instructions *)
    register_op_funct3 inst rv32iF3BEQ
                       (IF (getRs1ValueE st #inst == getRs2ValueE st #inst)
                        then #pc + (UniBit (SignExtendTrunc _ _)
                                           ((getOffsetSBE #inst) << $$(natToWord 1 1)))
                        else #pc + $4)%kami_expr.
    register_op_funct3 inst rv32iF3BNE
                       (IF (getRs1ValueE st #inst != getRs2ValueE st #inst)
                        then #pc + (UniBit (SignExtendTrunc _ _)
                                           ((getOffsetSBE #inst) << $$(natToWord 1 1)))
                        else #pc + $4)%kami_expr.
    register_op_funct3 inst rv32iF3BLT
                       (IF ((UniBit (TruncLsb 31 1)
                                    (getRs1ValueE st #inst - getRs2ValueE st #inst)) == $1)
                        then #pc + (UniBit (SignExtendTrunc _ _)
                                           ((getOffsetSBE #inst) << $$(natToWord 1 1)))
                        else #pc + $4)%kami_expr.
    register_op_funct3 inst rv32iF3BGE
                       (IF ((UniBit (TruncLsb 31 1)
                                    (getRs1ValueE st #inst - getRs2ValueE st #inst)) == $0)
                        then #pc + (UniBit (SignExtendTrunc _ _)
                                           ((getOffsetSBE #inst) << $$(natToWord 1 1)))
                        else #pc + $4)%kami_expr.
    register_op_funct3 inst rv32iF3BLTU
                       (IF (getRs1ValueE st #inst < getRs2ValueE st #inst)
                        then #pc + (UniBit (SignExtendTrunc _ _)
                                           ((getOffsetSBE #inst) << $$(natToWord 1 1)))
                        else #pc + $4)%kami_expr.
    register_op_funct3 inst rv32iF3BGEU
                       (IF (getRs1ValueE st #inst >= getRs2ValueE st #inst)
                        then #pc + (UniBit (SignExtendTrunc _ _)
                                           ((getOffsetSBE #inst) << $$(natToWord 1 1)))
                        else #pc + $4)%kami_expr.
    exact (#pc + $4)%kami_expr.
  Defined.

End RV32I.

(* For easy RV32I programming *)
Section RV32IStruct.

  Inductive Gpr :=
  | x0 | x1 | x2 | x3 | x4 | x5 | x6 | x7
  | x8 | x9 | x10 | x11 | x12 | x13 | x14 | x15
  | x16 | x17 | x18 | x19 | x20 | x21 | x22 | x23
  | x24 | x25 | x26 | x27 | x28 | x29 | x30 | x31.

  Definition gprToRaw (r: Gpr): word 5 :=
    match r with
    | x0 => natToWord _ 0 | x1 => natToWord _ 1 | x2 => natToWord _ 2 | x3 => natToWord _ 3
    | x4 => natToWord _ 4 | x5 => natToWord _ 5 | x6 => natToWord _ 6 | x7 => natToWord _ 7
    | x8 => natToWord _ 8 | x9 => natToWord _ 9 | x10 => natToWord _ 10 | x11 => natToWord _ 11
    | x12 => natToWord _ 12 | x13 => natToWord _ 13 | x14 => natToWord _ 14 | x15 => natToWord _ 15
    | x16 => natToWord _ 16 | x17 => natToWord _ 17 | x18 => natToWord _ 18 | x19 => natToWord _ 19
    | x20 => natToWord _ 20 | x21 => natToWord _ 21 | x22 => natToWord _ 22 | x23 => natToWord _ 23
    | x24 => natToWord _ 24 | x25 => natToWord _ 25 | x26 => natToWord _ 26 | x27 => natToWord _ 27
    | x28 => natToWord _ 28 | x29 => natToWord _ 29 | x30 => natToWord _ 30 | x31 => natToWord _ 31
    end.

  Inductive Rv32i :=
  | JAL (rd: Gpr) (ofs: word 20): Rv32i
  | JALR (rs1 rd: Gpr) (ofs: word 12): Rv32i
  | BEQ (rs1 rs2: Gpr) (ofs: word 12): Rv32i
  | BNE (rs1 rs2: Gpr) (ofs: word 12): Rv32i
  | BLT (rs1 rs2: Gpr) (ofs: word 12): Rv32i
  | BGE (rs1 rs2: Gpr) (ofs: word 12): Rv32i
  | BLTU (rs1 rs2: Gpr) (ofs: word 12): Rv32i
  | BGEU (rs1 rs2: Gpr) (ofs: word 12): Rv32i
  | LW (rs1 rd: Gpr) (ofs: word 12): Rv32i
  | SW (rs1 rs2: Gpr) (ofs: word 12): Rv32i
  | ADDI (rs1 rd: Gpr) (ofs: word 12): Rv32i
  | ADD (rs1 rs2 rd: Gpr): Rv32i
  | SUB (rs1 rs2 rd: Gpr): Rv32i
  | MUL (rs1 rs2 rd: Gpr): Rv32i
  | SLL (rs1 rs2 rd: Gpr): Rv32i
  | SRL (rs1 rs2 rd: Gpr): Rv32i
  | OR (rs1 rs2 rd: Gpr): Rv32i
  | AND (rs1 rs2 rd: Gpr): Rv32i
  | XOR (rs1 rs2 rd: Gpr): Rv32i
  (* pseudo-instructions *)
  | LI (rd: Gpr) (ofs: word 20): Rv32i
  | MV (rs1 rd: Gpr): Rv32i
  | BEQZ (rs1: Gpr) (ofs: word 12): Rv32i
  | BNEZ (rs1: Gpr) (ofs: word 12): Rv32i
  | BLEZ (rs1: Gpr) (ofs: word 12): Rv32i
  | BGEZ (rs1: Gpr) (ofs: word 12): Rv32i
  | BLTZ (rs1: Gpr) (ofs: word 12): Rv32i
  | BGTZ (rs1: Gpr) (ofs: word 12): Rv32i
  | J (ofs: word 20): Rv32i
  | NOP: Rv32i
  | TOHOST (rs1: Gpr): Rv32i.

  Local Infix "~~" := combine (at level 0).

  Definition offsetUJToRaw (ofs: word 20) :=
    let ofs20_12 := spl1 11 9 ofs in
    let ofs11_1 := spl2 11 9 ofs in
    cmb (cmb (spl1 8 1 ofs20_12) (spl2 10 1 ofs11_1))
        (cmb (spl1 10 1 ofs11_1) (spl2 8 1 ofs20_12)).

  Definition offsetSBToRaw12 (ofs: word 12) := spl1 11 1 ofs.
  Definition offsetSBToRaw11 (ofs: word 12) := spl2 1 1 (spl1 10 2 ofs).
  Definition offsetSBToRaw10_5 (ofs: word 12) := spl2 6 2 (spl1 4 8 ofs).
  Definition offsetSBToRaw4_1 (ofs: word 12) := spl2 4 8 ofs.

  Definition offsetSToRaw11_5 (ofs: word 12) := spl1 5 7 ofs.
  Definition offsetSToRaw4_0 (ofs: word 12) := spl2 5 7 ofs.

  Definition RtypeToRaw (op: word 7) (rs1 rs2 rd: Gpr) (f7: word 7) (f3: word 3) :=
    op~~(gprToRaw rd)~~f3~~(gprToRaw rs1)~~(gprToRaw rs2)~~f7.
  Definition ItypeToRaw (op: word 7) (rs1 rd: Gpr) (f3: word 3) (ofs: word 12) :=
    op~~(gprToRaw rd)~~f3~~(gprToRaw rs1)~~ofs.
  Definition StypeToRaw (op: word 7) (rs1 rs2: Gpr) (f3: word 3) (ofs: word 12) :=
    op~~(offsetSToRaw4_0 ofs)~~f3~~(gprToRaw rs1)~~(gprToRaw rs2)~~(offsetSToRaw11_5 ofs).
  Definition SBtypeToRaw (op: word 7) (rs1 rs2: Gpr) (f3: word 3) (ofs: word 12) :=
    op~~(offsetSBToRaw11 ofs)~~(offsetSBToRaw4_1 ofs)
      ~~f3~~(gprToRaw rs1)~~(gprToRaw rs2)
      ~~(offsetSBToRaw10_5 ofs)~~(offsetSBToRaw12 ofs).
  Definition UJtypeToRaw (op: word 7) (rd: Gpr) (ofs: word 20) :=
    op~~(gprToRaw rd)~~(offsetUJToRaw ofs).
               
  Fixpoint rv32iToRaw (inst: Rv32i): word 32 :=
    match inst with
    | JAL rd ofs => UJtypeToRaw rv32iOpJAL rd ofs
    | JALR rs1 rd ofs => ItypeToRaw rv32iOpJALR rs1 rd WO~0~0~0 ofs
    | BEQ rs1 rs2 ofs => SBtypeToRaw rv32iOpBRANCH rs1 rs2 rv32iF3BEQ ofs
    | BNE rs1 rs2 ofs => SBtypeToRaw rv32iOpBRANCH rs1 rs2 rv32iF3BNE ofs
    | BLT rs1 rs2 ofs => SBtypeToRaw rv32iOpBRANCH rs1 rs2 rv32iF3BLT ofs
    | BGE rs1 rs2 ofs => SBtypeToRaw rv32iOpBRANCH rs1 rs2 rv32iF3BGE ofs
    | BLTU rs1 rs2 ofs => SBtypeToRaw rv32iOpBRANCH rs1 rs2 rv32iF3BLTU ofs
    | BGEU rs1 rs2 ofs => SBtypeToRaw rv32iOpBRANCH rs1 rs2 rv32iF3BGEU ofs
    | LW rs1 rd ofs => ItypeToRaw rv32iOpLOAD rs1 rd rv32iF3LW ofs
    | SW rs1 rs2 ofs => StypeToRaw rv32iOpSTORE rs1 rs2 rv32iF3SW ofs
    | ADDI rs1 rd ofs => ItypeToRaw rv32iOpOPIMM rs1 rd rv32iF3ADDI ofs
    | ADD rs1 rs2 rd => RtypeToRaw rv32iOpOP rs1 rs2 rd rv32iF7ADD rv32iF3ADD
    | SUB rs1 rs2 rd => RtypeToRaw rv32iOpOP rs1 rs2 rd rv32iF7SUB rv32iF3SUB
    | MUL rs1 rs2 rd => RtypeToRaw rv32iOpOP rs1 rs2 rd rv32mF7MUL rv32mF3MUL
    | SLL rs1 rs2 rd => RtypeToRaw rv32iOpOP rs1 rs2 rd rv32iF7SLL rv32iF3SLL
    | SRL rs1 rs2 rd => RtypeToRaw rv32iOpOP rs1 rs2 rd rv32iF7SRL rv32iF3SRL
    | OR rs1 rs2 rd => RtypeToRaw rv32iOpOP rs1 rs2 rd rv32iF7OR rv32iF3OR
    | AND rs1 rs2 rd => RtypeToRaw rv32iOpOP rs1 rs2 rd rv32iF7AND rv32iF3AND
    | XOR rs1 rs2 rd => RtypeToRaw rv32iOpOP rs1 rs2 rd rv32iF7XOR rv32iF3XOR
    (* pseudo-instructions *)
    | LI rd ofs => ItypeToRaw rv32iOpOPIMM x0 rd rv32iF3ADDI (split1 12 8 ofs)
    | MV rs1 rd => ItypeToRaw rv32iOpOPIMM rs1 rd rv32iF3ADDI (natToWord _ 0)
    | BEQZ rs1 ofs => SBtypeToRaw rv32iOpBRANCH rs1 x0 rv32iF3BEQ ofs
    | BNEZ rs1 ofs => SBtypeToRaw rv32iOpBRANCH rs1 x0 rv32iF3BNE ofs 
    | BLEZ rs1 ofs => SBtypeToRaw rv32iOpBRANCH x0 rs1 rv32iF3BGE ofs
    | BGEZ rs1 ofs => SBtypeToRaw rv32iOpBRANCH rs1 x0 rv32iF3BGE ofs
    | BLTZ rs1 ofs => SBtypeToRaw rv32iOpBRANCH rs1 x0 rv32iF3BLT ofs
    | BGTZ rs1 ofs => SBtypeToRaw rv32iOpBRANCH x0 rs1 rv32iF3BLT ofs
    | J ofs => UJtypeToRaw rv32iOpJAL x0 ofs
    | NOP => ItypeToRaw rv32iOpOPIMM x0 x0 rv32iF3ADDI (wzero _)
    (* custom instructions *)
    | TOHOST rs1 => RtypeToRaw rv32iOpTOHOST rs1 x0 x0 rv32iF7ADD rv32iF3ADD
    end.

End RV32IStruct.

Section UnitTests.

  Definition RtypeToRaw_getOpcodeE_correct:
    evalExpr (getOpcodeE
                (Const _ (ConstBit (RtypeToRaw rv32iOpOP x1 x2 x3 rv32iF7SRLI rv32iF3SRLI)))) =
    rv32iOpOP := eq_refl.
  Definition RtypeToRaw_getRs1E_correct:
    evalExpr (getRs1E
                (Const _ (ConstBit (RtypeToRaw rv32iOpOP x1 x2 x3 rv32iF7SRLI rv32iF3SRLI)))) =
    gprToRaw x1 := eq_refl.
  Definition RtypeToRaw_getRs2E_correct:
    evalExpr (getRs2E
                (Const _ (ConstBit (RtypeToRaw rv32iOpOP x1 x2 x3 rv32iF7SRLI rv32iF3SRLI)))) =
    gprToRaw x2 := eq_refl.
  Definition RtypeToRaw_getRdE_correct:
    evalExpr (getRdE
                (Const _ (ConstBit (RtypeToRaw rv32iOpOP x1 x2 x3 rv32iF7SRLI rv32iF3SRLI)))) =
    gprToRaw x3 := eq_refl.
  Definition RtypeToRaw_getFunct7E_correct:
    evalExpr (getFunct7E
                (Const _ (ConstBit (RtypeToRaw rv32iOpOP x1 x2 x3 rv32iF7SRLI rv32iF3SRLI)))) =
    rv32iF7SRLI := eq_refl.
  Definition RtypeToRaw_getFunct3E_correct:
    evalExpr (getFunct3E
                (Const _ (ConstBit (RtypeToRaw rv32iOpOP x1 x2 x3 rv32iF7SRLI rv32iF3SRLI)))) =
    rv32iF3SRLI := eq_refl.

  Definition ItypeToRaw_getOpcodeE_correct:
    evalExpr (getOpcodeE
                (Const _ (ConstBit (ItypeToRaw rv32iOpOPIMM x1 x2 rv32iF3SRLI (natToWord _ 5))))) =
    rv32iOpOPIMM := eq_refl.
  Definition ItypeToRaw_getRs1E_correct:
    evalExpr (getRs1E
                (Const _ (ConstBit (ItypeToRaw rv32iOpOPIMM x1 x2 rv32iF3SRLI (natToWord _ 5))))) =
    gprToRaw x1 := eq_refl.
  Definition ItypeToRaw_getRdE_correct:
    evalExpr (getRdE
                (Const _ (ConstBit (ItypeToRaw rv32iOpOPIMM x1 x2 rv32iF3SRLI (natToWord _ 5))))) =
    gprToRaw x2 := eq_refl.
  Definition ItypeToRaw_getFunct3E_correct:
    evalExpr (getFunct3E
                (Const _ (ConstBit (ItypeToRaw rv32iOpOPIMM x1 x2 rv32iF3SRLI (natToWord _ 5))))) =
    rv32iF3SRLI := eq_refl.
  Definition ItypeToRaw_getOffsetIE_correct:
    evalExpr (getOffsetIE
                (Const _ (ConstBit (ItypeToRaw rv32iOpOPIMM x1 x2 rv32iF3SRLI (natToWord _ 5))))) =
    natToWord _ 5 := eq_refl.

  Definition StypeToRaw_getOpcodeE_correct:
    evalExpr (getOpcodeE
                (Const _ (ConstBit (StypeToRaw rv32iOpSTORE x1 x2 rv32iF3SW (natToWord _ 5))))) =
    rv32iOpSTORE := eq_refl.
  Definition StypeToRaw_getRs1E_correct:
    evalExpr (getRs1E
                (Const _ (ConstBit (StypeToRaw rv32iOpOPIMM x1 x2 rv32iF3SW (natToWord _ 5))))) =
    gprToRaw x1 := eq_refl.
  Definition StypeToRaw_getRs2E_correct:
    evalExpr (getRs2E
                (Const _ (ConstBit (StypeToRaw rv32iOpOPIMM x1 x2 rv32iF3SW (natToWord _ 5))))) =
    gprToRaw x2 := eq_refl.
  Definition StypeToRaw_getFunct3E_correct:
    evalExpr (getFunct3E
                (Const _ (ConstBit (StypeToRaw rv32iOpOPIMM x1 x2 rv32iF3SW (natToWord _ 5))))) =
    rv32iF3SW := eq_refl.
  Definition StypeToRaw_getOffsetSE_correct:
    evalExpr (getOffsetSE
                (Const _ (ConstBit (StypeToRaw rv32iOpOPIMM x1 x2 rv32iF3SW (natToWord _ 5))))) =
    natToWord _ 5 := eq_refl.

  Definition SBtypeToRaw_getOpcodeE_correct:
    evalExpr (getOpcodeE
                (Const _ (ConstBit (SBtypeToRaw rv32iOpBRANCH x1 x2 rv32iF3BGE (natToWord _ 5))))) =
    rv32iOpBRANCH := eq_refl.
  Definition SBtypeToRaw_getRs1E_correct:
    evalExpr (getRs1E
                (Const _ (ConstBit (SBtypeToRaw rv32iOpOPIMM x1 x2 rv32iF3BGE (natToWord _ 5))))) =
    gprToRaw x1 := eq_refl.
  Definition SBtypeToRaw_getRs2E_correct:
    evalExpr (getRs2E
                (Const _ (ConstBit (SBtypeToRaw rv32iOpOPIMM x1 x2 rv32iF3BGE (natToWord _ 5))))) =
    gprToRaw x2 := eq_refl.
  Definition SBtypeToRaw_getFunct3E_correct:
    evalExpr (getFunct3E
                (Const _ (ConstBit (SBtypeToRaw rv32iOpOPIMM x1 x2 rv32iF3BGE (natToWord _ 5))))) =
    rv32iF3BGE := eq_refl.
  Definition SBtypeToRaw_getOffsetSE_correct:
    evalExpr (getOffsetSBE
                (Const _ (ConstBit (SBtypeToRaw rv32iOpOPIMM x1 x2 rv32iF3BGE (natToWord _ 5))))) =
    natToWord _ 5 := eq_refl.

  Definition UJtypeToRaw_getOpcodeE_correct:
    evalExpr (getOpcodeE
                (Const _ (ConstBit (UJtypeToRaw rv32iOpJAL x1 (natToWord _ 5))))) =
    rv32iOpJAL := eq_refl.
  Definition UJtypeToRaw_getRdE_correct:
    evalExpr (getRdE
                (Const _ (ConstBit (UJtypeToRaw rv32iOpJAL x1 (natToWord _ 5))))) =
    gprToRaw x1 := eq_refl.
  Definition UJtypeToRaw_getOffsetUJE_correct:
    evalExpr (getOffsetUJE
                (Const _ (ConstBit (UJtypeToRaw rv32iOpJAL x1 (natToWord _ 5))))) =
    natToWord _ 5 := eq_refl.
  
End UnitTests.

