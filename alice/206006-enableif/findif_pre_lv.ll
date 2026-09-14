; ModuleID = '/tmp/findif.cpp'
source_filename = "/tmp/findif.cpp"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"
; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: read) uwtable
define dso_local noundef ptr @_Z11find_simplePiS_i(ptr nofree noundef readonly captures(address, ret: address, provenance) %first, ptr nofree noundef readnone captures(address, ret: address, provenance) %last, i32 noundef %v) local_unnamed_addr #0 {
entry:
  %cmp.not6 = icmp eq ptr %first, %last
  br i1 %cmp.not6, label %return, label %for.body.preheader
for.body.preheader:                               ; preds = %entry
  br label %for.body
for.body:                                         ; preds = %for.body.preheader, %for.inc
  %first.addr.07 = phi ptr [ %incdec.ptr, %for.inc ], [ %first, %for.body.preheader ]
  %0 = load i32, ptr %first.addr.07, align 4, !tbaa !9
  %cmp1 = icmp eq i32 %0, %v
  br i1 %cmp1, label %return.loopexit, label %for.inc
for.inc:                                          ; preds = %for.body
  %incdec.ptr = getelementptr inbounds nuw i8, ptr %first.addr.07, i64 4
  %cmp.not = icmp eq ptr %incdec.ptr, %last
  br i1 %cmp.not, label %return.loopexit, label %for.body, !llvm.loop !10
return.loopexit:                                  ; preds = %for.inc, %for.body
  %retval.0.ph = phi ptr [ %first.addr.07, %for.body ], [ %last, %for.inc ]
  br label %return
return:                                           ; preds = %return.loopexit, %entry
  %retval.0 = phi ptr [ %last, %entry ], [ %retval.0.ph, %return.loopexit ]
  ret ptr %retval.0
}
; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: read) uwtable
define dso_local noundef ptr @_Z14find_unrolled4PiS_i(ptr noundef %first, ptr noundef %last, i32 noundef %v) local_unnamed_addr #0 {
entry:
  %sub.ptr.lhs.cast = ptrtoint ptr %last to i64
  %sub.ptr.rhs.cast = ptrtoint ptr %first to i64
  %sub.ptr.sub = sub i64 %sub.ptr.lhs.cast, %sub.ptr.rhs.cast
  %shr = ashr i64 %sub.ptr.sub, 4
  %cmp77 = icmp sgt i64 %shr, 0
  br i1 %cmp77, label %for.body.preheader, label %for.end
for.body.preheader:                               ; preds = %entry
  %0 = and i64 %sub.ptr.sub, -16
  %scevgep = getelementptr i8, ptr %first, i64 %0
  br label %for.body
for.body:                                         ; preds = %for.body.preheader, %if.end12
  %n.079 = phi i64 [ %dec, %if.end12 ], [ %shr, %for.body.preheader ]
  %first.addr.078 = phi ptr [ %incdec.ptr13, %if.end12 ], [ %first, %for.body.preheader ]
  %1 = load i32, ptr %first.addr.078, align 4, !tbaa !9
  %cmp1 = icmp eq i32 %1, %v
  br i1 %cmp1, label %return, label %if.end
if.end:                                           ; preds = %for.body
  %incdec.ptr = getelementptr inbounds nuw i8, ptr %first.addr.078, i64 4
  %2 = load i32, ptr %incdec.ptr, align 4, !tbaa !9
  %cmp2 = icmp eq i32 %2, %v
  br i1 %cmp2, label %return.loopexit.split.loop.exit, label %if.end4
if.end4:                                          ; preds = %if.end
  %incdec.ptr5 = getelementptr inbounds nuw i8, ptr %first.addr.078, i64 8
  %3 = load i32, ptr %incdec.ptr5, align 4, !tbaa !9
  %cmp6 = icmp eq i32 %3, %v
  br i1 %cmp6, label %return.loopexit.split.loop.exit85, label %if.end8
if.end8:                                          ; preds = %if.end4
  %incdec.ptr9 = getelementptr inbounds nuw i8, ptr %first.addr.078, i64 12
  %4 = load i32, ptr %incdec.ptr9, align 4, !tbaa !9
  %cmp10 = icmp eq i32 %4, %v
  br i1 %cmp10, label %return.loopexit.split.loop.exit87, label %if.end12
if.end12:                                         ; preds = %if.end8
  %incdec.ptr13 = getelementptr inbounds nuw i8, ptr %first.addr.078, i64 16
  %dec = add nsw i64 %n.079, -1
  %cmp = icmp sgt i64 %n.079, 1
  br i1 %cmp, label %for.body, label %for.end.loopexit, !llvm.loop !12
for.end.loopexit:                                 ; preds = %if.end12
  %.pre = ptrtoint ptr %scevgep to i64
  %.pre84 = sub i64 %sub.ptr.lhs.cast, %.pre
  br label %for.end
for.end:                                          ; preds = %for.end.loopexit, %entry
  %sub.ptr.sub16.pre-phi = phi i64 [ %.pre84, %for.end.loopexit ], [ %sub.ptr.sub, %entry ]
  %first.addr.0.lcssa = phi ptr [ %scevgep, %for.end.loopexit ], [ %first, %entry ]
  %sub.ptr.div17 = ashr exact i64 %sub.ptr.sub16.pre-phi, 2
  switch i64 %sub.ptr.div17, label %sw.default [
    i64 3, label %sw.bb
    i64 2, label %sw.bb22
    i64 1, label %sw.bb27
  ]
sw.bb:                                            ; preds = %for.end
  %5 = load i32, ptr %first.addr.0.lcssa, align 4, !tbaa !9
  %cmp18 = icmp eq i32 %5, %v
  br i1 %cmp18, label %return, label %if.end20
if.end20:                                         ; preds = %sw.bb
  %incdec.ptr21 = getelementptr inbounds nuw i8, ptr %first.addr.0.lcssa, i64 4
  br label %sw.bb22
sw.bb22:                                          ; preds = %for.end, %if.end20
  %first.addr.2 = phi ptr [ %incdec.ptr21, %if.end20 ], [ %first.addr.0.lcssa, %for.end ]
  %6 = load i32, ptr %first.addr.2, align 4, !tbaa !9
  %cmp23 = icmp eq i32 %6, %v
  br i1 %cmp23, label %return, label %if.end25
if.end25:                                         ; preds = %sw.bb22
  %incdec.ptr26 = getelementptr inbounds nuw i8, ptr %first.addr.2, i64 4
  br label %sw.bb27
sw.bb27:                                          ; preds = %for.end, %if.end25
  %first.addr.3 = phi ptr [ %incdec.ptr26, %if.end25 ], [ %first.addr.0.lcssa, %for.end ]
  %7 = load i32, ptr %first.addr.3, align 4, !tbaa !9
  %cmp28 = icmp eq i32 %7, %v
  br i1 %cmp28, label %return, label %sw.default
sw.default:                                       ; preds = %sw.bb27, %for.end
  br label %return
return.loopexit.split.loop.exit:                  ; preds = %if.end
  %incdec.ptr.le = getelementptr inbounds nuw i8, ptr %first.addr.078, i64 4
  br label %return
return.loopexit.split.loop.exit85:                ; preds = %if.end4
  %incdec.ptr5.le = getelementptr inbounds nuw i8, ptr %first.addr.078, i64 8
  br label %return
return.loopexit.split.loop.exit87:                ; preds = %if.end8
  %incdec.ptr9.le = getelementptr inbounds nuw i8, ptr %first.addr.078, i64 12
  br label %return
return:                                           ; preds = %return.loopexit.split.loop.exit, %return.loopexit.split.loop.exit85, %return.loopexit.split.loop.exit87, %for.body, %sw.bb27, %sw.bb22, %sw.bb, %sw.default
  %retval.1 = phi ptr [ %last, %sw.default ], [ %first.addr.3, %sw.bb27 ], [ %first.addr.0.lcssa, %sw.bb ], [ %first.addr.2, %sw.bb22 ], [ %incdec.ptr9.le, %return.loopexit.split.loop.exit87 ], [ %incdec.ptr5.le, %return.loopexit.split.loop.exit85 ], [ %incdec.ptr.le, %return.loopexit.split.loop.exit ], [ %first.addr.078, %for.body ]
  ret ptr %retval.1
}
; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: read) uwtable
define dso_local noundef zeroext i1 @_Z6any_eqPKiS0_i(ptr nofree noundef readonly captures(address) %first, ptr nofree noundef readnone captures(address) %last, i32 noundef %v) local_unnamed_addr #0 {
entry:
  %cmp.not4.not = icmp eq ptr %first, %last
  br i1 %cmp.not4.not, label %return, label %for.body
for.cond:                                         ; preds = %for.body
  %incdec.ptr = getelementptr inbounds nuw i8, ptr %first.addr.05, i64 4
  %cmp.not.not = icmp eq ptr %incdec.ptr, %last
  br i1 %cmp.not.not, label %return, label %for.body, !llvm.loop !13
for.body:                                         ; preds = %entry, %for.cond
  %first.addr.05 = phi ptr [ %incdec.ptr, %for.cond ], [ %first, %entry ]
  %0 = load i32, ptr %first.addr.05, align 4, !tbaa !9
  %cmp1 = icmp eq i32 %0, %v
  br i1 %cmp1, label %return, label %for.cond
return:                                           ; preds = %for.body, %for.cond, %entry
  %cmp.not.lcssa = phi i1 [ false, %entry ], [ true, %for.body ], [ false, %for.cond ]
  ret i1 %cmp.not.lcssa
}
attributes #0 = { mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: read) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="skylake-avx512" "target-features"="+adx,+aes,+avx,+avx2,+avx512bw,+avx512cd,+avx512dq,+avx512f,+avx512vl,+bmi,+bmi2,+clflushopt,+clwb,+cmov,+crc32,+cx16,+cx8,+f16c,+fma,+fsgsbase,+fxsr,+invpcid,+lzcnt,+mmx,+movbe,+pclmul,+pku,+popcnt,+prfchw,+rdrnd,+rdseed,+sahf,+sse,+sse2,+sse3,+sse4.1,+sse4.2,+ssse3,+x87,+xsave,+xsavec,+xsaveopt,+xsaves" }
!llvm.module.flags = !{!0, !1, !2}
!llvm.ident = !{!3}
!llvm.errno.tbaa = !{!4}
!0 = !{i32 8, !"PIC Level", i32 2}
!1 = !{i32 7, !"PIE Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 2}
!3 = !{!"clang version 24.0.0git (hoshimi@fbk01:/home/hoshimi/code/llvm-contribute 1fb85afe43ccf09792b68508420d6aef9bd48e55)"}
!4 = !{!5, !6, i64 0}
!5 = !{!"__libc_errno", !6, i64 0}
!6 = !{!"int", !7, i64 0}
!7 = !{!"omnipotent char", !8, i64 0}
!8 = !{!"Simple C++ TBAA"}
!9 = !{!6, !6, i64 0}
!10 = distinct !{!10, !11}
!11 = !{!"llvm.loop.mustprogress"}
!12 = distinct !{!12, !11}
!13 = distinct !{!13, !11}
