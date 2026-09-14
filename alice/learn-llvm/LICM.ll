; ModuleID = 'learn-llvm/LICM.c'
source_filename = "learn-llvm/LICM.c"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

@__const.main.data = private unnamed_addr constant [4 x i32] [i32 1, i32 2, i32 3, i32 4], align 16

; Function Attrs: noinline nounwind uwtable
define dso_local i32 @LICM(i32 noundef %scale_factor, ptr noundef %data) #0 {
entry:
  %scale_factor.addr = alloca i32, align 4
  %data.addr = alloca ptr, align 8
  %adjusted_value = alloca i32, align 4
  %i = alloca i32, align 4
  store i32 %scale_factor, ptr %scale_factor.addr, align 4
  store ptr %data, ptr %data.addr, align 8
  store i32 0, ptr %adjusted_value, align 4
  store i32 0, ptr %i, align 4
  br label %for.cond

for.cond:                                         ; preds = %for.inc, %entry
  %0 = load i32, ptr %i, align 4
  %cmp = icmp slt i32 %0, 4
  br i1 %cmp, label %for.body, label %for.end

for.body:                                         ; preds = %for.cond
  %1 = load ptr, ptr %data.addr, align 8
  %2 = load i32, ptr %i, align 4
  %idxprom = sext i32 %2 to i64
  %arrayidx = getelementptr inbounds i32, ptr %1, i64 %idxprom
  %3 = load i32, ptr %arrayidx, align 4
  %4 = load i32, ptr %scale_factor.addr, align 4
  %mul = mul nsw i32 %4, 5
  %add = add nsw i32 %3, %mul
  %5 = load i32, ptr %adjusted_value, align 4
  %add1 = add nsw i32 %5, %add
  store i32 %add1, ptr %adjusted_value, align 4
  br label %for.inc

for.inc:                                          ; preds = %for.body
  %6 = load i32, ptr %i, align 4
  %inc = add nsw i32 %6, 1
  store i32 %inc, ptr %i, align 4
  br label %for.cond, !llvm.loop !5

for.end:                                          ; preds = %for.cond
  %7 = load i32, ptr %adjusted_value, align 4
  ret i32 %7
}

; Function Attrs: noinline nounwind uwtable
define dso_local i32 @main() #0 {
entry:
  %retval = alloca i32, align 4
  %data = alloca [4 x i32], align 16
  store i32 0, ptr %retval, align 4
  call void @llvm.memcpy.p0.p0.i64(ptr align 16 %data, ptr align 16 @__const.main.data, i64 16, i1 false)
  %arraydecay = getelementptr inbounds [4 x i32], ptr %data, i64 0, i64 0
  %call = call i32 @LICM(i32 noundef 7, ptr noundef %arraydecay)
  ret i32 %call
}

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias writeonly captures(none), ptr noalias readonly captures(none), i64, i1 immarg) #1

attributes #0 = { noinline nounwind uwtable "frame-pointer"="all" "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }

!llvm.module.flags = !{!0, !1, !2, !3}
!llvm.ident = !{!4}

!0 = !{i32 8, !"PIC Level", i32 2}
!1 = !{i32 7, !"PIE Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 2}
!3 = !{i32 7, !"frame-pointer", i32 2}
!4 = !{!"clang version 23.0.0git (/home/hoshimi/code/llvm-contribute/ 0ee12432c2741ba913d597bc03faab968c1d22bc)"}
!5 = distinct !{!5, !6}
!6 = !{!"llvm.loop.mustprogress"}
