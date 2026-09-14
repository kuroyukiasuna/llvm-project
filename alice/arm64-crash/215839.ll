; ModuleID = 'arm64-crash/215839.c'
source_filename = "arm64-crash/215839.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx26.0.0"

@g1 = local_unnamed_addr global i32 1662431956, align 4
@g30 = local_unnamed_addr global i16 0, align 2
@f29_c9 = local_unnamed_addr global i8 0, align 1
@g19 = local_unnamed_addr global i8 0, align 1

; Function Attrs: nofree nounwind ssp uwtable(sync)
define noundef i32 @main() local_unnamed_addr #0 {
entry:
  %0 = load i32, ptr @g1, align 4
  %1 = zext i32 %0 to i33
  %2 = tail call { i33, i1 } @llvm.sadd.with.overflow.i33(i33 %1, i33 %1)
  %3 = extractvalue { i33, i1 } %2, 1
  %4 = extractvalue { i33, i1 } %2, 0
  %5 = add i33 %4, 2147483648
  %6 = icmp slt i33 %5, 0
  %7 = or i1 %3, %6
  br label %lbl_b59

lbl_b59:                                          ; preds = %if.then, %entry
  %v10.0 = phi i16 [ 24726, %entry ], [ %add, %if.then ]
  %bc4.0 = phi <4 x i16> [ <i16 0, i16 13133, i16 0, i16 0>, %entry ], [ %vecins, %if.then ]
  %8 = tail call i16 @llvm.bswap.i16(i16 %v10.0)
  %shuffle = shufflevector <4 x i16> %bc4.0, <4 x i16> poison, <4 x i32> <i32 0, i32 3, i32 2, i32 1>
  %9 = bitcast <4 x i16> %shuffle to i64
  %10 = and i64 %9, -2305843009213693952
  %cmp = icmp eq i64 %10, 2305843009213693952
  br i1 %cmp, label %if.then, label %if.end

if.then:                                          ; preds = %lbl_b59
  %vecins = insertelement <4 x i16> %shuffle, i16 %8, i64 0
  %conv = zext i16 %8 to i32
  %cond = select i1 %7, i32 0, i32 %conv
  %vecext = extractelement <4 x i16> %vecins, i32 %cond
  %cmp2 = icmp slt i16 %vecext, 1
  %storedv = zext i1 %cmp2 to i8
  store i8 %storedv, ptr @g19, align 1, !tbaa !10
  %add = add i16 %vecext, -28618
  switch i16 %add, label %lbl_b59 [
    i16 9878, label %sw.bb
    i16 26065, label %sw.bb
  ]

if.end:                                           ; preds = %lbl_b59
  store i16 %8, ptr @g30, align 2, !tbaa !12
  tail call void @abort() #3
  unreachable

sw.bb:                                            ; preds = %if.then, %if.then
  store i16 %8, ptr @g30, align 2, !tbaa !12
  ret i32 0
}

; Function Attrs: mustprogress nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare i16 @llvm.bswap.i16(i16) #1

; Function Attrs: cold nofree noreturn nounwind
declare void @abort() local_unnamed_addr #2

; Function Attrs: mustprogress nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare { i33, i1 } @llvm.sadd.with.overflow.i33(i33, i33) #1

attributes #0 = { nofree nounwind ssp uwtable(sync) "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" "tune-cpu"="apple-m5" }
attributes #1 = { mustprogress nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none) }
attributes #2 = { cold nofree noreturn nounwind "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" "tune-cpu"="apple-m5" }
attributes #3 = { cold noreturn nounwind }

!llvm.module.flags = !{!0, !1, !2, !3}
!llvm.ident = !{!4}
!llvm.errno.tbaa = !{!5}

!0 = !{i32 2, !"SDK Version", [2 x i32] [i32 26, i32 5]}
!1 = !{i32 8, !"PIC Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 1}
!3 = !{i32 7, !"frame-pointer", i32 4}
!4 = !{!"clang version 24.0.0git (hoshimi@fbk01:/home/hoshimi/code/llvm-contribute 1fb85afe43ccf09792b68508420d6aef9bd48e55)"}
!5 = !{!6, !7, i64 0}
!6 = !{!"__libc_errno", !7, i64 0}
!7 = !{!"int", !8, i64 0}
!8 = !{!"omnipotent char", !9, i64 0}
!9 = !{!"Simple C/C++ TBAA"}
!10 = !{!11, !11, i64 0}
!11 = !{!"_Bool", !8, i64 0}
!12 = !{!13, !13, i64 0}
!13 = !{!"short", !8, i64 0}
