; ModuleID = './st2/st2_optimization.cpp'
source_filename = "./st2/st2_optimization.cpp"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "aarch64-unknown-linux-gnu"

; Function Attrs: mustprogress nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable
define dso_local void @_Z11single_loopPKfPfj(ptr noalias nofree noundef readonly captures(none) %src, ptr noalias nofree noundef writeonly captures(none) %dst, i32 noundef %n) local_unnamed_addr #0 {
entry:
  %cmp13.not = icmp eq i32 %n, 0
  br i1 %cmp13.not, label %for.cond.cleanup, label %for.body.preheader

for.body.preheader:                               ; preds = %entry
  %add.ptr = getelementptr inbounds nuw i8, ptr %dst, i64 4
  %wide.trip.count = zext i32 %n to i64
  %min.iters.check = icmp ult i32 %n, 8
  br i1 %min.iters.check, label %for.body.preheader23, label %vector.ph

vector.ph:                                        ; preds = %for.body.preheader
  %n.vec = and i64 %wide.trip.count, 4294967288
  %0 = shl nuw nsw i64 %n.vec, 3
  %1 = getelementptr i8, ptr %add.ptr, i64 %0
  %2 = getelementptr i8, ptr %dst, i64 %0
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %index = phi i64 [ 0, %vector.ph ], [ %index.next, %vector.body ]
  %3 = shl i64 %index, 3
  %next.gep = getelementptr i8, ptr %dst, i64 %3
  %4 = getelementptr i8, ptr %dst, i64 %3
  %next.gep18 = getelementptr i8, ptr %4, i64 32
  %5 = getelementptr inbounds nuw [4 x i8], ptr %src, i64 %index
  %6 = getelementptr inbounds nuw i8, ptr %5, i64 16
  %wide.load = load <4 x float>, ptr %5, align 4, !tbaa !16
  %wide.load19 = load <4 x float>, ptr %6, align 4, !tbaa !16
  %7 = fmul <4 x float> %wide.load, splat (float 2.000000e+00)
  %8 = fmul <4 x float> %wide.load19, splat (float 2.000000e+00)
  %9 = fmul <4 x float> %wide.load, splat (float 3.000000e+00)
  %10 = fmul <4 x float> %wide.load19, splat (float 3.000000e+00)
  %interleaved.vec = shufflevector <4 x float> %7, <4 x float> %9, <8 x i32> <i32 0, i32 4, i32 1, i32 5, i32 2, i32 6, i32 3, i32 7>
  store <8 x float> %interleaved.vec, ptr %next.gep, align 4, !tbaa !16
  %interleaved.vec20 = shufflevector <4 x float> %8, <4 x float> %10, <8 x i32> <i32 0, i32 4, i32 1, i32 5, i32 2, i32 6, i32 3, i32 7>
  store <8 x float> %interleaved.vec20, ptr %next.gep18, align 4, !tbaa !16
  %index.next = add nuw i64 %index, 8
  %11 = icmp eq i64 %index.next, %n.vec
  br i1 %11, label %middle.block, label %vector.body, !llvm.loop !18

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i64 %n.vec, %wide.trip.count
  br i1 %cmp.n, label %for.cond.cleanup, label %for.body.preheader23

for.body.preheader23:                             ; preds = %for.body.preheader, %middle.block
  %indvars.iv.ph = phi i64 [ 0, %for.body.preheader ], [ %n.vec, %middle.block ]
  %pB.015.ph = phi ptr [ %add.ptr, %for.body.preheader ], [ %1, %middle.block ]
  %pA.014.ph = phi ptr [ %dst, %for.body.preheader ], [ %2, %middle.block ]
  br label %for.body

for.cond.cleanup:                                 ; preds = %for.body, %middle.block, %entry
  ret void

for.body:                                         ; preds = %for.body.preheader23, %for.body
  %indvars.iv = phi i64 [ %indvars.iv.next, %for.body ], [ %indvars.iv.ph, %for.body.preheader23 ]
  %pB.015 = phi ptr [ %add.ptr5, %for.body ], [ %pB.015.ph, %for.body.preheader23 ]
  %pA.014 = phi ptr [ %add.ptr4, %for.body ], [ %pA.014.ph, %for.body.preheader23 ]
  %arrayidx = getelementptr inbounds nuw [4 x i8], ptr %src, i64 %indvars.iv
  %12 = load float, ptr %arrayidx, align 4, !tbaa !16
  %mul = fmul float %12, 2.000000e+00
  store float %mul, ptr %pA.014, align 4, !tbaa !16
  %mul3 = fmul float %12, 3.000000e+00
  store float %mul3, ptr %pB.015, align 4, !tbaa !16
  %add.ptr4 = getelementptr inbounds nuw i8, ptr %pA.014, i64 8
  %add.ptr5 = getelementptr inbounds nuw i8, ptr %pB.015, i64 8
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %wide.trip.count
  br i1 %exitcond.not, label %for.cond.cleanup, label %for.body, !llvm.loop !22
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable
define dso_local void @_Z11nested_loopPKfPfjjj(ptr noalias nofree noundef readonly captures(none) %src, ptr noalias nofree noundef writeonly captures(none) %dst, i32 noundef %width, i32 noundef %height, i32 noundef %srcStride) local_unnamed_addr #0 {
entry:
  %cmp29 = icmp ne i32 %height, 0
  %cmp324 = icmp ne i32 %width, 0
  %or.cond = and i1 %cmp29, %cmp324
  br i1 %or.cond, label %for.body.preheader, label %for.cond.cleanup

for.body.preheader:                               ; preds = %entry
  %add.ptr = getelementptr inbounds nuw i8, ptr %dst, i64 4
  %wide.trip.count37 = zext i32 %height to i64
  %wide.trip.count = zext i32 %width to i64
  br label %for.body

for.cond.cleanup:                                 ; preds = %for.cond2.for.cond.cleanup4_crit_edge, %entry
  ret void

for.body:                                         ; preds = %for.body.preheader, %for.cond2.for.cond.cleanup4_crit_edge
  %indvars.iv34 = phi i64 [ 0, %for.body.preheader ], [ %indvars.iv.next35, %for.cond2.for.cond.cleanup4_crit_edge ]
  %pA.032 = phi ptr [ %dst, %for.body.preheader ], [ %add.ptr10, %for.cond2.for.cond.cleanup4_crit_edge ]
  %pB.030 = phi ptr [ %add.ptr, %for.body.preheader ], [ %add.ptr11, %for.cond2.for.cond.cleanup4_crit_edge ]
  %0 = trunc nuw i64 %indvars.iv34 to i32
  %mul = mul i32 %srcStride, %0
  %idx.ext = zext i32 %mul to i64
  %add.ptr1 = getelementptr inbounds nuw [4 x i8], ptr %src, i64 %idx.ext
  br label %for.body5

for.cond2.for.cond.cleanup4_crit_edge:            ; preds = %for.body5
  %indvars.iv.next35 = add nuw nsw i64 %indvars.iv34, 1
  %exitcond38.not = icmp eq i64 %indvars.iv.next35, %wide.trip.count37
  br i1 %exitcond38.not, label %for.cond.cleanup, label %for.body, !llvm.loop !23

for.body5:                                        ; preds = %for.body, %for.body5
  %indvars.iv = phi i64 [ 0, %for.body ], [ %indvars.iv.next, %for.body5 ]
  %pA.126 = phi ptr [ %pA.032, %for.body ], [ %add.ptr10, %for.body5 ]
  %pB.125 = phi ptr [ %pB.030, %for.body ], [ %add.ptr11, %for.body5 ]
  %arrayidx = getelementptr inbounds nuw [4 x i8], ptr %add.ptr1, i64 %indvars.iv
  %1 = load float, ptr %arrayidx, align 4, !tbaa !16
  %mul6 = fmul float %1, 2.000000e+00
  store float %mul6, ptr %pA.126, align 4, !tbaa !16
  %mul9 = fmul float %1, 3.000000e+00
  store float %mul9, ptr %pB.125, align 4, !tbaa !16
  %add.ptr10 = getelementptr inbounds nuw i8, ptr %pA.126, i64 8
  %add.ptr11 = getelementptr inbounds nuw i8, ptr %pB.125, i64 8
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %wide.trip.count
  br i1 %exitcond.not, label %for.cond2.for.cond.cleanup4_crit_edge, label %for.body5, !llvm.loop !24
}

attributes #0 = { mustprogress nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="generic" "target-features"="+fp-armv8,+neon,+v8a,-fmv" }

!llvm.module.flags = !{!0, !1, !2, !3, !4, !5, !6, !7, !8, !9}
!llvm.ident = !{!10}
!llvm.errno.tbaa = !{!11}

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
!11 = !{!12, !13, i64 0}
!12 = !{!"__libc_errno", !13, i64 0}
!13 = !{!"int", !14, i64 0}
!14 = !{!"omnipotent char", !15, i64 0}
!15 = !{!"Simple C++ TBAA"}
!16 = !{!17, !17, i64 0}
!17 = !{!"float", !14, i64 0}
!18 = distinct !{!18, !19, !20, !21}
!19 = !{!"llvm.loop.mustprogress"}
!20 = !{!"llvm.loop.isvectorized", i32 1}
!21 = !{!"llvm.loop.unroll.runtime.disable"}
!22 = distinct !{!22, !19, !21, !20}
!23 = distinct !{!23, !19}
!24 = distinct !{!24, !19}
