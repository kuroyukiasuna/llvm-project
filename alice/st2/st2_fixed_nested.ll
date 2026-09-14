; ModuleID = './st2/st2_nested_pre_lv.ll'
source_filename = "./st2/st2_optimization.cpp"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "aarch64-unknown-linux-gnu"

; Function Attrs: mustprogress noinline nounwind uwtable
define dso_local void @_Z11nested_loopPKfPfjjj(ptr noalias noundef %src, ptr noalias noundef %dst, i32 noundef %width, i32 noundef %height, i32 noundef %srcStride) #0 {
entry:
  %add.ptr = getelementptr inbounds float, ptr %dst, i64 1
  %0 = zext i32 %width to i64
  %1 = shl nuw nsw i64 %0, 3
  %2 = add nuw nsw i64 %1, 8
  %3 = shl nuw nsw i64 %0, 2
  %4 = add nuw nsw i64 %3, 4
  %scevgep2 = getelementptr i8, ptr %src, i64 %4
  br label %for.cond

for.cond:                                         ; preds = %for.inc11, %entry
  %pA.0 = phi ptr [ %dst, %entry ], [ %pA.1.lcssa, %for.inc11 ]
  %pB.0 = phi ptr [ %add.ptr, %entry ], [ %pB.1.lcssa, %for.inc11 ]
  %y.0 = phi i32 [ 0, %entry ], [ %inc12, %for.inc11 ]
  %5 = mul i32 %srcStride, %y.0
  %6 = zext i32 %5 to i64
  %7 = shl nuw nsw i64 %6, 2
  %scevgep1 = getelementptr i8, ptr %src, i64 %7
  %scevgep3 = getelementptr i8, ptr %scevgep2, i64 %7
  %cmp = icmp ult i32 %y.0, %height
  br i1 %cmp, label %for.body, label %for.end13

for.body:                                         ; preds = %for.cond
  %mul = mul i32 %y.0, %srcStride
  %idx.ext = zext i32 %mul to i64
  %add.ptr1 = getelementptr inbounds nuw float, ptr %src, i64 %idx.ext
  %8 = zext i32 %width to i64
  %9 = add nuw nsw i64 %8, 1
  %min.iters.check = icmp ule i64 %9, 4
  br i1 %min.iters.check, label %scalar.ph, label %vector.memcheck

vector.memcheck:                                  ; preds = %for.body
  %scevgep = getelementptr i8, ptr %pA.0, i64 %2
  %bound0 = icmp ult ptr %pA.0, %scevgep3
  %bound1 = icmp ult ptr %scevgep1, %scevgep
  %found.conflict = and i1 %bound0, %bound1
  br i1 %found.conflict, label %scalar.ph, label %vector.ph

vector.ph:                                        ; preds = %vector.memcheck
  %n.mod.vf = urem i64 %9, 4
  %10 = icmp eq i64 %n.mod.vf, 0
  %11 = select i1 %10, i64 4, i64 %n.mod.vf
  %n.vec = sub i64 %9, %11
  %12 = shl i64 %n.vec, 3
  %13 = getelementptr i8, ptr %pA.0, i64 %12
  %14 = getelementptr i8, ptr %pB.0, i64 %12
  %15 = trunc i64 %n.vec to i32
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %index = phi i64 [ 0, %vector.ph ], [ %index.next, %vector.body ]
  %16 = shl i64 %index, 3
  %next.gep = getelementptr i8, ptr %pA.0, i64 %16
  %17 = trunc i64 %index to i32
  %18 = zext i32 %17 to i64
  %19 = getelementptr inbounds nuw float, ptr %add.ptr1, i64 %18
  %wide.load = load <4 x float>, ptr %19, align 4, !alias.scope !11
  %20 = fmul <4 x float> %wide.load, splat (float 2.000000e+00)
  %wide.load4 = load <4 x float>, ptr %19, align 4, !alias.scope !11
  %21 = fmul <4 x float> %wide.load4, splat (float 3.000000e+00)
  %22 = shufflevector <4 x float> %20, <4 x float> %21, <8 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7>
  %interleaved.vec = shufflevector <8 x float> %22, <8 x float> poison, <8 x i32> <i32 0, i32 4, i32 1, i32 5, i32 2, i32 6, i32 3, i32 7>
  store <8 x float> %interleaved.vec, ptr %next.gep, align 4, !alias.scope !14, !noalias !11
  %index.next = add nuw i64 %index, 4
  %23 = icmp eq i64 %index.next, %n.vec
  br i1 %23, label %middle.block, label %vector.body, !llvm.loop !16

middle.block:                                     ; preds = %vector.body
  br label %scalar.ph

scalar.ph:                                        ; preds = %vector.memcheck, %for.body, %middle.block
  %bc.resume.val = phi ptr [ %13, %middle.block ], [ %pA.0, %for.body ], [ %pA.0, %vector.memcheck ]
  %bc.resume.val5 = phi ptr [ %14, %middle.block ], [ %pB.0, %for.body ], [ %pB.0, %vector.memcheck ]
  %bc.resume.val6 = phi i32 [ %15, %middle.block ], [ 0, %for.body ], [ 0, %vector.memcheck ]
  br label %for.cond2

for.cond2:                                        ; preds = %scalar.ph, %for.inc
  %pA.1 = phi ptr [ %bc.resume.val, %scalar.ph ], [ %add.ptr9, %for.inc ]
  %pB.1 = phi ptr [ %bc.resume.val5, %scalar.ph ], [ %add.ptr10, %for.inc ]
  %x.0 = phi i32 [ %bc.resume.val6, %scalar.ph ], [ %inc, %for.inc ]
  %cmp3 = icmp ult i32 %x.0, %width
  br i1 %cmp3, label %for.body4, label %for.end

for.body4:                                        ; preds = %for.cond2
  %idxprom = zext i32 %x.0 to i64
  %arrayidx = getelementptr inbounds nuw float, ptr %add.ptr1, i64 %idxprom
  %24 = load float, ptr %arrayidx, align 4
  %mul5 = fmul float %24, 2.000000e+00
  store float %mul5, ptr %pA.1, align 4
  %idxprom6 = zext i32 %x.0 to i64
  %arrayidx7 = getelementptr inbounds nuw float, ptr %add.ptr1, i64 %idxprom6
  %25 = load float, ptr %arrayidx7, align 4
  %mul8 = fmul float %25, 3.000000e+00
  %pB.gep = getelementptr inbounds float, ptr %pA.1, i64 1
  store float %mul8, ptr %pB.gep, align 4
  %add.ptr9 = getelementptr inbounds float, ptr %pA.1, i64 2
  %add.ptr10 = getelementptr inbounds float, ptr %pB.1, i64 2
  br label %for.inc

for.inc:                                          ; preds = %for.body4
  %inc = add i32 %x.0, 1
  br label %for.cond2, !llvm.loop !20

for.end:                                          ; preds = %for.cond2
  %pA.1.lcssa = phi ptr [ %pA.1, %for.cond2 ]
  %pB.1.lcssa = phi ptr [ %pB.1, %for.cond2 ]
  br label %for.inc11

for.inc11:                                        ; preds = %for.end
  %inc12 = add i32 %y.0, 1
  br label %for.cond, !llvm.loop !21

for.end13:                                        ; preds = %for.cond
  ret void
}

attributes #0 = { mustprogress noinline nounwind uwtable "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="generic" "target-features"="+fp-armv8,+neon,+v8a,-fmv" }

!llvm.module.flags = !{!0, !1, !2, !3, !4, !5, !6, !7, !8, !9}
!llvm.ident = !{!10}

!0 = !{i32 1, !"ptrauth-elf-got", i32 0}
!1 = !{i32 1, !"ptrauth-init-fini", i32 0}
!2 = !{i32 1, !"ptrauth-init-fini-address-discrimination", i32 0}
!3 = !{i32 1, !"ptrauth-sign-personality", i32 0}
!4 = !{i32 1, !"aarch64-elf-pauthabi-platform", i32 268435458}
!5 = !{i32 1, !"aarch64-elf-pauthabi-version", i32 0}
!6 = !{i32 8, !"PIC Level", i32 2}
!7 = !{i32 7, !"PIE Level", i32 2}
!8 = !{i32 7, !"uwtable", i32 2}
!9 = !{i32 7, !"frame-pointer", i32 4}
!10 = !{!"clang version 24.0.0git (hoshimi@fbk01:/home/hoshimi/code/llvm-contribute 4070621c866fb4156f7c7d15039d12a4295f46c2)"}
!11 = !{!12}
!12 = distinct !{!12, !13}
!13 = distinct !{!13, !"LVerDomain"}
!14 = !{!15}
!15 = distinct !{!15, !13}
!16 = distinct !{!16, !17, !18, !19}
!17 = !{!"llvm.loop.mustprogress"}
!18 = !{!"llvm.loop.isvectorized", i32 1}
!19 = !{!"llvm.loop.unroll.runtime.disable"}
!20 = distinct !{!20, !17, !18}
!21 = distinct !{!21, !17}
