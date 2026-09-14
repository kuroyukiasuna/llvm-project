# Postmortem: a 9-hour infinite loop inside `DenseMap::doFind`

**Symptom.** Two LLVM lit tests spun at ~95% CPU forever. A full
`test/Transforms` + `test/CodeGen/AArch64` sweep ran 9h15m without completing.

**Verdict.** Not an LLVM bug. Two stacked defects in a throwaway debug commit,
plus an optimizer transformation that is entirely legal and turned a crash into
a hang.

**Scope.** The defect was in `a45f447c2924 "experiment"` — scratch debug prints
added to `analyzeInterleaving` while investigating llvm#211229. The actual
#211229 fix (`replaceOffsetCongruentIVs` in `IndVarSimplify`/`SCEVExpander`) is
untouched by any of this. Confirmed: the new lit tests' CHECK lines were
generated against a build *with* the experiment commit and still pass without
it, so no interleaving decision was affected.

---

## 1. The offending code

```cpp
    errs() << "////////////////////////////load/////////////////////\n";
    for (auto *group : LoadGroups) {
      for (int i = 0; i < group->getNumMembers(); i++) {
        errs() << "name: " << group->getMember(i)->getName()
               << " ,opcode: " << group->getMember(i)->getOpcodeName() << "\n";
      }
    }
```

Two independent bugs in three lines.

### Bug 1 — wrong index space

`llvm/include/llvm/Analysis/VectorUtils.h`:

```cpp
uint32_t getNumMembers() const { return Members.size(); }   // a COUNT

InstTy *getMember(uint32_t Index) const {
  int32_t Key = SmallestKey + Index;                        // a POSITION
  return Members.lookup(Key);
}

DenseMap<int32_t, InstTy *> Members;
int32_t SmallestKey = 0;
```

`getNumMembers()` counts members. `getMember(Index)` indexes *position within
the interleave pattern*. These agree only when the group has no gaps.

For a gapped group — `Factor = 4`, members at positions 0, 1, 3:

```
position:   0     1     2     3
          [ a ] [ b ] [ - ] [ d ]     Factor=4, getNumMembers()=3, GAP at 2
```

The loop runs `i = 0, 1, 2`. At `i = 2` it looks up key `SmallestKey + 2 = 2` —
the gap. The third member lives at position 3, which the loop never reaches.

`interleave-with-gaps.ll` is a test *about* gapped groups, which is why it was
one of the two that hung.

### Bug 2 — unchecked null

`getMember` is documented to return null:

```cpp
/// \returns nullptr if contains no such member.
```

Every other caller in the tree null-checks it (`VectorUtils.h:804`), and there
is a helper that does it for you:

```cpp
auto members() const {
  return make_filter_range(
      map_range(seq<uint32_t>(0, Factor), [this](uint32_t I) { return getMember(I); }),
      [](InstTy *I) { return I != nullptr; });
}
```

The debug loop dereferenced it unconditionally. That is the UB that everything
below follows from.

---

## 2. Why it hangs instead of crashing

This is the interesting part. **Nothing is ever dereferenced.** `getName()` is
never called on `0x0`. Control never escapes the map lookup.

### The loop it hangs in

`llvm/include/llvm/ADT/DenseMap.h`:

```cpp
template <typename LookupKeyT>
const BucketT *doFind(const LookupKeyT &Val) const {
  auto [BucketsPtr, U, NumBuckets] = getRep();
  if (NumBuckets == 0)
    return nullptr;

  const unsigned Mask = NumBuckets - 1;
  unsigned BucketNo = KeyInfoT::getHashValue(Val) & Mask;
  while (true) {
    // An empty bucket terminates the probe: the key isn't in the map.
    if (LLVM_LIKELY(!llvm::densemap::detail::used(U, BucketNo)))
      return nullptr;
    const BucketT *Bucket = BucketsPtr + BucketNo;
    if (LLVM_LIKELY(KeyInfoT::isEqual(Val, Bucket->getFirst())))
      return Bucket;
    // Hash collision: continue linear probing.
    BucketNo = (BucketNo + 1) & Mask;
  }
}
```

### This loop provably terminates as written

`findBucketForInsertion` caps the load factor:

```cpp
// Grow the table if the load factor would exceed 3/4 after insertion.
unsigned NewNumEntries = getNumEntries() + 1;
unsigned NumBuckets = getNumBuckets();
if (LLVM_UNLIKELY(NewNumEntries * 4 >= NumBuckets * 3)) {
  this->grow(NumBuckets * 2);
  LookupBucketFor(Lookup, TheBucket);
}
```

Load factor ≤ 3/4 ⟹ at least one unused bucket always exists. Linear probing
(`BucketNo = (BucketNo + 1) & Mask`) visits every bucket within one wrap.
Therefore `!used(U, BucketNo)` must fire. **The source cannot spin.**

### What the compiled code actually looks like

`InterleavedAccessInfo::analyzeInterleaving`, Release+assertions, arm64:

```asm
<+1424>: add    w9, w9, #0x1        ; BucketNo + 1
<+1428>: and    w9, w9, w10         ; & Mask
<+1432>: ubfiz  x12, x9, #4, #32    ; × 16 (bucket stride)
<+1436>: ldr    w12, [x8, x12]      ; load bucket key      <-- PC parked here
<+1440>: cmp    w11, w12            ; == Val?
<+1444>: b.eq   <+1360>             ;   yes -> return Bucket
<+1448>: b      <+1424>             ;   no  -> probe again  <-- UNCONDITIONAL

<+1360>: add    x8, x8, x9, lsl #4
<+1364>: ldr    x0, [x8, #0x8]      ; load the mapped value
<+1368>: bl     llvm::Value::getName() const
```

**No load of the `U` bitmap. No bit test. One comparison. The not-equal path is
an unconditional backward branch.** The `return nullptr` exit is not in the
binary.

### The chain that licensed the deletion

1. `getMember(i)->getName()` calls a non-static member function on the returned
   pointer, and `getName()` loads `this->HasName`. Null ⟹ undefined behaviour.
2. A program execution with UB has *no* defined behaviour — not "the UB part
   misbehaves," but no constraints on that execution at all.
3. So the optimizer may assume the pointer is non-null at the load.
4. After inlining, the value is a phi: `[bucket->second, found]`, `[null, not-found]`.
   If the phi result must be non-null, the `null` incoming edge is never taken.
5. A never-taken edge is dead. Delete it — and with it the `used()` test, whose
   only consumer was that branch.
6. What remains has exactly one exit: "key found." For a missing key, that
   never happens. Infinite loop.

Every step is a standard, individually-uncontroversial transformation.

---

## 3. Minimal reproducer

15 lines that produce the identical codegen shape.

```cpp
#include <cstddef>
struct Bucket { int key; void *val; };

// A miniature doFind: linear probing, empty bucket terminates the probe.
static void *doFind(Bucket *B, unsigned Mask, const unsigned char *Used, int Key) {
  unsigned N = (unsigned)Key & Mask;
  while (true) {
    if (!(Used[N >> 3] & (1u << (N & 7))))
      return nullptr;                  // <-- the "not found" exit
    if (B[N].key == Key)
      return B[N].val;
    N = (N + 1) & Mask;
  }
}

// UB: dereferences the result unconditionally.
int deref_unchecked(Bucket *B, unsigned Mask, const unsigned char *U, int Key) {
  return *(int *)doFind(B, Mask, U, Key);
}

// Same thing, null-checked. No UB.
int deref_checked(Bucket *B, unsigned Mask, const unsigned char *U, int Key) {
  void *p = doFind(B, Mask, U, Key);
  return p ? *(int *)p : -1;
}
```

```sh
clang++ -O2 -S -o - ub.cpp
```

### `deref_unchecked` — exit deleted

```asm
LBB0_1:
	ubfiz	x9, x8, #4, #32
	ldr	w9, [x0, x9]             ; load bucket key
	cmp	w9, w3                   ; == Key?
	b.eq	LBB0_3                   ;   yes -> done
	add	w8, w8, #1               ;   no  -> next bucket
	and	w8, w8, w1
	b	LBB0_1                   ; UNCONDITIONAL
```

No `ldrb` of `Used`, no `tbz`. Byte-for-byte the shape of the real
`analyzeInterleaving` disassembly above.

### `deref_checked` — exit survives

```asm
	lsr	x9, x8, #3
	ldrb	w9, [x2, x9]             ; load Used byte
	and	w10, w8, #0x7
	lsr	w9, w9, w10
	tbz	w9, #0, LBB1_6           ; bit clear -> empty -> EXIT
LBB1_2:
	...
	b.eq	LBB1_4
	...
	ldrb	w8, [x2, x8]             ; and again each iteration
```

Same source, same optimizer, same flags. The only difference is whether the
caller can observe a null.

---

## 4. The fix

```cpp
for (Instruction *M : group->members())
  errs() << "name: " << M->getName() << " ,opcode: " << M->getOpcodeName() << "\n";
```

`members()` fixes both bugs at once: it iterates `seq<uint32_t>(0, Factor)`
(correct index space) and filters nulls (no UB). Spelled out:

```cpp
for (uint32_t i = 0; i < group->getFactor(); i++)
  if (Instruction *M = group->getMember(i))
    ...
```

There is also a latent third issue: `for (int i = 0; i < group->getNumMembers(); i++)`
emits `-Wsign-compare` (`int` vs `uint32_t`). Benign here, but it was one of
only two warnings the file produced — worth not ignoring.

---

## 5. How it was actually found

Recording the false starts, because two of them cost real time.

| Step | Outcome |
|---|---|
| `ninja check-llvm`-style sweep, output piped through `tail -60` | Ran 9h15m. Killing it discarded **all** accumulated results, because the pipe buffers. No failure data survived. |
| `lit --timeout=120` | Refused: needs `psutil`, not installed. No per-test cap, so nothing caught the hang early. |
| `ps -o etime=,time=` on the stuck PIDs | 553 min CPU / 555 min elapsed ⟹ **spinning, not blocked**. First real signal. |
| `sample <pid> 3` | 2484/2484 samples in `analyzeInterleaving`, no callee frames. Localized it. |
| `lldb -b -o "process launch" ...` | **Useless.** Batch mode blocked forever on a process that never exits; `bt` never ran. |
| Launch detached, then `lldb -b -p <pid> -o 'disassemble -s $pc-92 -c 28'` | Worked. Gave the disassembly above. |
| Read `findBucketForInsertion` | Proved the source loop terminates ⟹ the bug must be in codegen, not logic. |
| 15-line reproducer | Confirmed the mechanism in isolation. |

### Two wrong conclusions along the way

- **"The experiment commit deleted `continue` statements."** It did not. This
  came from grepping `+`/`-` lines *without context*; the `-` lines were
  un-braced `if` headers being re-braced, and every `continue` was preserved as
  a context line. Reading the full hunk would have prevented it.
- **"Therefore the commit is behaviour-changing and the `st2` results are
  contaminated."** Also wrong, and it followed from the first error. Verified
  empirically afterwards: CHECK lines generated against the contaminated build
  still pass without it.

### Traps worth remembering

- **Instrumenting inside a UB-affected inline function can dissolve the bug.**
  Adding `std::cout` to `doFind` inflates it past the inlining threshold; if it
  no longer inlines, the caller's "dereferences the result" fact can't
  propagate, the exit survives, and the symptom flips from hang to SIGSEGV.
- **There is no crash for a debugger to trap on.** No signal, no exception,
  just a normal process in a loop with no exit. "Run it under lldb and wait"
  cannot work. Attach and interrupt, or breakpoint before entry.
- **Never pipe a long lit run through `tail`/`head`.** Use
  `2>&1 | tee /tmp/check.log`.

---

## 6. Background

Concepts this bug sits on top of.

### Bucket

A hash map turns a key into an array index. The slots are **buckets**.
`DenseMap<int32_t, Instruction *>` buckets are 16 bytes on arm64 (4-byte key,
4 padding, 8-byte pointer) — hence `ubfiz x12, x9, #4` in the disassembly:
shift left 4 = ×16 = "bucket index → byte offset."

Two keys can hash to the same bucket. `DenseMap` resolves this with **linear
probing** — if your bucket is taken, walk to the next one:

```
want key 7, hashes to bucket 5:

bucket:   3      4      5      6      7      8
        [ 12 ] [ -- ] [ 99 ] [ 41 ] [  7 ] [ -- ]
                        ^      ^      ^
                        occupied      found, 3 probes in
```

For a *missing* key the probe stops at the first empty bucket — because
insertion would have put the key there. `U` is a side bitmap, one bit per
bucket, recording occupancy.

### Load factor

`entries ÷ buckets`. Probe length grows sharply as it approaches 1, and **at
exactly 1 a lookup for a missing key never finds an empty bucket and never
terminates**. Open-addressing tables therefore grow before reaching that point;
`DenseMap` caps at 3/4 (`NewNumEntries * 4 >= NumBuckets * 3`, which is
`entries/buckets >= 3/4` without a division).

### Why "DenseMap"

Nothing to do with this bug — it's about layout:

```
std::unordered_map            DenseMap
─────────────────             ────────
buckets -> linked lists       one flat array
one heap allocation per node  zero per-entry allocation
pointer chasing = cache miss  neighbours adjacent = cache friendly
```

"Dense" = all entries packed contiguously in one array. The cost of that choice
is in-array collision handling (probing) and a load-factor cap.

### "Dense group" — an unrelated meaning

In interleaved-access analysis, "dense" means *no gaps in the access pattern*
and has nothing to do with `DenseMap`.

An **interleave group** is a set of memory accesses forming one strided pattern
that a single wide instruction can service:

```c
*pA = ...;  pA += 2;      // dst[0], dst[2], dst[4], ...
*pB = ...;  pB += 2;      // dst[1], dst[3], dst[5], ...
```

Interleaved in memory that is `A B A B A B` — stride 2, so `Factor = 2`, and
`Members` is keyed by position:

```
position:   0     1
          [ pA ] [ pB ]        Factor=2, 2 members, no gaps -> isFull()
```

AArch64 has exactly one instruction for this: `st2`. LLVM's name for "no gaps"
is:

```cpp
bool isFull() const { return getNumMembers() == getFactor(); }
```

A group with a gap (`Factor = 4`, members at 0, 1, 3) is *not* full — and is
precisely the input that triggers this bug, because it is the only case where
`getNumMembers()` and the position index disagree.
