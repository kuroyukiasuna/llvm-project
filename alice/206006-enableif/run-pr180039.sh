#!/bin/bash
# Measure PR #180039 (fhahn, speculative load intrinsics) on the #206006 repro.
#
# Setup that produced PRBIN (from the llvm-project-alice repo root):
#   git fetch https://github.com/llvm/llvm-project.git pull/180039/head:pr180039
#   git worktree add ../llvm-pr180039 pr180039
#   cmake -G Ninja -S ../llvm-pr180039/llvm -B ../llvm-pr180039/build \
#     -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_ASSERTIONS=ON \
#     -DLLVM_TARGETS_TO_BUILD="X86;AArch64" -DLLVM_ENABLE_PROJECTS="" \
#     -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
#     -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_USE_LINKER=lld
#   ninja -C ../llvm-pr180039/build -j 10 opt llc
# Teardown: git worktree remove ../llvm-pr180039 --force; git branch -D pr180039
set -u
PRBIN=${PRBIN:-../../../llvm-pr180039/build/bin}
CURBIN=${CURBIN:-../bin}

for t in x86 aarch64; do
  for w in "$CURBIN main" "$PRBIN pr180039"; do
    set -- $w
    echo "=== $2, triple=$t ==="
    $1/opt -passes=loop-vectorize -pass-remarks-analysis=loop-vectorize \
       -pass-remarks-missed=loop-vectorize -pass-remarks=loop-vectorize \
       findif_simple_$t.ll -S -o /tmp/206006_$2_$t.ll 2>&1 | grep -o "remark:.*"
    echo "  vector.body=$(grep -c 'vector.body' /tmp/206006_$2_$t.ll)" \
         "speculative.load=$(grep -c 'llvm.speculative.load' /tmp/206006_$2_$t.ll)" \
         "can.load.spec=$(grep -c 'llvm.can.load.speculatively' /tmp/206006_$2_$t.ll)"
  done
done
