# LLVM to NVPTX Study Plan

This lane assumes prior LLVM experience. It emphasizes target contracts,
source tracing, regression tests, and execution. Run it in parallel with the
[CUDA study plan](cuda-study-plan.md).

## Evidence discipline

For each exercise retain:

- minimal `.ll` and, where relevant, `.cu` input;
- exact LLVM revision and command line;
- selected pre/post-pass IR or MIR;
- generated PTX and `ptxas` diagnostics;
- selected SASS when executed;
- a `lit`-style assertion of the property being studied;
- an explanation separating verified behavior from inference.

Never judge a code-generation change only by textually nicer PTX. Establish
semantic correctness and, for performance claims, measure the final binary.

## Phase 0: build and orient

Create the separate NVPTX-enabled build described in
[the materials](llvm-nvptx-learning-materials.md#toolchain-preparation-for-this-checkout).
Run the existing NVPTX code-generation tests from the generated test tree:

```bash
build-nvptx/bin/llvm-lit -sv build-nvptx/test/CodeGen/NVPTX
```

For a faster first pass, give `llvm-lit` one generated test path corresponding
to a source file under `llvm/test/CodeGen/NVPTX`. Record the exact command.

Read `NVPTXUsage.md`, then choose one simple test each for kernel parameters,
address spaces, barriers, atomics, and architecture feature gating. Reproduce
their `RUN:` lines manually.

Exit: `llc --version` lists `nvptx` and `nvptx64`, and you can explain the
triple, `-mcpu`, and PTX feature/version choices.

## Phase 1: hand-written kernel IR

Write a minimal `ptx_kernel` that computes a global linear index using:

- `llvm.nvvm.read.ptx.sreg.tid.x`;
- `llvm.nvvm.read.ptx.sreg.ctaid.x`;
- `llvm.nvvm.read.ptx.sreg.ntid.x`.

Load two `float`s from global pointers, add them, and store the result. Generate
PTX at `-O0` and an optimized level. Annotate:

- `.entry` and parameters;
- special-register moves;
- address-space-specific or generic loads/stores;
- predicate/bounds-check lowering;
- transformations that prevent a one-to-one IR/PTX mapping.

**Join 1:** compare this module with Clang IR for the CUDA lane's grid-stride
SAXPY. Normalize irrelevant naming and metadata before comparing structure.

Exit: load and execute the PTX through a small CUDA Driver API harness using
`cuModuleLoadData`, `cuModuleGetFunction`, and `cuLaunchKernel`.

## Phase 2: address spaces and shared memory

Construct variants using generic, global, and shared pointers. Add a
shared-memory global in address space 3 and a CTA barrier. Exercise legal
`addrspacecast`s and one intentionally invalid form, checking the verifier or
backend diagnostic.

Trace the relevant lowering through `NVPTXISelLowering`, instruction patterns,
and `NVPTXAsmPrinter`. Read nearby address-space tests before forming claims.

**Join 2:** emit Clang IR for naive and tiled CUDA transpose. Explain how
`__shared__`, pointer arithmetic, and `__syncthreads()` appear in IR and PTX.

Exit: add a small local regression test that distinguishes at least two state
spaces with robust `FileCheck` assertions.

## Phase 3: synchronization, shuffles, and atomics

For the CUDA reduction, collect device IR before and after optimization.
Identify:

- barrier intrinsics and convergence markers;
- shuffle/vote intrinsics and active masks;
- LLVM atomic ordering and sync scope;
- corresponding PTX scopes and qualifiers.

Create one negative experiment that removes or weakens an essential semantic
property. Explain why textual instruction presence is insufficient to prove
correctness. Do not run deliberately racy code except in a controlled
sanitizer exercise.

**Join 3:** compare CUDA correctness/sanitizer evidence with the IR/PTX memory
model argument.

Exit: write a mapping table for the reduction covering CUDA operation, LLVM
representation, PTX representation, and the semantic property preserved.

## Phase 4: Clang's CUDA compilation

Use `clang -###` and device-only compilation modes to reconstruct:

1. host compilation;
2. device IR generation;
3. libdevice linking and device optimization;
4. PTX emission;
5. `ptxas` invocation;
6. fatbinary packaging and host registration.

Compare one-source compilation for two SM targets. Inspect the fatbinary and
explain when PTX fallback is or is not embedded. Trace one CUDA builtin from
Clang AST/code generation into an NVVM intrinsic.

Exit: diagnose one artificial failure at each of these boundaries: missing
CUDA toolkit, unsupported SM, `ptxas` rejecting PTX, and runtime image mismatch.

## Phase 5: backend source trace

Choose one moderately simple operation, such as a special-register read,
barrier, shuffle, conversion, or atomic. Produce a call graph/source map from:

```text
Intrinsic definition -> legalization/lowering -> instruction pattern
-> machine instruction -> assembly printer -> regression test
```

Use debug dumps or `-stop-before`/`-stop-after` where supported to validate the
map. Note which conclusions come from source reading and which are confirmed
by a dump.

Exit: another LLVM developer could use the map to find the correct edit and
test location without reading the whole backend.

## Phase 6: make a bounded code-generation change

Choose a deliberately small change, for example:

- improve a diagnostic for an illegal feature/architecture combination;
- add coverage for a missing legal type or immediate boundary;
- correct an instruction predicate or attribute propagation issue you can
  demonstrate;
- add a narrowly justified combine or selection improvement.

Start with the failing `.ll` test. Run the focused test, the NVPTX codegen
suite, and relevant verifier/unit tests. If behavior changes, assemble the PTX
with compatible `ptxas`; if performance is claimed, execute and measure it.

Exit: the change has a minimal reproducer, negative/edge coverage, and no
unsupported claim about SASS or performance.

## Phase 7: compatibility matrix

Select two LLVM revisions or configurations, two installed toolkit/driver
combinations if available, and two GPU architectures. For a small intrinsic
set record:

- whether LLVM accepts the IR;
- emitted PTX version and target;
- whether `ptxas` accepts it;
- whether the driver loads it;
- whether the hardware executes and passes correctness tests.

Exit: failures are assigned to a precise boundary rather than summarized as
“NVPTX does not work.”

## Capstone: one kernel through both lanes

Use the same transpose or reduction selected in the CUDA capstone:

1. establish source-level correctness and profiler baseline;
2. capture Clang device IR and identify ABI/address-space/intrinsic decisions;
3. create a reduced hand-written IR form preserving the important semantics;
4. run the relevant LLVM optimization and NVPTX pipeline stages;
5. compare generated PTX with the CUDA-source path;
6. assemble both with the same `ptxas` and compare resources and SASS;
7. execute both through a common Driver API harness;
8. explain performance differences with measurements or label them unresolved.

The joined outcome is not merely familiarity with two toolchains. It is the
ability to locate a behavior at the correct abstraction boundary:

```text
algorithm -> CUDA mapping -> Clang IR -> LLVM transforms -> NVPTX PTX
          -> NVIDIA native compilation -> runtime/hardware
```

Completion means you can form and test hypotheses across that entire path
without treating PTX as native assembly or compiler output as performance
evidence by itself.
