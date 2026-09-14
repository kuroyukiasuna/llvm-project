define void @f(<vscale x 2 x ptr> %p, i64 %inc, <vscale x 2 x i1> %m) {
  call void @llvm.experimental.vector.histogram.umax(<vscale x 2 x ptr> %p, i64 %inc, <vscale x 2 x i1> %m)
  ret void
}