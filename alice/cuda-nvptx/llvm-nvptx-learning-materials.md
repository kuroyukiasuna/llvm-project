# LLVM to NVPTX Learning Materials

This guide assumes familiarity with LLVM IR, the pass pipeline, SelectionDAG
or GlobalISel concepts, TableGen, and LLVM testing conventions. It focuses on
what changes when the target is an NVIDIA GPU.

Pair it with [the LLVM to NVPTX study plan](llvm-nvptx-study-plan.md) and the
source-level [CUDA materials](cuda-learning-materials.md).

## Keep the layers distinct

```text
CUDA C++
  | Clang device compilation
  v
LLVM IR + NVVM conventions/intrinsics
  | LLVM optimization and NVPTX code generation
  v
PTX virtual ISA
  | NVIDIA ptxas or driver JIT
  v
cubin containing native SASS
  | driver launch
  v
GPU
```

- **NVPTX** is LLVM's target/backend name.
- **PTX** is NVIDIA's documented virtual ISA, not native machine code.
- **NVVM IR** is NVIDIA's specified LLVM-based compiler IR. It is related to,
  but not interchangeable with every upstream LLVM IR version and feature.
- **SASS** is architecture-specific native code. LLVM normally emits PTX;
  NVIDIA's tools perform the final translation.
- **libdevice** supplies NVVM bitcode implementations of device math and other
  operations.

PTX and SASS inspection answer different questions. PTX shows LLVM's output;
SASS shows the result after NVIDIA instruction selection, scheduling, and
register allocation.

## Primary references

### In this checkout

- [`llvm/docs/NVPTXUsage.md`](../../llvm/docs/NVPTXUsage.md): target triple,
  kernel convention, address spaces, function attributes, and intrinsics.
- [`llvm/docs/CompileCudaWithLLVM.md`](../../llvm/docs/CompileCudaWithLLVM.md):
  Clang's CUDA compilation and fatbinary flow.
- [`llvm/include/llvm/IR/IntrinsicsNVVM.td`](../../llvm/include/llvm/IR/IntrinsicsNVVM.td):
  canonical upstream intrinsic declarations.
- [`llvm/lib/Target/NVPTX/`](../../llvm/lib/Target/NVPTX/): backend source.
- [`llvm/test/CodeGen/NVPTX/`](../../llvm/test/CodeGen/NVPTX/): executable
  examples of accepted IR and expected PTX.
- [`clang/lib/CodeGen/CGCUDANV.cpp`](../../clang/lib/CodeGen/CGCUDANV.cpp) and
  [`clang/lib/CodeGen/TargetBuiltins/NVPTX.cpp`](../../clang/lib/CodeGen/TargetBuiltins/NVPTX.cpp):
  selected Clang lowering entry points.
- [`clang/test/CodeGenCUDA/`](../../clang/test/CodeGenCUDA/): CUDA frontend
  code-generation tests.

Tests are often the fastest reliable answer to “what IR form does this
checkout support?” Documentation describes the contract; tests expose exact
syntax and feature gates.

### NVIDIA contracts

- [PTX ISA](https://docs.nvidia.com/cuda/parallel-thread-execution/): virtual
  machine model, state spaces, instructions, memory consistency, and feature
  requirements.
- [NVVM IR specification](https://docs.nvidia.com/cuda/nvvm-ir-spec/): the
  NVIDIA-supported IR subset and its versioned differences.
- [libdevice User's Guide](https://docs.nvidia.com/cuda/libdevice-users-guide/):
  device bitcode library and functions.
- [CUDA Driver API](https://docs.nvidia.com/cuda/cuda-driver-api/): module
  loading, JIT options, linking, kernel lookup, and launch.
- [CUDA Binary Utilities](https://docs.nvidia.com/cuda/cuda-binary-utilities/):
  cubin inspection and SASS disassembly.

Treat PTX ISA version, target SM, CUDA toolkit, driver, and LLVM revision as a
compatibility tuple. “Valid LLVM IR” does not imply that an older `ptxas` or
driver accepts the emitted PTX.

## Concepts to learn

### Kernels and ABI

`ptx_kernel` identifies a host-launchable entry. Ordinary device functions
lower to PTX functions. Study:

- kernel parameter lowering into PTX parameter space;
- by-value aggregates and alignment;
- device calls, declarations, and linking;
- function attributes such as `nvvm.maxntid`, `nvvm.reqntid`, and register or
  cluster constraints;
- module annotations produced by Clang versus attributes consumed by current
  backend code.

Grid and block dimensions are normally launch-time state. Kernels obtain them
through special-register intrinsics rather than ordinary function parameters.

### Address spaces

The central mapping is:

| LLVM address space | PTX state space |
|---:|---|
| 0 | generic |
| 1 | global |
| 3 | shared CTA |
| 4 | constant |
| 5 | local |
| 7 | shared cluster |

Address spaces affect legality, aliasing, instruction selection, and pointer
conversion. Study `addrspacecast`, generic versus state-space-specific
pointers, global-variable restrictions, and inference of kernel pointer
arguments. Do not infer physical placement from the word “local”: PTX local
memory is per-thread but can be backed by device memory.

### NVVM intrinsics and ordinary LLVM IR

Ordinary `add`, `load`, `atomicrmw`, and control flow remain ordinary LLVM IR
where it can express the semantics. Target intrinsics represent operations or
state that target-independent IR cannot fully express, including:

- special registers such as thread and CTA IDs;
- barriers and warp vote/shuffle operations;
- architecture-specific math and conversion instructions;
- asynchronous copies and memory barriers;
- tensor, cluster, and newer hardware operations.

Read each intrinsic's types, attributes, convergence requirements, memory
effects, target feature gates, and lowering tests. Similar names do not imply
identical ordering semantics.

### Memory model and convergence

Connect four levels explicitly:

1. CUDA C++ scopes and memory orders;
2. LLVM atomics, sync scopes, convergent operations, and barriers;
3. PTX memory model qualifiers and scopes;
4. observed native code.

Preserving the opcode while losing convergence, scope, or ordering is a
miscompile. Use PTX memory-model documentation and LLVM tests rather than
reasoning from mnemonic resemblance.

### Code-generation path

Read the backend in this order:

1. `NVPTXTargetMachine.cpp` for pipeline construction;
2. `NVPTXSubtarget.*` and `NVPTX.td` for SM/PTX features;
3. `NVPTXISelLowering.*` for legalization and custom lowering;
4. `NVPTXISelDAGToDAG.cpp` and `.td` patterns for selection;
5. `NVPTXInstrInfo.td` and `NVPTXIntrinsics.td` for instruction models;
6. `NVPTXAsmPrinter.cpp` for final PTX syntax;
7. `NVPTXTargetTransformInfo.cpp` for target-aware optimization decisions.

Trace one operation end to end rather than reading every file sequentially.

## Toolchain preparation for this checkout

The existing `build/bin/llc` in this checkout currently registers AArch64 and
X86 only. Create a separate build so existing work is undisturbed:

```bash
cmake -G Ninja -S llvm -B build-nvptx \
  -DLLVM_ENABLE_PROJECTS=clang \
  -DLLVM_TARGETS_TO_BUILD='AArch64;X86;NVPTX' \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_ASSERTIONS=ON
ninja -C build-nvptx llc opt clang llvm-as llvm-dis FileCheck
build-nvptx/bin/llc --version
```

On a Linux GPU host, point Clang at an installed CUDA toolkit when compiling
CUDA C++. Pure LLVM IR-to-PTX experiments can run without a GPU or CUDA
runtime; assembling PTX and executing it require compatible NVIDIA tooling
and hardware.

Useful inspection modes include:

```bash
llc -mtriple=nvptx64-nvidia-cuda -mcpu=sm_XX input.ll -o output.ptx
llc -mtriple=nvptx64-nvidia-cuda -mcpu=sm_XX -stop-after=<pass> input.ll -o out.mir
llc -mtriple=nvptx64-nvidia-cuda -mcpu=sm_XX -debug-pass-manager input.ll -o /dev/null
ptxas -arch=sm_XX -v output.ptx -o output.cubin
nvdisasm output.cubin
```

Select `sm_XX`, PTX features, and pass names supported by the exact LLVM/CUDA
versions under test. Derive working command lines from nearby `lit` tests.

## Completion criteria

You are ready to modify the backend when you can:

- write a small legal NVPTX LLVM module without copying Clang output;
- explain kernel ABI, special-register access, and address-space choices;
- trace an intrinsic or IR operation through selection and assembly printing;
- add a focused `llvm/test/CodeGen/NVPTX` regression test;
- identify whether a failure belongs to Clang lowering, LLVM optimization,
  NVPTX code generation, `ptxas` compatibility, or runtime launch;
- compare PTX and SASS without claiming that LLVM directly selected SASS.
