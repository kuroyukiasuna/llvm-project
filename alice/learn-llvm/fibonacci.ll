; ModuleID = 'learn-llvm/fibonacci.c'
source_filename = "learn-llvm/fibonacci.c"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

; Function Attrs: noinline nounwind uwtable
define dso_local i32 @main() #0 {
entry:
  %retval = alloca i32, align 4
  %calculate_until = alloca i32, align 4
  %x0 = alloca i32, align 4
  %x1 = alloca i32, align 4
  %i = alloca i32, align 4
  %next = alloca i32, align 4
  store i32 0, ptr %retval, align 4
  store i32 10, ptr %calculate_until, align 4
  store i32 0, ptr %x0, align 4
  store i32 1, ptr %x1, align 4
  store i32 0, ptr %i, align 4
  br label %for.cond

for.cond:                                         ; preds = %for.inc, %entry
  %0 = load i32, ptr %i, align 4
  %1 = load i32, ptr %calculate_until, align 4
  %cmp = icmp slt i32 %0, %1
  br i1 %cmp, label %for.body, label %for.end

for.body:                                         ; preds = %for.cond
  %2 = load i32, ptr %x0, align 4
  %3 = load i32, ptr %x1, align 4
  %add = add nsw i32 %2, %3
  store i32 %add, ptr %next, align 4
  %4 = load i32, ptr %i, align 4
  %rem = srem i32 %4, 2
  %cmp1 = icmp eq i32 %rem, 0
  br i1 %cmp1, label %if.then, label %if.else

if.then:                                          ; preds = %for.body
  %5 = load i32, ptr %next, align 4
  store i32 %5, ptr %x0, align 4
  br label %if.end

if.else:                                          ; preds = %for.body
  %6 = load i32, ptr %next, align 4
  store i32 %6, ptr %x1, align 4
  br label %if.end

if.end:                                           ; preds = %if.else, %if.then
  br label %for.inc

for.inc:                                          ; preds = %if.end
  %7 = load i32, ptr %i, align 4
  %inc = add nsw i32 %7, 1
  store i32 %inc, ptr %i, align 4
  br label %for.cond, !llvm.loop !5

for.end:                                          ; preds = %for.cond
  %8 = load i32, ptr %calculate_until, align 4
  %rem2 = srem i32 %8, 2
  %cmp3 = icmp eq i32 %rem2, 0
  br i1 %cmp3, label %cond.true, label %cond.false

cond.true:                                        ; preds = %for.end
  %9 = load i32, ptr %x0, align 4
  br label %cond.end

cond.false:                                       ; preds = %for.end
  %10 = load i32, ptr %x1, align 4
  br label %cond.end

cond.end:                                         ; preds = %cond.false, %cond.true
  %cond = phi i32 [ %9, %cond.true ], [ %10, %cond.false ]
  ret i32 %cond
}

attributes #0 = { noinline nounwind uwtable "frame-pointer"="all" "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }

!llvm.module.flags = !{!0, !1, !2, !3}
!llvm.ident = !{!4}

!0 = !{i32 8, !"PIC Level", i32 2}
!1 = !{i32 7, !"PIE Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 2}
!3 = !{i32 7, !"frame-pointer", i32 2}
!4 = !{!"clang version 23.0.0git (/home/hoshimi/code/llvm-contribute/ 609b651890d91b2157b4880ab74e8df1c1b73ae4)"}
!5 = distinct !{!5, !6}
!6 = !{!"llvm.loop.mustprogress"}
