; ModuleID = 'st2/st2_pre_optimize.ll'
source_filename = "./st2/st2_optimization.cpp"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "aarch64-unknown-linux-gnu"

; Function Attrs: mustprogress noinline nounwind uwtable
define dso_local void @_Z11nested_loopPKfPfjjj(ptr noalias nofree noundef readonly captures(none) %src, ptr noalias nofree noundef writeonly captures(none) %dst, i32 noundef %width, i32 noundef %height, i32 noundef %srcStride) local_unnamed_addr #0 {
entry:
  %add.ptr = getelementptr inbounds nuw i8, ptr %dst, i64 4
  %cmp15 = icmp ne i32 %height, 0
  %cmp310 = icmp ne i32 %width, 0
  %or.cond = and i1 %cmp15, %cmp310
  br i1 %or.cond, label %for.body.preheader, label %for.end13

for.body.preheader:                               ; preds = %entry
  br label %for.body

for.body:                                         ; preds = %for.body.preheader, %for.cond2.for.inc11_crit_edge
  %pA.018 = phi ptr [ %add.ptr9.lcssa, %for.cond2.for.inc11_crit_edge ], [ %dst, %for.body.preheader ]
  %y.017 = phi i32 [ %inc12, %for.cond2.for.inc11_crit_edge ], [ 0, %for.body.preheader ]
  %pB.016 = phi ptr [ %add.ptr10.lcssa, %for.cond2.for.inc11_crit_edge ], [ %add.ptr, %for.body.preheader ]
  %mul = mul i32 %y.017, %srcStride
  %idx.ext = zext i32 %mul to i64
  %add.ptr1 = getelementptr inbounds nuw [4 x i8], ptr %src, i64 %idx.ext
  br label %for.body4

for.body4:                                        ; preds = %for.body, %for.body4
  %x.013 = phi i32 [ 0, %for.body ], [ %inc, %for.body4 ]
  %pA.112 = phi ptr [ %pA.018, %for.body ], [ %add.ptr9, %for.body4 ]
  %pB.111 = phi ptr [ %pB.016, %for.body ], [ %add.ptr10, %for.body4 ]
  %idxprom = zext i32 %x.013 to i64
  %arrayidx = getelementptr inbounds nuw [4 x i8], ptr %add.ptr1, i64 %idxprom
  %0 = load float, ptr %arrayidx, align 4
  %mul5 = fmul float %0, 2.000000e+00
  store float %mul5, ptr %pA.112, align 4
  %mul8 = fmul float %0, 3.000000e+00
  store float %mul8, ptr %pB.111, align 4
  %add.ptr9 = getelementptr inbounds nuw i8, ptr %pA.112, i64 8
  %add.ptr10 = getelementptr inbounds nuw i8, ptr %pB.111, i64 8
  %inc = add nuw i32 %x.013, 1
  %cmp3 = icmp ult i32 %inc, %width
  br i1 %cmp3, label %for.body4, label %for.cond2.for.inc11_crit_edge, !llvm.loop !11

for.cond2.for.inc11_crit_edge:                    ; preds = %for.body4
  %add.ptr9.lcssa = phi ptr [ %add.ptr9, %for.body4 ]
  %add.ptr10.lcssa = phi ptr [ %add.ptr10, %for.body4 ]
  %inc12 = add i32 %y.017, 1
  %cmp = icmp ult i32 %inc12, %height
  br i1 %cmp, label %for.body, label %for.end13.loopexit, !llvm.loop !13

for.end13.loopexit:                               ; preds = %for.cond2.for.inc11_crit_edge
  br label %for.end13

for.end13:                                        ; preds = %for.end13.loopexit, %entry
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
!11 = distinct !{!11, !12}
!12 = !{!"llvm.loop.mustprogress"}
!13 = distinct !{!13, !12}
