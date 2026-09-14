; ModuleID = './st2/st2_pre_optimize.ll'
source_filename = "./st2/st2_optimization.cpp"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "aarch64-unknown-linux-gnu"

; Function Attrs: mustprogress noinline nounwind uwtable
define dso_local void @_Z11single_loopPKfPfj(ptr noalias noundef %src, ptr noalias noundef %dst, i32 noundef %n) #0 {
entry:
  %add.ptr = getelementptr inbounds float, ptr %dst, i64 1
  br label %for.cond

for.cond:                                         ; preds = %for.inc, %entry
  %pA.0 = phi ptr [ %dst, %entry ], [ %add.ptr4, %for.inc ]
  %pB.0 = phi ptr [ %add.ptr, %entry ], [ %add.ptr5, %for.inc ]
  %i.0 = phi i32 [ 0, %entry ], [ %inc, %for.inc ]
  %cmp = icmp ult i32 %i.0, %n
  br i1 %cmp, label %for.body, label %for.end

for.body:                                         ; preds = %for.cond
  %idxprom = zext i32 %i.0 to i64
  %arrayidx = getelementptr inbounds nuw float, ptr %src, i64 %idxprom
  %0 = load float, ptr %arrayidx, align 4
  %mul = fmul float %0, 2.000000e+00
  store float %mul, ptr %pA.0, align 4
  %idxprom1 = zext i32 %i.0 to i64
  %arrayidx2 = getelementptr inbounds nuw float, ptr %src, i64 %idxprom1
  %1 = load float, ptr %arrayidx2, align 4
  %mul3 = fmul float %1, 3.000000e+00
  store float %mul3, ptr %pB.0, align 4
  %add.ptr4 = getelementptr inbounds float, ptr %pA.0, i64 2
  %add.ptr5 = getelementptr inbounds float, ptr %pB.0, i64 2
  br label %for.inc

for.inc:                                          ; preds = %for.body
  %inc = add i32 %i.0, 1
  br label %for.cond, !llvm.loop !11

for.end:                                          ; preds = %for.cond
  ret void
}

; Function Attrs: mustprogress noinline nounwind uwtable
define dso_local void @_Z11nested_loopPKfPfjjj(ptr noalias noundef %src, ptr noalias noundef %dst, i32 noundef %width, i32 noundef %height, i32 noundef %srcStride) #0 {
entry:
  %add.ptr = getelementptr inbounds float, ptr %dst, i64 1
  br label %for.cond

for.cond:                                         ; preds = %for.inc11, %entry
  %pA.0 = phi ptr [ %dst, %entry ], [ %pA.1, %for.inc11 ]
  %pB.0 = phi ptr [ %add.ptr, %entry ], [ %pB.1, %for.inc11 ]
  %y.0 = phi i32 [ 0, %entry ], [ %inc12, %for.inc11 ]
  %cmp = icmp ult i32 %y.0, %height
  br i1 %cmp, label %for.body, label %for.end13

for.body:                                         ; preds = %for.cond
  %mul = mul i32 %y.0, %srcStride
  %idx.ext = zext i32 %mul to i64
  %add.ptr1 = getelementptr inbounds nuw float, ptr %src, i64 %idx.ext
  br label %for.cond2

for.cond2:                                        ; preds = %for.inc, %for.body
  %pA.1 = phi ptr [ %pA.0, %for.body ], [ %add.ptr9, %for.inc ]
  %pB.1 = phi ptr [ %pB.0, %for.body ], [ %add.ptr10, %for.inc ]
  %x.0 = phi i32 [ 0, %for.body ], [ %inc, %for.inc ]
  %cmp3 = icmp ult i32 %x.0, %width
  br i1 %cmp3, label %for.body4, label %for.end

for.body4:                                        ; preds = %for.cond2
  %idxprom = zext i32 %x.0 to i64
  %arrayidx = getelementptr inbounds nuw float, ptr %add.ptr1, i64 %idxprom
  %0 = load float, ptr %arrayidx, align 4
  %mul5 = fmul float %0, 2.000000e+00
  store float %mul5, ptr %pA.1, align 4
  %idxprom6 = zext i32 %x.0 to i64
  %arrayidx7 = getelementptr inbounds nuw float, ptr %add.ptr1, i64 %idxprom6
  %1 = load float, ptr %arrayidx7, align 4
  %mul8 = fmul float %1, 3.000000e+00
  store float %mul8, ptr %pB.1, align 4
  %add.ptr9 = getelementptr inbounds float, ptr %pA.1, i64 2
  %add.ptr10 = getelementptr inbounds float, ptr %pB.1, i64 2
  br label %for.inc

for.inc:                                          ; preds = %for.body4
  %inc = add i32 %x.0, 1
  br label %for.cond2, !llvm.loop !13

for.end:                                          ; preds = %for.cond2
  br label %for.inc11

for.inc11:                                        ; preds = %for.end
  %inc12 = add i32 %y.0, 1
  br label %for.cond, !llvm.loop !14

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
!11 = distinct !{!11, !12}
!12 = !{!"llvm.loop.mustprogress"}
!13 = distinct !{!13, !12}
!14 = distinct !{!14, !12}
