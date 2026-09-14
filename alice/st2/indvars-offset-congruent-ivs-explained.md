# Offset-congruent pointer IVs — concepts and mechanics

**Companion to:** [`indvars-gep-fix-211229.md`](indvars-gep-fix-211229.md) (the fix
plan). This document is the *background*: what each moving part is, why the
obvious approach fails, and how the induction argument works. Read this first if
`AddRec`, `preheader`, or `SCEVParameterRewriter` are unfamiliar.

**Verified against:** branch `jerry/fix-211229`, base `4070621c866f`.
All IR and SCEV output in this doc is real `build/bin/opt` output, not sketched.

> Note: `build/` is a CMake output directory and is not tracked by git. Move this
> doc somewhere tracked before it matters.

---

## Contents

0. [What the code is](#0-what-the-code-is)
1. [Loop anatomy: the block vocabulary](#1-loop-anatomy-the-block-vocabulary)
2. [Phi nodes and induction variables](#2-phi-nodes-and-induction-variables)
3. [SCEV: turning phis into algebra](#3-scev-turning-phis-into-algebra)
4. [Why SCEV gave up on the outer pointer phis](#4-why-scev-gave-up-on-the-outer-pointer-phis)
5. [Pointer SCEVs: bases and byte units](#5-pointer-scevs-bases-and-byte-units)
6. [Why the existing pass doesn't fire](#6-why-the-existing-pass-doesnt-fire-and-why-the-obvious-fix-doesnt-either)
7. [The missing half is an induction proof](#7-the-missing-half-is-an-induction-proof)
8. [SCEVParameterRewriter: injecting the hypothesis](#8-scevparameterrewriter-how-you-inject-the-hypothesis)
9. [The rewrite, and the deletion cascade](#9-the-rewrite-and-why-deleting-one-thing-deletes-five)
10. [Putting the pieces in order](#10-putting-the-pieces-in-order)

---

## 0. What the code is

From [`st2_optimization.cpp`](st2_optimization.cpp):

```cpp
void nested_loop(const float* __restrict src, float* __restrict dst,
                 unsigned width, unsigned height, unsigned srcStride) {
    float* pA = dst;
    float* pB = dst + 1;              // 4 bytes past pA
    for (unsigned y = 0; y < height; y++) {
        const float* row = src + y * srcStride;
        for (unsigned x = 0; x < width; x++) {
            *pA = row[x] * 2.0f;
            *pB = row[x] * 3.0f;
            pA += 2;                  // +8 bytes
            pB += 2;                  // +8 bytes
        }
    }
}
```

`pA` and `pB` start 4 bytes apart and both advance 8 bytes per iteration, so
**they are 4 bytes apart forever**. That is a two-way interleaved store — exactly
what AArch64's `st2` instruction does in one go.

The vectorizer can only emit `st2` if it recognizes the two stores as one
*interleave group*, and it can only do that if the fixed 4-byte relationship is
visible. Right now it isn't: the two pointers are carried in two independent phi
nodes with no expressed connection. That is issue #211229.

The IR under discussion is [`st2_nested_pre_iv.ll`](st2_nested_pre_iv.ll) — the
input to `opt -passes=indvars`.

---

## 1. Loop anatomy: the block vocabulary

Every LLVM loop transform speaks this vocabulary. Here it is on our IR:

```llvm
entry:                                      ; %add.ptr = dst + 4 computed here
for.body.preheader:                         ; -- PREHEADER of outer loop
for.body:                                   ; -- HEADER of outer loop
                                            ;    ...and PREHEADER of inner loop
for.body4:                                  ; -- HEADER of inner loop
                                            ;    ...and LATCH of inner loop
for.cond2.for.inc11_crit_edge:              ; -- EXIT block of inner loop
                                            ;    ...and LATCH of outer loop
for.end13.loopexit:                         ; -- EXIT block of outer loop
```

| Term | Meaning | Why it matters here |
|---|---|---|
| **Header** | The one block every iteration enters through. All loop-carried phis live here. | `L->getHeader()->phis()` is where we look for candidate IVs. |
| **Preheader** | The unique block outside the loop that jumps into the header. | Holds the **initial values**. This is where the constant `4` is visible. |
| **Latch** | The block with the branch back to the header (the *backedge*). | Holds the **next-iteration values**. |
| **Exit block** | Block outside the loop reached when it finishes. | Holds LCSSA phis. |

**The single most important structural fact in this whole problem:** `for.body`
is simultaneously the outer loop's *header* and the inner loop's *preheader*. So
when you ask "what value does the inner `%pB.111` start with?", the answer is the
outer loop's phi `%pB.016`. That dual role is what makes the recursion in the fix
land where it needs to.

LLVM guarantees preheaders and single latches exist by running **LoopSimplify**
first. `IndVarSimplify::run` bails out immediately if the loop isn't in that form
([`IndVarSimplify.cpp:2069-2070`](../../llvm/lib/Transforms/Scalar/IndVarSimplify.cpp#L2069-L2070)),
which is why the fix can safely assume `getLoopPreheader()` and `getLoopLatch()`
are non-null.

**LCSSA** (Loop-Closed SSA) is a normal form where every value defined inside a
loop and used outside it must pass through a single-entry phi in the exit block.
That's what these are:

```llvm
for.cond2.for.inc11_crit_edge:
  %add.ptr9.lcssa  = phi ptr [ %add.ptr9,  %for.body4 ]   ; one incoming — pure bookkeeping
  %add.ptr10.lcssa = phi ptr [ %add.ptr10, %for.body4 ]
```

They look pointless, but they matter later: they are the reason the dead-code
cascade goes in the order it does.

---

## 2. Phi nodes and induction variables

A **phi** picks a value based on which block control came from:

```llvm
%pA.112 = phi ptr [ %pA.018, %for.body ], [ %add.ptr9, %for.body4 ]
;                   ^ from preheader       ^ from latch
;                   (first iteration)      (every later iteration)
```

An **induction variable** is a phi that changes by a fixed amount each iteration.
The inner loop has three:

```llvm
%x.013  = phi i32 [ 0,        %for.body ], [ %inc,       %for.body4 ]  ; 0, 1, 2, ...
%pA.112 = phi ptr [ %pA.018,  %for.body ], [ %add.ptr9,  %for.body4 ]  ; +8 bytes each
%pB.111 = phi ptr [ %pB.016,  %for.body ], [ %add.ptr10, %for.body4 ]  ; +8 bytes each
```

### Aside: where do these names come from?

`x.013`, `pA.112`, `pB.111` all come from clang. The `.0`/`.1` part is mem2reg's
SSA-version suffix for the source variable (`x.0` = first promoted version of
`x`, `pA.1` = the inner-loop copy of `pA`); the trailing digits are LLVM's
symbol-table uniquifier appended because the base names collided. No semantics
there.

`indvars.iv` (which appears after the pass runs) is different — it is synthesized
by IndVarSimplify itself during **IV widening**. The name is literally
`IVName + ".iv"`, where `IVName` is the string passed to the expander at
[`IndVarSimplify.cpp:2077`](../../llvm/lib/Transforms/Scalar/IndVarSimplify.cpp#L2077)
(`SCEVExpander Rewriter(*SE, "indvars")`), and the phi is created at
[`ScalarEvolutionExpander.cpp:1123`](../../llvm/lib/Transforms/Utils/ScalarEvolutionExpander.cpp#L1123).
Widening applies only to *integer* IVs — pointer phis are never widened, which is
why the pointer IVs keep their clang names throughout.

---

## 3. SCEV: turning phis into algebra

**Scalar Evolution** answers: "what is this value, as a formula in terms of the
iteration number?" `SE.getSCEV(V)` returns a `const SCEV *` — a node in a uniqued
expression DAG. The node kinds that matter here:

| Node | Printed as | Means |
|---|---|---|
| `SCEVConstant` | `4` | A literal. |
| `SCEVUnknown` | `%dst` | An opaque value SCEV can't decompose — a function argument, or **a phi it gave up on**. |
| `SCEVAddExpr` | `(4 + %dst)` | A sum. |
| `SCEVAddRecExpr` | `{start,+,step}<%loop>` | **The important one.** See below. |
| `SCEVCouldNotCompute` | `<<Unknown>>` | An explicit failure marker. |

### AddRec — the add recurrence

`{start,+,step}<%loop>` means: **at iteration `i` of `%loop`, the value is
`start + i*step`.**

```
{%pA.018,+,8}<%for.body4>
   |        |      \___ which loop the iteration counter belongs to
   |        \__________ step: +8 bytes per iteration
   \___________________ start: value on iteration 0
```

Iteration 0 is `%pA.018`, iteration 1 is `%pA.018 + 8`, iteration 5 is
`%pA.018 + 40`. Flags like `<nuw>` mean "no unsigned wrap" — SCEV proved the
arithmetic can't overflow, which lets it be more aggressive later.

An AddRec is a *closed form*. That's the payoff: once a phi becomes an AddRec you
no longer have to reason about the loop iteratively — you can do algebra on the
formula.

### The real dump

`build/bin/opt -disable-output -passes='print<scalar-evolution>' st2/st2_nested_pre_iv.ll`:

```
%pA.112 = phi ptr [ %pA.018, %for.body ], [ %add.ptr9, %for.body4 ]
  -->  {%pA.018,+,8}<nuw><%for.body4>

%pB.111 = phi ptr [ %pB.016, %for.body ], [ %add.ptr10, %for.body4 ]
  -->  {%pB.016,+,8}<nuw><%for.body4>

%pA.018 = phi ptr [ %add.ptr9.lcssa, ... ], [ %dst, %for.body.preheader ]
  -->  %pA.018                    <-- SCEVUnknown! Not an AddRec.

%pB.016 = phi ptr [ %add.ptr10.lcssa, ... ], [ %add.ptr, %for.body.preheader ]
  -->  %pB.016                    <-- SCEVUnknown!
```

The inner phis became AddRecs. **The outer phis did not.** Understanding why is
the crux of the whole bug.

---

## 4. Why SCEV gave up on the outer pointer phis

`createAddRecFromPHI` works like this:

1. Temporarily map the phi to a placeholder symbol (`SCEVUnknown(%pA.018)`).
2. Compute the SCEV of the **latch incoming value**.
3. Check the result is a `SCEVAddExpr` that *contains the placeholder*. If it
   looks like `placeholder + Accum` with `Accum` loop-invariant, you've found a
   recurrence: `{StartValue,+,Accum}`.

For the **inner** phi `%pA.112` this works perfectly. The latch value is
`%add.ptr9 = getelementptr i8, ptr %pA.112, i64 8`, whose SCEV is the add
`(%pA.112 + 8)` — placeholder plus the invariant `8`. Recurrence found:
`{%pA.018,+,8}`.

For the **outer** phi `%pA.018` it fails. The latch value is `%add.ptr9.lcssa`,
and its SCEV is:

```
{(8 + %pA.018),+,8}<%for.body4>
```

That is an **AddRec of the inner loop**, not a `SCEVAddExpr`. The
`dyn_cast<SCEVAddExpr>` returns null, step 3 fails, and SCEV falls back to
`getUnknown(PN)` — the phi stays opaque forever.

> The friendlier-looking `(8 + 8*(zext(width-1)) + %pA.018)` that also appears in
> the printer output is the **exit value**, computed later and separately by
> `getSCEVAtScope`. `createAddRecFromPHI` never sees it.
> `getSCEV` = "value at an arbitrary iteration";
> `getSCEVAtScope` = "value once this loop has finished".

**This is not a bug in SCEV — it is a structural limitation**, and it is exactly
the shape of a pointer that advances inside an inner loop. Which is exactly our
case.

---

## 5. Pointer SCEVs: bases and byte units

SCEV treats pointers specially. Two rules matter.

**Rule 1 — one base per expression.** `getPointerBase` peels an expression down
to its root pointer
([`ScalarEvolution.cpp:5020-5041`](../../llvm/lib/Analysis/ScalarEvolution.cpp#L5020-L5041)):
for an AddRec take the start, for an Add take the single pointer operand,
otherwise stop.

```
getPointerBase({%pB.016,+,8})  ->  %pB.016   (an opaque SCEVUnknown)
getPointerBase({%pA.018,+,8})  ->  %pA.018   (a different opaque SCEVUnknown)
```

**Rule 2 — subtraction requires a shared base.** `getMinusSCEV` refuses to relate
pointers rooted at different bases
([`ScalarEvolution.cpp:4859-4868`](../../llvm/lib/Analysis/ScalarEvolution.cpp#L4859-L4868)):

```cpp
  if (RHS->getType()->isPointerTy()) {
    if (!LHS->getType()->isPointerTy() ||
        getPointerBase(LHS) != getPointerBase(RHS))
      return getCouldNotCompute();      // <-- bails out here
    LHS = removePointerBase(LHS);
    RHS = removePointerBase(RHS);
  }
```

This is a *safety* rule: two unrelated allocations have no defined numeric
relationship. But when both bases are opaque phis, SCEV cannot tell "genuinely
unrelated" from "related but I failed to analyze it", so it conservatively says
no.

`removePointerBase` strips to raw **byte** arithmetic, so any delta you get out is
in bytes. That is why the rewrite must emit an `i8` GEP — a typed GEP would scale
the offset a second time.

---

## 6. Why the existing pass doesn't fire, and why the obvious fix doesn't either

`replaceCongruentIVs`
([`ScalarEvolutionExpander.cpp`](../../llvm/lib/Transforms/Utils/ScalarEvolutionExpander.cpp))
hashes each header phi by its SCEV into a `DenseMap` and merges exact duplicates.
"Congruent" means *identical SCEV*. Ours are `{%pA.018,+,8}` and `{%pB.016,+,8}`
— different. No match. Nothing happens.

The obvious extension is "instead of exact equality, allow a constant
difference": call `getMinusSCEV(Q, P)` and check for a `SCEVConstant`.
**This does not work.** Verified by injecting a subtraction into the IR and
printing its SCEV:

```
%probe.inner = sub i64 (ptrtoint %pB.111), (ptrtoint %pA.112)
  -->  ((-1 * (ptrtoint ptr %pA.018 to i64)) + (ptrtoint ptr %pB.016 to i64))
```

Read that result carefully, because it says two things:

- The `+8` steps **cancelled**. SCEV proves "same step" for free.
- What is left is `%pB.016 - %pA.018` — two opaque symbols with different pointer
  bases, so Rule 2 rejects it and the whole thing is `CouldNotCompute`.

SCEV gets you exactly half the proof. The missing half is: *are these two opaque
base pointers a constant distance apart?*

---

## 7. The missing half is an induction proof

Look at where the `4` actually lives:

```llvm
entry:
  %add.ptr = getelementptr inbounds nuw i8, ptr %dst, i64 4    ; <-- the only literal 4
```

It is outside both loops. To connect it to `%pB.111` deep inside the inner loop
you have to argue inductively, the same way you would prove a loop invariant on
paper:

> **Base case.** On entry to the outer loop, `pB = dst + 4` and `pA = dst`, so
> `pB - pA = 4`.
>
> **Inductive step.** *Assume* `pB - pA = 4` at the top of some iteration. At the
> bottom, `pA` has become `%add.ptr9.lcssa` and `pB` has become
> `%add.ptr10.lcssa`. Both advanced by the same amount, so the difference is
> still 4.
>
> Therefore `pB - pA = 4` on every iteration. QED

There is no way around the assumption in the middle. The fact is genuinely
loop-carried, and SCEV's AddRec machinery — which normally *does* this induction
for you — bailed out on these phis, so it has to be done by hand.

Concretely:

| Step | `pA` side | `pB` side | Delta |
|---|---|---|---|
| Base (preheader edge) | `%dst` | `%add.ptr` = `(4 + %dst)` | **4** OK |
| Step (latch edge) | `%add.ptr9.lcssa` -> `{(8 + %pA.018),+,8}` | `%add.ptr10.lcssa` -> `{(8 + %pB.016),+,8}` | needs the hypothesis |

The base case works because both sides share the base `%dst` — Rule 2 is
satisfied. The inductive step is where the assumption must be injected.

---

## 8. SCEVParameterRewriter: how you inject the hypothesis

`SCEVParameterRewriter`
([`ScalarEvolutionExpressions.h:998-1018`](../../llvm/include/llvm/Analysis/ScalarEvolutionExpressions.h#L998-L1018))
is a tiny visitor. It walks a SCEV tree and swaps out `SCEVUnknown` leaves
according to a map:

```cpp
  const SCEV *visitUnknown(const SCEVUnknown *Expr) {
    auto I = Map.find(Expr->getValue());
    if (I == Map.end())
      return Expr;        // not in the map -- leave alone
    return I->second;     // substitute
  }
```

Everything else (Add, Mul, AddRec) is visited recursively and rebuilt. Rebuilding
goes through the normal `SE.getAddExpr` / `SE.getAddRecExpr` constructors, **so
the result gets fully folded and simplified**. That folding is what does the real
work.

Watch it on the inductive step. The hypothesis is `%pB.016 = %pA.018 + 4`, so the
map is `{ %pB.016 -> (4 + %pA.018) }`.

```
Before:  getSCEV(%add.ptr10.lcssa)  =  {(8 + %pB.016),+,8}<%for.body4>
                                              ^ SCEVUnknown leaf, in the map

Rewrite: substitute %pB.016 -> (4 + %pA.018), then refold:
             8 + (4 + %pA.018)  =  (12 + %pA.018)

After:   {(12 + %pA.018),+,8}<%for.body4>
```

Now subtract the `pA` side:

```
  {(12 + %pA.018),+,8}  -  {(8 + %pA.018),+,8}
```

Both are AddRecs of the same loop with the same step, and now they share the
pointer base `%pA.018`. Rule 2 is satisfied, the steps cancel, and the result is:

```
  4                                              <-- SCEVConstant. Proof complete.
```

That is the entire trick. `SCEVParameterRewriter` does not prove anything by
itself — it is a substitution engine. *You* supply the hypothesis; the rewriter
plugs it in; SCEV's folding turns the result into a constant you can test.

### Carrying the fact inward

One subtlety, and it is the one that breaks a naive implementation. Having proven
the outer fact, the map `{ %pB.016 -> (4 + %pA.018) }` must stay alive when you
examine the **inner** pair. Apply it there:

```
getSCEV(%pB.111) = {%pB.016,+,8}   --rewrite-->  {(4 + %pA.018),+,8}
getSCEV(%pA.112) = {%pA.018,+,8}

difference = 4                                   <-- done, no second induction needed
```

The inner level does not need to redo the induction. SCEV *did* build AddRecs for
the inner phis, and an AddRec already encodes the induction. All the inner level
needed was the base relationship, which the outer proof supplied.

Verified empirically: hand-editing the IR to replace `%pB.016` with
`getelementptr i8, ptr %pA.018, i64 4` and re-running the probe gives

```
%probe.inner  -->  4        U: [4,5) S: [4,5)
```

> **Trap.** If you key the hypothesis map on the wrong value — on `%pB.111`
> instead of `%pB.016` — the rewrite is a silent no-op, because `%pB.111` never
> appears as a `SCEVUnknown` anywhere (SCEV resolved it into an AddRec). The
> subtraction falls back to `%pB.016 - %pA.018` and you get `CouldNotCompute`.
> **The map must be keyed on the symbol that actually appears in the
> expression**, which is the opaque outer phi.

---

## 9. The rewrite, and why deleting one thing deletes five

Once proven, the transform emits a GEP at the top of the header and does
`replaceAllUsesWith`:

```llvm
%pB.111.off = getelementptr i8, ptr %pA.112, i64 4
```

`RAUW` rewires every *user* of `%pB.111` to point at the GEP instead. It does not
touch `%pB.111`'s own operands, and it does not delete anything. Deletion is a
separate, later step — `IndVarSimplify` drains its `DeadInsts` list at
[`IndVarSimplify.cpp:2185-2193`](../../llvm/lib/Transforms/Scalar/IndVarSimplify.cpp#L2185-L2193),
and `RecursivelyDeleteDeadPHINode` walks the operand chain freeing whatever
became unused.

Verified by performing exactly one RAUW by hand and running plain
`-passes=dce`. Five instructions disappeared:

```
%pB.111          zero uses after RAUW              -> dead
  %pB.016        its only user was %pB.111         -> dead
    %add.ptr10.lcssa   only user was %pB.016       -> dead
      %add.ptr10       only user was the lcssa phi -> dead
        %add.ptr (in entry)  only user was %pB.016 -> dead
```

Two things worth internalizing. First, `%add.ptr10` is **not** dead immediately
after the RAUW — the LCSSA phi still holds a reference, and it only lets go once
the *outer* phi dies. Second, one RAUW on the innermost phi killed the outer phi
too, for free. That is why the transform does not need to run on the outer loop
at all, which is convenient because IndVarSimplify's loop pass manager visits
loops **innermost-first**.

The final IR:

```llvm
for.body4:
  %pA.112 = phi ptr [ %pA.018, %for.body ], [ %add.ptr9, %for.body4 ]
  %pB.111.off = getelementptr i8, ptr %pA.112, i64 4
  ...
  store float %mul5, ptr %pA.112
  store float %mul8, ptr %pB.111.off
  %add.ptr9 = getelementptr inbounds nuw i8, ptr %pA.112, i64 8
```

One pointer IV instead of two, and the 4-byte relationship is now a literal in
the IR where the vectorizer can see it and form the interleave group.

---

## 10. Putting the pieces in order

```
  proveConstPtrOffset(inner loop, %pA.112, %pB.111)
    |
    +- Base case: delta(%pA.018, %pB.016)?
    |     -> CouldNotCompute (two opaque bases)
    |     -> recurse outward, because these are the parent loop's header phis
    |
    |     proveConstPtrOffset(outer loop, %pA.018, %pB.016)
    |       +- Base case: delta(%dst, %add.ptr) = delta(%dst, 4+%dst) = 4   OK
    |       +- Fast path: delta(getSCEV(%pA.018), getSCEV(%pB.016))?
    |       |     -> both SCEVUnknown -> fails -> fall through to manual induction
    |       +- Hypothesis: %pB.016 -> (4 + %pA.018)
    |       +- Step: delta(latch values) under the hypothesis = 4 == C      OK
    |       +- COMMIT { %pB.016 -> (4 + %pA.018) } and return 4
    |
    +- Fast path, now with the committed fact in scope:
    |     {%pB.016,+,8} --rewrite--> {(4 + %pA.018),+,8}
    |     minus {%pA.018,+,8}  =  4                                         OK
    |
    +- return 4

  -> emit  %pB.111.off = getelementptr i8, ptr %pA.112, i64 4
  -> RAUW %pB.111, push it to DeadInsts, let the cascade clean up
```

Two design consequences fall out, and they are the difference between code that
works and code that silently never fires:

**Don't filter candidates on `isa<SCEVAddRecExpr>`.** SCEV failing to build an
AddRec for a pointer phi is the *signature* of the case being fixed, not a reason
to skip it. At the outer header both phis are `SCEVUnknown`, and an AddRec filter
would drop them before anything else ran.

**Thread the hypothesis map through the recursion.** A fresh local map at each
level means the outer fact never reaches the inner level, and the inner pair is
rejected right after the outer one was correctly proven — a failure mode that
looks exactly like "the transform doesn't work" while every individual piece is
correct.

---

## Reproducing the evidence in this doc

All from `build/`:

```sh
# The SCEV dump (section 3)
./bin/opt -disable-output -passes='print<scalar-evolution>' st2/st2_nested_pre_iv.ll

# The pass output, showing widening and indvars.iv (section 2 aside)
./bin/opt -passes=indvars st2/st2_nested_pre_iv.ll -S -o -
./bin/opt -passes=indvars -indvars-widen-indvars=false st2/st2_nested_pre_iv.ll -S -o -

# The probe experiments (sections 6 and 8) inject ptrtoint/sub pairs into the
# loop bodies and re-run print<scalar-evolution>; the cascade test (section 9)
# performs one RAUW by hand and runs -passes=dce.
```
