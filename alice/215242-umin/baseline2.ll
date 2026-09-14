 define void @g(<vscale x 4 x ptr> %p, i32 %inc, <vscale x 4 x i1> %m) {
  call void @llvm.experimental.vector.histogram.umax(<vscale x 4 x ptr> %p, i32 %inc, <vscale x 4 x i1> %m)
  ret void
}