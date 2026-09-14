# CUDA Programming Learning Materials

This guide is for a programmer who already understands C/C++, basic CUDA
allocation and copies, and simple `__global__` launches. Its goal is to build a
correct mental model before collecting APIs.

Pair this guide with [the CUDA study plan](cuda-study-plan.md). The companion
compiler lane begins in
[LLVM to NVPTX learning materials](llvm-nvptx-learning-materials.md).

## The map

CUDA programming has four interacting layers:

1. **Programming model:** threads, warps, blocks/CTAs, grids, clusters, and
   SIMT control flow.
2. **Memory and synchronization:** registers, local/shared/global/constant
   memory, caches, atomics, barriers, scopes, and ordering.
3. **Host orchestration:** contexts, allocations, transfers, streams, events,
   graphs, modules, and launches.
4. **Performance engineering:** coalescing, reuse, bank conflicts, occupancy,
   latency hiding, launch overhead, profiling, and library selection.

The arithmetic inside a kernel is usually the easy part. Performance and
correctness come from mapping that arithmetic onto these layers.

## Primary reading path

Prefer current primary documentation. Blog posts and talks are useful after
the source contract is clear.

### Stage 1: execution and memory

- [CUDA Programming Guide](https://docs.nvidia.com/cuda/cuda-programming-guide/):
  read the introduction, CUDA C++ basics, writing SIMT kernels, advanced kernel
  programming, and the CUDA C++ memory model.
- [CUDA C++ Best Practices Guide](https://docs.nvidia.com/cuda/cuda-c-best-practices-guide/):
  concentrate on timing, bandwidth, coalescing, shared memory, bank conflicts,
  occupancy, and instruction throughput.
- [CUDA Runtime API](https://docs.nvidia.com/cuda/cuda-runtime-api/): use as a
  reference for allocation, streams, events, errors, device properties, and
  launch APIs; do not read it front to back.
- [CUDA Samples](https://github.com/NVIDIA/cuda-samples): use samples to answer
  focused questions, but reduce each borrowed example to a small experiment.

Questions you should be able to answer:

- What is scheduled: a thread, warp, or block?
- Which ordering is guaranteed within a stream and across streams?
- When may two blocks communicate safely?
- Why can thread-local data cause off-chip traffic?
- What makes a warp's global accesses coalesced?
- What does a barrier guarantee that a fence does not?

### Stage 2: cooperation

- Programming Guide sections on synchronization, warp vote/shuffle
  operations, atomics, and [Cooperative Groups](https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/cooperative-groups.html).
- [libcu++ concurrency](https://nvidia.github.io/cccl/libcudacxx/): scoped
  atomics, barriers, latches, semaphores, and pipelines.
- [CUB](https://nvidia.github.io/cccl/cub/): warp, block, and device primitives.
  Compare a hand-written reduction or scan with CUB rather than treating CUB
  as a black box.

Learn the distinction among:

- `__syncwarp()` and `__syncthreads()`;
- arrival synchronization and memory visibility;
- atomics, fences, and barriers;
- block-, device-, and system-scoped operations;
- control-flow convergence and memory synchronization.

### Stage 3: asynchronous execution

- Programming Guide sections on
  [asynchronous execution](https://docs.nvidia.com/cuda/cuda-programming-guide/02-basics/asynchronous-execution.html),
  [stream-ordered allocation](https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/stream-ordered-memory-allocation.html),
  [CUDA Graphs](https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/cuda-graphs.html),
  and [asynchronous data copies](https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/async-copies.html).
- Runtime API references for `cudaStream*`, `cudaEvent*`, `cudaMemcpyAsync`,
  `cudaMallocHost`, `cudaHostRegister`, `cudaMallocAsync`, and `cudaGraph*`.

Use a timeline profiler to verify overlap. An `Async` suffix expresses an API
contract; it does not prove that a particular execution overlaps.

### Stage 4: libraries

Before writing a major kernel, check whether the operation belongs in:

- cuBLAS/cuBLASLt for dense linear algebra;
- cuFFT, cuSPARSE, or cuSOLVER for their domains;
- CUB or Thrust for common parallel primitives;
- NCCL for multi-GPU collectives;
- CUTLASS when studying or composing matrix-multiplication kernels.

Libraries provide both production solutions and performance baselines.

## Tooling path

- [Compute Sanitizer](https://docs.nvidia.com/compute-sanitizer/): begin with
  `memcheck`, then use `racecheck`, `initcheck`, and `synccheck` as applicable.
- [Nsight Systems](https://docs.nvidia.com/nsight-systems/): inspect the
  CPU/GPU timeline, copies, synchronization, launch gaps, and overlap.
- [Nsight Compute](https://docs.nvidia.com/nsight-compute/): inspect one kernel
  after the timeline identifies it as important.
- [CUDA Binary Utilities](https://docs.nvidia.com/cuda/cuda-binary-utilities/):
  use `cuobjdump` and `nvdisasm` to distinguish embedded PTX from native SASS.
- Compiler diagnostics: `nvcc --resource-usage`, `ptxas -v`, and line
  information help connect source to registers, spills, and instructions.

For every benchmark, record correctness, warm-up policy, synchronization
points, input size, GPU/driver/toolkit, compiler flags, and multiple samples.

## Hardware-aware learning

Do not label machines merely "RTX" or "Spark." Record their actual GPU and
compute capability. Keep an inventory using `nvidia-smi`, the CUDA
`deviceQuery` sample, or `cudaGetDeviceProperties`.

For each device, record:

- GPU name and compute capability;
- SM count, warp size, and maximum threads per block;
- global memory and reported memory bandwidth;
- shared-memory and register limits;
- driver and CUDA toolkit versions;
- whether required features are supported.

Compile for the device's actual `sm_XX`. Treat architecture-specific features
such as asynchronous copy, tensor cores, clusters, distributed shared memory,
and TMA as capability-gated extensions. Do not hard-code an architecture based
on a product-family nickname.

## Topics to defer

Dynamic parallelism, texture/surface programming, cluster launches, TMA, and
hand-written PTX are real tools, but they are poor substitutes for mastering
coalescing, shared-memory reuse, synchronization, streams, and measurement.

## Completion criteria

You are ready for the joined CUDA/NVPTX projects when you can:

- explain a kernel at thread, warp, block, and grid levels;
- predict its important memory transactions and synchronization points;
- build a correct asynchronous host pipeline;
- use sanitizers and both Nsight profilers appropriately;
- compare an implementation against a library baseline;
- inspect PTX and SASS without assuming a one-to-one mapping.
