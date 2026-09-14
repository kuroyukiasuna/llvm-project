# Stack Frames, ABIs, and Prologue/Epilogue

### A differential study plan for a four-platform lab

You have something most people learning this don't: the same program can be compiled and
**actually run** across three distinct ABIs, two object formats, and three unwind formats.
That makes differential study possible, and differential study is by far the fastest way to
learn this material. When a rule holds on all four platforms it is fundamental; when it
differs, the difference itself is the lesson.

This plan is built around that. Your own LLVM checkout is the instrument throughout, not a
destination at the end.

---

## 1. Your lab

| Platform | ABI | Object format | Unwind format | What it uniquely teaches |
|---|---|---|---|---|
| **M4 Pro / macOS** | Darwin `arm64` | Mach-O | Compact unwind (+ DWARF fallback) | Mandatory frame pointer, stack-passed varargs, reserved `x18`, SME |
| **DGX Spark** | AAPCS64 / Linux | ELF | `.eh_frame` | The AArch64 reference ABI, SVE2 scalable frames |
| **Intel x86** | SysV x86-64 | ELF | `.eh_frame` | Red zone, CET / `endbr64`, shadow stack |
| **AMD x86** | SysV x86-64 | ELF | `.eh_frame` | AVX-512 spills → stack realignment, Zen shadow stack |

Two of these pairs are the high-value ones:

- **M4 Pro vs DGX Spark** — same instruction set, *different ABI*. Everything that differs
  is a pure ABI decision, stripped of any ISA excuse. This pair is the single best teaching
  instrument you own.
- **Intel vs AMD** — identical ABI, different microarchitecture and feature set. Everything
  that differs is a codegen/feature-availability decision, not an ABI one.

If either x86 box can boot Windows, add a fifth column later — the Win64 ABI has different
callee-saved registers, mandatory home/shadow space, structured epilogue rules, and
`.pdata`/`.xdata` unwind tables. It's an excellent third data point, but leave it until
Phase 4.

### Verify your hardware first

Don't take spec sheets on faith; you'll need these facts repeatedly.

```bash
# macOS
sysctl -a | grep -E 'hw.optional.arm|brand_string|cachelinesize'
# specifically: FEAT_SME, FEAT_SME2, FEAT_PAuth, FEAT_BTI, FEAT_LSE

# DGX Spark (expect a mix of Cortex-X925 and Cortex-A725, Armv9.2-A)
lscpu; cat /proc/cpuinfo | grep -m1 Features
# look for: sve sve2 bf16 i8mm paca pacg bti

# x86 boxes
lscpu | grep -E 'Model name|Flags' | tr ' ' '\n' | grep -E 'avx512|shstk|ibt|cet'
```

Record the results in a `LAB.md` in your workspace. Several exercises below branch on them
— in particular, whether your Intel part has usable AVX-512 (many recent consumer parts
have it fused off) and whether the M4 exposes SME.

---

## 2. Setup: one compiler, four targets

### Principle: analysis is cross-target, execution is native

You do not need sysroots, and you should not fight cross-toolchain installation. For
**analysis** — emitting assembly, IR, and MachineIR — a single `clang` targeting any triple
works fine, as long as your test sources are freestanding (no `#include`). For **execution**
— running, debugging, measuring — use each machine natively.

So: keep test sources header-free wherever possible. Declare what you need:

```c
// no #include anywhere in test sources
typedef unsigned long size_t;
extern void escape(void *);      // opaque, defeats optimization
extern long opaque(long);
```

This one discipline makes the entire cross-target workflow frictionless.

### Build a cross-capable clang from your checkout

```bash
cmake -S llvm -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_ASSERTIONS=ON \
  -DLLVM_ENABLE_PROJECTS="clang" \
  -DLLVM_ENABLE_RUNTIMES="" \
  -DLLVM_TARGETS_TO_BUILD="AArch64;X86" \
  -DLLVM_OPTIMIZED_TABLEGEN=ON \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DLLVM_USE_LINKER=lld
ninja -C build clang llc llvm-objdump llvm-readobj llvm-dwarfdump llvm-mc
```

`LLVM_ENABLE_ASSERTIONS=ON` matters — it enables `-debug-only` and many internal
consistency checks you'll want in Phase 7. Build this on the M4 Pro (it's likely your
fastest machine for compile jobs) and use it as the analysis compiler for everything.

**Methodological point:** using *one* clang across all four targets means every difference
you observe is attributable to the target, not to a compiler version difference. Don't mix
in Apple Clang or the distro GCC during comparison work. Bring those in deliberately, later,
as a separate axis.

### The differential harness

This is the core piece of infrastructure. Build it in Phase 0 and use it for the rest of the
plan.

```bash
#!/usr/bin/env bash
# quad — compile one source for all four targets, side by side
# usage: quad test.c [-O2] [extra clang flags...]
set -euo pipefail
CLANG=${CLANG:-$HOME/llvm-project/build/bin/clang}
SRC=$1; shift
BASE=$(basename "$SRC" .c)
OUT=out/$BASE; mkdir -p "$OUT"

emit() {  # name, triple, extra-flags...
  local name=$1 triple=$2; shift 2
  "$CLANG" --target="$triple" "$@" -S -o "$OUT/$name.s" "$SRC"
  "$CLANG" --target="$triple" "$@" -S -emit-llvm -o "$OUT/$name.ll" "$SRC"
}

emit mac     arm64-apple-macosx15.0        -mcpu=apple-m4 "$@"
emit spark   aarch64-unknown-linux-gnu     -mcpu=cortex-x925 "$@"
emit intel   x86_64-unknown-linux-gnu      -march=x86-64-v3 "$@"
emit amd     x86_64-unknown-linux-gnu      -march=znver4 "$@"

echo "=== $BASE ==="
for f in mac spark intel amd; do
  printf '\n--- %s ---\n' "$f"
  # strip directives to see instructions; drop the grep to see CFI
  grep -v '^\s*\.' "$OUT/$f.s" | grep -v '^\s*$'
done
```

Adjust `-mcpu=apple-m4` if your LLVM revision doesn't know it (`apple-m3` is a safe
fallback; check with `clang --target=arm64-apple-macos -mcpu=help`). Add a `-d` mode later
that pipes the two AArch64 outputs through `diff --side-by-side` — that specific diff is
where most of your learning will happen.

### Inspection commands per platform

| Task | ELF (Spark, x86) | Mach-O (M4 Pro) |
|---|---|---|
| Disassemble | `llvm-objdump -d --no-show-raw-insn` | same, add `--macho` for Mach-O specifics |
| Unwind tables | `readelf --debug-dump=frames-interp` | `llvm-objdump --macho --unwind-info` |
| Raw unwind section | `readelf -x .eh_frame` | `otool -s __TEXT __unwind_info` |
| DWARF CFI (both) | `llvm-dwarfdump --eh-frame` | `llvm-dwarfdump --eh-frame` |
| Symbols | `readelf -sW` | `nm -m` |
| Debugger | `gdb` | `lldb` |

---

## 3. The method

Every exercise uses the same loop. It is the most important thing in this document.

1. Write the source.
2. **Before compiling, write down your prediction** for each of the four targets. Which
   registers are saved? Frame size? Is there a frame pointer? Where do arguments land?
3. Run `quad`.
4. Diff prediction against reality, and diff the four outputs against each other.
5. For every difference, decide: *is this an ABI rule, a target feature, or a codegen
   heuristic?* Write the answer down.

Step 5 is what separates this from passive reading. Keep a lab notebook — a single
`NOTES.md` with one dated entry per exercise. You'll refer back to it constantly, and the
act of writing the classification is what makes it stick.

---

## 4. Phase 1 — ABI divergence (start here)

Most courses start with specs. Yours shouldn't, because you can *observe* the ABI. Read the
specs to explain what you saw.

### 1.1 — The four-way baseline

```c
long add(long a, long b) { return a + b; }
long many(long a, long b, long c, long d, long e, long f, long g, long h, long i);
double mix(int a, double b, int c, double d, float e);
```

Run `quad` at `-O0` and `-O2`. Annotate every instruction on every target. Where does the
9th argument go on each? Which target's `-O0` output is largest, and why?

### 1.2 — The Darwin/AAPCS64 divergence hunt

This is the marquee exercise of the phase. Your M4 Pro and your Spark run the same
instruction set with different ABIs. Find the differences empirically, then confirm against
the specs.

```c
// (a) variadics — the big one
extern int vprintf_like(const char *fmt, ...);
int call_variadic(void) { return vprintf_like("x", 1, 2L, 3.0, 'c'); }

// (b) small-type stack arguments
void takes_many_small(char a, short b, char c, short d, int e,
                      char f, short g, char h, short i, char j, short k);

// (c) narrow argument extension
extern void takes_bool(_Bool);
void pass_bool(int x) { takes_bool(x & 1); }

// (d) x18
register long r18 __asm__("x18");   // observe what each target says

// (e) long double
long double ld(long double x) { return x * 2; }
```

You should find, and be able to explain, at least these five:

1. **Variadic arguments.** AAPCS64 passes variadic arguments in registers first, spilling to
   a register save area that the callee's prologue constructs; Darwin passes *all* variadic
   arguments on the stack. Consequence: `va_list` on Linux AArch64 is a five-field struct;
   on Darwin it's essentially a `char *`. Look at both prologues of a variadic *callee* and
   note the size difference. This is the most common source of real-world AArch64 portability
   bugs.
2. **Stack argument packing.** AAPCS64 pads each stack-passed argument to an 8-byte slot;
   Darwin packs them at natural alignment. Count the stack bytes for `takes_many_small` on
   each.
3. **Narrow argument extension.** Darwin requires the caller to sign/zero-extend values
   narrower than 32 bits; AAPCS64 leaves the upper bits unspecified. Find the extra `and`/
   `uxtb` in one output and not the other, and reason about what happens when a
   Darwin-assumption callee is fed a Linux-convention caller's register.
4. **`x18`.** Reserved as the platform register on Darwin — the OS uses it, and touching it
   is a correctness bug. Free on Linux (unless shadow call stack is enabled). Try to force
   the allocator to use it on each target.
5. **`long double`.** 64-bit on Darwin (identical to `double`), 128-bit quad on Linux
   AArch64. Look at the difference in the generated multiply.

### 1.3 — x86-64 struct classification

The SysV eightbyte classification algorithm (INTEGER / SSE / MEMORY, with the merge rules)
is the fiddliest thing in this phase. Work it by hand before checking.

```c
struct Small  { int a, b; };                  // 8 bytes
struct Mixed  { int a; double b; };           // 16 bytes, two eightbytes
struct Float2 { float x, y; };                // 8 bytes, one SSE eightbyte
struct Float4 { float a, b, c, d; };
struct Big    { long a, b, c, d; };           // 32 bytes → MEMORY
struct Odd    { char a; long b; char c; };

struct Big  ret_big(int);
struct Small ret_small(int);
struct Mixed ret_mixed(int);
void takes(struct Small, struct Mixed, struct Float2, struct Big);
```

For each: predict the register/stack assignment and the return mechanism (registers vs
hidden `sret` pointer). Compare against AArch64's much simpler rules — HFAs/HVAs
(homogeneous float/vector aggregates) get passed in up to four vector registers, which is a
genuinely different design. Note that `Float4` is an HFA on AArch64 and gets four registers,
while x86-64 crams it into two SSE eightbytes.

### 1.4 — Hand-written callee, four times

Write `long sum_array(const long *p, long n)` in raw assembly for each target, using at
least three callee-saved registers. Test each on its native hardware with a C harness at
both `-O0` and `-O2`.

Then break each one — remove a single restore — and characterize the failure. You will find
that some failures are silent at `-O0` and catastrophic at `-O2`, and that the Darwin
version may fail differently because of the mandatory frame pointer.

### Read (now that you've seen it)

- [AAPCS64](https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst) §5, §6.1, §6.4
- [Apple: Writing ARM64 code for Apple platforms](https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms) — short, and it's precisely the delta you just measured
- [x86-64 System V psABI](https://gitlab.com/x86-psABIs/x86-64-ABI) ch. 3.2

**Checkpoint:** Given a C signature, you can write the register allocation for Darwin arm64,
AAPCS64, and SysV x86-64 from memory, and explain every place the two AArch64 ABIs disagree.

---

## 5. Phase 2 — Frame layout and the frame pointer

### 2.1 — Is the frame pointer optional?

```c
long leaf(long x) { return x * 3; }
long calls(long x) { return opaque(x) + 1; }
```

Compile at `-O2` **with and without** `-fomit-frame-pointer` on all four targets. You should
discover that Darwin arm64 emits the frame record (`stp x29, x30` + `mov x29, sp`)
regardless — Apple's ABI mandates a valid frame pointer chain — while Linux AArch64 and both
x86-64 targets will happily elide it.

Now reason about the consequences. Apple gets free, reliable, sampling-profiler-safe
backtraces at a cost of two instructions and 16 bytes per frame. Linux gets a marginally
faster function call and needs `.eh_frame` parsing to unwind. This is one of the more
consequential ABI trade-offs in wide deployment, and you can measure both sides of it.

### 2.2 — Walk the chain by hand

In `lldb` on the M4 Pro and `gdb` on the Spark, manually walk the saved frame-pointer chain
three frames deep — read `$x29`, dereference, find the saved `x30` beside it — without using
`bt`. Then write it programmatically:

```c
void naive_backtrace(void);   // walk the FP chain, print return addresses
```

Test on all four. It will work unconditionally on macOS. On the others it works only in
frame-pointer builds, and you can demonstrate exactly how it breaks. Keep this function —
you'll extend it in Phase 4.

On AArch64, also strip pointer-authentication bits from the return address before printing
(`ptrauth_strip` on Darwin, or mask the top bits) — a preview of Phase 6.

### 2.3 — Frame growth and probing

```c
long f(long n) { char buf[N]; escape(buf); return n; }
```

Sweep `N` over `8, 100, 1024, 4096, 65536, 1000000` across all four targets. Tabulate frame
size and prologue instruction count. Find:

- The x86-64 red zone (128 bytes below `rsp` usable without adjustment in leaf functions) —
  and confirm AArch64 has no equivalent
- Where AArch64 switches from an immediate `sub sp, sp, #N` to materializing the constant
- Where `-fstack-clash-protection` (Linux targets) introduces a probe loop, and why skipping
  the guard page is a security problem

### 2.4 — Dynamic and over-aligned frames

```c
void vla(int n)   { char buf[n]; escape(buf); }
void aligned(void){ _Alignas(64) char buf[64]; escape(buf); }
void both(int n)  { _Alignas(64) char a[64]; char b[n]; escape(a); escape(b); }
```

Find where the frame pointer becomes *mandatory* rather than merely conventional. On x86-64,
find the stack realignment sequence (`and rsp, -64`) and the base-register dance that
follows. Explain why `rsp`-relative addressing of locals stops working once `alloca` is in
play.

**Checkpoint:** You can look at a function's locals and predict its frame size and whether it
needs a frame pointer, on all four targets.

---

## 6. Phase 3 — Callee-saved registers, spills, and vectors

### 3.1 — The spill ramp

Generate a family of functions with increasing live-across-call pressure:

```c
long f_N(long a0, long a1, /* ... */) {
    /* compute from all args, call opaque(), then combine all args */
}
```

Script this for N = 2, 4, 6, 8, 12, 16, 24. At `-O2` on each target, tabulate CSR count and
frame size, and plot it. AArch64 has eleven integer CSRs (`x19`–`x29`) against x86-64's five
(`rbx`, `rbp`, `r12`–`r15`) — you should see the x86 curve bend into stack spills much
earlier. That register-count difference is one of the more visible practical consequences of
the two ISAs.

### 3.2 — Vector callee-saved registers

A genuinely instructive asymmetry:

- **SysV x86-64:** *no* vector register is callee-saved
- **AAPCS64 / Darwin:** the low 64 bits of `v8`–`v15` are callee-saved — the upper halves are
  not

Construct a function that demonstrates the AArch64 half-register rule biting: hold a full
128-bit value in `v8` across a call and watch the compiler spill rather than rely on the
partial guarantee. Then compare against Win64, where `xmm6`–`xmm15` are fully callee-saved.

### 3.3 — AVX-512 and forced realignment (AMD box)

If your AMD part is Zen 4 or Zen 5, it has full AVX-512; many contemporary Intel consumer
parts do not. Use that asymmetry:

```c
void wide(float *restrict a, float *restrict b, long n) {
    for (long i = 0; i < n; i++) a[i] = a[i] * b[i] + 1.0f;
}
```

Compile with `-march=znver4 -O3` and `-march=x86-64-v3 -O3`. When 64-byte ZMM spill slots
appear, watch the frame alignment requirement jump to 64 and stack realignment appear
*without you asking for it*. This is the cleanest demonstration that frame layout is driven
by register allocation results, not by source-level declarations — which is exactly why PEI
must run after the allocator.

---

## 7. Phase 4 — Unwind information (three formats)

The hardest phase, and the one that pays off most. Your lab is unusually well suited to it
because you have three formats side by side.

### The core idea

Unwind info is a **table indexed by program counter**, stating where the canonical frame
address is and where each saved register lives — at *every* instruction boundary, including
partway through a prologue, because a signal or an exception can arrive there.

### 4.1 — Read the DWARF table (Spark, x86 boxes)

```bash
readelf --debug-dump=frames-interp ./a.out
llvm-dwarfdump --eh-frame ./a.out
```

Pick one function. Map each row of the decoded table to a specific instruction in the
disassembly. Confirm the CFA offset changes exactly where the prologue adjusts the stack.

### 4.2 — Compact unwind (M4 Pro)

macOS uses `__TEXT,__unwind_info` — a compressed two-level page table — as its primary
format, falling back to DWARF `.eh_frame` only for functions whose frames can't be described
by the compact encoding.

```bash
llvm-objdump --macho --unwind-info ./a.out
llvm-dwarfdump --eh-frame ./a.out          # the fallback entries only
```

Note that the assembly still contains `.cfi_*` directives — the assembler synthesizes compact
entries from them where it can.

Your exercise: **find a function that forces the DWARF fallback.** Try large frames, dynamic
`alloca`, unusual CSR sets, and stack realignment. Then read
`llvm/lib/MC/MCObjectFileInfo.cpp` and `llvm/lib/Target/AArch64/AArch64AsmPrinter.cpp` plus
`AArch64FrameLowering`'s compact-unwind encoder to see what the encoding can and cannot
express. This tells you a lot about which frame shapes Apple considers "normal."

Compare the total unwind-section size for the same program on macOS vs Linux. The compression
argument for compact unwind becomes obvious immediately.

### 4.3 — Hand-written CFI

Take your `sum_array` implementations from 1.4 and add correct `.cfi_startproc`,
`.cfi_def_cfa_offset`, `.cfi_offset`, `.cfi_def_cfa_register`, `.cfi_endproc`. Verify on each
platform by:

- Breaking inside and confirming a correct debugger backtrace
- Calling it from C++ with a callback that throws, and confirming the exception propagates

Then remove the CFI and watch the throw become `std::terminate`. Then make the CFI *subtly*
wrong — an off-by-8 CFA — and observe that it corrupts backtraces rather than failing
cleanly. That failure mode is why this material matters in production.

### 4.4 — Async-correct prologues

Write a multi-instruction prologue whose CFI is correct at every intermediate instruction,
not merely at the end. Test by delivering a signal mid-prologue: a tight `SIGPROF` interval
timer plus a handler that backtraces will hit it within seconds. Do this on both AArch64
platforms and note how the mandatory Darwin frame pointer changes what "correct" requires.

### 4.5 — Optional: Windows

If either x86 box runs Windows, dump `.pdata`/`.xdata` with `llvm-readobj --unwind`. The
Win64 model is *structural* rather than tabular — the unwind codes describe a canonical
prologue shape, and the epilogue must match a restricted grammar so the unwinder can
recognize it by decoding instructions. Contrast this with DWARF's fully general approach and
consider the trade-off in table size, generality, and codegen freedom.

**Checkpoint:** You can explain why `-fasynchronous-unwind-tables` is the default on Linux
x86-64, what compact unwind gives up to gain compression, and why Windows constrains epilogue
shape.

---

## 8. Phase 5 — Epilogues, tail calls, shrink-wrapping

### 5.1 — Counting epilogues

A function with five `return` statements, at `-O0` and `-O2`, on all four targets. Where does
the compiler funnel returns through a shared exit block, and where does it duplicate?

### 5.2 — Tail calls

```c
long a(long x);
long b(long x) { return a(x + 1); }                        // sibling call
long c(long x) { return a(x + 1) + 1; }                    // not a tail call
long d(long x) { char buf[1000]; escape(buf); return a(x); } // can it?
long e(long x) { return a(x); }                            // with __attribute__((noreturn))?
```

At `-O2`, explain each result on each target. Then use `[[clang::musttail]]` and find a case
that produces a hard error — the diagnostic states an ABI rule you should be able to derive.

Pay attention to how tail calls interact with the Darwin mandatory frame pointer, and with
pointer authentication (a `retaa`-signed return address complicates tail-call sequences).

### 5.3 — Shrink-wrapping

```c
long f(long *p, long n) {
    if (n == 0) return 0;               /* cheap early exit */
    /* heavy work: many live values, large locals */
}
```

At `-O2`, confirm the prologue is *not* at function entry. Compare against
`-mllvm -enable-shrink-wrap=false`. Then look at the resulting CFI and appreciate how much
harder shrink-wrapping makes the unwind tables — and check whether the macOS build could
still use compact unwind, or was forced to DWARF.

---

## 9. Phase 6 — Hardening

For each feature: same function, with and without, diff prologue and epilogue, explain the
threat model and the cost. Your lab covers essentially the whole modern matrix.

| Feature | Where | Flag | Look for |
|---|---|---|---|
| Stack protector | all | `-fstack-protector-strong` | canary from `fs:[0x28]` (x86) / `tpidr_el0` or `__stack_chk_guard` (AArch64) |
| Stack clash | Linux | `-fstack-clash-protection` | page-by-page probe loop |
| Intel CET IBT | Intel | `-fcf-protection=full` | `endbr64` at entry and indirect targets |
| Shadow stack | Intel + Zen 3+ | `-fcf-protection=full`, kernel support | `SSP` handling; check `lscpu` for `shstk` |
| PAC | both AArch64 | `-mbranch-protection=pac-ret` | `paciasp`/`autiasp`, or `retaa` fused |
| BTI | both AArch64 | `-mbranch-protection=bti` | `bti c` at entry |
| Shadow call stack | Linux AArch64 | `-fsanitize=shadow-call-stack` | `x18`-relative LR store — **note this is impossible on Darwin**, since `x18` is reserved |
| Profiling hooks | all | `-pg` / `-fentry` | `mcount` / `__fentry__` placement relative to frame setup |

### 6.1 — The `x18` collision

Work out why Linux AArch64 can implement shadow call stack using `x18` and Darwin cannot,
and what Apple uses instead (pointer authentication of the return address, plus `arm64e` for
system binaries). This is a nice worked example of an ABI decision closing off a security
implementation strategy years later.

### 6.2 — PAC on real hardware

Both AArch64 machines support pointer authentication. Compile with `-mbranch-protection=pac-ret`
and:

- Find `paciasp`/`autiasp` (or the fused `retaa`)
- Confirm your Phase 2 hand-written backtracer now prints garbage, and fix it by stripping
  authentication bits
- Deliberately corrupt a saved return address at runtime and observe the authentication
  failure fault rather than a successful hijack

---

## 10. Phase 7 — Inside LLVM

Now connect everything to the code that produced it. You already have the build.

### 7.1 — Watch PEI run, four times

```bash
B=$HOME/llvm-project/build/bin
$B/clang --target=aarch64-unknown-linux-gnu -O2 -S -emit-llvm test.c -o test.ll

$B/llc -mtriple=aarch64-unknown-linux-gnu \
       -print-before=prologepilog -print-after=prologepilog test.ll 2>&1 | less
```

In the "before" MachineIR, find the abstract frame references (`%stack.0`, `%stack.1`) and
the `ADJCALLSTACKDOWN`/`ADJCALLSTACKUP` pseudos. In the "after", find what each became.
Trace one specific stack object all the way from an IR `alloca`, through `MachineFrameInfo`,
to a concrete `[sp, #40]`.

Then do the same with `-mtriple=arm64-apple-macosx15.0` on identical IR and diff the
MachineIR. Same target backend, different ABI — you're now seeing where in the code the
Phase 1 differences are decided.

Other useful invocations:

```bash
$B/llc -stop-after=prologepilog test.ll -o test.mir     # freeze the MIR
$B/llc -print-machineinstrs test.ll                      # full pipeline
$B/llc -debug-only=frame-info test.ll                    # needs assertions build
$B/llc -mtriple=... -run-pass=prologepilog test.mir      # replay just PEI
```

That last one is the real workhorse: `-run-pass` lets you take a frozen `.mir` file, tweak it
by hand, and rerun a single pass. It's how LLVM's own regression tests for this area work —
look at `llvm/test/CodeGen/AArch64/framelayout-*.mir` for dozens of worked examples.

### 7.2 — Read the source, in this order

1. `llvm/include/llvm/CodeGen/MachineFrameInfo.h` — the frame object model. Read this
   properly; everything else assumes it.
2. `llvm/lib/CodeGen/PrologEpilogInserter.cpp` — start at `runOnMachineFunction`, then
   `calculateCalleeSavedRegisters`, `calculateFrameObjectOffsets`, `replaceFrameIndices`,
   `insertPrologEpilogCode`.
3. `llvm/lib/Target/AArch64/AArch64FrameLowering.cpp` — **the comment block at the top of
   this file is one of the best frame-layout documents in existence.** Read it with your
   Phase 2 disassembly beside you and match each described layout to output you generated.
4. `llvm/lib/Target/X86/X86FrameLowering.cpp` — `emitPrologue`. Long and full of special
   cases; read it against real output rather than straight through.
5. `llvm/lib/CodeGen/ShrinkWrap.cpp` — the dominance/post-dominance computation.
6. `llvm/lib/CodeGen/RegisterScavenging.cpp` — see 7.4.

Also read `AArch64Subtarget::isTargetDarwin()` call sites, and
`llvm/lib/Target/AArch64/AArch64CallingConv.td`. The TableGen file is where the Phase 1
divergences you measured are literally written down — finding your five empirical findings in
the `.td` source is a satisfying loop closure.

### 7.3 — Instrument it

Add a debug print to `calculateFrameObjectOffsets` reporting each frame object's index, size,
alignment, and assigned offset. Rebuild, run it on your Phase 2 test cases across all four
targets, and confirm the numbers match assembly you already analyzed by hand. This is the
moment the abstraction stops being a black box.

### 7.4 — Register scavenging

Construct an AArch64 function with a frame large enough that stack offsets don't fit a
load/store immediate field. Find the scavenged scratch register and the address
materialization. Then read `RegisterScavenging.cpp` to see how that register was chosen and
what happens when none is free (spill-to-emergency-slot — and find where the emergency spill
slot was reserved, back in PEI).

### 7.5 — Write a real test

Contribute-quality exercise: write a `.mir` test in the style of
`llvm/test/CodeGen/AArch64/framelayout-*.mir` that pins down one behavior you discovered
empirically in Phase 1 or 2. Run it under `llvm-lit`. Even if you never upstream it, writing
a passing MIR test forces exactness that reading never will.

---

## 11. Phase 8 — Scalable vectors (the advanced track)

This is where your specific hardware gets you something most people can't easily reach:
frames whose *layout is not known at compile time*.

### 8.1 — SVE frames on the Spark

Armv9 mandates SVE2, so your Spark's Cortex-X925/A725 cores have it (verify: `sve2` in
`/proc/cpuinfo` Features; determine the vector length at runtime with `rdvl x0, #1` or by
reading `ZCR_EL1`-derived values — likely 128-bit on these cores, but *measure* it).

```c
#include <arm_sve.h>
svfloat32_t f(svfloat32_t a, svfloat32_t b, float32_t *p) {
    svbool_t pg = svptrue_b32();
    svfloat32_t c = svmla_f32_x(pg, a, b, b);
    escape(p);                       // force a call, forcing SVE spills
    return c;
}
```

Compile with `-march=armv9.2-a+sve2 -O2`. In the prologue, find:

- `addvl sp, sp, #-N` — stack adjustment in units of the *runtime* vector length
- `addpl` — the same for predicate registers (VL/8)
- `str z8, [sp, #1, mul vl]` — vector-length-scaled addressing
- `.cfi_escape` directives — because the CFA offset is no longer a constant, LLVM must emit a
  DWARF *expression* involving the `VG` pseudo-register (AArch64 DWARF register 46, holding
  the vector granule count) rather than a plain offset

That last point is the payoff. Decode one `.cfi_escape` byte sequence by hand against the
DWARF 5 expression opcode table. You will come away understanding CFI as a small programming
language rather than a table of numbers, which is the correct mental model.

Then read the SVE sections of `AArch64FrameLowering.cpp` — the callee-saved SVE area is laid
out separately from the fixed-size area precisely because their sizes can't be added at
compile time.

### 8.2 — SME on the M4 Pro (if available)

Check `sysctl hw.optional.arm.FEAT_SME` and `FEAT_SME2`. If present, you have access to
Streaming SVE mode and the ZA array, whose ABI involves genuinely novel frame concepts:
streaming-mode transitions (`smstart`/`smstop`), the lazy-save scheme for ZA state, the
`TPIDR2` block, and `__arm_new("za")` / `__arm_streaming` / `__arm_locally_streaming` function
attributes in Clang.

```c
__arm_locally_streaming void f(void) __arm_new("za") { /* ... */ }
```

Look at what the prologue must now do: allocate a ZA save buffer whose size is
VL-dependent-squared, set up `TPIDR2`, and transition modes. Read
`llvm/lib/Target/AArch64/AArch64FrameLowering.cpp`'s SME handling and the
[AAPCS64 SME ABI supplement](https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst).

This is close to the frontier of what production compilers do with frames, and having the
hardware to actually run it is rare.

---

## 12. Capstones (pick one or two)

### A — A real unwinder, three formats

Extend your Phase 2 backtracer into a library that unwinds *without* frame pointers, by
parsing:

- `.eh_frame` on the Spark and both x86 boxes (CFA rules, register rules, DWARF expressions)
- `__unwind_info` compact entries on the M4 Pro, with DWARF fallback
- optionally `.pdata`/`.xdata` if you added Windows

Test against deep recursion, shrink-wrapped functions, hand-written assembly, SVE frames with
`.cfi_escape`, and PAC-signed return addresses. Compare against `libunwind`.

If Phase 4 landed, this is achievable. If it didn't, this will reveal exactly where.

### B — A JIT with correct frames

Emit machine code at runtime for a small expression language, on all four targets. Emit
correct prologues, epilogues, and unwind info — registered via `__register_frame` on Linux —
such that debuggers can walk through your generated frames and C++ exceptions propagate
through them. The macOS path will teach you why dynamic code and compact unwind interact
awkwardly.

### C — Stack switching

Implement `setjmp`/`longjmp` from scratch in assembly for AArch64 (both ABIs) and x86-64, then
extend to a stackful coroutine switch. You must reason about which registers to save, what
the unwinder believes is happening, how signal stacks interact, and — on AArch64 — how
pointer authentication and the shadow call stack complicate switching stacks at all. Compare
your result against `boost::context`'s assembly.

### D — Back to where you started

Write an LLVM pass that inserts a runtime check at function entry and on every normal return
path — a hand-rolled version of C++26 contract lowering. Requirements:

- The postcondition check runs after the return value is materialized, and survives NRVO
- It does **not** run on exception paths
- It survives `-O2`, multiple returns, tail-call opportunities, and shrink-wrapping
- The handler call can throw without corrupting the frame or the unwind tables

Then verify on all four targets, and compare against GCC's experimental `-fcontracts`.
Checking that your postcondition still fires correctly on a shrink-wrapped, PAC-signed,
compact-unwound Darwin function is a genuinely stringent test — and it closes the loop on the
question that started this: you'll see concretely why "prologue and epilogue" was the wrong
mental model.

---

## 13. Suggested sequencing

You don't need equal time on all four platforms. A workable allocation:

- **Phases 1–2:** all four targets, every exercise. This is where the differential method
  pays the most.
- **Phase 3:** AArch64 pair for register pressure; AMD box for the AVX-512 realignment work.
- **Phase 4:** M4 Pro and Spark primarily (the format contrast is the lesson); x86 for a
  third `.eh_frame` data point.
- **Phase 5:** all four — tail-call legality genuinely differs.
- **Phase 6:** Intel for CET, AMD for shadow stack, both AArch64 for PAC/BTI, Spark alone for
  shadow call stack.
- **Phase 7:** M4 Pro as the build machine, targeting everything.
- **Phase 8:** Spark for SVE, M4 Pro for SME.

Rough effort: Phases 1–2 are 6–10 hours each given four targets; Phase 4 is the longest at
10–15; Phases 3, 5, 6 are 4–6 each; Phase 7 is 8–12; Phase 8 is open-ended.

---

## 14. Reference shelf

**Specifications**
- [AAPCS64](https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst)
- [Apple: Writing ARM64 code for Apple platforms](https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms)
- [x86-64 System V psABI](https://gitlab.com/x86-psABIs/x86-64-ABI)
- [Microsoft x64 calling convention](https://learn.microsoft.com/en-us/cpp/build/x64-software-conventions)
- [Itanium C++ ABI](https://itanium-cxx-abi.github.io/cxx-abi/abi.html) — exceptions, object layout
- DWARF 5, ch. 6.4 (Call Frame Information) and ch. 2.5 (expressions)
- [Arm A64 ISA reference](https://developer.arm.com/documentation/ddi0602/latest)
- Intel SDM Vol. 2; AMD APM Vol. 3

**In your own tree** — these are underrated as documentation:
- `llvm/lib/Target/AArch64/AArch64FrameLowering.cpp` (top comment block)
- `llvm/lib/Target/AArch64/AArch64CallingConv.td`
- `llvm/docs/CodeGenerator.rst`
- `llvm/test/CodeGen/AArch64/framelayout-*.mir`

**Writing**
- Ian Lance Taylor's [`.eh_frame` series](https://www.airs.com/blog/archives/460)
- Bryant & O'Hallaron, *CS:APP* ch. 3 — best on-ramp if any of Phase 1 feels shaky
- Agner Fog, *Optimizing Subroutines in Assembly Language*

---

## 15. Pitfalls

- **Comparing across different compilers by accident.** Use your one built clang for all
  comparison work. Apple Clang, distro GCC, and your build differ in version *and* defaults;
  mixing them silently attributes compiler differences to ABI differences. Introduce other
  compilers deliberately, as a separate axis, later.
- **Forgetting macOS defaults differ.** Apple Clang enables things your build doesn't
  (and vice versa) — stack protector defaults, PAC on `arm64e`, deployment-target-dependent
  behavior. Always pass flags explicitly rather than relying on defaults.
- **Studying only `-O0`.** Shrink-wrapping, tail calls, and frame-pointer elimination — the
  interesting parts — only appear with optimization.
- **Trusting a passing test.** ABI violations frequently work by accident at one optimization
  level on one platform. Your four-platform lab is the antidote: test everything everywhere,
  at `-O0` and `-O2`.
- **Reading LLVM source before the assembly.** `X86FrameLowering.cpp` is nearly opaque until
  you already know what output it should produce. Do Phases 1–6 first.
- **Treating CFI as decoration.** It's a program, and it's where most "my hand-written
  assembly mysteriously breaks exceptions" bugs live.
- **Skipping the prediction step.** It feels slow and it is the entire method.