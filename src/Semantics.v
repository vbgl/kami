Require Import Bool List String Structures.Equalities.
Require Import Lib.Struct Lib.Word Lib.CommonTactics Lib.StringBound Lib.ilist Syntax.
Require Import FunctionalExtensionality Program.Equality Eqdep Eqdep_dec.

Set Implicit Arguments.

(* TODO: may move to lib/Struct.v *)
Lemma opt_some_eq: forall {A} (v1 v2: A), Some v1 = Some v2 -> v1 = v2.
Proof. intros; inv H; reflexivity. Qed.

Lemma typed_type_eq:
  forall {A} (a1 a2: A) (B: A -> Type) (v1: B a1) (v2: B a2),
    {| objType := a1; objVal := v1 |} = {| objType := a2; objVal := v2 |} ->
    exists (Heq: a1 = a2), match Heq with eq_refl => v1 end = v2.
Proof. intros; inv H; exists eq_refl; reflexivity. Qed.

Lemma typed_eq:
  forall {A} (a: A) (B: A -> Type) (v1 v2: B a),
    {| objType := a; objVal := v1 |} = {| objType := a; objVal := v2 |} ->
    v1 = v2.
Proof. intros; inv H; apply Eqdep.EqdepTheory.inj_pair2 in H1; assumption. Qed.

(* concrete representations of data kinds *)
Fixpoint type (t: Kind): Type :=
  match t with
    | Bool => bool
    | Bit n => word n
    | Vector nt n => word n -> type nt
    | Struct attrs => forall i, @GetAttrType _ (map (mapAttr type) attrs) i
  end.

(*
Fixpoint fullType (k : FullKind) : Type := match k with
  | SyntaxKind t => type t
  | NativeKind t => t
  end.
 *)

Section WordFunc.

  Definition wordZero (w: word 0): w = WO :=
    shatter_word w.

  Variable A: Type.

  (* a lemma for wordVecDec *)
  Definition wordVecDec':
    forall n (f g: word n -> A), (forall x: word n, {f x = g x} + {f x <> g x}) ->
                                 {forall x, f x = g x} + {exists x, f x <> g x}.
  Proof.
    intro n.
    induction n; intros f g H.
    - destruct (H WO).
      + left; intros x.
        rewrite (wordZero x) in *; intuition.
      + right; eauto.
    - assert (Hn: forall b (x: word n),
                    {f (WS b x) = g (WS b x)} + {f (WS b x) <> g (WS b x)}) by
             (intros; specialize (H (WS b x)); intuition).
      destruct (IHn _ _ (Hn false)) as [ef | nf].
      + destruct (IHn _ _ (Hn true)) as [et | nt].
        * left; intros x.
          specialize (ef (wtl x)).
          specialize (et (wtl x)).
          pose proof (shatter_word x) as use; simpl in *.
          destruct (whd x); rewrite <- use in *; intuition.
        * right; destruct_ex; eauto.
      + right; destruct_ex; eauto.
  Qed.

  Definition wordVecDec:
    forall n (f g: word n -> A), (forall x: word n, {f x = g x} + {f x <> g x}) ->
                                 {f = g} + {f <> g}.
  Proof.
    intros.
    pose proof (wordVecDec' _ _ H) as [lt | rt].
    left; apply functional_extensionality; intuition.
    right; unfold not; intros eq; rewrite eq in *.
    destruct rt; intuition.
  Qed.
End WordFunc.

Section VecFunc.
  Variable A: Type.
  Fixpoint evalVec n (vec: Vec A n): word n -> A.
  Proof.
    refine match vec in Vec _ n return word n -> A with
             | Vec0 e => fun _ => e
             | VecNext n' v1 v2 =>
               fun w =>
                 match w in word m0 return m0 = S n' -> A with
                   | WO => _
                   | WS b m w' =>
                     if b
                     then fun _ => evalVec _ v2 (_ w')
                     else fun _ => evalVec _ v2 (_ w')
                 end eq_refl
           end;
    clear evalVec.
    abstract (intros; discriminate).
    abstract (injection _H; intros; subst; intuition).
    abstract (injection _H; intros; subst; intuition).
  Defined.

  Variable B: Type.
  Variable map: A -> B.
  Fixpoint mapVec n (vec: Vec A n): Vec B n :=
    match vec in Vec _ n return Vec B n with
      | Vec0 e => Vec0 (map e)
      | VecNext n' v1 v2 => VecNext (mapVec v1) (mapVec v2)
    end.
End VecFunc.

(* for any kind, we have decidable equality on its representation *)
Definition isEq : forall k (e1: type k) (e2: type k),
                    {e1 = e2} + {e1 <> e2}.
Proof.
  refine (fix isEq k : forall (e1: type k) (e2: type k), {e1 = e2} + {e1 <> e2} :=
            match k return forall (e1: type k) (e2: type k),
                             {e1 = e2} + {e1 <> e2} with
              | Bool => bool_dec
              | Bit n => fun e1 e2 => weq e1 e2
              | Vector n nt =>
                  fun e1 e2 =>
                    wordVecDec e1 e2 (fun x => isEq _ (e1 x) (e2 x))
              | Struct h =>
                (fix isEqs atts : forall (vs1 vs2 : forall i, @GetAttrType _ (map (mapAttr type) atts) i),
                                    {vs1 = vs2} + {vs1 <> vs2} :=
                   match atts return forall (vs1 vs2 : forall i, @GetAttrType _ (map (mapAttr type) atts) i),
                                       {vs1 = vs2} + {vs1 <> vs2} with
                     | nil => fun _ _ => Yes
                     | att :: atts' => fun vs1 vs2 =>
                       isEq _
                            (vs1 {| bindex := attrName att; indexb := {| ibound := 0;
                                      boundi := eq_refl :
                                                  nth_error
                                                    (map (attrName (Kind:=Type))
                                                         (map (mapAttr type) (att :: atts'))) 0
                                                    = Some (attrName att) |} |})
                            (vs2 {| bindex := attrName att; indexb := {| ibound := 0;
                                      boundi := eq_refl :
                                                  nth_error
                                                    (map (attrName (Kind:=Type))
                                                         (map (mapAttr type) (att :: atts'))) 0
                                                    = Some (attrName att) |} |});;
                       isEqs atts'
                       (fun i => vs1 {| indexb := {| ibound := S (ibound (indexb i)) |} |})
                       (fun i => vs2 {| indexb := {| ibound := S (ibound (indexb i)) |} |});;
                       Yes
                   end) h
            end); clear isEq; try clear isEqs;
  abstract (unfold BoundedIndexFull in *; simpl in *; try (intro; subst; tauto);
  repeat match goal with
           | [ |- _ = _ ] => extensionality i
           | [ x : BoundedIndex _ |- _ ] => destruct x
           | [ x : IndexBound _ _ |- _ ] => destruct x
           | [ H : nth_error nil ?n = Some _ |- _ ] => destruct n; discriminate
           | [ |- _ {| indexb := {| ibound := ?b |} |} = _ ] =>
             match goal with
               | [ x : _ |- _ ] =>
                 match x with
                   | b => destruct b; simpl in *
                 end
             end
           | [ H : Specif.value _ = Some _ |- _ ] => progress (injection H; intro; subst)
           | [ H : _ = _ |- _ ] => progress rewrite (UIP_refl _ _ H)
           | [ H : _ = _ |- _ {| bindex := ?bi; indexb := {| ibound := S ?ib; boundi := ?pf |} |} = _ ] =>
             apply (f_equal (fun f => f {| bindex := bi; indexb := {| ibound := ib; boundi := pf |} |})) in H
         end; auto).
Defined.

Definition evalUniBool (op: UniBoolOp) : bool -> bool :=
  match op with
    | Neg => negb
  end.

Definition evalBinBool (op: BinBoolOp) : bool -> bool -> bool :=
  match op with
    | And => andb
    | Or => orb
  end.

(* the head of a word, or false if the word has 0 bits *)
Definition whd' sz (w: word sz) :=
  match sz as s return word s -> bool with
    | 0 => fun _ => false
    | S n => fun w => whd w
  end w.

Definition evalUniBit n1 n2 (op: UniBitOp n1 n2): word n1 -> word n2.
refine match op with
         | Inv n => @wneg n
         | ConstExtract n1 n2 n3 => fun w => split2 n1 n2 (split1 (n1 + n2) n3 w)
         | ZeroExtendTrunc n1 n2 => fun w => split2 n1 n2 (_ (combine (wzero n2) w))
         | SignExtendTrunc n1 n2 => fun w => split2 n1 n2 (_ (combine (if whd' w
                                                                       then wones n2
                                                                       else wzero n2) w))
         | TruncLsb n1 n2 => fun w => split1 n1 n2 w
       end;
  assert (H: n3 + n0 = n0 + n3) by omega;
  rewrite H in *; intuition.
Defined.

Definition evalBinBit n1 n2 n3 (op: BinBitOp n1 n2 n3)
  : word n1 -> word n2 -> word n3 :=
  match op with
    | Add n => @wplus n
    | Sub n => @wminus n
  end.

Definition evalConstStruct attrs (ils : ilist (fun a => type (attrType a)) attrs) : type (Struct attrs) :=
  fun (i: BoundedIndex (namesOf (map (mapAttr type) attrs))) =>
    mapAttrEq1 type attrs i
               (ith_Bounded _ ils (getNewIdx1 type attrs i)).

(* evaluate any constant operation *)
Fixpoint evalConstT k (e: ConstT k): type k :=
  match e in ConstT k return type k with
    | ConstBool b => b
    | ConstBit n w => w
    | ConstVector k' n v => evalVec (mapVec (@evalConstT k') v)
    | ConstStruct attrs ils => evalConstStruct (imap _ (fun _ ba => evalConstT ba) ils)
  end.

Definition evalConstFullT k (e: ConstFullT k) :=
  match e in ConstFullT k return fullType type k with
    | SyntaxConst k' c' => evalConstT c'
    | NativeConst t c c' => c'
  end.

Section GetCms.
  Fixpoint getCmsA {k} (a: ActionT (fun _ => True) k): list string :=
    match a with
      | MCall m _ _ c => m :: (getCmsA (c I))
      | Let_ fk e c => getCmsA (c match fk as fk' return fullType (fun _ => True) fk' with
                                    | SyntaxKind _ => I
                                    | NativeKind _ c' => c'
                                  end)
      | ReadReg _ fk c => getCmsA (c match fk as fk' return fullType (fun _ => True) fk' with
                                       | SyntaxKind _ => I
                                       | NativeKind _ c' => c'
                                     end)
      | WriteReg _ _ _ c => getCmsA c
      | IfElse _ _ aT aF c =>
        (getCmsA aT) ++ (getCmsA aF)
                     ++ (getCmsA (c I))
      | Assert_ _ c => getCmsA c
      | Return _ => nil
    end.

  Fixpoint getCmsR (rl: list (Attribute (Action (Bit 0))))
  : list string :=
    match rl with
      | nil => nil
      | r :: rl' => (getCmsA (attrType r (fun _ => True))) ++ (getCmsR rl')
    end.

  Fixpoint getCmsM (ms: list DefMethT): list string :=
    match ms with
      | nil => nil
      | m :: ms' => (getCmsA ((objVal (attrType m)) (fun _ => True) I))
                      ++ (getCmsM ms')
    end.

Require Import Lib.FMap.

  Fixpoint getCmsMod (m: Modules): list string :=
    match m with
      | Mod _ rules meths => getCmsR rules ++ getCmsM meths
      | ConcatMod m1 m2 => (listSub (getCmsMod m1) (getDmsMod m2))
                             ++ (listSub (getCmsMod m2) (getDmsMod m1))
    end
  with getDmsMod (m: Modules): list string :=
         match m with
           | Mod _ _ meths => namesOf meths
           | ConcatMod m1 m2 => (listSub (getDmsMod m1) (getCmsMod m2))
                                  ++ (listSub (getDmsMod m2) (getCmsMod m1))
         end.

  Fixpoint getDmsBodies (m: Modules): list DefMethT :=
    match m with
      | Mod _ _ meths => meths
      | ConcatMod m1 m2 => (getDmsBodies m1) ++ (getDmsBodies m2)
    end.

End GetCms.

Hint Unfold getCmsMod getDmsMod getDmsBodies.

Module M := FMap.Map.
Module MF := FMap.MapF.

(* maps register names to the values which they currently hold *)
Definition RegsT := M.t (Typed (fullType type)).

(* a pair of the value sent to a method call and the value it returned *)
Definition SignT k := (type (arg k) * type (ret k))%type.

(* a list of simulatenous method call actions made during a single step *)
Definition CallsT := M.t (Typed SignT).

Section Semantics.
  Definition mkStruct attrs (ils : ilist (fun a => type (attrType a)) attrs) : type (Struct attrs) :=
    fun (i: BoundedIndex (namesOf (map (mapAttr type) attrs))) =>
      mapAttrEq1 type attrs i (ith_Bounded _ ils (getNewIdx1 type attrs i)).

  Fixpoint evalExpr exprT (e: Expr type exprT): fullType type exprT :=
    match e in Expr _ exprT return fullType type exprT with
      | Var _ v => v
      | Const _ v => evalConstT v
      | UniBool op e1 => (evalUniBool op) (evalExpr e1)
      | BinBool op e1 e2 => (evalBinBool op) (evalExpr e1) (evalExpr e2)
      | UniBit n1 n2 op e1 => (evalUniBit op) (evalExpr e1)
      | BinBit n1 n2 n3 op e1 e2 => (evalBinBit op) (evalExpr e1) (evalExpr e2)
      | ITE _ p e1 e2 => if evalExpr p
                         then evalExpr e1
                         else evalExpr e2
      | Eq _ e1 e2 => if isEq _ (evalExpr e1) (evalExpr e2)
                      then true
                      else false
      | ReadIndex _ _ i f => (evalExpr f) (evalExpr i)
      | ReadField heading fld val =>
          mapAttrEq2 type fld
            ((evalExpr val) (getNewIdx2 type fld))
      | BuildVector _ k vec => evalVec (mapVec (@evalExpr _) vec)
      | BuildStruct attrs ils => mkStruct (imap _ (fun _ ba => evalExpr ba) ils)
      | UpdateVector _ _ fn i v =>
          fun w => if weq w (evalExpr i) then evalExpr v else (evalExpr fn) w
    end.

  (*register names and constant expressions for their initial values *)
  Variable regInit: list RegInitT.

  Variable rules: list (Attribute (Action (Bit 0))).

  (* register values just before the current cycle *)
  Variable oldRegs: RegsT.

  Inductive SemAction:
    forall k, ActionT type k -> RegsT -> CallsT -> type k -> Prop :=
  | SemMCall
      meth s (marg: Expr type (SyntaxKind (arg s)))
      (mret: type (ret s))
      retK (fret: type retK)
      (cont: type (ret s) -> ActionT type retK)
      newRegs (calls: CallsT) acalls
      (HAcalls: acalls = M.add meth {| objVal := (evalExpr marg, mret) |} calls)
      (HSemAction: SemAction (cont mret) newRegs calls fret):
      SemAction (MCall meth s marg cont) newRegs acalls fret
  | SemLet
      k (e: Expr type k) retK (fret: type retK)
      (cont: fullType type k -> ActionT type retK) newRegs calls
      (HSemAction: SemAction (cont (evalExpr e)) newRegs calls fret):
      SemAction (Let_ e cont) newRegs calls fret
  | SemReadReg
      (r: string) regT (regV: fullType type regT)
      retK (fret: type retK) (cont: fullType type regT -> ActionT type retK)
      newRegs calls
      (HRegVal: M.find r oldRegs = Some {| objType := regT; objVal := regV |})
      (HSemAction: SemAction (cont regV) newRegs calls fret):
      SemAction (ReadReg r _ cont) newRegs calls fret
  | SemWriteReg
      (r: string) k
      (e: Expr type k)
      retK (fret: type retK)
      (cont: ActionT type retK) newRegs calls anewRegs
      (HANewRegs: anewRegs = M.add r {| objVal := (evalExpr e) |} newRegs)
      (HSemAction: SemAction cont newRegs calls fret):
      SemAction (WriteReg r e cont) anewRegs calls fret
  | SemIfElseTrue
      (p: Expr type (SyntaxKind Bool)) k1
      (a: ActionT type k1)
      (a': ActionT type k1)
      (r1: type k1)
      k2 (cont: type k1 -> ActionT type k2)
      newRegs1 newRegs2 calls1 calls2 (r2: type k2)
      (HTrue: evalExpr p = true)
      (HAction: SemAction a newRegs1 calls1 r1)
      (HSemAction: SemAction (cont r1) newRegs2 calls2 r2)
      unewRegs ucalls
      (HUNewRegs: unewRegs = MF.union newRegs1 newRegs2)
      (HUCalls: ucalls = MF.union calls1 calls2):
      SemAction (IfElse p a a' cont) unewRegs ucalls r2
  | SemIfElseFalse
      (p: Expr type (SyntaxKind Bool)) k1
      (a: ActionT type k1)
      (a': ActionT type k1)
      (r1: type k1)
      k2 (cont: type k1 -> ActionT type k2)
      newRegs1 newRegs2 calls1 calls2 (r2: type k2)
      (HFalse: evalExpr p = false)
      (HAction: SemAction a' newRegs1 calls1 r1)
      (HSemAction: SemAction (cont r1) newRegs2 calls2 r2)
      unewRegs ucalls
      (HUNewRegs: unewRegs = MF.union newRegs1 newRegs2)
      (HUCalls: ucalls = MF.union calls1 calls2):
      SemAction (IfElse p a a' cont) unewRegs ucalls r2
  | SemAssertTrue
      (p: Expr type (SyntaxKind Bool)) k2
      (cont: ActionT type k2) newRegs2 calls2 (r2: type k2)
      (HTrue: evalExpr p = true)
      (HSemAction: SemAction cont newRegs2 calls2 r2):
      SemAction (Assert_ p cont) newRegs2 calls2 r2
  | SemReturn
      k (e: Expr type (SyntaxKind k)) evale
      (HEvalE: evale = evalExpr e):
      SemAction (Return e) (M.empty _) (M.empty _) evale.

  Theorem inversionSemAction
          k a news calls retC
          (evalA: @SemAction k a news calls retC):
    match a with
      | MCall m s e c =>
        exists mret pcalls,
          SemAction (c mret) news pcalls retC /\
          calls = M.add m {| objVal := (evalExpr e, mret) |} pcalls
      | Let_ _ e cont =>
        SemAction (cont (evalExpr e)) news calls retC
      | ReadReg r k c =>
        exists rv,
          M.find r oldRegs = Some {| objType := k; objVal := rv |} /\
          SemAction (c rv) news calls retC
      | WriteReg r _ e a =>
        exists pnews,
          SemAction a pnews calls retC /\
          news = M.add r {| objVal := evalExpr e |} pnews
      | IfElse p _ aT aF c =>
        exists news1 calls1 news2 calls2 r1,
          match evalExpr p with
            | true =>
              SemAction aT news1 calls1 r1 /\
              SemAction (c r1) news2 calls2 retC /\
              news = MF.union news1 news2 /\
              calls = MF.union calls1 calls2
            | false =>
              SemAction aF news1 calls1 r1 /\
              SemAction (c r1) news2 calls2 retC /\
              news = MF.union news1 news2 /\
              calls = MF.union calls1 calls2
          end
      | Assert_ e c =>
        SemAction c news calls retC /\
        evalExpr e = true
      | Return e =>
        retC = evalExpr e /\
        news = M.empty _ /\
        calls = M.empty _
    end.
  Proof.
    destruct evalA; eauto; repeat eexists; destruct (evalExpr p); eauto; try discriminate.
  Qed.

  Inductive SemMod: option string -> RegsT -> list DefMethT -> CallsT -> CallsT -> Prop :=
  | SemEmpty news meths dm cm
             (HEmptyRegs: news = M.empty _)
             (HEmptyDms: dm = M.empty _)
             (HEmptyCms: cm = M.empty _):
      SemMod None news meths dm cm
  | SemAddRule (ruleName: string)
               (ruleBody: Action (Bit 0))
               (HInRule: In {| attrName := ruleName; attrType := ruleBody |} rules)
               news calls retV
               (HAction: SemAction (ruleBody type) news calls retV)
               news2 meths dm2 cm2
               (HSemMod: SemMod None news2 meths dm2 cm2)
               (HNoDoubleWrites: MF.Disj news news2)
               (HNoCallsBoth: MF.Disj calls cm2)
               unews ucalls
               (HRegs: unews = MF.union news news2)
               (HCalls: ucalls = MF.union calls cm2):
      SemMod (Some ruleName) unews meths dm2 ucalls
  (* method `meth` was also called this clock cycle *)
  | SemAddMeth calls news (meth: DefMethT) meths argV retV
               (HIn: In meth meths)
               (HAction: SemAction ((objVal (attrType meth)) type argV) news calls retV)
               news2 dm2 cm2
               (HSemMod: SemMod None news2 meths dm2 cm2)
               (HNoDoubleWrites: MF.Disj news news2)
               (HNoCallsBoth: MF.Disj calls cm2)
               unews ucalls udefs
               (HRegs: unews = MF.union news news2)
               (HCalls: ucalls = MF.union calls cm2)
               (HNew: M.find (attrName meth) dm2 = None)
               (HDefs: udefs = M.add (attrName meth) {| objVal := (argV, retV) |} dm2):
      SemMod None unews meths udefs ucalls.

End Semantics.

Ltac cheap_firstorder :=
  repeat match goal with
           | [ H : ex _ |- _ ] => destruct H
           | [ H : _ /\ _ |- _ ] => destruct H
         end.

Ltac invertAction H := apply inversionSemAction in H; simpl in H; cheap_firstorder; try subst.
Ltac invertActionFirst :=
  match goal with
    | [H: SemAction _ _ _ _ _ |- _] => invertAction H
  end.
Ltac invertActionRep :=
  repeat
    match goal with
      | [H: SemAction _ _ _ _ _ |- _] => invertAction H
      | [H: if ?c
            then
              SemAction _ _ _ _ _ /\ _ /\ _ /\ _
            else
              SemAction _ _ _ _ _ /\ _ /\ _ /\ _ |- _] =>
        let ic := fresh "ic" in
        (remember c as ic; destruct ic; dest; subst)
    end.

Ltac invertSemMod H :=
  inv H;
  repeat match goal with
           | [H: MF.Disj _ _ |- _] => clear H
         end.

Ltac invertSemModRep :=
  repeat
    match goal with
      | [H: SemMod _ _ _ _ _ _ _ |- _] => invertSemMod H
    end.

Lemma SemAction_olds_ext:
  forall retK a olds1 olds2 news calls (retV: type retK),
    MF.Sub olds1 olds2 ->
    SemAction olds1 a news calls retV ->
    SemAction olds2 a news calls retV.
Proof.
  induction a; intros.
  - invertAction H1; econstructor; eauto.
  - invertAction H1; econstructor; eauto.
  - invertAction H1; econstructor; eauto.
    apply M.find_1. apply H0. apply MF.F.P.F.find_mapsto_iff. assumption.
  - invertAction H0; econstructor; eauto.
  - invertAction H1.
    remember (evalExpr e) as cv; destruct cv; dest.
    + eapply SemIfElseTrue; eauto.
    + eapply SemIfElseFalse; eauto.
  - invertAction H0; econstructor; eauto.
  - invertAction H0; econstructor; eauto.
Qed.

Lemma SemMod_empty:
  forall rules or dms, SemMod rules or None (M.empty _) dms (M.empty _) (M.empty _).
Proof. intros; apply SemEmpty; auto. Qed.

Lemma SemMod_empty_inv:
  forall rules or nr dms cmMap,
    SemMod rules or None nr dms (M.empty _) cmMap ->
    nr = M.empty _ /\ cmMap = M.empty _.
Proof.
  intros; inv H; [intuition|].
  apply @Equal_val with (k:= meth) in HDefs.
  rewrite MF.find_add_1 in HDefs.
  rewrite MF.find_empty in HDefs. inv HDefs.
Qed.

Lemma SemMod_olds_ext:
  forall rules or1 or2 rm nr dms dmMap cmMap,
    MF.Sub or1 or2 -> SemMod rules or1 rm nr dms dmMap cmMap ->
    SemMod rules or2 rm nr dms dmMap cmMap.
Proof.
  induction 2; intros.
  - subst; constructor; auto.
  - eapply SemAddRule; eauto.
    eapply SemAction_olds_ext; eauto.
  - eapply SemAddMeth; eauto.
    eapply SemAction_olds_ext; eauto.
Qed.

Lemma SemMod_dmMap_InDomain:
  forall rules dms or rm nr dmMap cmMap,
    SemMod rules or rm nr dms dmMap cmMap ->
    MF.InDomain dmMap (namesOf dms).
Proof.
  induction 1; intros; subst; intuition.
  unfold MF.InDomain. intros.
  apply MF.F.P.F.empty_in_iff in H. contradiction.
  apply MF.InDomain_add; auto.
  apply in_map; auto.
Qed.

Lemma SemMod_rule_singleton:
  forall dms rules olds news r rb cmMap (Hrb: Some rb = getAttribute r rules)
         (Hwf: NoDup (namesOf rules))
         (Hsem: SemMod rules olds (Some r) news dms (M.empty _) cmMap),
    SemAction olds (attrType rb type) news cmMap WO.
Proof.
  admit.
Qed.

Lemma SemMod_meth_singleton:
  forall dms rules olds news dm a (Ha: Some a = getAttribute dm dms)
         argV retV cmMap
         (Hwf: NoDup (namesOf dms))
         (Hsem: SemMod rules olds None news dms
                       (M.add dm
                            {| objType := objType (attrType a);
                               objVal := (argV, retV) |} (M.empty _)) cmMap),
    SemAction olds (objVal (attrType a) type argV) news cmMap retV.
Proof.
  intros; inv Hsem;
  [apply @Equal_val with (k:= dm) in HEmptyDms; (*map_compute HEmptyDms*)admit; inv HEmptyDms|].

  admit.
Qed.

Lemma SemMod_dms_cut:
  forall dms2 rules dms1 or rm nr dmMap cmMap,
    SemMod rules or rm nr dms1 dmMap cmMap ->
    MF.InDomain dmMap (namesOf dms2) -> (forall k, In k dms2 -> In k dms1) -> 
    SemMod rules or rm nr dms2 dmMap cmMap.
Proof.
  admit.
Qed.

Lemma SemMod_dms_ext:
  forall dms2 rules dms1 or rm nr dmMap cmMap,
    SemMod rules or rm nr dms1 dmMap cmMap ->
    (forall k, In k dms1 -> In k dms2) ->
    SemMod rules or rm nr dms2 dmMap cmMap.
Proof.
  admit.
Qed.

Lemma SemMod_dms_free:
  forall rules dms1 dms2 or rm nr cmMap,
    SemMod rules or rm nr dms1 (M.empty _) cmMap ->
    SemMod rules or rm nr dms2 (M.empty _) cmMap.
Proof.
  admit.
Qed.

Lemma SemMod_rules_free:
  forall rules1 rules2 dms or nr dmMap cmMap,
    SemMod rules1 or None nr dms dmMap cmMap ->
    SemMod rules2 or None nr dms dmMap cmMap.
Proof.
  admit.
Qed.

Lemma SemMod_rules_ext:
  forall rules1 rules2 r dms or nr dmMap cmMap,
    SemMod rules1 or (Some r) nr dms dmMap cmMap ->
    SubList rules1 rules2 ->
    SemMod rules2 or (Some r) nr dms dmMap cmMap.
Proof.
  admit.
Qed.

Lemma SemMod_div:
  forall rules olds rm news dms dmMap1 dmMap2 cmMap
         (Hsem: SemMod rules olds rm news dms (MF.union dmMap1 dmMap2) cmMap)
         (Hdisj: MF.Disj dmMap1 dmMap2),
  exists news1 news2 cmMap1 cmMap2,
    MF.Disj news1 news2 /\ news = MF.union news1 news2 /\
    MF.Disj cmMap1 cmMap2 /\ cmMap = MF.union cmMap1 cmMap2 /\
    SemMod rules olds rm news1 dms dmMap1 cmMap1 /\
    SemMod rules olds None news2 dms dmMap2 cmMap2.
Proof.
  admit.
Qed.

Lemma SemMod_merge_meths:
  forall rules dms or nr1 nr2 dmMap1 dmMap2 cmMap1 cmMap2,
    SemMod rules or None nr1 dms dmMap1 cmMap1 ->
    SemMod rules or None nr2 dms dmMap2 cmMap2 ->
    MF.Disj nr1 nr2 -> MF.Disj dmMap1 dmMap2 -> MF.Disj cmMap1 cmMap2 ->
    SemMod rules or None (MF.union nr1 nr2) dms (MF.union dmMap1 dmMap2) (MF.union cmMap1 cmMap2).
Proof.
  admit.
Qed.

Lemma SemMod_merge_rule:
  forall rules dms or r nr1 nr2 dmMap1 dmMap2 cmMap1 cmMap2,
    SemMod rules or (Some r) nr1 dms dmMap1 cmMap1 ->
    SemMod rules or None nr2 dms dmMap2 cmMap2 ->
    MF.Disj nr1 nr2 -> MF.Disj dmMap1 dmMap2 -> MF.Disj cmMap1 cmMap2 ->
    SemMod rules or (Some r) (MF.union nr1 nr2) dms (MF.union dmMap1 dmMap2) (MF.union cmMap1 cmMap2).
Proof.
  admit.
Qed.

(* dm       : defined methods
   cm       : called methods
   ruleMeth : `None` if it is a method,
              `Some [rulename]` if it is a rule *)
Record RuleLabelT := { ruleMeth: option string;
                       dms: list string;
                       dmMap: CallsT;
                       cms: list string;
                       cmMap: CallsT }.

Hint Unfold ruleMeth dms dmMap cms cmMap.

Definition CombineRm (rm1 rm2 crm: option string) :=
  (rm1 = None \/ rm2 = None) /\
  crm = match rm1, rm2 with
          | Some rn1, None => Some rn1
          | None, Some rn2 => Some rn2
          | _, _ => None
        end.

Lemma combineRm_prop_1:
  forall r1 rm2 cr (Hcrm: CombineRm (Some r1) rm2 (Some cr)),
    r1 = cr.
Proof.
  intros; unfold CombineRm in Hcrm; dest.
  destruct rm2; inv H0; reflexivity.
Qed.

Lemma combineRm_prop_2:
  forall rm1 r2 cr (Hcrm: CombineRm rm1 (Some r2) (Some cr)),
    r2 = cr.
Proof.
  intros; unfold CombineRm in Hcrm; dest.
  destruct rm1; inv H0; reflexivity.
Qed.

Lemma combineRm_prop_3:
  forall rm1 crm (Hcrm: CombineRm rm1 None crm),
    rm1 = crm.
Proof.
  intros; unfold CombineRm in Hcrm; dest.
  destruct rm1; inv H0; reflexivity.
Qed.

Lemma combineRm_prop_4:
  forall rm2 crm (Hcrm: CombineRm None rm2 crm),
    rm2 = crm.
Proof.
  intros; unfold CombineRm in Hcrm; dest.
  destruct rm2; inv H0; reflexivity.
Qed.

Lemma combineRm_prop_5:
  forall rm1 rm2 (Hcrm: CombineRm rm1 rm2 None),
    rm1 = None /\ rm2 = None.
Proof.
  intros; unfold CombineRm in Hcrm; dest.
  destruct rm1, rm2; intuition; inv H1.
Qed.

Definition CallIffDef (l1 l2: RuleLabelT) :=
  (forall m, In m (cms l1) -> In m (dms l2) -> M.find m (cmMap l1) = M.find m (dmMap l2)) /\
  (forall m, In m (cms l2) -> In m (dms l1) -> M.find m (dmMap l1) = M.find m (cmMap l2)).

Definition FiltDm (l1 l2 l: RuleLabelT) :=
  dmMap l = MF.union (MF.complement (dmMap l1) (cms l2)) (MF.complement (dmMap l2) (cms l1)).

Definition FiltCm (l1 l2 l: RuleLabelT) :=
  cmMap l = MF.union (MF.complement (cmMap l1) (dms l2)) (MF.complement (cmMap l2) (dms l1)).

Definition ConcatLabel (l1 l2 l: RuleLabelT) :=
  CombineRm (ruleMeth l1) (ruleMeth l2) (ruleMeth l) /\
  CallIffDef l1 l2 /\ FiltDm l1 l2 l /\ FiltCm l1 l2 l.

Hint Unfold CombineRm CallIffDef FiltDm FiltCm ConcatLabel.

Ltac destConcatLabel :=
  repeat match goal with
           | [H: ConcatLabel _ _ _ |- _] =>
             let Hcrm := fresh "Hcrm" in
             let Hcid := fresh "Hcid" in
             let Hfd := fresh "Hfd" in
             let Hfc := fresh "Hfc" in
             destruct H as [Hcrm [Hcid [Hfd Hfc]]]; clear H; dest;
             unfold ruleMeth in Hcrm
         end.

(* rm = ruleMethod *)
Inductive LtsStep:
  Modules -> option string -> RegsT -> RegsT -> CallsT -> CallsT -> Prop :=
| LtsStepMod regInits oRegs nRegs rules meths rm dmMap cmMap
             (HOldRegs: MF.InDomain oRegs (namesOf regInits))
             (Hltsmod: SemMod rules oRegs rm nRegs meths dmMap cmMap):
    LtsStep (Mod regInits rules meths) rm oRegs nRegs dmMap cmMap
| LtsStepConcat m1 rm1 olds1 news1 dmMap1 cmMap1
                m2 rm2 olds2 news2 dmMap2 cmMap2
                (HOldRegs1: MF.InDomain olds1 (namesOf (getRegInits m1)))
                (HOldRegs2: MF.InDomain olds2 (namesOf (getRegInits m2)))
                (Hlts1: @LtsStep m1 rm1 olds1 news1 dmMap1 cmMap1)
                (Hlts2: @LtsStep m2 rm2 olds2 news2 dmMap2 cmMap2)
                crm colds cnews cdmMap ccmMap
                (Holds: colds = MF.union olds1 olds2)
                (Hnews: cnews = MF.union news1 news2)
                (HdmMap: MF.Disj dmMap1 dmMap2)
                (HcmMap: MF.Disj cmMap1 cmMap2)
                (HMerge: ConcatLabel
                           (Build_RuleLabelT rm1 (getDmsMod m1) dmMap1 (getCmsMod m1) cmMap1)
                           (Build_RuleLabelT rm2 (getDmsMod m2) dmMap2 (getCmsMod m2) cmMap2)
                           (Build_RuleLabelT crm (getDmsMod (ConcatMod m1 m2)) cdmMap
                                             (getCmsMod (ConcatMod m1 m2)) ccmMap)):
    LtsStep (ConcatMod m1 m2) crm colds cnews cdmMap ccmMap.

Lemma ltsStep_rule:
  forall m rm r or nr dmMap cmMap
         (Hstep: LtsStep m rm or nr dmMap cmMap)
         (Hrm: rm = Some r),
    In r (namesOf (getRules m)).
Proof.
  intros; subst.
  dependent induction Hstep.
  - invertSemMod Hltsmod.
    apply in_map_iff; simpl; eexists; split; [|eassumption]; reflexivity.
  - simpl; destConcatLabel.
    unfold CombineRm in Hcrm; dest.
    destruct rm1, rm2.
    + destruct H; discriminate.
    + inv H0; specialize (IHHstep1 s eq_refl).
      unfold namesOf; rewrite map_app; apply in_or_app; left; assumption.
    + inv H0; specialize (IHHstep2 s eq_refl).
      unfold namesOf; rewrite map_app; apply in_or_app; right; assumption.
    + inv H0.
Qed.

Ltac constr_concatMod :=
  repeat autounfold with ModuleDefs;
  match goal with
    | [ |- LtsStep (ConcatMod ?m1 ?m2) (Some ?r) ?or _ _ _ ] =>
      (let Hvoid := fresh "Hvoid" in
       assert (In r (namesOf (getRules m1))) as Hvoid by in_tac;
       clear Hvoid;
       eapply LtsStepConcat with
       (olds1 := MF.restrict or (namesOf (getRegInits m1)))
         (olds2 := MF.complement or (namesOf (getRegInits m1)))
         (rm1 := Some r) (rm2 := None); eauto)
        || (eapply LtsStepConcat with
            (olds1 := MF.restrict or (namesOf (getRegInits m1)))
              (olds2 := MF.complement or (namesOf (getRegInits m1)))
              (rm1 := None) (rm2 := Some r); eauto)
    | [ |- LtsStep (ConcatMod ?m1 ?m2) None _ _ _ _ ] =>
      eapply LtsStepConcat with
      (olds1 := MF.restrict or (namesOf (getRegInits m1)))
        (olds2 := MF.complement or (namesOf (getRegInits m1)))
        (rm1 := None) (rm2 := None); eauto
  end.

Hint Extern 1 (LtsStep (Mod _ _ _) _ _ _ _ _) => econstructor.
Hint Extern 1 (LtsStep (ConcatMod _ _) _ _ _ _ _) => constr_concatMod.
Hint Extern 1 (SemMod _ _ _ _ _ _ _) => econstructor.
(* Hint Extern 1 (SemAction _ _ _ _ _) => econstructor. *)
Hint Extern 1 (SemAction _ (Return _) _ _ _) =>
match goal with
  | [ |- SemAction _ _ _ _ ?ret ] =>
    match type of ret with
      | type (Bit 0) => eapply SemReturn with (evale := WO)
      | _ => econstructor
    end
end.

Definition initRegs (init: list RegInitT): RegsT := makeMap (fullType type) evalConstFullT init.
Hint Unfold initRegs.

(* m = module
   or = old registers
   nr = new registers *)

Definition update {A : Type} (m1 m2 : M.t A) := MF.union m2 m1.

Inductive LtsStepClosure:
  Modules ->
  RegsT -> list RuleLabelT ->
  Prop :=
| lcNil m inits
        (Hinits: inits = (initRegs (getRegInits m))):
    LtsStepClosure m inits nil
| lcLtsStep m rm or nr c cNew dNew or'
            (Hlc: LtsStepClosure m or c)
            (Hlts: LtsStep m rm or nr dNew cNew)
            (Hrs: or' = update or nr):
    LtsStepClosure m or' ((Build_RuleLabelT rm (getDmsMod m) dNew (getCmsMod m) cNew) :: c).

Inductive ConcatLabelSeq: list RuleLabelT -> list RuleLabelT -> list RuleLabelT -> Prop :=
| ConcatNil: ConcatLabelSeq nil nil nil
| ConcatJoin l1 l2 l:
    ConcatLabelSeq l1 l2 l ->
    forall a1 a2 a, ConcatLabel a1 a2 a -> ConcatLabelSeq (a1 :: l1) (a2 :: l2) (a :: l).

Definition RegsInDomain m :=
  forall rm or nr dm cm,
    LtsStep m rm or nr dm cm -> MF.InDomain nr (namesOf (getRegInits m)).

Lemma concatMod_RegsInDomain:
  forall m1 m2 (Hin1: RegsInDomain m1) (Hin2: RegsInDomain m2),
    RegsInDomain (ConcatMod m1 m2).
Proof.
  unfold RegsInDomain; intros; inv H.
  specialize (Hin1 _ _ _ _ _ Hlts1).
  specialize (Hin2 _ _ _ _ _ Hlts2).
  clear -Hin1 Hin2.
  unfold getRegInits, namesOf; rewrite map_app.
  unfold MF.InDomain in *; intros.
  repeat autounfold with MapDefs in H.
  specialize (Hin1 k); specialize (Hin2 k).
  apply MF.union_In in H.
  destruct H; apply in_or_app; intuition auto.
Qed.

Section Domain.
  Variable m: Modules.
  Variable newRegsDomain: RegsInDomain m.
  Theorem regsDomain r l
    (clos: LtsStepClosure m r l):
    MF.InDomain r (namesOf (getRegInits m)).
  Proof.
    induction clos.
    - unfold MF.InDomain, initRegs in *; intros.
      subst.
      clear -H.
      induction (getRegInits m); simpl in *.
      + apply MF.F.P.F.empty_in_iff in H. assumption.
      + destruct a; destruct attrType; simpl in *.
        destruct (string_dec attrName k); intuition auto.
        right. apply IHl.
        rewrite MF.F.P.F.add_in_iff in H.
        destruct H. specialize (n H). contradiction. assumption.
    - pose proof (@newRegsDomain _ _ _ _ _ Hlts).
      rewrite Hrs. unfold update.
      apply MF.InDomain_union; intuition.
  Qed.
End Domain.

Section WellFormed.
  Variable m1 m2: Modules.

  Variable newRegsDomainM1: RegsInDomain m1.
  Variable newRegsDomainM2: RegsInDomain m2.

  Variable disjRegs:
    forall r, ~ (In r (namesOf (getRegInits m1)) /\
                 In r (namesOf (getRegInits m2))).
  Variable r: RegsT.
  Variable l: list RuleLabelT.

  Theorem ltsStepClosure_split:
    LtsStepClosure (ConcatMod m1 m2) r l ->
    exists r1 r2 l1 l2,
      LtsStepClosure m1 r1 l1 /\
      LtsStepClosure m2 r2 l2 /\
      MF.union r1 r2 = r /\
      ConcatLabelSeq l1 l2 l.
  Proof.
    admit. (* Proof deprecated due to disjUnion -> union *)
    (* intros clos. *)
    (* remember (ConcatMod m1 m2) as m. *)
    (* induction clos; rewrite Heqm in *; simpl in *. *)
    (* - exists (initRegs (getRegInits m1)). *)
    (*          exists (initRegs (getRegInits m2)). *)
    (*          unfold initRegs, namesOf in *. *)
    (*          rewrite (disjUnionProp (f1 := ConstFullT) (fullType type) evalConstFullT *)
    (*                                 (getRegInits m1) (getRegInits m2)) in *. *)
    (*          exists nil; exists nil. *)
    (*          repeat (constructor || intuition). *)
    (* - destruct (IHclos eq_refl) as [r1 [r2 [l1 [l2 [step1 [step2 [regs labels]]]]]]]; *)
    (*   clear IHclos. *)
    (*   inversion Hlts; subst. *)
    (*   exists (update olds1 news1). *)
    (*   exists (update olds2 news2). *)
    (*   exists ((Build_RuleLabelT rm1 (getDmsMod m1) dmMap1 (getCmsMod m1) cmMap1) :: l1). *)
    (*   exists ((Build_RuleLabelT rm2 (getDmsMod m2) dmMap2 (getCmsMod m2) cmMap2) :: l2). *)
    (*   pose proof (regsDomain newRegsDomainM1 step1) as regs1. *)
    (*   pose proof (regsDomain newRegsDomainM2 step2) as regs2. *)
    (*   pose proof (disjUnion_div disjRegs regs1 regs2 HOldRegs1 HOldRegs2 Holds) as [H1 H2]. *)
    (*   subst. *)
    (*   constructor. *)
    (*   + apply (lcLtsStep (or' := update olds1 news1) step1 Hlts1 eq_refl). *)
    (*   + constructor. *)
    (*     * apply (lcLtsStep (or' := update olds2 news2) step2 Hlts2 eq_refl). *)
    (*     * constructor. *)
    (*       { pose proof newRegsDomainM1 Hlts1 as H1. *)
    (*         pose proof newRegsDomainM2 Hlts2 as H2. *)
    (*         apply disjUnion_update_comm. *)
    (*       } *)
    (*       { constructor; intuition. } *)
  Qed.
End WellFormed.

(** Tactics for dealing with semantics *)

(*
I got rid of this because I have no in_tac_ex

Ltac invStep :=
  repeat
    match goal with
      | [Horig: LtsStep ?m None _ _ _ _ |- _] =>
        let Ha := fresh "Ha" in
        assert (Ha: exists lm rm, m = ConcatMod lm rm) by (repeat eexists);
          clear Ha; inv Horig; destConcatLabel;
          match goal with
            | [Hcrm: CombineRm _ _ None |- _] =>
              pose proof (combineRm_prop_5 Hcrm); dest; subst
          end
      | [Horig: LtsStep ?m (Some ?r) _ _ _ _ |- _] =>
        let Ha := fresh "Ha" in
        assert (Ha: exists lm rm, m = ConcatMod lm rm) by (repeat eexists);
          clear Ha; inv Horig; destConcatLabel;
          match goal with
            | [Hcrm: CombineRm _ _ _, H: LtsStep ?m ?rm _ _ _ _ |- _] =>
              let Hin := fresh "Hin" in
              assert (Hin: ~ In r (namesOf (getRules m))) by in_tac_ex;
                assert (rm = None) by
                  (destruct rm; [exfalso; elim Hin|reflexivity];
                   eapply ltsStep_rule; [eassumption|];
                   (rewrite (combineRm_prop_1 Hcrm) || rewrite (combineRm_prop_2 Hcrm));
                   reflexivity);
                clear Hin; subst;
                (rewrite (combineRm_prop_3 Hcrm) in * || rewrite (combineRm_prop_4 Hcrm) in * );
                clear Hcrm
          end
    end;
  repeat
    match goal with
      | [H: LtsStep ?m _ _ _ _ _ |- _] =>
        let Ha := fresh "Ha" in
        assert (Ha: exists m1 m2 m3, m = Mod m1 m2 m3) by (repeat eexists);
          clear Ha; inv H
    end.
*)

Ltac destRule Hlts :=
  match type of Hlts with
    | (LtsStep _ ?rm _ _ _ _) =>
      inv Hlts;
        repeat match goal with
                 | [H: SemMod _ _ rm _ _ _ _ |- _] =>
                   destruct rm; [inv H; repeat match goal with
                                                 | [H: In _ _ |- _] => inv H
                                               end|]
                 | [H: {| attrName := _; attrType := _ |} =
                       {| attrName := _; attrType := _ |} |- _] => inv H
               end
  end.

Ltac destRuleRep :=
  repeat match goal with
           | [H: LtsStep _ _ _ _ _ _ |- _] => destRule H
         end.

Ltac combRule :=
  match goal with
    | [H: CombineRm (Some _) (Some _) _ |- _] =>
      unfold CombineRm in H; destruct H as [[H|H] _]; inversion H
    | [H: CombineRm None (Some _) _ |- _] =>
      unfold CombineRm in H; destruct H as [_]; subst
    | [H: CombineRm (Some _) None _ |- _] =>
      unfold CombineRm in H; destruct H as [_]; subst
    | [H: CombineRm None None _ |- _] =>
      unfold CombineRm in H; destruct H as [_]; subst
  end.

Ltac callIffDef_dest :=
  repeat
    match goal with
      | [H: CallIffDef _ _ |- _] => unfold CallIffDef in H; dest
    end;
  unfold dmMap, cmMap, dms, cms in *.

Ltac filt_dest :=
  repeat
    match goal with
      | [H: FiltDm _ _ _ |- _] =>
        unfold FiltDm in H;
          unfold dmMap, cmMap, dms, cms in H;
          subst
      | [H: FiltCm _ _ _ |- _] =>
        unfold FiltCm in H;
          unfold dmMap, cmMap, dms, cms in H;
          subst
    end.

Ltac basic_dest :=
  repeat
    match goal with
      | [H: Some _ = Some _ |- _] => try (apply opt_some_eq in H; subst)
      | [H: {| objType := _; objVal := _ |} = {| objType := _; objVal := _ |} |- _] =>
        try (apply typed_eq in H; subst)
      | [H: (_, _) = (_, _) |- _] => inv H; subst
      | [H: existT _ _ _ = existT _ _ _ |- _] =>
        try (apply Eqdep.EqdepTheory.inj_pair2 in H; subst)
      | [H: Some _ = None |- _] => inversion H
      | [H: None = Some _ |- _] => inversion H
      | [H: true = false |- _] => inversion H
      | [H: false = true |- _] => inversion H
    end.

(* same story: missing in_tac_ex
Ltac pred_dest meth :=
  repeat
    match goal with
      | [H: forall m: string, In m nil -> _ |- _] =>
        clear H
    end;
  repeat
    match goal with
      | [H: forall m: string, In m _ -> _ |- _] =>
        let Hin := type of (H meth) in
        isNew Hin; let Hs := fresh "Hs" in pose proof (H meth) as Hs
    end;
  repeat
    match goal with
      | [H: In ?m ?l -> _ |- _] =>
        (let Hp := fresh "Hp" in
         assert (Hp: In m l)
           by (repeat autounfold; repeat autounfold with ModuleDefs; in_tac_ex);
         specialize (H Hp); clear Hp)
          || (clear H)
    end;
  repeat
    match goal with
      | [H: find _ _ = _ |- _] => repeat autounfold in H; repeat (map_compute H)
    end.
*)

(* missing map_simpl tactic
Ltac invariant_tac :=
  repeat
    match goal with
      | [H: find _ _ = Some _ |- _] => progress (map_simpl H)
      | [H1: ?lh = Some _, H2: ?lh = Some _ |- _] =>
        simpl in H1, H2; rewrite H1 in H2
      | [H1: ?lh = Some _, H2: Some _ = ?lh |- _] =>
        simpl in H1, H2; rewrite H1 in H2
      | [H1: ?lh = true, H2: ?lh = false |- _] =>
        simpl in H1, H2; rewrite H1 in H2
      | [H1: ?lh = true, H2: false = ?lh |- _] =>
        simpl in H1, H2; rewrite H1 in H2
      | [H1: ?lh = false, H2: true = ?lh |- _] =>
        simpl in H1, H2; rewrite H1 in H2
      | [H1: if weq ?w1 ?w2 then _ else _, H2: ?w1 = ?w3 |- _] =>
        rewrite H2 in H1; simpl in H1
      | [H: ?w1 = ?w3 |- context [if weq ?w1 ?w2 then _ else _] ] =>
        rewrite H; simpl
    end.
*)

(* missing pred_dest tactic
Ltac conn_tac meth :=
  callIffDef_dest; filt_dest; pred_dest meth; repeat (invariant_tac; basic_dest).
Ltac fconn_tac meth := exfalso; conn_tac meth.
*)

Ltac regsInDomain_tac := admit. (* TODO: reimplement *)
  (* hnf; intros; *)
  (* repeat match goal with *)
  (*        | [ H : LtsStep _ _ _ _ _ _ |- _ ] => inv H *)
  (*        | [ H : SemMod _ _ _ _ _ _ _ |- _ ] => inv H *)
  (*        end; in_tac_H; (deattr; simpl in *; repeat invertActionRep; inDomain_tac). *)

Global Opaque mkStruct.
