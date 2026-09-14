#!/bin/bash
# Reproduce the #206006 measurements. Run from this directory.
#   ./run.sh            -- everything
#   ./run.sh ir         -- fast loop: opt on the pre-LV IR only
#   ./run.sh asm        -- full clang -> asm, with instruction counts
#   ./run.sh forced     -- same but with -force-vector-width=8
#   ./run.sh sweep      -- unroll-factor sweep
#   ./run.sh deref      -- THE control experiment: deref-provable vs not
#   ./run.sh debug      -- LV/VPlan debug trace (shows the real gate)
#   ./run.sh std        -- real std::find_if against host libc++
set -u
BIN=${BIN:-../bin}
DBGBIN=${DBGBIN:-$BIN}
TRIPLE=x86_64-unknown-linux-gnu
MARCH=skylake-avx512
CXXFLAGS="-O3 --target=$TRIPLE -march=$MARCH -nostdinc++"

count_asm() {   # $1 = .s file, $2... = function names
  local f=$1; shift
  python3 - "$f" "$@" <<'EOF'
import re,sys
s=open(sys.argv[1]).read()
for fn in sys.argv[2:]:
    m=re.search(r'^_Z\w*'+fn+r'\w*:(.*?)(?=^\s*\.size|\Z)', s, re.S|re.M)
    b=m.group(1) if m else ''
    vec=len(re.findall(r'\b(vpcmpeqd|kortest|vptest|vpor|vmovdqu)\b', b))
    regs=len(set(re.findall(r'%[zy]mm[0-9]+', b)))
    print(f"  {fn:16} lines={b.count(chr(10)):4}  vector-cmp={vec:3}  vec-regs={regs}")
EOF
}

do_ir() {
  echo "=== opt -passes=loop-vectorize on findif_pre_lv.ll (fast iteration loop) ==="
  $BIN/opt -passes='loop-vectorize' \
     -pass-remarks-analysis=loop-vectorize -pass-remarks-missed=loop-vectorize \
     findif_pre_lv.ll -S -o /tmp/206006_lv.ll 2>&1 | grep remark
  echo "  vector.body blocks: $(grep -c 'vector.body' /tmp/206006_lv.ll)"
}

do_asm() {
  echo "=== clang -O3 -> asm ==="
  $BIN/clang++ $CXXFLAGS -S findif.cpp -o /tmp/206006.s 2>/dev/null
  count_asm /tmp/206006.s find_simple find_unrolled4 any_eq
  echo "--- remarks ---"
  $BIN/clang++ $CXXFLAGS -S -Rpass-analysis=loop-vectorize -Rpass-missed=loop-vectorize \
     -Rpass=loop-vectorize findif.cpp -o /dev/null 2>&1 | grep remark
}

do_forced() {
  echo "=== clang -O3 -force-vector-width=8 -> asm ==="
  $BIN/clang++ $CXXFLAGS -mllvm -force-vector-width=8 -S findif.cpp -o /tmp/206006_f.s 2>/dev/null
  count_asm /tmp/206006_f.s find_simple find_unrolled4 any_eq
}

do_sweep() {
  echo "=== unroll-factor sweep: which shape hits which gate ==="
  $BIN/clang++ $CXXFLAGS -S -Rpass-analysis=loop-vectorize -Rpass-missed=loop-vectorize \
     unrollsweep.cpp -o /dev/null 2>&1 | grep remark | sed 's/\[-Rpass[^]]*\]//'
}

# The control experiment. g_* are provably dereferenceable (global array),
# p_* are not (pointer argument). Unroll factor varies independently.
# Expected: g_* vectorize, p_* do not, regardless of unroll factor.
do_deref() {
  echo "=== deref control: provably-dereferenceable vs not ==="
  $BIN/clang++ $CXXFLAGS -S deref_control.cpp -o /tmp/206006_d.s 2>/dev/null
  count_asm /tmp/206006_d.s g_plain g_unrolled4 p_plain p_unrolled4
  echo "--- remarks ---"
  $BIN/clang++ $CXXFLAGS -S -Rpass-analysis=loop-vectorize -Rpass-missed=loop-vectorize \
     -Rpass=loop-vectorize deref_control.cpp -o /dev/null 2>&1 | grep remark | sed 's/\[-Rpass[^]]*\]//'
}

# The real gate is only visible with -debug-only=loop-vectorize,vplan: the
# "potentially faulting load" line comes from VPlanConstruction.cpp (DEBUG_TYPE
# "vplan"), NOT from loop-vectorize. Omitting ",vplan" hides it and leaves only
# the misleading cost-model remark.
# build/ is Release but has assertions ON, so LLVM_DEBUG works there -- no need
# for build-debug unless you want a debugger. Set DBGBIN=../../build-debug/bin
# to use the Debug tree instead.
do_debug() {
  echo "=== LV+VPlan debug trace ==="
  $DBGBIN/opt -passes=loop-vectorize -debug-only=loop-vectorize,vplan \
     -force-vector-width=8 findif_pre_lv.ll -S -o /dev/null 2>&1 \
     | grep -E "^LV: (Checking|Not vectorizing|We can vectorize|Vectorization is)"
}

do_std() {
  echo "=== real std::find_if / std::any_of (host libc++) ==="
  SDK=$(xcrun --show-sdk-path 2>/dev/null)
  $BIN/clang++ -O3 -isysroot "$SDK" -S \
     -Rpass-analysis=loop-vectorize -Rpass-missed=loop-vectorize -Rpass=loop-vectorize \
     findif_std.cpp -o /tmp/206006_std.s 2>&1 | grep remark
}

case "${1:-all}" in
  ir)     do_ir ;;
  asm)    do_asm ;;
  forced) do_forced ;;
  std)    do_std ;;
  sweep)  do_sweep ;;
  deref)  do_deref ;;
  debug)  do_debug ;;
  *)      do_ir; echo; do_asm; echo; do_forced; echo; do_sweep; echo; \
          do_deref; echo; do_debug; echo; do_std ;;
esac
