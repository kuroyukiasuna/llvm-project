; ModuleID = 'st2/st2_nested_pre_iv.ll'
source_filename = "./st2/st2_optimization.cpp"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "aarch64-unknown-linux-gnu"

; Function Attrs: mustprogress nofree noinline norecurse nosync nounwind memory(argmem: readwrite) uwtable
define dso_local void @_Z11nested_loopPKfPfjjj(ptr noalias nofree noundef readonly captures(none) %src, ptr noalias nofree noundef writeonly captures(none) %dst, i32 noundef %width, i32 noundef %height, i32 noundef %srcStride) local_unnamed_addr #0 {
entry:
  %cmp15 = icmp ne i32 %height, 0
  %cmp310 = icmp ne i32 %width, 0
  %or.cond = and i1 %cmp310, %cmp15
  br i1 %or.cond, label %for.body.preheader, label %for.end13

for.body.preheader:                               ; preds = %entry
  %wide.trip.count5 = zext i32 %height to i64
  %wide.trip.count = zext i32 %width to i64
  %0 = shl nuw nsw i64 %wide.trip.count, 3
  %1 = shl nuw nsw i64 %wide.trip.count, 2
  %scevgep8 = getelementptr i8, ptr %src, i64 %1
  %min.iters.check = icmp ult i32 %width, 8
  %n.vec = and i64 %wide.trip.count, 4294967288
  %2 = shl nuw nsw i64 %n.vec, 3
  %cmp.n = icmp eq i64 %n.vec, %wide.trip.count
  br label %for.body

for.body:                                         ; preds = %for.body.preheader, %for.cond2.for.inc11_crit_edge
  %indvars.iv2 = phi i64 [ 0, %for.body.preheader ], [ %indvars.iv.next3, %for.cond2.for.inc11_crit_edge ]
  %pA.018 = phi ptr [ %dst, %for.body.preheader ], [ %add.ptr9.lcssa, %for.cond2.for.inc11_crit_edge ]
  %3 = trunc nuw i64 %indvars.iv2 to i32
  %mul = mul i32 %srcStride, %3
  %idx.ext = zext i32 %mul to i64
  %add.ptr1 = getelementptr inbounds nuw [4 x i8], ptr %src, i64 %idx.ext
  br i1 %min.iters.check, label %for.body4.preheader, label %vector.memcheck

vector.memcheck:                                  ; preds = %for.body
  %4 = trunc i64 %indvars.iv2 to i32
  %5 = mul i32 %srcStride, %4
  %6 = zext i32 %5 to i64
  %7 = shl nuw nsw i64 %6, 2
  %scevgep9 = getelementptr i8, ptr %scevgep8, i64 %7
  %scevgep7 = getelementptr nuw i8, ptr %src, i64 %7
  %scevgep = getelementptr i8, ptr %pA.018, i64 %0
  %bound0 = icmp ult ptr %pA.018, %scevgep9
  %bound1 = icmp ult ptr %scevgep7, %scevgep
  %found.conflict = and i1 %bound0, %bound1
  br i1 %found.conflict, label %for.body4.preheader, label %vector.ph

vector.ph:                                        ; preds = %vector.memcheck
  %8 = getelementptr i8, ptr %pA.018, i64 %2
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %index = phi i64 [ 0, %vector.ph ], [ %index.next, %vector.body ]
  %9 = shl i64 %index, 3
  %next.gep = getelementptr i8, ptr %pA.018, i64 %9
  %10 = getelementptr i8, ptr %pA.018, i64 %9
  %next.gep10 = getelementptr i8, ptr %10, i64 32
  %11 = getelementptr inbounds nuw [4 x i8], ptr %add.ptr1, i64 %index
  %12 = getelementptr inbounds nuw i8, ptr %11, i64 16
  %wide.load = load <4 x float>, ptr %11, align 4, !alias.scope !11
  %wide.load11 = load <4 x float>, ptr %12, align 4, !alias.scope !11
  %13 = fmul <4 x float> %wide.load, splat (float 2.000000e+00)
  %14 = fmul <4 x float> %wide.load11, splat (float 2.000000e+00)
  %15 = fmul <4 x float> %wide.load, splat (float 3.000000e+00)
  %16 = fmul <4 x float> %wide.load11, splat (float 3.000000e+00)
  %interleaved.vec = shufflevector <4 x float> %13, <4 x float> %15, <8 x i32> <i32 0, i32 4, i32 1, i32 5, i32 2, i32 6, i32 3, i32 7>
  store <8 x float> %interleaved.vec, ptr %next.gep, align 4, !alias.scope !14, !noalias !11
  %interleaved.vec12 = shufflevector <4 x float> %14, <4 x float> %16, <8 x i32> <i32 0, i32 4, i32 1, i32 5, i32 2, i32 6, i32 3, i32 7>
  store <8 x float> %interleaved.vec12, ptr %next.gep10, align 4, !alias.scope !14, !noalias !11
  %index.next = add nuw i64 %index, 8
  %17 = icmp eq i64 %index.next, %n.vec
  br i1 %17, label %middle.block, label %vector.body, !llvm.loop !16

middle.block:                                     ; preds = %vector.body
  br i1 %cmp.n, label %for.cond2.for.inc11_crit_edge, label %for.body4.preheader

for.body4.preheader:                              ; preds = %vector.memcheck, %for.body, %middle.block
  %indvars.iv.ph = phi i64 [ 0, %vector.memcheck ], [ 0, %for.body ], [ %n.vec, %middle.block ]
  %pA.112.ph = phi ptr [ %pA.018, %vector.memcheck ], [ %pA.018, %for.body ], [ %8, %middle.block ]
  br label %for.body4

for.body4:                                        ; preds = %for.body4.preheader, %for.body4
  %indvars.iv = phi i64 [ %indvars.iv.next, %for.body4 ], [ %indvars.iv.ph, %for.body4.preheader ]
  %pA.112 = phi ptr [ %add.ptr9, %for.body4 ], [ %pA.112.ph, %for.body4.preheader ]
  %arrayidx = getelementptr inbounds nuw [4 x i8], ptr %add.ptr1, i64 %indvars.iv
  %18 = load float, ptr %arrayidx, align 4
  %19 = insertelement <2 x float> poison, float %18, i64 0
  %20 = shufflevector <2 x float> %19, <2 x float> poison, <2 x i32> zeroinitializer
  %21 = fmul <2 x float> %20, <float 2.000000e+00, float 3.000000e+00>
  store <2 x float> %21, ptr %pA.112, align 4
  %add.ptr9 = getelementptr inbounds nuw i8, ptr %pA.112, i64 8
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %wide.trip.count
  br i1 %exitcond.not, label %for.cond2.for.inc11_crit_edge, label %for.body4, !llvm.loop !20

for.cond2.for.inc11_crit_edge:                    ; preds = %for.body4, %middle.block
  %add.ptr9.lcssa = phi ptr [ %8, %middle.block ], [ %add.ptr9, %for.body4 ]
  %indvars.iv.next3 = add nuw nsw i64 %indvars.iv2, 1
  %exitcond6.not = icmp eq i64 %indvars.iv.next3, %wide.trip.count5
  br i1 %exitcond6.not, label %for.end13, label %for.body, !llvm.loop !21

for.end13:                                        ; preds = %for.cond2.for.inc11_crit_edge, %entry
  ret void
}

attributes #0 = { mustprogress nofree noinline norecurse nosync nounwind memory(argmem: readwrite) uwtable "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="generic" "target-features"="+fp-armv8,+neon,+v8a,-fmv" }

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
