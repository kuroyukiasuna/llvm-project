target datalayout = "e-m:e-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128"
target triple = "aarch64-unknown-linux-gnu"

; std::find_if reduced to its essentials: unit-stride early-exit search through
; a pointer argument, live-out pointer. Attribute-light so it parses on older
; trees (e.g. the PR #180039 branch, based on Feb 2026 main).
define ptr @find_simple(ptr %first, ptr %last, i32 %v) {
entry:
  %cmp.not6 = icmp eq ptr %first, %last
  br i1 %cmp.not6, label %return, label %for.body.preheader
for.body.preheader:
  br label %for.body
for.body:
  %first.addr.07 = phi ptr [ %incdec.ptr, %for.inc ], [ %first, %for.body.preheader ]
  %0 = load i32, ptr %first.addr.07, align 4
  %cmp1 = icmp eq i32 %0, %v
  br i1 %cmp1, label %return.loopexit, label %for.inc
for.inc:
  %incdec.ptr = getelementptr inbounds i8, ptr %first.addr.07, i64 4
  %cmp.not = icmp eq ptr %incdec.ptr, %last
  br i1 %cmp.not, label %return.loopexit, label %for.body
return.loopexit:
  %retval.0.ph = phi ptr [ %first.addr.07, %for.body ], [ %last, %for.inc ]
  br label %return
return:
  %retval.0 = phi ptr [ %last, %entry ], [ %retval.0.ph, %return.loopexit ]
  ret ptr %retval.0
}
