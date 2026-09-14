# LLVM Optimization Project Proposals

Draft GitHub issues / RFCs for AArch64-backend and Clang optimization work.
Grounded against this tree as of 2026-07-20.

## Suggested filing order

1. **#1 — Complete the in-order Cortex sched models** (`CompleteModel=1`). Lowest-risk; clean first PR.
2. **#3 — RFC: enable MachinePipeliner for in-order AArch64 cores.** **Depends on #1** for the in-order cores whose sched models are incomplete (A320/A510/A55).
3. **#4 — Extend LDP/STP pair formation to reg+reg addressing.** Independent.
4. **#6 — Tighten `-fsanitize=pointer-overflow` codegen for known-nonnegative indices.** Independent.

## Dependency

```
#1 complete sched models  ─────▶  #3 enable pipeliner (in-order cores)
#4 LDP/STP reg+reg        (independent)
#6 ubsan pointer-overflow (independent)
```
b## Key grounding notes

- The AArch64 MachinePipeliner is **fully implemented**, just gated off by default
  (`-aarch64-enable-pipeliner`, `cl::init(false)`). #3 is evaluation + heuristics +
  enablement, not implementation.
- In-order cores (`MicroOpBufferSize=0`): A53, A320, A510, A55, C1Nano, ThunderX.
- Incomplete sched models (`CompleteModel=0`): A320, A510, A55, Ampere1.
- The overlap (A320/A510/A55: in-order **and** incomplete) is the highest-value target
  and the reason #1 gates #3.

---

# #1 — [AArch64] Complete the in-order Cortex scheduling models (`CompleteModel=1`)

**Type:** Issue (missed-optimization / codegen-quality)
**Area:** AArch64 backend — scheduling
**Difficulty:** Low (self-contained TableGen; land one core at a time)

## Summary

`AArch64SchedA510.td`, `AArch64SchedA320.td`, and `AArch64SchedA55.td` all declare
`CompleteModel = 0`, meaning instructions without an explicit `SchedWrite` mapping
silently fall back to defaults instead of failing the build. On in-order cores
(`MicroOpBufferSize = 0`) the MachineScheduler leans heavily on model accuracy, so
these gaps directly cost codegen quality — and block reliable software pipelining
(see #3).

## Background

- Incomplete models (`CompleteModel = 0`): `A320`, `A510`, `A55`, `Ampere1`.
- In-order models (`MicroOpBufferSize = 0`): `A53`, `A320`, `A510`, `A55`, `C1Nano`,
  `ThunderX`.
- The overlap (**A320 / A510 / A55**) is in-order *and* incomplete — highest-value target.

## Proposal

1. Flip one model to `CompleteModel = 1`; build to enumerate every unmapped
   instruction class the TableGen verifier reports.
2. Map each against the core's Arm Software Optimization Guide (SWOG) — latencies,
   throughput (`ResourceCycles`), micro-op counts, forwarding paths.
3. Add `InstRW` / `SchedWriteRes` entries, especially for NEON / crypto / recent
   extensions that post-date the original model.

## Scope / feasibility

Self-contained TableGen, no algorithmic risk, incremental (one core per PR). Lowest-risk
of the four proposals and a good re-entry PR.

## How to measure

- `llvm-mca` throughput/latency deltas on representative loops before/after.
- Build with `CompleteModel=1` as the regression gate (unmapped instr → build failure).
- llvm-test-suite `-mcpu=cortex-a510` runtime on in-order hardware if available.

## Entry points

- `llvm/lib/Target/AArch64/AArch64SchedA510.td`
- `llvm/lib/Target/AArch64/AArch64SchedPredicates.td`
- Verify: `llvm-mca -mcpu=cortex-a510`
- Tests: `llvm/test/tools/llvm-mca/AArch64/`

---

# #3 — [RFC][AArch64] Enable software pipelining (MachinePipeliner) by default for in-order cores

**Type:** RFC (Discourse `#backend-aarch64`) + tracking issue
**Area:** AArch64 backend — scheduling
**Difficulty:** Medium (infra exists; measurement + heuristic tuning + real-bug fixing)
**Depends on:** #1 (complete sched models for the in-order cores)

## Summary

The AArch64 MachinePipeliner is **fully implemented** (`AArch64PipelinerLoopInfo`,
`analyzeLoopForPipelining`, `createRemainingIterationsGreaterCondition` —
`AArch64InstrInfo.cpp:11725`) but dormant behind `-aarch64-enable-pipeliner`
(`cl::init(false)`, `AArch64TargetMachine.cpp:222`). This RFC proposes characterizing it
and enabling it by default for in-order subtargets, where modulo scheduling has the
clearest payoff.

## Motivation

`enableMachinePipeliner()` currently only checks `hasInstrSchedModel()`
(`AArch64Subtarget.cpp:651`). In-order cores (A53/A55/A510/A320) can't hide latency
dynamically, so loop-carried latency chains stall — exactly what modulo scheduling
addresses. Because the feature ships off, it gets no production test coverage and
bit-rots.

## Plan

1. **Characterize:** run llvm-test-suite + microbenchmarks with the flag on across
   in-order `-mcpu`s; collect II achieved vs. resource/recurrence MII, compile-time
   cost, and correctness.
2. **Fix gaps** surfaced — likely epilogue/prologue codegen,
   `createTripCountGreaterCondition`, register-pressure regressions.
3. **Gate correctly:** make `enableMachinePipeliner()` return true only for in-order
   subtargets with a *complete* sched model → creates the dependency on #1.
4. **Propose default-on** for those subtargets, backed by data.

## Scope / feasibility

Medium. Infra is done, so this is measurement + heuristic tuning + real-bug fixing —
genuine scheduling research with a bounded surface. Best paired with #1.

## Risks

- Compile-time regressions → needs a cost gate.
- Correctness bugs in epilogue generation → where the real work is (the point of the
  project).

## How to measure

- II achieved vs. MII across the loop corpus.
- llvm-test-suite runtime on in-order hardware; compile-time tracking.
- New MIR tests under `llvm/test/CodeGen/AArch64/sms-*`.

## Entry points

- `llvm/lib/Target/AArch64/AArch64Subtarget.cpp:651` (`enableMachinePipeliner`)
- `llvm/lib/Target/AArch64/AArch64TargetMachine.cpp:875` (pass insertion)
- `llvm/lib/Target/AArch64/AArch64InstrInfo.cpp:11725` (`AArch64PipelinerLoopInfo`)
- `llvm/lib/CodeGen/MachinePipeliner.cpp`
- Tests: `llvm/test/CodeGen/AArch64/sms-*`

---

# #4 — [AArch64] LoadStoreOptimizer: support reg+reg (register-offset) addressing in pair formation

**Type:** Issue (missed-optimization)
**Area:** AArch64 backend — memory / load-store
**Difficulty:** Medium (start with narrowest safe subset)

## Summary

`AArch64LoadStoreOptimizer` bails on several addressing forms. A concrete, well-scoped
one: `AArch64LoadStoreOptimizer.cpp:2803` — *"FIXME: It is possible to extend it to
handle reg+reg cases."* Register-offset loads/stores currently miss LDP/STP merging.

## Background

The pass has 13 TODO/FIXMEs. Most tractable candidates:

| Line | Note |
|------|------|
| **2803** | reg+reg cases (**recommended primary target**) |
| 539 / 843 | "Add more index address stores" |
| 458 | pre-indexed creation restriction |
| 2752 | relax an over-conservative restriction |

## Proposal

Teach the pairing matcher to recognize matching base+offset-register operands, verify
the offset register isn't clobbered between candidates, and emit the paired form. Start
with the narrowest safe subset; expand once tests pass.

## Constraints to preserve

- Big-endian exclusion (`:1493`).
- Windows-SP exclusion (`:2576`, `:2672`).

## How to measure

- Count LDP/STP in generated asm on hot libc/SPEC paths.
- Add MIR tests under `llvm/test/CodeGen/AArch64/`.
- Code-size and llvm-test-suite perf.

## Entry point

- `llvm/lib/Target/AArch64/AArch64LoadStoreOptimizer.cpp:2803`

---

# #6 — [clang][ubsan] Redundant checks in pointer-overflow instrumentation for known-nonnegative indices

**Type:** Issue (sanitizer codegen-quality)
**Area:** Clang — CodeGen / sanitizers
**Difficulty:** Low–Medium

## Summary

In `EmitCheckedInBoundsGEP` (`clang/lib/CodeGen/CGExprScalar.cpp`), pointer-overflow
instrumentation emits `llvm.smul.with.overflow` + base/computed compares for GEPs. For
statically-nonnegative or unsigned indices (see `pointer_array_unsigned_indices` in
`clang/test/CodeGen/ubsan-pointer-overflow.c:52`), some of the emitted
comparison/`select` logic is redundant and could be simplified at emission time,
shrinking `-fsanitize=pointer-overflow` overhead.

## Proposal

Identify index value-facts already known in the front end (unsigned type, constant,
`__builtin_assume`) and skip the branch that can't fire, rather than relying on the
optimizer to clean it up post-hoc. Handler semantics stay identical; this purely emits
fewer instructions.

## Scope note (validate first)

Confirm the middle-end doesn't already fold these — check `-O2` output before claiming a
win. If InstCombine already removes them, reframe as a `-O0` sanitizer-overhead
improvement (still valuable for sanitizer builds).

## How to measure

- IR diff on the existing test cases.
- Sanitizer-overhead microbenchmark.
- `check-ubsan` compiler-rt tests pass unchanged.

## Entry points

- `clang/lib/CodeGen/CGExprScalar.cpp:5025` (`EmitCheckedInBoundsGEP`)
- Tests: `clang/test/CodeGen/ubsan-pointer-overflow.c`, `compiler-rt/test/ubsan/`
