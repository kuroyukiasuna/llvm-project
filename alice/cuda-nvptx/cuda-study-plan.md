# CUDA Programming Study Plan

This is an exercise-driven lane, not a fixed calendar. A phase is complete
when its exit criteria are met. Work through it alongside the
[LLVM to NVPTX plan](llvm-nvptx-study-plan.md); the **join** markers use the
same kernels and artifacts in both lanes.

## Ground rules and experiment layout

For each exercise keep:

```text
exercise-name/
  README.md          # hypothesis, machine, commands, results, conclusion
  src/
  results/           # small CSV/JSON summaries, not profiler databases
  inspect/           # selected PTX/SASS excerpts and compiler diagnostics
```

Every program must check CUDA API errors and the error from a kernel launch.
Every performance result must first pass a CPU or trusted-library correctness
check. Time GPU work with CUDA events; use wall time only for end-to-end
measurements. Report distributions or at least median and range, not one run.

Before starting, inventory every available device. Select at least two
different compute capabilities for cross-device phases. Run tools on a Linux
GPU host; NVIDIA no longer supports CUDA compilation on macOS.

## Phase 0: establish the laboratory

Build one utility that prints `cudaGetDeviceProperties` fields relevant to
launch limits, memory, and capabilities. Add a reusable error-check macro and
CUDA-event timer.

Exercises:

1. Compile one binary for one native architecture and another fat binary for
   two available architectures plus PTX fallback.
2. Use `cuobjdump` to list the images embedded in each binary.
3. Trigger and correctly report an invalid launch and an asynchronous kernel
   failure.

Exit: you can explain when an error becomes visible and identify which image a
device can execute.

## Phase 1: indexing, warps, and memory access

Implement SAXPY with a grid-stride loop. Sweep block sizes and problem sizes.
Then benchmark three access patterns: contiguous, fixed stride, and a
permutation.

Measure effective bandwidth and compare it with a copy baseline. Use Nsight
Compute to relate requested bytes to memory transactions. Add a branch whose
condition is uniform per warp, then one that alternates per lane.

Questions:

- When does changing block size matter, and why?
- Which results are explained by coalescing versus occupancy?
- Does divergent control flow actually dominate this kernel?

**Join 1:** preserve the smallest SAXPY kernel, generated PTX, and native SASS
for the compiler lane.

Exit: you can predict contiguous warp addresses and calculate effective
bandwidth.

## Phase 2: shared memory and tiling

Implement matrix transpose in this order:

1. naive out-of-place transpose;
2. shared-memory tiled transpose;
3. padded shared-memory tile;
4. boundary-safe version for non-multiple dimensions.

Compare against a device-to-device copy ceiling. Use metrics to identify
uncoalesced global accesses and shared-memory bank conflicts. Explain why a
tile such as `[32][33]` can outperform `[32][32]`.

**Join 2:** this kernel becomes the address-space case study: global,
shared, generic pointers, barriers, and address calculations.

Exit: the optimization is supported by transactions/conflict evidence, not
only elapsed time.

## Phase 3: cooperation, reductions, and atomics

Implement a sum reduction using:

1. global atomics as a deliberately simple baseline;
2. block shared memory and `__syncthreads()`;
3. warp shuffle for the last stage;
4. CUB as a production baseline.

Test awkward sizes, inactive lanes, NaNs where relevant, and several block
sizes. Run Compute Sanitizer `memcheck`, `racecheck`, and `synccheck`. Introduce
one race and one divergent barrier intentionally, demonstrate that a tool
detects them, then fix them.

Follow with a small release/acquire message-passing exercise using scoped
libcu++ atomics. Explain why a fence alone is not a rendezvous.

**Join 3:** map shuffle, barrier, and atomic source operations to
`llvm.nvvm.*` intrinsics/LLVM atomics and then to PTX.

Exit: all sizes are correct and the synchronization argument can be written as
a happens-before relation.

## Phase 4: streams and data movement

Build a chunked processing pipeline:

```text
H2D(chunk n) -> kernel(chunk n) -> D2H(chunk n)
```

Compare pageable and pinned host memory, synchronous execution, one stream,
and two or more streams. Use events for dependencies and Nsight Systems to
show what overlaps. Add `cudaMallocAsync`/`cudaFreeAsync` and explain their
stream ordering.

Exit: the report contains a timeline and distinguishes API submission time,
GPU execution time, and end-to-end time.

## Phase 5: graphs and reusable work

Take a short repeated pipeline and compare ordinary launches, stream capture,
and an explicitly constructed CUDA Graph. Vary work so both launch-bound and
compute-bound cases appear. Update a permitted node parameter between launches.

Exit: you can state when graphs help and when they merely add complexity.

## Phase 6: device comparison

Run the Phase 1 through Phase 5 benchmark summaries on at least two GPU
architectures. Do not compare raw time alone. Normalize with useful work,
bytes, clock behavior where available, and relevant hardware limits.

For each difference classify the likely cause as:

- memory-system capability;
- compute throughput or instruction support;
- occupancy/resource limit;
- host interconnect or launch overhead;
- compiler/code-generation difference;
- unresolved, requiring another experiment.

Exit: the report avoids product-name folklore and ties claims to measurements.

## Phase 7: one advanced feature

Choose based on available hardware and interests:

- `cuda::memcpy_async`/pipelines for global-to-shared staging;
- WMMA or CUTLASS for tensor-core study;
- clusters/distributed shared memory on supporting devices;
- unified memory with prefetch and observed page migration.

Implement a portable baseline and capability-gate the advanced path. Inspect
both correctness and fallback behavior on an older device.

Exit: the feature solves a measured problem and its hardware prerequisites are
documented.

## Capstone: CUDA source to executed SASS

Choose transpose or reduction and produce one auditable dossier:

1. CUDA C++ source and correctness tests;
2. Clang device LLVM IR;
3. optimized LLVM IR where obtainable;
4. LLVM NVPTX-generated PTX;
5. `ptxas` cubin and `nvdisasm` SASS;
6. resource usage and profiler evidence on two devices;
7. an explanation of mappings that stayed recognizable and mappings changed
   by optimization or final instruction selection.

This capstone joins the two lanes. Completion means you can move in both
directions: explain observed SASS from the source and design source/IR changes
from an observed performance or correctness issue.
