# LLVM #211229 — nested-loop `st2` interleave failure: fix plan

**Issue:** `nested_loop` with two outer-loop-carried pointer IVs fails to form an
interleaved store group, so AArch64 emits no `st2`.

**Verified against:** branch `jerry/fix-211229`, base `4070621c866f`.
Repro artifacts in `build/st2/`. All IR in this doc is real `build/bin/opt`
output, not sketched.

> Note: `build/` is a CMake output directory and is not tracked by git. Move this
> doc somewhere tracked before it matters.

---

## 1. Which pass

**`IndVarSimplify`.** Not the vectorizer — nothing under
`llvm/lib/Transforms/Vectorize/` changes.

The transform is *offset-congruent IV elimination*: rewrite the second pointer IV
as a GEP off the first, so the two accesses share a `getPointerBase`. That is the
single thing `analyzeInterleaving`'s `getMinusSCEV` call needs.

```llvm
-  store float %mul8, ptr %pB.1, align 4
+  %pB.gep = getelementptr float, ptr %pA.1, i64 1
+  store float %mul8, ptr %pB.gep, align 4
```

The transform itself lands in **`SCEVExpander`** (where the congruent-IV machinery
already lives); `IndVarSimplify` is the driver that calls it.

### Why this is the right home

- Its charter is literally this (`IndVarSimplify.cpp:9`): transform induction
  variables "into simpler forms suitable for subsequent analysis and
  transformation."
- It runs before the vectorizer. `opt -passes='default<O2>'
  -print-pipeline-passes` → `indvars` at position 48, `loop-vectorize` at 89.
- It already owns `SCEVExpander`, the `DeadInsts` list, and LCSSA maintenance.
- `replaceCongruentIVs` is the same transform with a stricter equivalence
  relation. We are weakening `SCEV(A) == SCEV(B)` to `SCEV(B) == SCEV(A) + C`.

---

## 2. Files to touch

| File | Line | What |
|---|---|---|
| `llvm/lib/Transforms/Utils/ScalarEvolutionExpander.cpp` | 1829 | New helper alongside `replaceCongruentIVs` — copy its structure (header-phi scan, `DeadInsts` handling). `replaceCongruentIVInc` at `:1734` is the model for the increment-side rewrite. |
| `llvm/include/llvm/Transforms/Utils/ScalarEvolutionExpander.h` | 299 | Declaration next to `replaceCongruentIVs`. |
| `llvm/lib/Transforms/Scalar/IndVarSimplify.cpp` | 2103 | Call site, immediately after `NumElimIV += Rewriter.replaceCongruentIVs(...)`. Add a `STATISTIC` next to `NumElimIV` (`:90`). |
| `llvm/test/Transforms/IndVarSimplify/` | new | Unit test. Pattern-match existing: `2014-06-21-congruent-constant.ll`, `pr58702-invalidate-scev-when-replacing-congruent-phis.ll`. |
| `llvm/test/Transforms/LoopVectorize/AArch64/` | new | End-to-end: nested loop → interleave group forms. |

**Before starting:** HEAD `a45f447c2924 "experiment"` is +37/−4 in
`llvm/lib/Analysis/VectorUtils.cpp`. That is the *ruled-out* approach (extending
the interleave analysis). Drop or reset it first.

---

## 3. Root cause

### The IR indvars sees

After `mem2reg,loop-simplify,lcssa`:

```llvm
entry:
  %add.ptr = getelementptr inbounds float, ptr %dst, i64 1
  br label %for.cond

for.cond:                                  ; outer header
  %pA.0 = phi ptr [ %dst,     %entry ], [ %pA.1.lcssa, %for.inc11 ]
  %pB.0 = phi ptr [ %add.ptr, %entry ], [ %pB.1.lcssa, %for.inc11 ]
  %y.0  = phi i32 [ 0,        %entry ], [ %inc12,      %for.inc11 ]
  ...
for.cond2:                                 ; inner header
  %pA.1 = phi ptr [ %pA.0, %for.body ], [ %add.ptr9,  %for.inc ]
  %pB.1 = phi ptr [ %pB.0, %for.body ], [ %add.ptr10, %for.inc ]
  %x.0  = phi i32 [ 0,     %for.body ], [ %inc,       %for.inc ]
  ...
for.body4:
  store float %mul5, ptr %pA.1, align 4
  store float %mul8, ptr %pB.1, align 4
  %add.ptr9  = getelementptr inbounds float, ptr %pA.1, i64 2
  %add.ptr10 = getelementptr inbounds float, ptr %pB.1, i64 2
```

### The SCEVs

```
%pA.1  -->  {%pA.0,+,8}<nuw><%for.cond2>
%pB.1  -->  {%pB.0,+,8}<nuw><%for.cond2>
%pA.0  -->  %pA.0            (SCEVUnknown — opaque)
%pB.0  -->  %pB.0            (SCEVUnknown — opaque)
```

`getPointerBase({%pA.0,+,8})` is `%pA.0`; `getPointerBase({%pB.0,+,8})` is
`%pB.0`. Different bases, so `getMinusSCEV` bails at
`llvm/lib/Analysis/ScalarEvolution.cpp:4859`:

```cpp
  // If we subtract two pointers with different pointer bases, bail.
  if (RHS->getType()->isPointerTy()) {
    if (!LHS->getType()->isPointerTy() ||
        getPointerBase(LHS) != getPointerBase(RHS))
      return getCouldNotCompute();          // :4865 — this is what kills st2
```

No constant A−B distance → `analyzeInterleaving` forms no group → no `st2`.

### Key finding (not in the upstream issue)

SCEV does **not** need to model the outer loop. A single pointer IV with the
second access written as `pA[1]` vectorizes to `st2` while `%pA.0` stays an
opaque `SCEVUnknown`. The only requirement is a shared `getPointerBase`.

This rules out the hard `createAddRecFromPHI` fix, and rules out extending the
interleave analysis.

---

## 4. Why `replaceCongruentIVs` doesn't already fire

`SCEVExpander::replaceCongruentIVs` (`ScalarEvolutionExpander.cpp:1829`) is a
SCEV-keyed hash join over the header phis:

```cpp
  DenseMap<const SCEV *, PHINode *> ExprToIVMap;          // :1848
  for (PHINode *Phi : Phis) {
    ...
    PHINode *&OrigPhiRef = ExprToIVMap[SE.getSCEV(Phi)];  // :1881  ← the key
    if (!OrigPhiRef) { OrigPhiRef = Phi; ... continue; }  // first one wins

    if (OrigPhiRef->getType()->isPointerTy() != Phi->getType()->isPointerTy())
      continue;                                           // :1903

    replaceCongruentIVInc(Phi, OrigPhiRef, L, DT, DeadInsts);  // :1906
    ++NumElim;
    Phi->replaceAllUsesWith(NewIV);                       // :1920
    DeadInsts.emplace_back(Phi);                          // :1921
  }
```

The map key is **exact SCEV identity**. `{%pA.0,+,8} != {%pB.0,+,8}`, so the two
pointer phis land in different buckets and nothing happens. Confirmed with
`-debug-only=indvars`: every integer IV is rewritten, both pointer IVs survive.

---

## 5. Detection algorithm

You **cannot** just ask SCEV. Proving `%pB.0 == %pA.0 + 4` is exactly the query
`getMinusSCEV` refuses, because both operands are opaque `SCEVUnknown`s.

The way out: the offset *is* visible at loop entry, where both values share the
base `%dst`. `SCEV(%add.ptr) = (4 + %dst)`, `SCEV(%dst) = %dst` — shared base, so
`getMinusSCEV` works there and returns the constant `4`. That is the seed.
Propagate it around the phi cycle optimistically, like `createAddRecFromPHI`'s
`SymbolicName` trick: assume the relation, then check the assumption reproduces
itself on the backedge.

```
tryOffsetCongruentIV(L, PhiA, PhiB):                  // both in L->getHeader()
  Pre = L->getLoopPreheader()

  // --- SEED: constant byte offset between the two preheader-incoming values.
  //     Works because these share a getPointerBase.
  Diff = SE.getMinusSCEV(SE.getSCEV(PhiB->getIncomingValueForBlock(Pre)),
                         SE.getSCEV(PhiA->getIncomingValueForBlock(Pre)))
  Off  = dyn_cast<SCEVConstant>(Diff)
  if (!Off) return false

  // --- OPTIMISTIC ASSUMPTION, then verify on the backedge.
  Assumed = { (PhiB, PhiA) -> Off }
  return provesOffset(PhiB->getIncomingValueForBlock(L->getLoopLatch()),
                      PhiA->getIncomingValueForBlock(L->getLoopLatch()),
                      Off, Assumed)

provesOffset(VB, VA, Off, Assumed):
  if (VB == VA)                       return Off.isZero()
  if (Assumed.lookup({VB,VA}) == Off) return true          // fixpoint reached

  // cheap path: SCEV can answer whenever the bases already agree
  if (auto *C = dyn_cast<SCEVConstant>(SE.getMinusSCEV(SCEV(VB), SCEV(VA))))
    return C == Off

  if (both are PHINodes in the same parent block):
    Assumed.insert({VB,VA} -> Off)                          // optimistic
    return all_of(predecessors, [&](BB *P) {
      return provesOffset(VB->getIncomingValueForBlock(P),
                          VA->getIncomingValueForBlock(P), Off, Assumed) })

  if (both are GEPs with identical source element type and identical operands
      after the pointer operand):
    return provesOffset(VB->getPointerOperand(), VA->getPointerOperand(),
                        Off, Assumed)

  return false
```

### Traced on the real IR

| Step | Pair (B, A) | Rule | Result |
|---|---|---|---|
| seed | `%add.ptr` vs `%dst` | `getMinusSCEV`, shared base `%dst` | **Off = 4** |
| 1 | `%pB.1.lcssa` vs `%pA.1.lcssa` | single-incoming phis | recurse → `%pB.1` vs `%pA.1` |
| 2 | `%pB.1` vs `%pA.1` | phis in `for.cond2`; assume `+4`; check both preds | ↓ |
| 2a | from `%for.body`: `%pB.0` vs `%pA.0` | already in `Assumed` | ✅ |
| 2b | from `%for.inc`: `%add.ptr10` vs `%add.ptr9` | both `gep float, …, i64 2` — same type, same index | recurse on pointer operands |
| 3 | `%pB.1` vs `%pA.1` | in `Assumed` | ✅ fixpoint |

Assumption reproduces itself → `%pB.x == %pA.x + 4` holds on every iteration of
both loops.

Step 2b is where a SCEV-only approach dies and structural GEP matching saves you:
`SCEV(%add.ptr10) − SCEV(%add.ptr9)` is `CouldNotCompute` for the same
different-base reason, but the two GEPs are syntactically identical modulo their
pointer operand, so the offset passes straight through.

---

## 6. The rewrite

Pick `%pA` as the keeper (first in header phi order, matching
`replaceCongruentIVs`'s "first one wins" at `:1882`). For each phi in the proven
`%pB` chain, insert at that block's `getFirstInsertionPt()` and RAUW:

```llvm
for.cond2:
  %pA.1 = phi ptr [ %pA.0, %for.body ], [ %add.ptr9, %for.inc ]
  %pB.gep = getelementptr float, ptr %pA.1, i64 1        ; ← inserted
  ...
- store float %mul8, ptr %pB.1, align 4
+ store float %mul8, ptr %pB.gep, align 4
```

The cascade is self-cleaning, same as `:1920-1921`: RAUW on `%pB.1` rewrites its
use inside `%add.ptr10`, breaking the cycle; `%pB.1` and then `%pB.0` become
unused; `DeadInsts` → `RecursivelyDeleteDeadPHINode` (`IndVarSimplify.cpp:2187`)
and `DeleteDeadPHIs` (`:2205`) collect them.

Post-rewrite, `SCEV(%pB.gep) = {(4 + %pA.0),+,8}`, `getPointerBase` is `%pA.0`
for both accesses, `getMinusSCEV` returns 4, and `analyzeInterleaving` forms the
group.

### Four things to get right

- **`inbounds`.** Emit the GEP *without* it unless you propagate a proof. The
  original `%pB` chain was `inbounds` relative to `%dst`, not relative to
  `%pA.1`. Not needed for base-sharing, so don't reach for it.
- **Poison.** You create a new use of `%pA.1` where none existed. Same hazard
  `replaceCongruentIVInc` handles via `hoistIVInc(..., /*RecomputePoisonFlags*/
  true)` at `:1786`; yours is milder (no code motion) but nowrap flags on the new
  GEP must stay conservative.
- **LCSSA.** `run()` asserts `isRecursivelyLCSSAForm` on entry (`:2055`) and exit
  (`:2208`). You are rewriting inner-loop values from the outer loop's
  invocation, so check `SE.LI.replacementPreservesLCSSAForm` the way `:1772`
  does, or insert per-block so each definition dominates its uses.
- **SCEV invalidation.** `SE.forgetValue` on every rewritten phi (cf. `:1868`).

---

## 7. Pipeline facts that constrain the implementation

- **Inner loops are visited first.** `appendReversedLoopsToWorklist`
  (`llvm/lib/Transforms/Utils/LoopUtils.cpp`) builds a preorder list and pushes
  it into a LIFO priority worklist. Confirmed with `-debug-only=indvars`: the
  `%x.0` (inner) loop is processed before `%y.0` (outer).
- Therefore the seed must come from the **outer** header — the inner header can't
  seed, since its phi start values *are* the outer phis.
- Therefore the outer-loop invocation modifies instructions inside an
  already-processed subloop. Legal (no CFG or loop-nest change), but the lit test
  must run `loop(indvars)` over the whole nest.

---

## 8. Reproduction commands

```sh
cd build

# IR as indvars sees it
./bin/clang -O0 -Xclang -disable-O0-optnone -S -emit-llvm \
    --target=aarch64-unknown-linux-gnu st2/st2_optimization.cpp -o /tmp/st2_o0.ll
./bin/opt /tmp/st2_o0.ll -passes='mem2reg,loop-simplify,lcssa' -S -o /tmp/st2_pre_indvars.ll

# SCEVs
./bin/opt /tmp/st2_pre_indvars.ll -passes='print<scalar-evolution>' -disable-output

# What indvars currently does
./bin/opt /tmp/st2_pre_indvars.ll -passes='loop-mssa(indvars)' \
    -debug-only=indvars -S -o /tmp/st2_post_indvars.ll

# Isolate sub-transforms
#   -indvars-widen-indvars=false   disable IV widening
#   -disable-lftr                  disable exit-condition rewrite

# Interleave analysis (note: DEBUG_TYPE is "vectorutils", NOT "loop-vectorize")
./bin/opt /tmp/st2_post_indvars.ll -passes='loop-vectorize' \
    -debug-only=vectorutils -o /dev/null 2>&1 | grep -i interleav
```

Gotchas: `dbgs()` goes to stderr, so always `2>&1` and `-o /dev/null`. Clang
`-O0` IR carries `optnone` unless you pass `-Xclang -disable-O0-optnone`. Don't
pipe `opt` through `head` while also writing `-o <file>` — SIGPIPE leaves a stale
output file.
