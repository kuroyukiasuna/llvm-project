# Implementing `-fsanitize=unaligned-pointer-subtraction`

Notes & learnings from adding a new UndefinedBehaviorSanitizer (UBSan) check to
Clang + compiler-rt. Tracks LLVM issue #206775.

---

## 0. Glossary (acronyms up front)

| Term | Meaning |
|------|---------|
| **UB** | Undefined Behavior — the C/C++ standard imposes no requirements; the compiler may assume it never happens and optimize accordingly. |
| **UBSan** | UndefinedBehaviorSanitizer — a set of *runtime* checks that detect UB during execution and print a diagnostic. Part of `-fsanitize=undefined`. |
| **IR** | Intermediate Representation — LLVM's typed SSA instruction language that Clang lowers C/C++ into before optimization/codegen. |
| **ABI** | Application Binary Interface — the binary contract (symbol names, argument layout) between the compiler-emitted call and the runtime library. |
| **VLA** | Variable-Length Array — a C array whose size is a runtime value, e.g. `int a[n]`. Standard in C99; only a GNU *extension* in C++. |
| **ptrdiff_t** | The signed integer type that results from subtracting two pointers. |
| **GEP** | `getelementptr` — the LLVM IR instruction for pointer arithmetic (address computation). |
| **SSA** | Static Single Assignment — each IR value is assigned exactly once. |
| **RAII** | Resource Acquisition Is Initialization — C++ idiom where a scoped object sets up/tears down state in its ctor/dtor (used by the sanitizer scope objects). |
| **lipo** | macOS tool that combines per-architecture object files into one "fat"/universal binary. |
| **SDK** | Software Development Kit — here, the macOS system headers/libraries under `MacOSX.sdk`, located via `xcrun --show-sdk-path`. |

---

## 1. The problem this check detects

C/C++ define `p - q` only when both pointers point into the **same array
object**. That rule guarantees the byte distance between them is an exact
multiple of the element size (array elements sit at `0, size, 2*size, …`), so
the "how many elements apart" division is always exact.

Violating example (the issue's case):

```c
typedef struct { int x, y; } A;        // sizeof(A) == 8
long f(int *p) { return (A *)(p + 1) - (A *)p; }   // byte distance 4, not a multiple of 8 → UB
```

Clang already **relies** on this rule: it lowers `p - q` with `sdiv exact`
(exact signed division). The `exact` flag promises the remainder is zero; if it
isn't, the result is **poison** and the optimizer may miscompile. The check adds
a runtime test that the byte distance really is a multiple of the element size.

Relationship to the companion flag `-fstable-pointer-subtraction` (PR #196392):
that flag drops `exact` (plain `sdiv`) to *define* the behavior for low-level
code. This sanitizer is the opposite audience — it *reports* the UB so you can
fix it. Same structure as `-fwrapv` (defines signed overflow) vs
`-fsanitize=signed-integer-overflow` (detects it).

**Naming caveat:** "unaligned" here means the *distance* isn't a multiple of
`sizeof(element)`. This is NOT the same as `-fsanitize=alignment`, which checks a
pointer address against its type's `alignof`. `sizeof != alignof` (e.g.
`struct{int x,y;}` has `sizeof 8`, `alignof 4`), so two properly-aligned pointers
can still fail this check. Worth stating explicitly in the docs.

---

## 2. Why this lives in CodeGen + runtime, not the frontend

The frontend pipeline for `p - q`:

- **Lexer** (`clang/lib/Lex/Lexer.cpp`) — turns the byte `-` into `tok::minus`. No type knowledge.
- **Parser** (`clang/lib/Parse/ParseExpr.cpp`, `ParseRHSOfBinaryExpression`) — assembles the `BinaryOperator` by operator precedence; calls `Actions.ActOnBinOp`.
- **Sema** (`clang/lib/Sema/SemaExpr.cpp`, `CheckSubtractionOperands`) — type-checks: requires compatible pointee types, sets the result type to `ptrdiff_t`. Only checks **static** properties.

The frontend **cannot** catch this bug: whether the byte distance is a multiple
of the element size depends on **runtime pointer values**. In the issue's
example both operands are `A*`, so Sema is perfectly happy — the UB slips
through silently. Hence the check must be a *runtime* check emitted in CodeGen,
with a runtime library to report it.

---

## 3. Architecture: two registries + three layers

### Two registries (they answer different questions)

| File | Question it answers | What we add |
|------|--------------------|-------------|
| `clang/include/clang/Basic/Sanitizers.def` | "What can `-fsanitize=` turn on?" | `SANITIZER("unaligned-pointer-subtraction", UnalignedPointerSubtraction)` + add to the `undefined` group |
| `clang/lib/CodeGen/SanitizerHandler.h` | "Which `__ubsan_handle_*` routines does CodeGen call inline?" | one `SANITIZER_CHECK(...)` line |

Pass-based sanitizers (ASan/TSan/MSan) are instrumented by LLVM IR *passes* and
are absent from `SanitizerHandler.h`. UBSan checks are emitted **inline by Clang
CodeGen** at the operation site (where the element size / types are known), so
each needs an entry there.

`SANITIZER_CHECK(Enum, Name, Version, Msg)` is the single source of truth for:
- the `SanitizerHandler::Enum` value,
- the runtime symbol `__ubsan_handle_<Name>` (built in `CGExpr.cpp`),
- the ABI version suffix (`_v<N>`),
- the **trap message** (used in trap mode / minimal runtime).

### Three layers

1. **Detection** — Clang CodeGen emits the runtime test inline (cheap, per-site).
2. **Dispatch** — `EmitCheck` emits a cold conditional branch to a call of `__ubsan_handle_*`.
3. **Reaction** — the compiler-rt handler formats + prints the diagnostic (expensive, shared, one copy in the runtime lib).

Analogy: `assert` — the `if (!cond)` is inline at each site; `__assert_fail`
(print + abort) is one shared library function. UBSan is the same, with a fancier
handler.

---

## 4. The CodeGen side (detection)

Entry chain for a scalar `p - q`:

```
CodeGenFunction::EmitScalarExpr            (CGExprScalar.cpp)
  → ScalarExprEmitter::Visit               → StmtVisitor dispatch on BO_Sub
  → VisitBinSub                            (generated by HANDLEBINOP(Sub) macro)
  → EmitBinOps (evaluate LHS/RHS) + EmitSub
  → EmitSub: both-operands-pointer branch  ← our check lives here
```

The both-pointers branch computes the byte distance and divides by the element
size. We insert the check just before the `sdiv exact`:

```cpp
// clang/lib/CodeGen/CGExprScalar.cpp  (inside EmitSub, ptr - ptr branch)
if (CGF.SanOpts.has(SanitizerKind::UnalignedPointerSubtraction)) {
  auto checkOrdinal = SanitizerKind::SO_UnalignedPointerSubtraction;
  auto CheckHandler = SanitizerHandler::UnalignedPointerSubtraction;
  SanitizerDebugLocation SanScope(&CGF, {checkOrdinal}, CheckHandler);

  llvm::Value *Zero    = llvm::ConstantInt::get(CGF.PtrDiffTy, 0);
  llvm::Value *Rem     = Builder.CreateSRem(diffInChars, divisor, "sub.ptr.rem");
  llvm::Value *IsExact = Builder.CreateICmpEQ(Rem, Zero, "sub.ptr.exact");

  llvm::Constant *StaticArgs[] = {
      CGF.EmitCheckSourceLocation(op.E->getExprLoc()),
      CGF.EmitCheckTypeDescriptor(op.E->getType())};   // ptrdiff_t (signed)
  llvm::Value *DynamicArgs[] = {diffInChars, divisor};
  CGF.EmitCheck({{IsExact, checkOrdinal}}, CheckHandler, StaticArgs, DynamicArgs);
}
return Builder.CreateExactSDiv(diffInChars, divisor, "sub.ptr.div");
```

Key points:
- **Condition is "true when OK":** `EmitCheck` fires the handler on the *false*
  branch, so we pass `remainder == 0`, not `!= 0`.
- **Two enums:** `SanitizerKind::SO_*` (the *ordinal*, keys `-fsanitize-recover`/
  `-fsanitize-trap`) vs `SanitizerHandler::*` (names the runtime function).
- **`SanitizerDebugLocation`** opens the sanitizer scope (`EmitCheck` asserts it).
- **StaticArgs** → baked into a private global, become the handler's `Data*`
  struct. **DynamicArgs** → runtime values passed as `intptr_t`.
- **Placement matters:** it sits after the two early-returns for element size 1
  and `void*`/function pointers (nothing to check there), and it also handles the
  VLA path for free because it just uses whatever `divisor` is.

### Resulting IR (constant element size 8)

```llvm
%sub.ptr.lhs.cast = ptrtoint ptr %add.ptr to i64
%sub.ptr.rhs.cast = ptrtoint ptr %1 to i64
%sub.ptr.sub  = sub i64 %sub.ptr.lhs.cast, %sub.ptr.rhs.cast   ; byte distance
%sub.ptr.rem  = srem i64 %sub.ptr.sub, 8, !nosanitize
%sub.ptr.exact = icmp eq i64 %sub.ptr.rem, 0, !nosanitize
br i1 %sub.ptr.exact, label %cont, label %handler.unaligned_pointer_subtraction, !prof !N, !nosanitize
handler.unaligned_pointer_subtraction:                          ; cold (branch weights)
  call void @__ubsan_handle_unaligned_pointer_subtraction(ptr @0, i64 %sub.ptr.sub, i64 8)
  br label %cont                                                ; or `unreachable` for the _abort variant
cont:
  %sub.ptr.div = sdiv exact i64 %sub.ptr.sub, 8
```

### LLVM IR instructions / intrinsics involved

| IR | Role |
|----|------|
| `ptrtoint` | Cast each pointer to an integer so we can subtract byte addresses. |
| `sub` | Byte distance between the two pointers (`sub.ptr.sub`). |
| `srem` | Signed remainder of distance ÷ element size — our test (`== 0` means valid). |
| `icmp eq` | Compare remainder to 0 → the check condition. |
| `br` (conditional) + `!prof` branch weights | Skip to `cont` when OK; jump to the cold handler block otherwise. |
| `!nosanitize` metadata | Marks the check's own instructions so they aren't themselves instrumented. |
| `sdiv exact` | The original element-count division; `exact` ⇒ non-zero remainder is **poison** — the UB this check guards. |
| `call @__ubsan_handle_*` | The dispatch into compiler-rt (see §5). |
| `@llvm.ubsantrap` | Used **instead** of the call in trap mode (`-fsanitize-trap=`); emits `brk`/`ud2`, no runtime lib needed, no message. |

Where the call is actually emitted: `EmitCheck` (`clang/lib/CodeGen/CGExpr.cpp`)
builds the cond-branch and cold block, then `emitCheckHandlerCall` constructs the
name `"__ubsan_handle_" + Name` (+ `_abort` for fatal, `_v<N>`, `_minimal`,
`_preserve` suffixes) and emits the `call`.

---

## 5. How compiler-rt (the runtime) works

The emitted call is just an `extern "C"` declaration; the definition lives in the
runtime library, linked by **name + argument layout** (nothing checks this at
compile time — keep them in sync by hand). Three files:

### 5a. `compiler-rt/lib/ubsan/ubsan_checks.inc` — the check registry (X-macro)

```cpp
UBSAN_CHECK(UnalignedPointerSubtraction, "unaligned-pointer-subtraction",
            "unaligned-pointer-subtraction")
```
Generates `ErrorType::UnalignedPointerSubtraction` (via `ubsan_diag.h`) **and**
the runtime→`-fsanitize=`-flag-name mapping used by `ignoreReport` to honor
recover/suppress settings. Arg 3 must exactly match the `Sanitizers.def` flag
name. Add this **first** — the handler won't compile without the `ErrorType`.

### 5b. `compiler-rt/lib/ubsan/ubsan_handlers.h` — data struct + declaration

```cpp
struct UnalignedPointerSubtractionData {
  SourceLocation Loc;
  const TypeDescriptor &Type;   // order must match StaticArgs: Loc, then Type
};
RECOVERABLE(unaligned_pointer_subtraction, UnalignedPointerSubtractionData *Data,
            ValueHandle Diff, ValueHandle EltSize)
```
The `RECOVERABLE` macro auto-declares **both** `__ubsan_handle_...` and
`..._abort`. The struct fields map positionally onto the CodeGen `StaticArgs`;
the two `ValueHandle`s map onto `DynamicArgs = {diffInChars, divisor}`. A
`const TypeDescriptor&` is a pointer under the hood — matches the type-descriptor
global Clang emits (identical shape to `OverflowData`).

### 5c. `compiler-rt/lib/ubsan/ubsan_handlers.cpp` — implementation

```cpp
static void handleUnalignedPointerSubtractionImpl(
    UnalignedPointerSubtractionData *Data, ValueHandle Diff,
    ValueHandle EltSize, ReportOptions Opts) {
  SourceLocation Loc = Data->Loc.acquire();          // read loc + mark for dedup
  ErrorType ET = ErrorType::UnalignedPointerSubtraction;
  if (ignoreReport(Loc, Opts, ET)) return;           // honor suppress/recover flags
  ScopedReport R(Opts, Loc, ET);                     // locks, prints SUMMARY, exit policy
  Diag(Loc, DL_Error, ET,
       "pointer subtraction with byte distance %0 that is not a multiple of "
       "the element size %1")
      << Value(Data->Type, Diff) << (unsigned long long)EltSize;
}

void __ubsan::__ubsan_handle_unaligned_pointer_subtraction(/*…*/) {
  GET_REPORT_OPTIONS(false); handleUnalignedPointerSubtractionImpl(/*…*/);
}
void __ubsan::__ubsan_handle_unaligned_pointer_subtraction_abort(/*…*/) {
  GET_REPORT_OPTIONS(true);  handleUnalignedPointerSubtractionImpl(/*…*/); Die();
}
```

- **recover vs abort:** default clang picks the non-`_abort` symbol → prints and
  continues. `-fno-sanitize-recover=…` picks `_abort` → prints then `Die()`
  (SIGABRT, exit 134).
- **Signed display:** `Diff` is a signed `ptrdiff_t`; `Diag` has no signed
  overload, so `(unsigned long long)Diff` would misprint negatives. The idiomatic
  fix is `Value(Data->Type, Diff)` — `Value` pairs the raw handle with the
  `TypeDescriptor` and formats using `Type.isSignedIntegerTy()`, exactly like the
  integer-overflow handlers. `EltSize` stays `unsigned long long` (a size is
  always positive — matches how alignments/sizes are printed elsewhere; no fix
  needed there).

---

## 6. Files changed (the patch)

```
clang/include/clang/Basic/Sanitizers.def     flag + `undefined` group membership
clang/lib/CodeGen/SanitizerHandler.h         SANITIZER_CHECK entry (enum/name/msg)
clang/lib/CodeGen/CGExprScalar.cpp           EmitCheck in EmitSub (ptr - ptr branch)
compiler-rt/lib/ubsan/ubsan_checks.inc       UBSAN_CHECK (ErrorType + flag mapping)
compiler-rt/lib/ubsan/ubsan_handlers.h       Data struct + RECOVERABLE decl
compiler-rt/lib/ubsan/ubsan_handlers.cpp     handler impl (+ _abort)
compiler-rt/lib/ubsan/ubsan_interface.inc    register __ubsan_handle_* interface symbols
compiler-rt/lib/ubsan_minimal/ubsan_minimal_handlers.cpp  HANDLER() for the _minimal runtime
```
The three names must stay in lockstep: flag `unaligned-pointer-subtraction` →
enum `UnalignedPointerSubtraction` → symbol `__ubsan_handle_unaligned_pointer_subtraction`.

---

## 7. Build & workflow learnings (macOS / Apple Silicon)

This tree builds compiler-rt as a **runtime** (`LLVM_ENABLE_RUNTIMES=compiler-rt`),
so it's compiled by the freshly-built `build/bin/clang`. Its effective cache is
`build/runtimes/runtimes-bins/CMakeCache.txt`; the top-level forwards variables
with the `COMPILER_RT`, `SANITIZER`, and `DARWIN` prefixes down to it
(`llvm/runtimes/CMakeLists.txt`).

Config that actually works here:
```
COMPILER_RT_SANITIZERS_TO_BUILD = "asan;tsan"   # NOT ubsan/lsan (see below)
DARWIN_osx_ARCHS = "arm64"                       # host-only (see below)
```

Gotchas hit and fixed, in order:

1. **`check-ubsan` wants a `tsan` target that doesn't exist.** The ubsan/
   sanitizer_common *test* suites add cross-sanitizer deps (tsan, lsan, …) based
   on *platform support*, not on your build list. Restricting the build to `asan`
   while tests are on ⇒ dangling `tsan` dep. Fix: include `tsan` in the build
   list (or set `COMPILER_RT_INCLUDE_TESTS=OFF` for manual testing only).

2. **Do NOT list `ubsan` (or `lsan`) in `COMPILER_RT_SANITIZERS_TO_BUILD`.**
   `compiler-rt/lib/CMakeLists.txt` adds `lsan` and `ubsan` **unconditionally**;
   listing them again ⇒ `add_subdirectory` called twice ⇒ *"binary directory is
   already used to build a source directory."* `ubsan` is always built anyway.

3. **`lipo: … x86_64 and x86_64h … can't be in the same fat output file.`** The
   Darwin runtime builds universal (fat) dylibs across `arm64;x86_64;x86_64h`;
   CommandLineTools `lipo` can't distinguish `x86_64` from its `x86_64h` subtype.
   Fix: `DARWIN_osx_ARCHS=arm64` (host-only) — set **plain** at the top level so
   the `DARWIN` passthrough forwards it (NOT `RUNTIMES_`-prefixed, which is passed
   verbatim and ignored). `darwin_test_archs` returns early if it's already set.

4. **Cleaning the runtimes sub-build:** deleting `runtimes/runtimes-bins` is fine,
   but do it **before** the top-level `cmake` (or the mkdir stamp goes stale and
   `configure` can't `cd` into the missing dir). Do NOT delete
   `runtimes/runtimes-stamps` — it contains `*-info.txt` files generated by the
   top-level configure that have no build rule to regenerate; if you nuke them,
   re-run the top-level `cmake` to restore them.

5. **The built `clang` has no default sysroot.** Compiling test programs needs
   `-isysroot "$(xcrun --show-sdk-path)"`, else `ld: library 'System' not found`.

Reconfigure an existing build dir by passing the build dir **positionally**
(`cmake -D… build`); `-B build` without `-S` wrongly treats the cwd as the source.

Iterate with: `ninja -C build clang compiler-rt`.

### Running the tests

Check targets are **per component** — `check-llvm` covers only `llvm/test/` and
runs *none* of this change. Use the component targets:

| Command | Runs | Covers our tests? |
|---------|------|-------------------|
| `ninja -C build check-clang` | all of `clang/test/` | ✅ CodeGen test |
| `ninja -C build check-compiler-rt` | all compiler-rt suites | ✅ runtime test |
| `ninja -C build check-runtimes` | all enabled runtimes | ✅ (superset) |
| `ninja -C build check-all` | everything enabled | ✅ (slow) |
| `ninja -C build check-llvm` | `llvm/test/` only | ❌ nothing |

Target-name gotchas learned the hard way:
- **No `check-ubsan` target** in a runtimes build — the per-sanitizer check
  targets live *inside* the runtimes sub-build. Use `check-compiler-rt`
  (top-level) or `check-runtimes`.
- **`llvm-lit` is not a build target** — it's a script generated at cmake
  configure time at `build/bin/llvm-lit`. Run it directly; `ninja llvm-lit` fails.
- **`ninja compiler-rt` only exists when compiler-rt is a runtime**
  (`LLVM_ENABLE_RUNTIMES=compiler-rt`). "unknown target" ⇒ reconfigure to enable it.

Fast single-test iteration (skips the whole suite):
```bash
# CodeGen (clang) test:
build/bin/llvm-lit -v clang/test/CodeGen/ubsan-unaligned-pointer-subtraction.c

# runtime (compiler-rt) test — point lit at the HOST ubsan config:
build/bin/llvm-lit -v \
  build/runtimes/runtimes-bins/compiler-rt/test/ubsan/Standalone-arm64 \
  --filter=unaligned-pointer-subtraction
```
On macOS the *host* config is `Standalone-arm64` (`apple_target_is_host=True`);
`Standalone-osx-arm64` is a remote-device target that fails to parse here
(missing `ios_commands/ios_prepare.py`), so avoid it — and avoid a whole-suite
`check-compiler-rt` locally for the same reason.

---

## 8. Validation performed

All via `build/bin/clang [++] -isysroot "$(xcrun --show-sdk-path)" -fsanitize=unaligned-pointer-subtraction`:

- **Constant element size** — `(A*)(p+1) - (A*)p` → `runtime error: … byte distance 4 that is not a multiple of the element size 8`.
- **Group membership** — `-fsanitize=undefined` pulls the check in.
- **Recover vs abort** — default prints & continues (exit 0); `-fno-sanitize-recover=…` prints & aborts (exit 134).
- **Signed distance** — with `q > p` (negative distance), `Value(Data->Type, Diff)` prints `-4` (not a huge unsigned number).
- **VLA / runtime divisor** — `int (*p)[n]`: IR shows `%9 = mul nuw i64 4, %n` then `srem … %9`, and the diagnostic reports the runtime element size (`12` for `n=3`). Works.
- **Negative control** — a valid same-array subtraction prints nothing.

VLA-specific findings (the point of the "sanity check"):
- **VLA pointer subtraction is C-only.** C++ treats each `int (*)[n]` with runtime
  `n` as a distinct, incompatible type → the cast/subtraction are errors. So the
  VLA test case must be a `.c` file.
- **Latent div-by-zero at `n == 0`:** `srem X, 0` is UB, but the pre-existing
  `sdiv exact X, 0` already has this and Sema warns on zero-size pointee
  subtraction — not introduced here; worth a one-line PR note.

---

## 9. Test fallout: adding a check renumbers ordinals

Adding the check made ~29 clang tests fail. Two causes are about **ordinal
renumbering**; the third is plain group-membership.

1. **`SanitizerHandler` enum ordinal (the `llvm.ubsantrap` code).** Inserting the
   `SANITIZER_CHECK` *mid-list* in `SanitizerHandler.h` shifts every following
   handler's ordinal, changing `@llvm.ubsantrap(i8 N)` for `shift`,
   `sub-overflow`, `type-mismatch`, `alignment-assumption`, `vla-bound`.
   **Fix: append the entry at the very end of `LIST_SANITIZER_CHECKS`** — that's
   why `AlignmentAssumption`/`BoundsSafety` already sit out of alphabetical order
   there. Then no test edits are needed. Broke: `catch-alignment-assumption-*`,
   `catch-undef-behavior`, `ubsan-trap-reason-*`.

2. **`SanitizerKind` ordinal (`SanitizerOrdinal`).** Alphabetical insertion in
   `Sanitizers.def` is idiomatic but shifts the ordinal of every later sanitizer
   (e.g. `local-bounds` 71→72). That ordinal is embedded by
   `@llvm.allow.ubsan.check(i8 N)` **and** is the `llvm.ubsantrap` code for checks
   with no dedicated handler (like `local-bounds`). Broke: `allow-ubsan-check.c`
   (bump the hardcoded `71`→`72`). Expected churn for an alphabetical add.

3. **Group membership.** `-fsanitize=undefined` now expands to include the new
   check, so every Driver test enumerating the group needs it added — sorted
   between `signed-integer-overflow` and `unreachable`, and any alternation CHECK
   also needs its `{N}` match-count bumped: `fsanitize.c`, `fsanitize-{trap,
   recover,undefined,merge,minimal-runtime,skip-hot-cutoff,annotate-debug-info}.c`,
   `amdgpu-validate-sanitize.cl`.

4. **New runtime symbols must be registered.** The handler exports
   `__ubsan_handle_unaligned_pointer_subtraction[_abort]`; add them to
   `compiler-rt/lib/ubsan/ubsan_interface.inc`, or the Linux-only
   `asan/TestCases/Linux/interface_symbols_linux.cpp` fails (it diffs the
   runtime's exported symbols against that list). It's not run on macOS
   (`nm -D`/ELF), so this only surfaces on Linux/CI.

5. **Minimal runtime needs its own handler.** Because the check is in the
   `undefined` group, `-fsanitize-minimal-runtime` emits
   `__ubsan_handle_unaligned_pointer_subtraction_minimal`; add a `HANDLER(...)`
   in `ubsan_minimal_handlers.cpp` or it's a link error, and
   `ubsan_minimal/TestCases/test-darwin-interface.c` (x86_64-darwin only, so
   CI-only) fails — it diffs the minimal runtime's `__ubsan_handle_*` symbols
   against the full runtime's, which must match.

Ruled out (no change needed): Windows uses attribute-based symbol export (no
maintained `.def`/exports list enumerating handlers); no per-check
`__has_feature`/preprocessor macro; `ubsan_interface.inc` + the two runtimes are
the only handler enumerations tree-wide.

Key asymmetry: **`SanitizerHandler.h` → append at end** (avoid trap-code churn);
**`Sanitizers.def` → alphabetical** (accept ordinal churn + fix
`allow-ubsan-check.c`).

---

## 10. Remaining work for the upstream PR

- **Tests**
  - `clang/test/CodeGen/` — FileCheck the emitted `srem`/branch/`__ubsan_handle_*` (constant + VLA + negative-distance).
  - `compiler-rt/test/ubsan/TestCases/Pointer/` — runtime output tests; VLA case in a `.c` file.
- **Docs** — `clang/docs/ReleaseNotes.md` + `UsersManual.md`; explicitly contrast
  with `-fsanitize=alignment` (this is `sizeof`-multiple of the *distance*, not
  `alignof` of an *address*).
- Note the `n == 0` div-by-zero edge in the PR description.
