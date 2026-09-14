# LLDB Cheatsheet (LLVM flavour)

Every command here was checked against the LLDB this setup actually uses —
CodeLLDB's bundled **lldb 22.1.4**. Type them in the **DEBUG CONSOLE** while
stopped at a breakpoint.

The console is in `commands` mode, so input is an LLDB command. For raw C++ use
`ev` (see below). Companion docs: [DEBUG-MANUAL.md](DEBUG-MANUAL.md),
[DEBUG-SETUP.md](DEBUG-SETUP.md).

**★ = custom to this repo**, defined in `.vscode/lldbinit`. Everything else is
stock LLDB.

---

## Start here — the six you'll actually use

| | |
|---|---|
| `ev <expr>` ★ | evaluate C++ — **the one with tab-completion** |
| `ir <ptr>` ★ | dump LLVM IR for a pointer expression |
| `v` | list all locals in the current frame |
| `bt` | backtrace |
| `n` / `s` / `finish` | step over / step into / run to end of frame |
| `c` | continue |

## Custom commands ★

| command | expands to | note |
|---|---|---|
| `ev X` | `expression -- X` | `command alias` → **has completion** |
| `ir X` | `expr -- (X)->dump()` | pointers |
| `irv X` | `expr -- (X).dump()` | references / values |
| `irfn I` | `expr -- (I)->getParent()->getParent()->dump()` | enclosing function of an instruction |

Only `ev` completes. `ir`/`irv`/`irfn` are `command regex` (raw substitution,
no completion handler). When exploring an unfamiliar class, use
`ev Thing->dump()` — same output, with hints.

## Running and stepping

| command | short | what |
|---|---|---|
| `run` | `r` | start the process |
| `continue` | `c` | resume |
| `next` | `n` | step over |
| `step` | `s` | step into |
| `stepi` | `si` | step one instruction |
| `finish` | | run until current frame returns |
| `thread until 2250` | | run to line 2250 in this frame (loop-friendly) |
| `thread return` | | force an immediate return — skip the rest of the frame |
| `process interrupt` | | pause a running process |
| `process status` | | where am I |

## Breakpoints

```
b IndVarSimplify.cpp:2223          # file:line  (b is a regex shortcut)
b llvm::IndVarSimplifyPass::run    # by symbol
breakpoint set --file IndVarSimplify.cpp --name run     # scope an overloaded name
breakpoint set --name __assert_rtn                      # catch a failed assert (macOS)
breakpoint set --name abort
breakpoint set --func-regex 'llvm::.*::runOnFunction'
```

`--file X.cpp --name run` is the workhorse for pass entry points: `run` exists
in hundreds of files, and this pins it to one.

Managing them:

```
br list                    # br l
br delete 1                # br del
br disable 1 / br enable 1
br modify -c 'F->getName() == "foo"' 1     # add/replace a condition
br modify -i 100 1                         # skip the first 100 hits
breakpoint command add -o "ir F" 1         # auto-run a command on every hit
```

Conditions use `==` for `StringRef`, **not** `.equals()` — that method no longer
exists on trunk.

## Moving around the stack

```
bt              # backtrace         bt 5 = innermost 5 frames
up / down       # move one frame
f 3             # select frame 3
frame info      # where the selected frame is
```

**Expressions evaluate in the *selected* frame.** If `L` reports "undeclared
identifier", you are probably in the wrong frame — that is the #1 cause.

## Inspecting values

```
v                     # all locals (frame variable)
v -a                  # locals only, omitting arguments
ev L.getName()        # evaluate an expression
p Something           # dwim-print: variable or expression (no completion)
po obj                # print via description
expr -i false -- F->dump()    # ignore breakpoints while evaluating
```

`-i false` matters when the thing you are dumping would re-enter the very
breakpoint you are stopped on — otherwise the evaluation halts and you get
nothing back.

⚠️ **`ev` cannot take flags.** It is an alias for `expression --`, so the `--`
is already consumed and anything after it is parsed as C++:

```
ev -i false -- L.getName()      error: use of undeclared identifier 'i'
expr -i false -- L.getName()    (llvm::StringRef) "loop"          <- correct
```

Use plain `expr` whenever you need options; use `ev` for the common flagless
case, where it buys you completion.

Display limits (already raised in `lldbinit`, raise further if truncated):

```
settings set target.max-children-count 500
settings set target.max-children-depth 8
```

## LLVM IR inspection

```
ir I                  # an instruction
ir F                  # a whole function
ir BB                 # a basic block
ir L.getHeader()      # the header block of a Loop
irv L                 # a Loop& (reference form)
irfn I                # the function containing instruction I
```

Small accessors are often better than a full dump, and unlike `dump()` these
return a value you can see inline:

```
ev I->getOpcodeName()      # (const char *) "phi"
ev I->getNumOperands()
ev L.getName()             # (llvm::StringRef) "loop"
ev F->getName()
ev F->arg_size()
ev Ty->isVectorTy()
```

**The Variables pane cannot show IR.** `llvm/utils/lldbDataFormatters.py` covers
ADT containers only (`StringRef`, `SmallVector`, `ArrayRef`, `DenseMap`,
`SmallBitVector`) — there is nothing for `Value`, `Instruction`, `Type`,
`Function` or `BasicBlock`. Use `ir`.

`dump()` writes to **stderr**, which reaches the Debug Console because the
launch configs set `"terminal": "console"`.

## Watchpoints — catch who modified something

```
watchpoint set variable Count
watchpoint set expression -- (int *)&someObj->Field
watchpoint list
watchpoint delete 1
```

Useful when a field changes and you cannot find the writer. Note hardware
watchpoints are limited in number (typically 4).

## Symbols, addresses, crash triage

```
image lookup -a 0x10bc3aec8       # what is at this address (crash backtrace)
image lookup -n llvm::Value::dump # find a symbol
image lookup -r -n 'IndVarSimpl'  # regex symbol search
image list libLLVMScalarOpts      # is the dylib loaded, and from where
disassemble -f                    # current function
register read                     # all registers
memory read -c 64 -f x -s 8 <addr>
```

`image lookup -a` is the fast way to decode a raw address from an LLVM crash
dump into `file:line`.

## Settings worth knowing

```
settings show target.process.thread.step-avoid-regexp    # default: ^std::
settings set  target.process.thread.step-avoid-regexp '^(std|llvm::(SmallVector|DenseMap|StringRef))::'
```

Extending the step-avoid regex stops `s` from diving into ADT internals every
time you step over a container access — a large quality-of-life win in LLVM.

```
settings set target.process.follow-fork-mode child   # used by the clang -cc1 config
settings list                                        # everything
```

## Automation

```
target stop-hook add -o "bt 3"          # run commands at every stop
target stop-hook list / delete
breakpoint command add -o "ir F" 1      # per-breakpoint commands
command source /path/to/file            # run a command file
statistics dump                         # breakpoint resolve times, expression counts
log enable lldb breakpoints             # debug LLDB itself when a bp won't bind
```

## Defining your own commands

The rule that matters:

```
command alias NAME expression --        # argument goes LAST  -> keeps completion
command regex NAME 's/(.+)/expr -- (%1)->dump()/'   # argument in the MIDDLE -> no completion
```

`command alias` forwards to the real command and inherits its tab-completion.
`command regex` is textual substitution and has no completion handler. Verified
with `SBCommandInterpreter.HandleCompletion` on the partial input `L.getHea`:
`expr --` and an alias both return 2 matches (`getHeader()`); a regex command
returns none.

A regex command's name is **permanent** — you cannot later redefine it with
`command alias`; you must edit the original definition.

Add yours to `.vscode/lldbinit`, which every launch config sources.

## Getting unstuck

```
help <command>          # e.g. help breakpoint set
apropos watchpoint      # search commands by keyword
gui                     # curses UI (from a real terminal, not the Debug Console)
```

`help` on a `command regex` alias shows only `Syntax: ir` — the comments in
`.vscode/lldbinit` are the real documentation for those.
