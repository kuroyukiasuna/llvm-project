; ModuleID = './st2/st2_optimization.cpp'
source_filename = "./st2/st2_optimization.cpp"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "aarch64-unknown-linux-gnu"

; Function Attrs: mustprogress noinline nounwind uwtable
define dso_local void @_Z11nested_loopPKfPfjjj(ptr noalias noundef %src, ptr noalias noundef %dst, i32 noundef %width, i32 noundef %height, i32 noundef %srcStride) #0 {
entry:
  %src.addr = alloca ptr, align 8
  %dst.addr = alloca ptr, align 8
  %width.addr = alloca i32, align 4
  %height.addr = alloca i32, align 4
  %srcStride.addr = alloca i32, align 4
  %pA = alloca ptr, align 8
  %pB = alloca ptr, align 8
  %y = alloca i32, align 4
  %row = alloca ptr, align 8
  %x = alloca i32, align 4
  store ptr %src, ptr %src.addr, align 8
  store ptr %dst, ptr %dst.addr, align 8
  store i32 %width, ptr %width.addr, align 4
  store i32 %height, ptr %height.addr, align 4
  store i32 %srcStride, ptr %srcStride.addr, align 4
  %0 = load ptr, ptr %dst.addr, align 8
  store ptr %0, ptr %pA, align 8
  %1 = load ptr, ptr %dst.addr, align 8
  %add.ptr = getelementptr inbounds float, ptr %1, i64 1
  store ptr %add.ptr, ptr %pB, align 8
  store i32 0, ptr %y, align 4
  br label %for.cond

for.cond:                                         ; preds = %for.inc11, %entry
  %2 = load i32, ptr %y, align 4
  %3 = load i32, ptr %height.addr, align 4
  %cmp = icmp ult i32 %2, %3
  br i1 %cmp, label %for.body, label %for.end13

for.body:                                         ; preds = %for.cond
  %4 = load ptr, ptr %src.addr, align 8
  %5 = load i32, ptr %y, align 4
  %6 = load i32, ptr %srcStride.addr, align 4
  %mul = mul i32 %5, %6
  %idx.ext = zext i32 %mul to i64
  %add.ptr1 = getelementptr inbounds nuw float, ptr %4, i64 %idx.ext
  store ptr %add.ptr1, ptr %row, align 8
  store i32 0, ptr %x, align 4
  br label %for.cond2

for.cond2:                                        ; preds = %for.inc, %for.body
  %7 = load i32, ptr %x, align 4
  %8 = load i32, ptr %width.addr, align 4
  %cmp3 = icmp ult i32 %7, %8
  br i1 %cmp3, label %for.body4, label %for.end

for.body4:                                        ; preds = %for.cond2
  %9 = load ptr, ptr %row, align 8
  %10 = load i32, ptr %x, align 4
  %idxprom = zext i32 %10 to i64
  %arrayidx = getelementptr inbounds nuw float, ptr %9, i64 %idxprom
  %11 = load float, ptr %arrayidx, align 4
  %mul5 = fmul float %11, 2.000000e+00
  %12 = load ptr, ptr %pA, align 8
  store float %mul5, ptr %12, align 4
  %13 = load ptr, ptr %row, align 8
  %14 = load i32, ptr %x, align 4
  %idxprom6 = zext i32 %14 to i64
  %arrayidx7 = getelementptr inbounds nuw float, ptr %13, i64 %idxprom6
  %15 = load float, ptr %arrayidx7, align 4
  %mul8 = fmul float %15, 3.000000e+00
  %16 = load ptr, ptr %pB, align 8
  store float %mul8, ptr %16, align 4
  %17 = load ptr, ptr %pA, align 8
  %add.ptr9 = getelementptr inbounds float, ptr %17, i64 2
  store ptr %add.ptr9, ptr %pA, align 8
  %18 = load ptr, ptr %pB, align 8
  %add.ptr10 = getelementptr inbounds float, ptr %18, i64 2
  store ptr %add.ptr10, ptr %pB, align 8
  br label %for.inc

for.inc:                                          ; preds = %for.body4
  %19 = load i32, ptr %x, align 4
  %inc = add i32 %19, 1
  store i32 %inc, ptr %x, align 4
  br label %for.cond2, !llvm.loop !13

for.end:                                          ; preds = %for.cond2
  br label %for.inc11

for.inc11:                                        ; preds = %for.end
  %20 = load i32, ptr %y, align 4
  %inc12 = add i32 %20, 1
  store i32 %inc12, ptr %y, align 4
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
