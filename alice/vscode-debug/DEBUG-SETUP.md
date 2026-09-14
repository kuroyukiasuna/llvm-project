# Debug Setup Guide

How the VSCode debugging environment for this checkout was built, and how to
recreate or change it. For day-to-day use see [DEBUG-MANUAL.md](DEBUG-MANUAL.md).

Set up 2026-08-11 on macOS arm64 (M-series), 12 cores.

---

## 1. Why there are two build trees

| | `build/` | `build-debug/` |
|---|---|---|
| Build type | `Release` (`-O3 -DNDEBUG`) | `Debug` (`-O0 -g`) |
| Assertions | ON | ON |
| Debug info | **none** | full DWARF |
| Libraries | static | shared (`.dylib`) |
| Size | 8.8 GB | 14 GB |
| Use for | lit tests, `-debug-only` tracing, fast repros | **stepping in a debugger** |

`build/` cannot be debugged in any useful way. Verify for yourself:

```sh
nm -pa build/bin/opt | grep -c OSO        # 0  -> no debug info
nm -pa build-debug/bin/opt | grep -c OSO  # >0 -> debug map present
```

Assertions are ON in *both*, so `LLVM_DEBUG(...)` and `-debug-only=` work in
either tree. Debug info is the only thing `build/` is missing — and it cannot be
added without a full recompile, which is why a second tree exists rather than a
reconfigure of the first.

## 2. Recreating `build-debug/` from scratch

```sh
cd /Users/Tianyi.Dang/workspace/llvm-project-alice

cmake -G Ninja -S llvm -B build-debug \
  -DCMAKE_BUILD_TYPE=Debug \
  -DLLVM_ENABLE_ASSERTIONS=ON \
  -DLLVM_ENABLE_PROJECTS="clang" \
  -DLLVM_TARGETS_TO_BUILD="AArch64;X86" \
  -DBUILD_SHARED_LIBS=ON \
  -DLLVM_OPTIMIZED_TABLEGEN=ON \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DCLANG_INCLUDE_TESTS=OFF \
  -DLLVM_APPEND_VC_REV=OFF \
  -DLLVM_PARALLEL_LINK_JOBS=4 \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DCMAKE_C_COMPILER=/opt/homebrew/opt/llvm/bin/clang \
  -DCMAKE_CXX_COMPILER=/opt/homebrew/opt/llvm/bin/clang++

ninja -C build-debug -j 10 opt clang llc
```

Reference numbers from the original run: 4095 ninja edges, **7.1 min** wall
clock at `-j 10`, 14 GB total (7.2 GB of it in `lib/`, 218 dylibs).

### Why each non-obvious flag

**`BUILD_SHARED_LIBS=ON`** — the important one. A static `Debug` tree *including
clang* runs roughly 50–60 GB, which did not fit the 63 GB free at setup time.
Shared libraries link each LLVM component once instead of copying it into every
tool binary, cutting the tree to 14 GB and making links much faster. This is the
standard LLVM developer configuration for Debug builds; it is explicitly not
meant for release/distribution.

Consequence: `build-debug/bin/opt` is **83 KB**. That is correct, not a broken
build. The pass code and its DWARF live in `build-debug/lib/libLLVM*.dylib`,
found at run time via rpath `@loader_path/../lib`:

```sh
otool -L build-debug/bin/opt | head -3   # @rpath/libLLVM....24.0git.dylib
otool -l build-debug/bin/opt | grep -A2 LC_RPATH | grep path
```

The tree is self-contained — nothing resolves to `build/` or to Homebrew LLVM,
and the version-stamped names (`24.0git` vs Homebrew's `20.1.2`) make an
accidental collision impossible.

**`LLVM_OPTIMIZED_TABLEGEN=ON`** — builds `llvm-tblgen` at `-O2` even in a Debug
tree. TableGen at `-O0` is painfully slow and you almost never need to step
through it. Set to `OFF` if you actually need to debug TableGen itself.

**`LLVM_INCLUDE_TESTS=OFF`** (+ examples, benchmarks, `CLANG_INCLUDE_TESTS`) —
disk savings; the gtest unittest binaries are large in Debug. There is therefore
**no `check-llvm` target in this tree** — run lit tests in `build/`. See §4 to
turn them back on.

**`LLVM_APPEND_VC_REV=OFF`** — stops a relink of everything on every commit,
since the git revision is otherwise baked into the binaries.

**`LLVM_PARALLEL_LINK_JOBS=4`** — Debug links are memory-hungry; this keeps them
from thrashing. Less critical with shared libs, but cheap insurance.

**`CMAKE_EXPORT_COMPILE_COMMANDS=ON`** — produces the `compile_commands.json`
that `clangd` is pointed at in `settings.json`.

Compilers are pinned to Homebrew clang to match what `build/` used.

## 3. VSCode side

**Required extension: CodeLLDB** (`vadimcn.vscode-lldb`).

```sh
"/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
  --install-extension vadimcn.vscode-lldb
```

It bundles its own LLDB (22.1.4 at setup) at
`~/.vscode/extensions/vadimcn.vscode-lldb-*/lldb/bin/lldb`. Prefer it over
Microsoft C/C++ (`ms-vscode.cpptools`), whose `cppdbg`/`lldb-mi` bridge is
deprecated and unreliable on Apple Silicon. Note `ms-vscode.cpptools-themes` is
a color theme only and provides no debugger.

Files in this directory:

- `launch.json` — seven debug configurations (see the manual)
- `tasks.json` — ninja build tasks used as `preLaunchTask`
- `settings.json` — clangd pointed at `build-debug/compile_commands.json`,
  cmake-tools pointed at this checkout, LLDB display preferences

## 4. Common modifications

**Re-enable lit tests in the debug tree** (costs several GB):

```sh
cmake -B build-debug -DLLVM_INCLUDE_TESTS=ON -DCLANG_INCLUDE_TESTS=ON
ninja -C build-debug check-llvm
```

**Add a target** (e.g. RISCV): re-run cmake with
`-DLLVM_TARGETS_TO_BUILD="AArch64;X86;RISCV"`, then rebuild.

**Add a project** (e.g. `lld`, `mlir`): `-DLLVM_ENABLE_PROJECTS="clang;lld"`.
Each project adds build time and disk.

**Build another tool**: `ninja -C build-debug <toolname>` — e.g. `llvm-as`,
`FileCheck`, `llvm-dis`. Then add a config to `launch.json` copying an existing
one and changing `program`.

**After adding or renaming a source file**, cmake must regenerate before ninja
sees it. `ninja` usually detects the changed `CMakeLists.txt` and re-runs cmake
itself; if not, `cmake -B build-debug` manually.

## 5. Verifying the setup

```sh
cd build-debug
./bin/opt -passes=indvars -S /tmp/dbg-smoke.ll -o /dev/null   # runs clean
nm -pa lib/libLLVMScalarOpts.dylib | grep -c OSO              # 150 -> DWARF present
```

End-to-end debugger check:

```sh
~/.vscode/extensions/vadimcn.vscode-lldb-*/lldb/bin/lldb -b \
  -o 'breakpoint set --file IndVarSimplify.cpp --name run' \
  -o run -o bt -o 'frame variable' \
  -- ./bin/opt -passes=indvars -S /tmp/dbg-smoke.ll -o /dev/null
```

Expected: a stop in `libLLVMScalarOpts.24.0git.dylib` at
`IndVarSimplify.cpp:2222` with named arguments (`L`, `AM`, `AR`) — not a bare
address.

## 6. Maintenance warnings

- **Do not `ninja clean` or move `build-debug/` while debugging.** macOS uses a
  *debug map*: the linked binary holds pointers to the `.o` files, and DWARF is
  read from them on demand. Deleting the object files silently strips your
  symbols — you get a working binary with no debuggability and no error.
- Keep the two trees in sync with your source edits, or you will debug one
  version while testing another.
- If disk gets tight, `build-debug/` is the disposable one — §2 recreates it in
  about 7 minutes.
