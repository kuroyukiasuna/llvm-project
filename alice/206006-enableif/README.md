# #206006 — Clang doesn't vectorize `std::find_if`

**Issue:** <https://github.com/llvm/llvm-project/issues/206006>
(labels: `vectorizers`, `loopoptim`, `missed-optimization`; unassigned; 1 comment)

**Motivation:** blocks the OCUDU benchmark, where GCC beats clang — see
[#198106](https://github.com/llvm/llvm-project/issues/198106). GCC emits
`vpcmpeqd` + `kortestw`; clang only unrolls 4x and stays scalar.

> Directory is named `206006-enableif` for historical reasons; the issue is
> about `find_if`.

---

## State: root-caused. Upstream fix already exists in an unmerged PR stack.

**There is one blocker, not two, and it is not the cost model.**

`std::find_if` searches through a pointer argument. LV cannot prove that
pointer is dereferenceable for the whole symbolic-max trip count, so VPlan
construction refuses to build any plan — a speculative wide load could fault
past the element that would have ended the search. With no plan at any VF, LV
falls back to VF=1 and emits the generic "cost model" remark on the way out.

The bail is at
[VPlanConstruction.cpp:1270-1272](../../llvm/lib/Transforms/Vectorize/VPlanConstruction.cpp#L1270-L1272),
in `VPlanTransforms::handleEarlyExits`:

```cpp
    if (Style == UncountableExitStyle::ReadOnly &&
        !areAllLoadsDereferenceable(HeaderVPBB, TheLoop, PSE, DT, AC))
      return false;
```

`areAllLoadsDereferenceable` ([:1214](../../llvm/lib/Transforms/Vectorize/VPlanConstruction.cpp#L1214))
calls `isDereferenceableAndAlignedInLoop` on every load in the body and returns
false on the first one it can't prove.

### The control experiment

`./run.sh deref` (`deref_control.cpp`) varies dereferenceability and unroll
factor independently. Global array => provable; pointer argument => not.

| | unit stride | 4x manually unrolled |
|---|---|---|
| **deref provable** (`g_*`) | **vectorized, VF=8** | **vectorized, VF=4** |
| **deref not provable** (`p_*`) | scalar — fake cost-model remark | scalar — stride remark |

The top row is the whole point: the early-exit vectorizer already handles both
shapes end to end on x86, including four uncountable exits in one loop. Nothing
about `find_if`'s control flow, its live-out pointer, or the cost model is the
problem. Only dereferenceability is.

### Three claims from the earlier triage that were wrong

1. *"Problem B is a cost-model problem."* No. `-force-vector-width=8` doesn't
   help because there is no VPlan to apply a VF to. `the cost-model indicates
   that vectorization is not beneficial` is a **misreport** — see
   [LoopVectorize.cpp:8172-8177](../../llvm/lib/Transforms/Vectorize/LoopVectorize.cpp#L8172-L8177),
   which fires on `VF.Width.isScalar()` with no idea why the width is scalar.
2. *"A and B are two independent problems."* They are one. The stride check is
   only reached for loads already known non-dereferenceable
   ([LoopVectorizationLegality.cpp:1752](../../llvm/lib/Transforms/Vectorize/LoopVectorizationLegality.cpp#L1752)
   iterates `NonDerefLoads`), so it is a second gate on the same path.
3. *"Relaxing the stride check might be independently valuable."* Measured, via
   `exp-relax-stride.patch`: `find_unrolled4` then passes legality and bails at
   the deref gate instead. Zero vector.body blocks before and after.

### Why `-debug-only=loop-vectorize` hid this

The "potentially faulting load" line is emitted from `VPlanConstruction.cpp`,
whose `DEBUG_TYPE` is **`vplan`**, not `loop-vectorize`. You need
`-debug-only=loop-vectorize,vplan` (that is what `./run.sh debug` does).
With only `loop-vectorize` the trace goes straight from "We can vectorize this
loop!" to "Vectorization is possible but not beneficial", which reads like a
cost-model decision and isn't one.

An earlier revision of this file blamed the missing output on `build/` being a
Release tree. That was wrong — `build/` has assertions ON, so `LLVM_DEBUG`
works there fine. It was always the `DEBUG_TYPE`. `build-debug/` is only needed
for an actual debugger.

---

## Upstream: fhahn already has a patch stack for exactly this

**[PR #180039 — [LV] Use speculative load intrinsics for early-exit
vectorization](https://github.com/llvm/llvm-project/pull/180039)** (fhahn, open,
non-draft, +2201/-247 over 47 files, last pushed 2026-02-05, premerge green,
**no human review comments yet**). Its description:

> Instead of checking dereferenceability early during
> LoopVectorizationLegality, instead check during VPlan transformations: if we
> cannot prove that an access is dereferenceable, we use speculative load
> intrinsics.

Four commits in the stack: add `@llvm.speculative.load` /
`@llvm.can.load.speculatively` intrinsics, a `Loads.cpp` helper, TTI costs
([#180036](https://github.com/llvm/llvm-project/pull/180036)), then the LV
change. It deletes the stride check this repro trips
(`LoopVectorizationLegality.cpp +1 -15`) — i.e. it subsumes both halves of the
old triage.

Neither intrinsic is in the tree yet:
`grep speculative_load llvm/include/llvm/IR/Intrinsics.td` is empty.

**#180039 deliberately does nothing on x86, and #206006 is an x86 report.**
The PR adds a `TargetLowering::emitCanLoadSpeculatively` hook (default returns
nullptr => the intrinsic folds to `false`), implements it for AArch64, and
leaves X86 on the default. Its own X86 tests say so out loud:

- `llvm/test/CodeGen/X86/can-load-speculatively.ll` — *"Test that
  `@llvm.can.load.speculatively` returns false (default) on X86, as X86 does
  not provide a target-specific expansion."* Every check line is `ret i1 false`.
- `llvm/test/Analysis/CostModel/X86/speculative-load.ll` — *"X86 does not
  implement `expandCanLoadSpeculatively`, so `speculative_load` should return
  invalid cost to prevent vectorizers from using it."*

Its end-to-end `std::find` test is `llvm/test/Transforms/PhaseOrdering/`**`AArch64`**`/std-find.ll`.

So the stack is the *enabling mechanism*; the x86 half is unwritten and is the
gap that maps onto this issue.

Related, narrower, and RVV-targeted:
**[PR #151300](https://github.com/llvm/llvm-project/pull/151300)** (arcbbb,
draft) uses the in-tree `@llvm.vp.load.ff` for unit-stride faulting loads —
16 comments, active review with lukel97, limited to a single unit-stride load
and IC=1. Does not help x86.

---

## Staged work

**S0 — post the triage on the issue.** (no code) The issue has no analysis and
is unassigned. The 2x2 table, the real bail site, and the pointer to #180039
are worth posting regardless of which path is taken next; it also prevents
duplicated effort.

**S1 — measure #180039 on this repro. DONE.** `./run-pr180039.sh`, captured in
`pr180039-results.txt`. Built `opt`+`llc` from a worktree at PR head
`d9abb0f7fb2e` (base `6e205c0d8e99`, Feb 2026); setup and teardown commands are
in the script header.

| | main | PR #180039 |
|---|---|---|
| **x86_64** | scalar | **scalar — unchanged** |
| **aarch64** | scalar | **vectorized, VF=4** |

On aarch64 the PR emits a `spec.load.check` block calling
`@llvm.can.load.speculatively(ptr %first, i64 16)` that bypasses to the scalar
loop, then `@llvm.speculative.load.v4i32.p0` in `vector.body`, plus a
`vector.early.exit` block that recovers the live-out pointer. Through `llc`
that becomes `and x10, x0, #0xf` for the check and a tight
`ldr q1, [x13], #16 / cmeq v1.4s, v1.4s, v0.4s / umaxv h2, v1.4h / cbnz` loop —
the structural equivalent of GCC's `vpcmpeqd` + `kortestw`.

On x86 nothing changes, by design, and the remark is still the misleading
cost-model one.

**So the outcome is the third of the three I listed: the mechanism is real and
proven, and the x86 half is the unwritten piece.**

**S1b — implement the x86 half.** The concrete, well-scoped task this measurement
points at. Two pieces, both small:
1. `X86TargetLowering::emitCanLoadSpeculatively` — override the hook added at
   `llvm/include/llvm/CodeGen/TargetLowering.h` (default returns nullptr, which
   folds the intrinsic to `false`). AArch64's version
   (`AArch64ISelLowering.cpp`, `emitCanLoadSpeculatively`) is 40 lines:
   `(ptr & (size-1)) == 0`. If the base is aligned to the vector width, every
   unit-stride load in the sequence is too, so none can cross a page. AArch64
   caps size at 16 bytes for MTE tag granules; **x86 has no such constraint**,
   so the cap can be the page size, which is what admits ymm/zmm.
2. X86 TTI cost for `@llvm.speculative.load`, currently deliberately `Invalid`
   to keep vectorizers away from it. Costing it as a plain vector load is the
   obvious start.

Both are gated on #180039 landing, so this is a follow-up patch offered on the
PR, not something to send standalone. Offering it also gives the stack — which
has sat unreviewed since 2026-02-05 — a reason to move.

**S2 — the misleading remark.** Small, independent, landable no matter what
happens to #180039: when `handleEarlyExits` bails, LV reports a cost-model
verdict it never reached. This cost the earlier triage most of a day and will
cost every other person who looks at an early-exit loop the same. Thread a
failure reason out of `handleEarlyExits` (or emit the remark at the bail site)
so the user sees "loop not vectorized: potentially faulting load in early exit
loop". Needs a lit test; touches `LoopVectorize.cpp` and `VPlanConstruction.cpp`.

**Not recommended: reimplementing speculative loads.** #180039 is a maintainer's
47-file stack with premerge green. Writing a competing one is wasted effort.

---

## Files

| file | what |
|---|---|
| `findif.cpp` | `find_simple`, `find_unrolled4`, `any_eq` — the reported shapes |
| `deref_control.cpp` | the 2x2 control: deref-provable x unroll factor |
| `unrollsweep.cpp` | `u1`/`u2`/`u4` — unroll factor alone |
| `findif_std.cpp` | real `std::find_if` / `std::any_of`, fidelity check |
| `findif_pre_lv.ll` | module IR as `LoopVectorizePass` first sees it — fast iteration vehicle |
| `findif_simple_{x86,aarch64}.ll` | attribute-light `find_simple`, one per triple; parses on older trees |
| `exp-relax-stride.patch` | the stride-relaxation experiment (proves it's a no-op) |
| `run.sh` | harness |
| `run-pr180039.sh` | main vs PR #180039, both triples; header has the worktree setup |
| `baseline.txt` | captured output of `./run.sh` on a clean tree |
| `pr180039-results.txt` | captured output of `./run-pr180039.sh` |

`findif_pre_lv.ll` was produced with
`-mllvm -print-before=loop-vectorize -mllvm -print-module-scope`, taking the
first module dump. It reproduces all three remarks under plain
`opt -passes=loop-vectorize`.

Fidelity: real libc++ `std::find_if` / `std::any_of` produce the identical
remark (`./run.sh std`), so the hand-written shapes are faithful. libstdc++
headers aren't on this macOS box, so `find_unrolled4` / `u4` / `p_unrolled4`
are **models** of libstdc++'s `#pragma GCC unroll 4` shape
([stl_algobase.h:2097](https://github.com/gcc-mirror/gcc/blob/master/libstdc%2B%2B-v3/include/bits/stl_algobase.h#L2097)),
not transcriptions.

## Harness

```sh
cd build/206006-enableif
./run.sh            # everything -> compare against baseline.txt
./run.sh deref      # the control experiment; start here
./run.sh debug      # LV+VPlan trace showing the real bail
./run.sh ir         # fast loop: opt on findif_pre_lv.ll
./run.sh asm        # clang -> asm, per-function instruction counts
./run.sh forced     # same with -force-vector-width=8
./run.sh sweep      # unroll-factor sweep
./run.sh std        # real std::find_if against host libc++ (needs xcrun SDK)
```

`./run.sh ir` and `./run.sh debug` need only `ninja -C ../../build opt`, not a
clang rebuild. `build/` is Release but has assertions on, so `-debug-only`
works; use `DBGBIN=../../build-debug/bin ./run.sh debug` only if you also want
to attach a debugger.

Write IR to a file before piping into `llc`; `opt ... -S | llc` silently
produced empty output more than once during the #211229 work.
