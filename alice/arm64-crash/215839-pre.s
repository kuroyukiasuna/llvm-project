	.build_version macos, 26, 0	sdk_version 26, 5
	.section	__TEXT,__text,regular,pure_instructions
	.globl	_main                           ; -- Begin function main
	.p2align	2
_main:                                  ; @main
	.cfi_startproc
; %bb.0:                                ; %entry
	sub	sp, sp, #32
	stp	x29, x30, [sp, #16]             ; 16-byte Folded Spill
	add	x29, sp, #16
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	adrp	x8, _g1@PAGE
	ldr	w8, [x8, _g1@PAGEOFF]
	add	x8, x8, x8
	lsl	x9, x8, #31
	subs	x8, x8, x9, asr #31
	mov	x8, #4611686018427387904        ; =0x4000000000000000
	add	x8, x9, x8
	ccmp	x8, #0, #8, eq
	cset	w8, mi
	mov	w9, #860684288                  ; =0x334d0000
	fmov	d0, x9
	mov	w10, #24726                     ; =0x6096
	b	LBB0_1
LBB0_1:                                 ; %lbl_b59
                                        ; =>This Inner Loop Header: Depth=1
	rev16	w9, w10
	ext.8b	v1, v0, v0, #6
	trn1.4h	v0, v0, v1
	fmov	x10, d0
	and	x10, x10, #0xe000000000000000
	mov	x11, #2305843009213693952       ; =0x2000000000000000
	cmp	x10, x11
	b.ne	LBB0_4
; %bb.2:                                ; %if.then
                                        ;   in Loop: Header=BB0_1 Depth=1
	mov.h	v0[0], w9
	and	w10, w9, #0xffff
	ands	w11, w8, #0x1
	csel	w10, wzr, w10, ne
	str	d0, [sp, #8]
	add	x11, sp, #8
	bfi	x11, x10, #1, #2
	ldrsh	w10, [x11]
	subs	w11, w10, #1
	cset	w11, lt
	adrp	x12, _g19@PAGE
	strb	w11, [x12, _g19@PAGEOFF]
	mov	w11, #-28618                    ; =0xffff9036
	add	w10, w10, w11
	mov	w11, #9878                      ; =0x2696
	subs	w11, w11, w10, uxth
	b.eq	LBB0_5
	b	LBB0_3
LBB0_3:                                 ; %if.then
                                        ;   in Loop: Header=BB0_1 Depth=1
	mov	w11, #26065                     ; =0x65d1
	subs	w11, w11, w10, uxth
	b.eq	LBB0_5
	b	LBB0_1
LBB0_4:                                 ; %if.end
	adrp	x8, _g30@PAGE
	add	x8, x8, _g30@PAGEOFF
	strh	w9, [x8]
	bl	_abort
LBB0_5:                                 ; %sw.bb
	adrp	x8, _g30@PAGE
	add	x8, x8, _g30@PAGEOFF
	strh	w9, [x8]
	mov	w0, #0                          ; =0x0
	ldp	x29, x30, [sp, #16]             ; 16-byte Folded Reload
	add	sp, sp, #32
	ret
	.cfi_endproc
                                        ; -- End function
	.section	__DATA,__data
	.globl	_g1                             ; @g1
	.p2align	2, 0x0
_g1:
	.long	1662431956                      ; 0x6316b2d4

	.globl	_g30                            ; @g30
.zerofill __DATA,__common,_g30,2,1
	.globl	_f29_c9                         ; @f29_c9
.zerofill __DATA,__common,_f29_c9,1,0
	.globl	_g19                            ; @g19
.zerofill __DATA,__common,_g19,1,0
.subsections_via_symbols
