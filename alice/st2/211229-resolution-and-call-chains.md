# #211229 resolution — SCEV fix, and the indvars / loop-vectorize call chains

**Status:** resolved upstream in SCEV by two PRs. No IndVarSimplify or LoopVectorize
change is required.

- [#215658](https://github.com/llvm/llvm-project/pull/215658) — *[SCEV] Form AddRecs for PHIs involving values from nested loops*
- [#215910](https://github.com/llvm/llvm-project/pull/215910) — *[SCEV] Avoid recursion in PHI handling in more cases*

**Companion docs:** [`indvars-gep-fix-211229.md`](indvars-gep-fix-211229.md) (the
original IndVarSimplify fix plan), [`indvars-offset-congruent-ivs-explained.md`](indvars-offset-congruent-ivs-explained.md)
(SCEV / AddRec / preheader concepts from first principles).

**Verified against:** branch `jerry/fix-211229`, base `4070621c866f`, both PRs applied
to `llvm/lib/Analysis/ScalarEvolution.cpp`. All numbers below are real
`build/bin/opt` + `build/bin/llc` output.

> `build/` is a CMake output directory and is not tracked by git. Move this doc
> somewhere tracked before it matters.

---

## Contents

1. [TL;DR](#1-tldr)
2. [Evidence](#2-evidence)
3. [What each PR does](#3-what-each-pr-does)
4. [Call chain: loop-vectorize](#4-call-chain-loop-vectorize)
5. [Call chain: indvars](#5-call-chain-indvars)
6. [Call chain: SCEV construction (shared)](#6-call-chain-scev-construction-shared)
7. [Debugger confirmation: DistanceToB](#7-debugger-confirmation-distancetob)
8. [Residual limitation](#8-residual-limitation)
9. [Reproducing](#9-reproducing)

---

## 1. TL;DR

The bug was never in the vectorizer or in IndVarSimplify. It was an **analysis gap
in ScalarEvolution**, and it had two independent causes:

1. **Capability.** `createAddRecFromPHI` could not build an AddRec for a pointer
   phi in an *outer* loop header, because the value coming round the outer
   backedge is the *inner* loop's AddRec — right information, wrong node kind for
   the pattern match. Fixed by #215658.
2. **Ordering.** Even with the capability, the outer phi's SCEV was only computed
   correctly if it was demanded by a *top-level* query. In practice the first
   demand always arrived re-entrantly from inside an inner-loop value's
   construction, where the fold does not complete — so `getUnknown(PN)` was
   returned and cached in `ValueExprMap` permanently. Fixed by #215910.

With both applied, the two pointer IVs get SCEVs rooted at the same base:

```
%pA.0 -->  {%dst,+,(8 * zext(width))}<%for.cond>
%pB.0 -->  {(4 + %dst),+,(8 * zext(width))}<%for.cond>
%pA.1 -->  {{%dst,+,S}<%for.cond>,+,8}<%for.cond2>
%pB.1 -->  {{(4 + %dst),+,S}<%for.cond>,+,8}<%for.cond2>
```

`getMinusSCEV` then folds their difference to a constant, LoopVectorize's existing
interleave-group logic groups the two stores, and AArch64 emits `st2`.

---

## 2. Evidence

Cold SCEV cache, no IR rewrite of any kind, `-passes='loop-vectorize'`:

| build | input | `shufflevector` | `st2` |
|---|---|---|---|
| neither PR | `st2_nested_pre_lv.ll` | 0 | 0 |
| #215658 + #215910 | `st2_nested_pre_lv.ll` | **2** | **1** |
| neither PR | post-indvars IR, un-rewritten | 0 | 0 |
| #215658 + #215910 | post-indvars IR, un-rewritten | **2** | **1** |

`llvm-lit llvm/test/Transforms/IndVarSimplify/` with both PRs: 265 passed,
2 expected-fail, 6 unsupported — no regressions.

Two earlier readings that turned out to be measurement errors, recorded so they
are not repeated:

- "`st2_nested_pre_lv.ll` already vectorizes without any fix, so it proves
  nothing" — **wrong**. Came from a shell pipeline where `opt ... | llc` was
  swallowing stdin. It is a valid reproducer: 0 `st2` with neither PR.
- "#215658 alone fixes it" — **wrong**. The first attempt applied the one-line
  change to `createAddRecFromPHIWithCastsImpl` (the *predicated* SCEV path,
  reachable only from `SCEVPredicateRewriter`) instead of `createAddRecFromPHI`.
  Plain `getSCEV` never enters that path, so the edit was unreachable. Even once
  placed correctly, #215658 alone is not enough — see the ordering cause above.

---

## 3. What each PR does

### #215658 — one line, in `createAddRecFromPHI`

```cpp
-  const SCEV *BEValue = getSCEV(BEValueV);
+  const SCEV *BEValue = getSCEVAtScope(BEValueV, L);
```

`createAddRecFromPHI` recognises a recurrence by checking that the backedge
value's SCEV is a `SCEVAddExpr` containing the phi's placeholder symbol. For an
outer pointer phi the backedge value's raw SCEV is `{(8 + %pA.0),+,8}<inner>` —
an AddRec, so `dyn_cast<SCEVAddExpr>` fails. `getSCEVAtScope(BEValueV, L)`
evaluates that inner AddRec at the point the inner loop finishes, collapsing it
into a plain Add the matcher accepts.

Careful: there is a near-identical line in `createAddRecFromPHIWithCastsImpl`.
That is the wrong one.

### #215910 — declare the worklist dependency

Extracts `valuesForAddRecFromPHI(LI, PN)` ([ScalarEvolution.cpp:5869](../../llvm/lib/Analysis/ScalarEvolution.cpp#L5869))
and uses it in `getOperandsToCreate` to declare the phi's start value as a
dependency, replacing the old comment *"It's complicated to handle here, so just
construct it recursively"*:

```cpp
    // The fourth way is createAddRecFromPHI.
    {
      auto [BEValueV, StartValueV] = valuesForAddRecFromPHI(LI, cast<PHINode>(U));
      if (BEValueV && StartValueV) {
        Ops.push_back(StartValueV);
        // FIXME: Find invariant values which feed into BEValueV. ...
      }
    }
```

It also removes two early `return nullptr`s so the phi branches in
`getOperandsToCreate` no longer shortcut each other.

For the inner phi `%pA.1`, the start value **is** the outer phi `%pA.0`. So
`createSCEVIter` computes `%pA.0` as its own top-level stack entry, before
`%pA.1` — which is exactly the context in which #215658's `getSCEVAtScope` can
compute the inner loop's backedge-taken count and succeed.

This is the same ordering `print<scalar-evolution>` achieved by accident (it walks
the function top-down), now guaranteed structurally rather than by luck.

---

## 4. Call chain: loop-vectorize

### Pass entry to the interleave analysis

```
LoopVectorizePass::run(Function&, FunctionAnalysisManager&)      LoopVectorize.cpp:8462
└─ LoopVectorizePass::runImpl(Function&)                         LoopVectorize.cpp:8403
   └─ collect loops, innermost first
      └─ LoopVectorizePass::processLoop(Loop *L)                 LoopVectorize.cpp:7899
         ├─ compute trip count; bail if not countable
         ├─ LoopVectorizationLegality::canVectorize()            (runs LoopAccessInfo)
         ├─ early-exit legality checks
         ├─ InterleavedAccessInfo IAI(PSE, L, DT, LI, LVL.getLAI(), OptForSize)
         ├─ UseInterleaved = IsInnerLoop && TTI->enableInterleavedAccessVectorization()
         ├─ IAI.analyzeInterleaving(useMaskedInterleavedAccesses(*TTI))    LoopVectorize.cpp:7991
         ├─ cost model, VF / UF selection
         └─ VPlan construction + widening  ->  emits the interleaved shufflevector
```

Note `IsInnerLoop &&` — interleave groups are only ever formed for innermost
loops.

### Inside `analyzeInterleaving`

```
InterleavedAccessInfo::analyzeInterleaving()                     VectorUtils.cpp:1377
├─ collectConstStrideAccesses(AccessStrideInfo, Strides, ...)    VectorUtils.cpp:1385
│  └─ for each load/store in the loop:                           (def at :1297)
│     ├─ getPtrStride(PSE, ElementTy, Ptr, TheLoop, *DT, ...)    VectorUtils.cpp:1331
│     ├─ replaceSymbolicStrideSCEV(PSE, Strides, Ptr)            VectorUtils.cpp:1335
│     │  └─ PSE.getSCEV(Ptr)                              LoopAccessAnalysis.cpp:158
│     │     (no symbolic stride here, so returned unchanged)
│     └─ AccessStrideInfo[&I] = StrideDescriptor(Stride, Scev, Size, Align)
│
└─ grouping loop: outer over B (group owner), inner over A (candidate)
   ├─ code-motion / dependence checks
   ├─ isStrided(DesA.Stride) && isStrided(DesB.Stride)
   ├─ DesA.Stride == DesB.Stride && DesA.Size == DesB.Size       VectorUtils.cpp:1535
   ├─ same address space                                         VectorUtils.cpp:1538
   ├─ DistToB = dyn_cast<SCEVConstant>(
   │      PSE.getSE()->getMinusSCEV(DesA.Scev, DesB.Scev))       VectorUtils.cpp:1544  ***
   │  if (!DistToB) continue;        // A and B never get grouped
   ├─ DistanceToB % DesB.Size == 0                               (rule 3)
   ├─ IndexA = GroupB->getIndex(B) + DistanceToB / DesB.Size     VectorUtils.cpp:1568
   └─ GroupB->insertMember(A, IndexA, DesA.Alignment)            VectorUtils.cpp:1572
```

`***` is the single call that decided this bug. In our IR the stores go straight
to the phis, so `DesA.Scev` / `DesB.Scev` are literally `getSCEV(%pA.1)` and
`getSCEV(%pB.1)`.

---

## 5. Call chain: indvars

### Pipeline position (`-O3`)

From `opt -passes='default<O3>' -print-pipeline-passes`:

```
42  loop-simplifycfg
43  licm
44  loop-rotate
45  licm
50  indvars                 <-- IV canonicalization
54  loop-unroll-full
...
88  loop-rotate
93  loop-vectorize          <-- interleave groups formed here
102 loop-unroll<O3>
```

Roughly 40 passes apart. Both sit inside loop pass managers, and loops are
visited **innermost-first**.

### Inside `IndVarSimplify::run` ([IndVarSimplify.cpp:2056](../../llvm/lib/Transforms/Scalar/IndVarSimplify.cpp#L2056))

| # | Step | Notes |
|---|---|---|
| 1 | assert LCSSA; bail if not LoopSimplify form | guarantees preheader + single latch |
| 2 | `rewriteNonIntegerIVs` | float recurrences → integer |
| 3 | `SCEVExpander Rewriter(*SE, "indvars")` | source of the `indvars.iv` name |
| 4 | `simplifyAndExtend` | simplify IV users **and widen IVs** (kills `zext`/`sext`) |
| 5 | `rewriteLoopExitValues` | out-of-loop uses → closed-form exit values |
| 6 | `replaceCongruentIVs` | merge IVs with *identical* SCEVs |
| 7 | `canonicalizeExitCondition` | |
| 8 | `optimizeLoopExits` | drop exits with analyzable counts |
| 9 | `predicateLoopExits` | |
| 10 | LFTR | rewrite the exit test against the trip count |
| 11 | drain `DeadInsts` | `RecursivelyDeleteDeadPHINode`, [:2185-2193](../../llvm/lib/Transforms/Scalar/IndVarSimplify.cpp#L2185-L2193) |

Step 4 runs *before* step 6, which is why a debug print inside
`replaceCongruentIVs` already sees `indvars.iv` in the header.

`replaceCongruentIVs` requires **identical** SCEVs, so it never merged the two
pointer IVs here (they differ by 4). That is the gap the original IndVarSimplify
patch targeted.

---

## 6. Call chain: SCEV construction (shared)

Both passes reach the same builder. This is the only part the two PRs touch.

```
PredicatedScalarEvolution::getSCEV(Value*)
└─ ScalarEvolution::getSCEV(Value *V)                      ScalarEvolution.cpp:4662
   ├─ getExistingSCEV(V)               // cache hit -> return
   └─ createSCEVIter(V)                                    ScalarEvolution.cpp:7651
      explicit-stack post-order loop, entries are (Value, operandsVisited):
      ├─ getOperandsToCreate(CurV, Ops)                    ScalarEvolution.cpp:7693
      │     header PHI -> Ops.push_back(StartValueV)         <-- #215910
      │     (dependencies are pushed ABOVE CurV, so built first)
      └─ createSCEV(CurV)                // once operands are done
         └─ createNodeForPHI(PN)                           ScalarEvolution.cpp:6144
            ├─ createAddRecFromPHI(PN)                     ScalarEvolution.cpp:5898
            │  ├─ valuesForAddRecFromPHI(LI, PN)           ScalarEvolution.cpp:5869  <-- #215910
            │  ├─ createSimpleAffineAddRec(...)            // fast path; fails for GEP-chain phis
            │  ├─ getSCEVAtScope(BEValueV, L)              ScalarEvolution.cpp:10450 <-- #215658
            │  ├─ dyn_cast<SCEVAddExpr>(BEValue)           // the pattern match
            │  └─ return nullptr on failure
            ├─ simplifyInstruction / createNodeForPHIWithIdenticalOperands
            ├─ createNodeFromSelectLikePHI
            └─ return getUnknown(PN)                       // the old failure mode
```

### `createSCEVIter` walk for `getSCEV(%pA.1)`, with #215910

```
stack                                        action
[(%pA.1, false)]                             getOperandsToCreate -> Ops=[%pA.0]
[(%pA.1, TRUE), (%pA.0, false)]              getOperandsToCreate -> Ops=[%dst]
[(%pA.1, T), (%pA.0, TRUE), (%dst, false)]   %dst -> getUnknown, cached, pop
[(%pA.1, T), (%pA.0, TRUE)]                  createSCEV(%pA.0)   <-- TOP LEVEL
                                               createAddRecFromPHI succeeds:
                                               {%dst,+,(8 * zext(width))}<%for.cond>
[(%pA.1, TRUE)]                              createSCEV(%pA.1)
                                               start value already good:
                                               {{%dst,+,S}<%for.cond>,+,8}<%for.cond2>
```

Without #215910, step 1 never pushed `%pA.0`, so it was resolved *inside*
`createSCEV(%pA.1)` where `getSCEVAtScope` does not complete → `getUnknown(%pA.0)`
cached forever. Running the pass twice does not recover it; the cache lives on the
`ScalarEvolution` instance.

> The precise failing sub-call inside the nested context was inferred from
> behaviour, not traced in a debugger. The observable facts are: cold fails, a
> preceding top-down `getSCEV` sweep succeeds, and a second pass run does not
> recover.

### Inside `getMinusSCEV` ([ScalarEvolution.cpp:4764](../../llvm/lib/Analysis/ScalarEvolution.cpp#L4764))

```
├─ if (RHS->getType()->isPointerTy()):
│     getPointerBase(LHS) != getPointerBase(RHS)            ScalarEvolution.cpp:4932
│        -> return getCouldNotCompute()          <-- where it used to die
│     else removePointerBase(LHS), removePointerBase(RHS)   // byte arithmetic
└─ getAddExpr(LHS, getNegativeSCEV(RHS))         // AddRec steps cancel -> constant
```

Two consequences worth remembering: the result is in **bytes** (because
`removePointerBase` strips to raw byte arithmetic), and a constant result implies
**the steps matched**, since `{a,+,s} - {b,+,s}` only folds when `s` is equal on
both sides.

---

## 7. Debugger confirmation: DistanceToB

Breaking at [VectorUtils.cpp:1550](../../llvm/lib/Analysis/VectorUtils.cpp#L1550)
with both PRs applied:

```
(lldb) ev DistanceToB
(int64_t) $0 = -4

(lldb) ir A
  store float %mul5, ptr %pA.1, align 4

(lldb) ir B
  store float %mul8, ptr %pB.1, align 4
```

This is the proof that the fix reaches the intended code path. Reading it:

- `DistanceToB = getMinusSCEV(DesA.Scev, DesB.Scev)` is **A minus B**, in bytes.
- `A` is the store to `pA`, `B` is the store to `pB`, and `pA` sits 4 bytes
  *before* `pB` — hence **-4**, not +4. The sign is correct, not a bug.
- Rule 3 passes: `-4 % 4 == 0`.
- `IndexA = GroupB->getIndex(B) + DistanceToB / DesB.Size` = `index(B) + (-4/4)`
  = `index(B) - 1`, so `A` is inserted one slot *below* `B` in the group. Correct:
  `pA` is the earlier element of each interleaved pair.
- `GroupB->insertMember(A, IndexA, DesA.Alignment)` then forms the 2-element store
  group that VPlan lowers to `shufflevector` + `store <8 x float>`, and AArch64
  lowers to `st2`.

Before the PRs, `DistToB` was null (the `getMinusSCEV` returned
`SCEVCouldNotCompute`), the code hit `continue`, no group formed, and LV then
judged two strided scalar stores unprofitable — so there was no vector loop at
all, not merely a non-interleaved one.

---

## 8. Residual limitation

`getSCEVAtScope` needs the inner loop's backedge-taken count. If the inner trip
count is data-dependent, the outer AddRec still does not form, even with both PRs:

```c
for (y ...)
  for (x = 0; stop[x] != 0; x++) {   // trip count not computable
      *pA = ...; *pB = ...; pA += 2; pB += 2;
  }
```

```
%pA.0        -->  %pA.0                                       (still SCEVUnknown)
%probe.inner -->  ((-1 * ptrtoaddr %pA.0) + ptrtoaddr %pB.0)   (still symbolic)
```

#215910 carries a matching `FIXME: Find invariant values which feed into BEValueV`,
so its author knows this is not the last word. No bug is filed against this case;
recorded here as a known limitation rather than something to build machinery for.

An IndVarSimplify-side transform *can* handle it, by proving `Q == P + C`
inductively from the preheader and latch incoming values instead of relying on
SCEV — see [`indvars-offset-congruent-ivs-explained.md`](indvars-offset-congruent-ivs-explained.md)
§7-8. That approach is order-independent by construction, which is why it worked
before either PR existed.

---

## 9. Reproducing

All from `build/`.

```sh
T=st2/st2_nested_pre_lv.ll

# The interleave group, cold SCEV, no IR rewrite
./bin/opt -passes='loop-vectorize' -force-vector-interleave=1 $T -S -o /tmp/lv.ll 2>/dev/null
grep -c shufflevector /tmp/lv.ll          # 2 with both PRs, 0 without

# All the way to st2 (write the IR to a file first -- piping opt into llc
# has bitten us twice)
./bin/llc -mtriple=aarch64-unknown-linux-gnu -O3 /tmp/lv.ll -o /tmp/lv.s
grep -cE '\bst2\b' /tmp/lv.s              # 1 with both PRs, 0 without

# The SCEVs themselves.  NOTE: the printer writes to stderr, and it also WARMS
# the cache -- so it cannot be used to observe the cold failure.
./bin/opt -disable-output -passes='print<scalar-evolution>' $T 2>&1 | grep -A1 'phi ptr'

# Full -O3 from source
./bin/clang -O3 --target=aarch64-unknown-linux-gnu -S st2/st2_optimization.cpp -o /tmp/full.s
awk '/^_Z11nested_loop/,/^\t\.size/' /tmp/full.s | grep -cE '\bst2\b'
```

Two traps, both hit during this investigation:

- **`-scalar-evolution-classify-expressions=false`** quiets the printer but also
  skips the per-instruction `getSCEV` walk that warms the cache. Quiet printer,
  no fix, no interleave group.
- **`opt ... -S | llc ...`** silently produced empty output more than once. Write
  the IR to a file and run `llc` on the file.
