# Debugging LLVM in VSCode — User Manual

Day-to-day usage. For how the environment was built, see
[DEBUG-SETUP.md](DEBUG-SETUP.md). For an LLDB command reference, see
[LLDB-CHEATSHEET.md](LLDB-CHEATSHEET.md).

---

## Quick start

1. Open the `.ll` (or `.c`/`.cpp`) file you want to run through a tool.
2. Set a breakpoint in the LLVM source you care about — e.g. click the gutter at
   `llvm/lib/Transforms/Scalar/IndVarSimplify.cpp`, in `IndVarSimplifyPass::run`.
3. Press **F5**, pick a configuration, edit the argument prompt, Enter.

The `preLaunchTask` rebuilds the relevant binary first, so **F5 is the whole
edit-build-debug loop**. An incremental rebuild after touching one `.cpp` is
typically a few seconds; touching a widely-included header is much longer.

## The launch configurations

| Configuration | Binary | Use it for |
|---|---|---|
| `opt: debug current .ll` | `build-debug/bin/opt` | Middle-end passes. Prompts for a pass pipeline; output discarded. |
| `opt: break at <file>:<func>` | `build-debug/bin/opt` | Same, but sets the breakpoint itself via `preRunCommands` — use when a gutter breakpoint isn't binding, or to guarantee a stop. |
| `opt: debug current .ll (print resulting IR)` | `build-debug/bin/opt` | Same, but prints the transformed IR to the console afterwards. |
| `llc: debug current .ll` | `build-debug/bin/llc` | Codegen / backend passes (e.g. AArch64 `InterleavedAccessPass`). |
| `clang: debug current file (driver only)` | `build-debug/bin/clang` | The driver itself: argument parsing, job construction. |
| `clang: follow fork into -cc1` | `build-debug/bin/clang` | The **frontend** — parsing, Sema, CodeGen to IR. |
| `opt: hand-edited args` | `build-debug/bin/opt` | Anything needing extra flags — edit the `args` array in `launch.json` directly. |
| `attach: pick a running process` | any | A tool already running, or one launched from a terminal. |

### The prompts take ONE token, not a command line

This is the single most common way to break these configs. CodeLLDB does **not**
shell-split arguments — every element of the `args` array becomes exactly one
argv entry (its schema declares `args` as `["array", "null"]`). So the prompts
here deliberately ask for a *single token*:

- `opt` prompt → just the pipeline: `indvars`, `mem2reg,loop-vectorize`,
  `default<O2>`. **Not** `-passes=indvars -S -o /dev/null`.
- `llc` prompt → just the triple: `aarch64-linux-gnu`.

Typing a whole command line at the prompt produces this pair of errors, which
are one bug wearing two hats — `-S` and `-o` got swallowed into the `-passes=`
value, so opt also fell back to writing bitcode to stdout:

```
opt: unknown pass name 'indvars -S -o /dev/null'
WARNING: You're attempting to print out a bitcode file...
```

To pass extra flags, use the **`opt: hand-edited args`** configuration and edit
its array in `launch.json`, one flag per element:

```json
"args": ["-passes=loop-vectorize", "-force-vector-width=4", "-disable-output", "${file}"]
```

Note the configs use `-disable-output` rather than `-S -o /dev/null`; it is the
idiomatic opt flag for "run passes, discard output" and makes the bitcode
warning structurally impossible.

Also worth remembering: `opt` with **no** `-passes=` at all runs nothing, so your
breakpoint never hits.

### Debugging clang: the fork

The `clang` driver **forks a `-cc1` subprocess** to do the actual compilation.
Breakpoints in Sema/CodeGen will not hit under the plain driver config. Two ways
around it:

- Use **`clang: follow fork into -cc1`**, which sets
  `target.process.follow-fork-mode child`; or
- Put `-cc1` at the front of your arguments to skip the driver entirely. Get the
  real `-cc1` line with `clang -### <your args>` and paste it in.

## Debug Console

**This is where you type `ir`, `p`, and every other command below.** It is the
**DEBUG CONSOLE** tab in the bottom panel (next to PROBLEMS / OUTPUT /
TERMINAL) — ``Ctrl+` `` then pick the tab, or **View → Debug Console**
(`Cmd+Shift+Y`). The input box is the `>` prompt at its bottom.

Three things must be true or you will get "no value" / "use of undeclared
identifier":

1. **You are paused at a breakpoint.** The console only evaluates against a
   stopped process. If the program is running or has exited, nothing resolves.
2. **The right frame is selected** in the CALL STACK pane. Expressions evaluate
   in the *selected* frame, so `L` only resolves while an
   `IndVarSimplifyPass::run` frame is highlighted. Click a frame to switch.
3. **The variable is actually in scope at that line.** Stopping *on* the line
   that assigns `F` means `F` is not assigned yet.

### "I typed `ir ...` and nothing printed"

Almost always: **the process was never stopped, so there was no session to
evaluate in.** With `-disable-output`, `opt` finishes in milliseconds — if no
breakpoint stopped it, it had already exited by the time you typed, and a
finished session's console silently ignores input.

Check the Debug Console transcript. A run that stopped looks like:

```
Launching: .../build-debug/bin/opt -passes=indvars -disable-output ...
Launched process 8815 from ...
Process stopped at IndVarSimplify.cpp:2222        <-- THIS LINE MUST BE THERE
```

If you go straight from `Launched process` to your command with no stop in
between, that is the bug. Then:

- Is there a breakpoint at all? The **BREAKPOINTS** pane should list it, and a
  *bound* breakpoint is a filled red dot — a hollow grey one never resolved.
- Is the toolbar showing pause/step buttons as active, and does **CALL STACK**
  show a `IndVarSimplifyPass::run` frame? If not, you are not stopped.
- Fastest way to rule out gutter-breakpoint problems entirely: use the
  **`opt: break at <file>:<func>`** configuration, which sets the breakpoint
  through `preRunCommands` before the process starts.

Output of `ir`/`dump()` is written by the debuggee to **stderr**. All launch
configs set `"terminal": "console"` so that lands in the Debug Console next to
your command; without it CodeLLDB defaults to `integrated` and the output goes
to the TERMINAL tab instead, which looks like the command silently did nothing.
Trade-off: with `console`, the debuggee's **stdin is unavailable** — irrelevant
here since every config passes an input file, but if you ever want to pipe IR
into `opt` via stdin, switch that config back to `"terminal": "integrated"`.

### Why bare C++ expressions are rejected

`settings.json` sets `"lldb.consoleMode": "commands"`, so input is parsed as an
**LLDB command name + arguments** — not as C++. Typing an expression directly
fails in confusing ways:

```
(Q)->dump()      error: '(Q)->dump()' is not a valid command.
Q->dump()        error: 'Q-' is not a valid command.     <- parser split on '>'
```

Ways to evaluate C++, and — importantly — whether each offers tab-completion:

| form | completion? | notes |
|---|---|---|
| `ev Q->dump()` | **yes** | `command alias` to `expression --`, from `.vscode/lldbinit` |
| `expr -- Q->dump()` | **yes** | the long form `ev` aliases |
| `ir Q` | no | `command regex`; shortest for dumps |
| `p Q->dump()` | no | `p` is `dwim-print`, which does not register expression completion |
| `?Q->dump()` | n/a | CodeLLDB escape: evaluate rest of line as an expression |

**Use `ev` as the daily driver.** It is the only short form that completes:

```
ev L.getHea<TAB>       ->  ev L.getHeader()
ev Q->getOpcodeName()      # (const char *) "phi"
ev L.getName()             # (llvm::StringRef) "loop"
```

Use `ir` when you already know the expression and just want IR text. When you
are *exploring* an unfamiliar class and want member hints, use
`ev Something->dump()` instead — same output, with completion.

Measured with `SBCommandInterpreter.HandleCompletion` on the partial input
`L.getHea`: `expr --` and `ev` return 2 matches (`getHeader()`); `ir` and `p`
return none.

Setting `"lldb.consoleMode": "evaluate"` inverts the polarity — bare expressions
work, but every LLDB command then needs a `/cmd ` prefix (`/cmd ir Q`,
`/cmd breakpoint set --file ...`). Not recommended: debugging LLVM leans heavily
on `breakpoint` / `frame` / `thread` commands, and `p` already costs one
character.

### Don't use the Variables pane for IR — use `ir`

**The Variables pane is close to useless for LLVM IR objects, and that is not a
misconfiguration.** `llvm/utils/lldbDataFormatters.py` only covers ADT
*containers* — `StringRef`, `SmallVector`, `ArrayRef`, `DenseMap`,
`SmallBitVector`. It has **zero** entries for `Value`, `Instruction`, `Type`,
`Function` or `BasicBlock`. Those are deliberately opaque handles whose meaning
lives in a `print`/`dump` method, not in their fields, so expanding one shows
you `SubclassID`, `Use` lists and pointer soup.

The way to actually read IR is the `ir` aliases, defined in `.vscode/lldbinit`:

```
ir I                  # one instruction
ir F                  # whole function
ir L.getHeader()      # a basic block
irv L                 # value/reference form (calls .dump(), not ->dump())
irfn I                # the function enclosing instruction I
```

`ir L.getHeader()` prints real IR:

```llvm
loop:                                   ; preds = %loop.preheader, %loop
  %i = phi i32 [ %i.next, %loop ], [ 0, %loop.preheader ]
  %idx = zext i32 %i to i64
  %v = load float, ptr %pa, align 4
  ...
```

These are `command regex` wrappers over `dump()`. The underlying calls work too
(`expr F->dump()`, `expr SE.dump()`, `expr getSCEV(V)->dump()`), and `dump()`
writes to **stderr**, so output lands in the Debug Console rather than coming
back as an expression result.

Two evaluator quirks worth knowing:

- **`std::string` is not available** in the expression context, so the
  "print into a `raw_string_ostream`" trick fails. Use `dump()`.
- **Default arguments are not applied.** `I->print(os)` errors with
  *"requires 2 arguments"*; you must write `I->print(os, false)`.

Small accessors are often more useful than a full dump anyway, and these do
render fine in a watch expression:

```
p I->getOpcodeName()   # (const char *) "phi"
p L.getName()          # (llvm::StringRef) "loop"
p F->getName()
```

### Where the aliases come from

Every configuration runs one `initCommands` line:

```json
"initCommands": ["command source ${workspaceFolder}/.vscode/lldbinit"]
```

`.vscode/lldbinit` imports the LLVM ADT data formatters, defines `ir` / `irv` /
`irfn`, and raises LLDB's child-display limits. **Add your own aliases there**,
not to individual configs — one file, applies everywhere. If you add a new
configuration, copy that `initCommands` line or you lose all of it.

## Breakpoint recipes

**On a pass entry point** — `run` is overloaded and appears in many files, so
scope it to one:

```
breakpoint set --file IndVarSimplify.cpp --name run
```

**On a specific line**: click the gutter, or
`breakpoint set --file VectorUtils.cpp --line 1234`.

**Conditional, on a named function** — invaluable when a pass runs hundreds of
times and only one case is wrong:

```
breakpoint set --file LoopVectorize.cpp --line 900 \
  --condition 'F->getName() == "my_hot_loop"'
```

(Use `==`, not `.equals()` — `StringRef::equals` no longer exists on trunk; only
`equals_insensitive` remains.)

**Break where an assertion fires**: `breakpoint set --name abort`, or just let it
crash — LLDB stops at the fault with the stack intact.

**Widen the Variables pane defaults** — already applied by `.vscode/lldbinit`,
but raise further if LLVM's nested types still truncate
("*Some of the displayed variables have more members…*"):

```
settings set target.max-children-count 500
settings set target.max-children-depth 8
```

## Understanding *flow* — do this before reaching for the debugger

A debugger answers **"why did this specific code do X"**. It is a poor tool for
**"what is happening to my IR overall"** — you will single-step through hundreds
of pass invocations and learn very little. Narrow it down at the IR level first,
then set one breakpoint.

**1. Which pass changed my IR?** `-print-changed=quiet` lists only passes that
actually modified something, in order:

```sh
build/bin/opt /tmp/x.ll -O2 -disable-output -print-changed=quiet 2>&1 | grep '^\*\*\* IR Dump'
```
```
*** IR Dump After IPSCCPPass on [module] ***
*** IR Dump After InstCombinePass on smoke ***
*** IR Dump After LoopSimplifyPass on smoke ***
...
```

Drop the `grep` to see the IR after each. To find the exact pass that introduced
something:

```sh
build/bin/opt x.ll -O2 -disable-output -print-changed=quiet 2>&1 \
  | awk '/\*\*\* IR Dump/{h=$0} /PATTERN/{print h; exit}'
```

**2. What did that pass see going in?**

```sh
build/bin/opt x.ll -passes=loop-vectorize -print-before=loop-vectorize \
  -print-module-scope -disable-output
```

`-print-module-scope` matters — without it the dump will not re-parse as
standalone IR.

**3. What was the pass thinking?** Now `-debug-only=`, then finally a breakpoint
in the one function that matters, with `ir` to inspect.

## Combining with `LLVM_DEBUG` tracing

Assertions are on in both trees, so `-debug-only=` works. Often the fastest
route is: trace first in the *fast* tree to find where things go wrong, then set
one breakpoint in the debug tree.

```sh
build/bin/opt -passes=loop-vectorize -debug-only=loop-vectorize \
  /tmp/x.ll -o /dev/null 2>&1 | less
```

`dbgs()` goes to **stderr** — without `2>&1` a grep sees nothing. Note also that
`analyzeInterleaving`'s output is under `-debug-only=vectorutils`, not
`loop-vectorize`, and `st2` generation is AArch64 `InterleavedAccessPass`
(`-debug-only=interleaved-access`, reachable via `llc`, not `opt`).

## Which tree to use

```sh
build-debug/bin/opt   # stepping. ~5-10x slower at run time - fine for small repros
build/bin/opt         # fast runs, -debug-only tracing, lit tests
```

**In a terminal, bare `opt`/`llc`/`clang` are neither of these** — they resolve
to `/opt/homebrew/opt/llvm/bin/`, i.e. Homebrew's LLVM 20. Always use an
explicit path when reproducing.

## Gotchas

- **`build-debug/bin/opt` is 83 KB.** Expected — the code is in
  `build-debug/lib/*.dylib` (shared-library build). Not a broken link.
- **Never `ninja clean` or move `build-debug/` mid-session.** macOS reads DWARF
  from the `.o` files via a debug map; deleting them strips symbols silently,
  with no error.
- **Comments in `launch.json` may be stripped** by a formatter on save — which is
  why the caveats live in these `.md` files instead.
- **`args` must be an array with ONE FLAG PER ELEMENT.** CodeLLDB does **not**
  shell-split; its JSON schema declares `args` as `["array", "null"]` and each
  element becomes exactly one argv entry. So `["-passes=indvars -S -o /dev/null"]`
  reaches opt as a single argument, and you get:

  ```
  opt: unknown pass name 'indvars -S -o /dev/null'
  WARNING: You're attempting to print out a bitcode file...
  ```

  (Two symptoms, one cause: `-S` and `-o` were swallowed into the `-passes=`
  value, so opt also fell back to writing bitcode to stdout.) Correct form:
  `["-passes=indvars", "-disable-output", "${file}"]`. This is why the argument
  prompts here ask only for a *single token* (a pass pipeline, a triple) rather
  than a whole command line.
- **Optimized-out variables**: should not happen in this `-O0` tree. If you see
  them, you are accidentally debugging a binary from `build/`.
- **First breakpoint resolution can take a few seconds** (tens of seconds for
  `clang`) while LLDB indexes the debug map across 218 dylibs. Only the first one
  in a session is slow.
- **Editing a widely-included header** (e.g. `DenseMap.h`) triggers a large
  rebuild under `preLaunchTask`. Expected, not a hang.

## Verify the toolchain still works

```sh
cd build-debug
./bin/opt -passes=indvars -S /tmp/dbg-smoke.ll -o /dev/null && echo OK
```

`/tmp/dbg-smoke.ll` is a small counted loop that both IndVarSimplify and
LoopVectorize act on — handy as a breakpoint target. Recreate it if `/tmp` is
cleared:

```llvm
define void @smoke(ptr %a, ptr %b, i32 %n) {
entry:
  %cmp = icmp sgt i32 %n, 0
  br i1 %cmp, label %loop, label %exit
loop:
  %i = phi i32 [ 0, %entry ], [ %i.next, %loop ]
  %idx = zext i32 %i to i64
  %pa = getelementptr inbounds float, ptr %a, i64 %idx
  %v = load float, ptr %pa, align 4
  %s = fadd float %v, 1.0
  %pb = getelementptr inbounds float, ptr %b, i64 %idx
  store float %s, ptr %pb, align 4
  %i.next = add nuw nsw i32 %i, 1
  %done = icmp eq i32 %i.next, %n
  br i1 %done, label %exit, label %loop
exit:
  ret void
}
```
