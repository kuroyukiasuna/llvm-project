# LLVM Backend: 21-Day Study Plan

**Prereqs:** C++ comfort, basic compiler theory (ASTs, IR, CFGs). You don't need prior LLVM experience.

**Setup (do this before Day 1):**
```bash
git clone https://github.com/llvm/llvm-project.git
cd llvm-project
mkdir build && cd build
cmake -G Ninja ../llvm \
  -DLLVM_ENABLE_PROJECTS="clang" \
  -DLLVM_TARGETS_TO_BUILD="X86;AArch64" \
  -DCMAKE_BUILD_TYPE=Debug \
  -DLLVM_ENABLE_ASSERTIONS=ON
ninja
```
Building X86 + AArch64 keeps rebuilds reasonably fast while letting you compare two real targets throughout the plan. Use `ninja opt`, `ninja llc`, `ninja clang` to build just the tool you need for a given day.

To generate AArch64 code without needing physical ARM hardware, just target it directly from any host:
```bash
llc -mtriple=aarch64-linux-gnu file.ll -o file.s
```
You can read and reason about the output assembly even on an x86 machine — no need to execute it, though `qemu-aarch64` plus a cross-toolchain will let you actually run it later if you want that.

---

## Week 1 — IR, the Pass Pipeline, and Optimization Passes

### Day 1: Tour the codebase + build system
- Read: `llvm/lib/IR`, `llvm/lib/Transforms`, `llvm/lib/CodeGen`, `llvm/lib/Target/X86` directory structure.
- Read the "LLVM IR" and "Writing an LLVM Pass" docs on llvm.org.
- **Exercise:** Compile a small `.c` file to `.ll` with `clang -S -emit-llvm -O0`. Compile the same file with `-O2` and diff the two `.ll` files. Identify which lines changed and guess which optimization did it (you'll confirm in Day 5).
- **Expected outcome:** You have a working build, can produce `.ll` IR from a `.c` file, and can identify at least 3 concrete differences between `-O0` and `-O2` IR (e.g., a dead store removed, a constant folded, a function call inlined) with a named guess for the responsible optimization.

### Day 2: LLVM IR fundamentals
- Read: LLVM Language Reference (SSA form, types, `phi`, basic blocks, metadata).
- **Exercise:** Hand-write a `.ll` file containing a function with a loop (use `phi` nodes yourself, no clang). Run `opt -S -passes=verify` on it to check it's valid IR, then `lli` to execute it and confirm the output is correct.
- **Expected outcome:** Your hand-written `.ll` passes `opt -passes=verify` without errors and `lli` produces the correct numeric output. You can explain in writing what each `phi` node in your loop represents and why SSA form requires them at join points.

### Day 3: The New Pass Manager
- Read: `llvm/docs/NewPassManager.md`, `llvm/lib/Transforms/Utils/` for a simple existing `FunctionPass`.
- **Exercise:** Write a new trivial `FunctionPass` (e.g., `HelloWorldPass` that prints the name of every function it visits). Register it, rebuild `opt`, and run `opt -passes="hello-world" input.ll`. Confirm your pass fires on each function.
- **Expected outcome:** Running `opt -passes="hello-world" input.ll` prints the name of every function in `input.ll`, in order, with no crashes. You can explain where in `PassBuilder.cpp` the pass was registered and how the pass manager resolves the name string to your pass.

### Day 4: Analysis passes
- Read: `llvm/include/llvm/IR/Dominators.h` (for `DominatorTree` and `DominatorTreeAnalysis`) and `llvm/include/llvm/Analysis/LoopInfo.h`.
- **Exercise:** Extend yesterday's pass to depend on `DominatorTreeAnalysis`, and print the dominator tree for each function. Modify one line of `DominatorTreePrinterPass::run` in `llvm/lib/IR/Dominators.cpp` and observe how the output format changes.
- **Expected outcome:** Your pass prints a correctly structured dominator tree for each function. After your `Dominators.cpp` edit, the output format change is visible when running `opt -passes="print<domtree>" input.ll`. You can trace `DominatorTreeAnalysis` from the header declaration down to the `run()` implementation in `Dominators.cpp`.

### Day 5: Transform passes — modify InstCombine
- Read: `llvm/lib/Transforms/InstCombine/InstCombineAddSub.cpp` (or similar small file).
- **Exercise:** Find a simple peephole rule in InstCombine (e.g., `x + 0 -> x`). Comment it out, rebuild `opt`, and run `opt -passes=instcombine` on IR containing that pattern — confirm the optimization no longer fires. Then restore it and add your **own** trivial rule (e.g., fold `x - x -> 0` if not already present) and prove it fires on a test case.
- **Expected outcome:** With the rule commented out, your test IR containing the pattern passes through `opt -passes=instcombine` unchanged (the redundant instruction survives). With your new rule active, running `opt -passes=instcombine` on a targeted `.ll` file produces folded output. You have a `FileCheck`-style `.ll` test file that can be run with `llvm-lit` or `opt | FileCheck`.

### Day 6: Loop optimizations
- Read: `llvm/lib/Transforms/Scalar/LoopUnrollPass.cpp`, `LICM.cpp`.
- **Exercise:** Write a loop in C with a loop-invariant computation inside it. Run `opt -passes=licm -S` and confirm the computation is hoisted out. Then tweak `LICM.cpp`'s hoisting condition (e.g., add a debug print or artificially disable hoisting for one instruction type) and rebuild to see the change reflected in output IR.
- **Expected outcome:** The unmodified `opt -passes=licm` output IR shows the invariant computation above the loop header. After your `LICM.cpp` tweak, either your debug print appears or the computation stays inside the loop, confirming you changed the right code path.

### Day 7: Week 1 capstone
- **Exercise:** Write a custom `FunctionPass` that detects a specific pattern in IR (e.g., a multiply by a power of two) and replaces it with a shift instruction. Wire it into the pipeline via `-passes=` and verify with a test `.ll` file that the transform is both correct (same runtime behavior) and applied (see the shift in output IR). This is your first "real" optimization pass.
- **Expected outcome:** A test `.ll` file containing `mul i32 %x, 8` (or another constant power-of-two multiply) is transformed by your pass into `shl i32 %x, 3` in the output IR. Running both the input and output through `lli` produces the same numeric result, confirming correctness. The shift appears in the `-S` output of `opt -passes=your-pass`.

---

## Week 2 — SelectionDAG: IR → Machine Instructions

### Day 8: TableGen and target description
- Read: `llvm/docs/TableGen/index.rst`, skim `llvm/lib/Target/X86/X86.td` and `X86InstrInfo.td`, then skim the AArch64 equivalents: `llvm/lib/Target/AArch64/AArch64.td` and `AArch64InstrInfo.td`.
- **Exercise:** Find one existing instruction definition in `X86InstrInfo.td` (pick something simple like an `ADD` variant), and find its rough AArch64 counterpart in `AArch64InstrInfo.td`. Note how AArch64's definitions tend to be more regular (fixed-width instructions, fewer addressing-mode variants) than X86's. Add a trivial new field/comment to the X86 one, rebuild, and use `llvm-tblgen -gen-instr-info` on the `.td` file to see your change reflected in the generated `.inc` output.
- **Expected outcome:** `llvm-tblgen -gen-instr-info` output (or the `.inc` file in `build/lib/Target/X86/`) reflects your added field/comment. You can articulate in one sentence the structural difference between how X86 and AArch64 instruction encodings are organized in `.td` files (e.g., X86 has many addressing-mode variants per mnemonic; AArch64's uniform encoding means one definition per instruction form).

### Day 9: SelectionDAG construction
- Read: `llvm/include/llvm/CodeGen/SelectionDAGNodes.h`, `llvm/lib/CodeGen/SelectionDAG/SelectionDAGBuilder.cpp`.
- **Exercise:** Compile a small function with `llc -view-dag-combine1-dags` (or `-debug-only=isel` if graphviz isn't set up) to dump the initial SelectionDAG. Identify the DAG nodes corresponding to your source-level arithmetic. Add a `dbgs()` print statement inside `SelectionDAGBuilder::visitBinary` in `SelectionDAGBuilder.cpp` (this is the function dispatched to for `ISD::ADD` and other binary ops) and confirm it fires when compiling your test function.
- **Expected outcome:** Your `dbgs()` print fires exactly once per addition in your test function. In the `-debug-only=isel` dump, you can point to the `add` DAG node that corresponds to the source-level operation.

### Day 10: DAG Combiner
- Read: `llvm/lib/CodeGen/SelectionDAG/DAGCombiner.cpp`.
- **Exercise:** Find a combine rule (e.g., `(add x, 0) -> x` at the DAG level, distinct from the IR-level InstCombine one). Disable it and observe the redundant node surviving into the pre-legalized DAG dump (`-debug-only=isel`). Then write a tiny new combine rule for a pattern of your choosing (e.g., `(xor (xor x, y), y) -> x`) and confirm it fires.
- **Expected outcome:** With the combine rule disabled, the redundant node appears in the DAG dump where it previously did not. Your new combine rule reduces your test pattern: you can see in the DAG dump that the combined form appears instead of the uncombined one.

### Day 11: Legalization
- Read: `llvm/lib/CodeGen/SelectionDAG/LegalizeTypes.cpp` and `LegalizeDAG.cpp`, `llvm/docs/CodeGenerator.rst` (legalization section).
- **Exercise:** Write IR using an illegal type on X86 (e.g., an `i1` vector, or `i128` arithmetic). Dump the DAG before and after legalization (`-debug-only=isel` shows both phases) and identify exactly which nodes got split/promoted/expanded. Add a print statement inside `PromoteIntegerResult` (or the relevant handler) to trace when your type triggers promotion.
- **Expected outcome:** The `-debug-only=isel` dump shows different DAG node types before and after legalization for your test input (e.g., a wide integer gets split into two narrower operations). Your added print fires exactly when the illegal type you chose is encountered, and you can name the legalization action applied (Promote, Expand, or Split).

### Day 12: Instruction Selection (patterns)
- Read: `llvm/lib/Target/X86/X86InstrInfo.td` patterns (the `Pat<>` and instruction `Pattern` fields), `llvm/lib/Target/X86/X86ISelDAGToDAG.cpp`. Also skim `llvm/lib/Target/AArch64/AArch64InstrInfo.td` patterns for the same idiom.
- **Exercise:** Pick an existing instruction pattern and comment it out in the X86 `.td` file. Rebuild `llc` and confirm compilation of code using that pattern now selects a different (probably worse) instruction sequence, or fails to select at all. Restore it, then add a new trivial pattern of your own (e.g., mapping a specific IR idiom to a single instruction that was previously matched by two). Then compile the same test case with `llc -mtriple=aarch64-linux-gnu` and compare: does AArch64 already have a single-instruction match for your idiom (e.g., via its `MADD`/`MSUB` fused patterns, or bitfield instructions like `UBFX` for shift+mask), and if so, in which `.td` pattern is that defined?
- **Expected outcome:** With the pattern commented out, `llc` emits a visibly different instruction sequence for your test function. Your new pattern causes one instruction to replace what was previously two in the `llc -O2` output. You can cite the specific `Pat<>` or `def` in `AArch64InstrInfo.td` (or another AArch64 `.td` file) that covers the equivalent idiom, or explain why no such single-instruction match exists.

### Day 13: Instruction scheduling (pre-RA, SelectionDAG level)
- Read: `llvm/lib/CodeGen/SelectionDAG/ScheduleDAGRRList.cpp` or `ScheduleDAGSDNodes.cpp`.
- **Exercise:** Compile a function with several independent arithmetic ops using `-pre-RA-sched=source` vs `-pre-RA-sched=list-ilp` (check available options via `llc --help-hidden`) and diff the emitted instruction order. Explain in your notes why the scheduler chose that order given the DAG's dependencies.
- **Expected outcome:** The two assembly outputs differ in instruction order for at least one pair of independent instructions. You have written notes explaining one concrete reordering in terms of the data-dependency edges in the DAG (e.g., "instruction B was moved earlier because it has no dependence on A and the ILP scheduler prefers to expose parallelism").

### Day 14: Week 2 capstone
- **Exercise:** Add a new, minimal machine instruction pattern end-to-end: define a `.td` pattern that recognizes a specific 2-instruction IR idiom (e.g., `shl` followed by `or`, i.e. a rotate) and lowers it to a single existing X86 instruction (e.g., `ROL`) if one doesn't already exist for your exact case. Verify with `llc -O2` that your test case now emits one instruction instead of two.
- **Expected outcome:** `llc -O2` on your test function emits a single `ROL` (or your chosen instruction) where it previously emitted two instructions. `llvm-tblgen` generates valid `.inc` files without errors from your modified `.td`. You can explain the `.td` `Pat<>` syntax you used and why TableGen maps it to that instruction.

---

## Week 3 — MachineIR, Register Allocation, and Code Emission

### Day 15: MachineFunction / MachineInstr
- Read: `llvm/include/llvm/CodeGen/MachineInstr.h`, `MachineFunction.h`, `MachineBasicBlock.h`.
- **Exercise:** Write a `MachineFunctionPass` that iterates over all `MachineInstr`s in a function and prints their opcode and operands. Run it with `llc -run-pass=your-pass-name` and confirm the printed instructions match `llc -print-after-all` output for the same stage.
- **Expected outcome:** Your pass output, when run at a fixed pipeline position with `-run-pass`, matches the `MachineInstr` list shown by `-print-after-all` at that same stage opcode-for-opcode. You can name the key difference between a `MachineInstr` at this stage and a finalized machine instruction (e.g., virtual registers have not yet been allocated to physical registers).

### Day 16: Register allocation
- Read: `llvm/lib/CodeGen/RegAllocGreedy.cpp` (just the high-level structure — it's large), `llvm/docs/CodeGenerator.rst` (register allocation section).
- **Exercise:** Compile a function with many live values using `-regalloc=fast` vs `-regalloc=greedy` and diff the generated assembly, paying attention to spill code (`mov`s to/from stack). Force extra register pressure (more local variables) until you can reliably observe a spill, then find the corresponding spill-insertion code path in `RegAllocFast.cpp` and add a debug print there.
- **Expected outcome:** The `-regalloc=fast` assembly contains visible spill `mov`s to/from stack slots that are absent (or fewer) in `-regalloc=greedy` output. Your debug print in `RegAllocFast.cpp` fires exactly when a spill is inserted, and you can correlate the printed virtual register with the `mov` you see in the assembly output.

### Day 17: Post-RA scheduling and peephole optimization
- Read: `llvm/lib/CodeGen/PeepholeOptimizer.cpp`, `llvm/lib/CodeGen/MachineScheduler.cpp`.
- **Exercise:** Find a peephole rule (e.g., redundant copy elimination) in `PeepholeOptimizer.cpp`. Construct a test case that triggers it, then disable the rule and confirm the redundant instruction survives to final assembly (`llc -O2 -S`).
- **Expected outcome:** With the rule active, the redundant instruction is absent from `llc -O2 -S` output. With the rule disabled (commented out), the redundant instruction appears in the final assembly. You can identify the specific lines in `PeepholeOptimizer.cpp` that matched your test case.

### Day 18: Target lowering and calling conventions — X86 vs. AArch64
- Read: `llvm/lib/Target/X86/X86ISelLoweringCall.cpp` (which contains `LowerCall` and `LowerFormalArguments`; the general operation-lowering infrastructure lives in `X86ISelLowering.cpp`) and `llvm/lib/Target/X86/X86CallingConv.td`. Then read the AArch64 equivalents: `llvm/lib/Target/AArch64/AArch64ISelLowering.cpp` (`LowerFormalArguments`, `LowerCall`) and `llvm/lib/Target/AArch64/AArch64CallingConvention.td` (note: the AArch64 file is named `AArch64CallingConvention.td`, not `AArch64CallingConv.td`).
- **Exercise, part 1 (X86):** Write a C function with 5+ integer arguments (more than fit in registers under the System V ABI). Compile with `llc` and identify in the assembly which args are passed in registers vs. stack.
- **Exercise, part 2 (AArch64):** Compile the *same* C-derived IR with `llc -mtriple=aarch64-linux-gnu`. AAPCS64 has 8 integer argument registers (`x0`-`x7`) vs. SysV's 6 (`rdi, rsi, rdx, rcx, r8, r9`), so find a function with 7-9 integer args where X86 has already spilled to the stack but AArch64 hasn't yet. Confirm this in the two assembly outputs side by side.
- **Exercise, part 3 (modify):** In `X86CallingConv.td`, change the register assignment order (e.g., swap two argument registers) and confirm the generated X86 call sequence changes accordingly. Then do the analogous edit in `AArch64CallingConvention.td` and confirm the AArch64 call sequence changes too — same concept, different `.td` file and register set. **Revert both changes afterward** — they break ABI compatibility with everything else.
- **Expected outcome:** You can identify in the X86 assembly which arguments spilled to the stack (beyond the 6 integer register arguments under SysV), and confirm the AArch64 output keeps those same arguments in registers (`x0`–`x7`). Both `.td` edits produce a visibly different register assignment order in generated call sequences before you revert them.

### Day 19: TargetLowering — custom lowering of an operation
- Read: `llvm/lib/Target/X86/X86ISelLowering.cpp` — find `setOperationAction` calls and a `LowerXXX` custom-lowering function for some operation. Then read the equivalent section in `llvm/lib/Target/AArch64/AArch64ISelLowering.cpp`'s constructor, where `setOperationAction` calls are set up similarly.
- **Exercise, part 1 (X86):** Pick an operation that's currently `Expand`ed (turned into a libcall or multiple instructions) on X86 for some type, and change its action to `Custom`, then write (or stub out, calling the existing expansion logic manually) a `LowerXXX` function for it. Confirm via `-debug-only=isel` that your custom lowering path is hit instead of the default expansion.
- **Exercise, part 2 (AArch64 comparison):** Find the *same* operation/type combination in `AArch64ISelLowering.cpp`'s constructor. Is its default action the same as X86's (`Expand`), or does AArch64 already mark it `Custom`/`Legal` because the architecture has a more direct instruction for it (a common case: certain bit-manipulation or floating-point conversion ops that map to a single AArch64 instruction but require multiple X86 instructions, or vice versa)? Write down which operations differ in default action between the two targets and why, based on what each ISA natively supports — this is the crux of what "target lowering" actually decides.
- **Expected outcome:** `-debug-only=isel` shows your custom lowering path is taken (e.g., "Using custom lowering" or a matching print you added). You have written notes documenting at least two operation/type pairs where X86 and AArch64 differ in `setOperationAction`, with a one-sentence explanation rooted in each ISA's native instruction set.

### Day 20: MC layer — assembly and object emission
- Read: `llvm/lib/MC/MCStreamer.h`, `llvm/lib/Target/X86/MCTargetDesc/X86AsmBackend.cpp`, and skim `llvm/lib/Target/AArch64/MCTargetDesc/AArch64AsmBackend.cpp` for comparison.
- **Exercise:** Compile a function to a `.o` file with `llc -filetype=obj`, then use `llvm-objdump -d` to disassemble it and confirm it matches the `-filetype=asm` textual output byte-for-byte in semantics. Add a debug print inside `X86AsmBackend`'s relaxation or fixup logic (e.g., where a branch instruction size is decided) and trigger it with a test case that needs branch relaxation (a jump far enough to need a longer encoding). Then compile the same test case for AArch64 (`llc -mtriple=aarch64-linux-gnu -filetype=obj`) — since every AArch64 instruction is a fixed 4 bytes, "relaxation" looks very different there (e.g., branch-range limits force a different long-branch sequence instead of a variable-length encoding change). Compare the two relaxation strategies in your notes.
- **Expected outcome:** `llvm-objdump -d` output and `-filetype=asm` output are semantically identical for your test function. Your debug print in `X86AsmBackend` fires when a branch requires relaxation to a longer encoding (e.g., short `jmp` promoted to near `jmp`). Your notes articulate the key difference: X86 varies the instruction byte-width during relaxation; AArch64 inserts an indirect branch stub instead because all instructions are fixed 4 bytes.

### Day 21: Capstone — full pipeline trace + mini feature
- **Exercise (three parts):**
  1. **Trace:** Pick one small C function. Run `clang -S -emit-llvm -O0`, then `opt -O2 -S`, then `llc -O2 -print-after-all` and save all intermediate IR/DAG/MachineIR dumps into one directory. Write a short doc (half a page) narrating what changed at each of the ~6 major stages (IR opt → SelectionDAG build → combine → legalize → isel → scheduling → RA → final asm).
  2. **Feature:** Combine what you built on Day 7 (IR pass), Day 14 (isel pattern), and Day 19 (custom lowering) into one coherent mini-feature — e.g., recognize a specific idiom at the IR level, ensure it survives to SelectionDAG, and confirm it lowers to your custom/optimal instruction sequence in the final assembly. This proves you can move a change through the entire pipeline, not just one stage.
  3. **Cross-target check:** Run the same source function through `llc -mtriple=aarch64-linux-gnu` and repeat the trace from part 1 at a high level (final assembly is enough, you don't need every intermediate dump again). Write a short comparison: which stages produced meaningfully different output (calling convention, instruction selection, legalization of any type) and which stages were essentially target-agnostic (most of the IR-level optimization passes from Week 1)? This is the real payoff of touching two targets — it makes clear which parts of LLVM's pipeline are shared infrastructure and which parts are genuinely target-specific.
- **Expected outcome:** You have (1) a written trace document covering all ~6 major pipeline stages for one small function, with the key IR/DAG/MachineIR change at each stage named explicitly; (2) a working mini-feature whose effect is visible at the IR level (`opt` output), the SelectionDAG level (`-debug-only=isel`), and in final assembly (`llc -O2 -S`); and (3) a written comparison identifying at least two stages where X86 and AArch64 diverge (e.g., legalization of an integer type, calling convention register count) and at least two stages where they are target-agnostic (e.g., most `-O2` IR passes, `mem2reg`).

---

## Reference commands you'll use constantly
```bash
clang -S -emit-llvm -O0 file.c -o file.ll        # C -> unoptimized IR
opt -passes=<pass-name> -S file.ll -o out.ll     # run specific IR passes
opt -passes=verify -S file.ll                    # validate hand-written IR
llc -O2 file.ll -o file.s                        # IR -> assembly
llc -mtriple=aarch64-linux-gnu -O2 file.ll -o file.s   # IR -> AArch64 assembly (cross-compile)
llc -filetype=obj file.ll -o file.o              # IR -> object file
llc -debug-only=isel file.ll                     # dump SelectionDAG phases
llc -print-after-all file.ll                     # dump MachineIR after each pass
llvm-tblgen -gen-instr-info X86.td               # inspect TableGen output
llvm-objdump -d file.o                           # disassemble
```

## Tips for the whole 3 weeks
- Keep every test `.c`/`.ll` file you write in a scratch folder — you'll reuse many of them across days.
- When something "doesn't fire," add a `dbgs() << ...` and rebuild rather than guessing; LLVM's codebase is large enough that intuition alone is unreliable.
- Rebuilds only need `ninja opt` or `ninja llc`, not a full rebuild — this keeps iteration fast.
- If a day's rebuild is slow, it usually means you edited a widely-included header; try to confine edits to `.cpp` files where possible while learning.