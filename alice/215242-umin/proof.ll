; %inc is the LOW 8 BITS of %big. High bits of %big must be irrelevant.
define void @umin_i8_trunc(<vscale x 2 x ptr> %p, i64 %big, <vscale x 2 x i1> %m) {
  %inc = trunc i64 %big to i8
  call void @llvm.experimental.vector.histogram.umin(<vscale x 2 x ptr> %p, i8 %inc, <vscale x 2 x i1> %m)
  ret void
}