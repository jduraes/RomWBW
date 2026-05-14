;-------------------------------------------------------------------------
; TurboSound runtime/context helpers 
;-------------------------------------------------------------------------

; Initialize both packed PT3 modules as independent instances.
;
TS_INIT:
	; save a pristine template of the player state
	LD	HL,TS_CTXTMPL_VARS
	LD	(CTX_VPTR),HL
	LD	HL,TS_CTXTMPL_PATCH
	LD	(CTX_PPTR),HL
	CALL	CTX_SAVE
	; init instance 1 @ MDLADDR on chip 1
	CALL	TS_SETPORTS1_IMPL
	CALL	TS_LOAD_TMPL
	LD	HL,MDLADDR
	CALL	INIT
	CALL	TS_SAVE_CTX1
	LD	A,(SETUP)
	LD	(TSSET1),A
	; init instance 2 @ MDLADDR+TS_OFF2 on chip 2
	CALL	TS_SETPORTS2_IMPL
	CALL	TS_LOAD_TMPL
	LD	HL,MDLADDR
	LD	DE,(TS_OFF2)
	ADD	HL,DE
	CALL	INIT
	CALL	TS_SAVE_CTX2
	LD	A,(SETUP)
	LD	(TSSET2),A
	RET
;
; Play one quark on both instances.
;
TS_PLAYQUARK:
	CALL	TS_LOAD_CTX1
	CALL	TS_SETPORTS1_IMPL
	CALL	PLAY
	LD	A,(SETUP)
	LD	(TSSET1),A
	CALL	TS_SAVE_CTX1
	CALL	TS_LOAD_CTX2
	CALL	TS_SETPORTS2_IMPL
	CALL	PLAY
	LD	A,(SETUP)
	LD	(TSSET2),A
	CALL	TS_SAVE_CTX2
	RET
;
; Mute both chips.
;
TS_MUTE:
	CALL	TS_LOAD_CTX1
	CALL	TS_SETPORTS1_IMPL
	CALL	MUTE
	CALL	TS_SAVE_CTX1
	CALL	TS_LOAD_CTX2
	CALL	TS_SETPORTS2_IMPL
	CALL	MUTE
	CALL	TS_SAVE_CTX2
	RET
;
; Adjust timing in delay mode to compensate for extra TS work.
; In timer mode, the timer gate already keeps playback on tempo.
;
; Context save/restore helpers
;
TS_LOAD_TMPL:
	LD	HL,TS_CTXTMPL_VARS
	LD	(CTX_VPTR),HL
	LD	HL,TS_CTXTMPL_PATCH
	LD	(CTX_PPTR),HL
	JP	CTX_LOAD
TS_SAVE_CTX1:
	LD	HL,TS_CTX1_VARS
	LD	(CTX_VPTR),HL
	LD	HL,TS_CTX1_PATCH
	LD	(CTX_PPTR),HL
	JP	CTX_SAVE
TS_LOAD_CTX1:
	LD	HL,TS_CTX1_VARS
	LD	(CTX_VPTR),HL
	LD	HL,TS_CTX1_PATCH
	LD	(CTX_PPTR),HL
	JP	CTX_LOAD
TS_SAVE_CTX2:
	LD	HL,TS_CTX2_VARS
	LD	(CTX_VPTR),HL
	LD	HL,TS_CTX2_PATCH
	LD	(CTX_PPTR),HL
	JP	CTX_SAVE
TS_LOAD_CTX2:
	LD	HL,TS_CTX2_VARS
	LD	(CTX_VPTR),HL
	LD	HL,TS_CTX2_PATCH
	LD	(CTX_PPTR),HL
	JP	CTX_LOAD
;
; Save/restore the Bulba player state (heap vars + self-modified bytes).
;
PTX_PATCHSZ	.EQU	52
;
PTX_PATCHTBL:
	; addr, len
	.DW	SETUP				; setup byte (loop status bit 7)
	.DB	1
	.DW	PTDECOD+1
	.DB	2
	.DW	PsCalc
	.DB	2
	.DW	PDSP_+1
	.DB	2
	.DW	PSP_+1
	.DB	2
	.DW	CSP_+1
	.DB	2
	.DW	L3
	.DB	1
	.DW	M2
	.DB	1
	.DW	OrnCP
	.DB	1
	.DW	OrnLD
	.DB	1
	.DW	SamClc2
	.DB	1
	.DW	SamCP
	.DB	1
	.DW	SamLD
	.DB	1
	.DW	SamCnv
	.DB	2
	.DW	PrNote+1
	.DB	1
	.DW	PrSlide+1
	.DB	2
	.DW	Version
	.DB	1
	.DW	LoStep
	.DB	1
	.DW	OrnPtrs
	.DB	2
	.DW	MDADDR2
	.DB	2
	.DW	SamPtrs
	.DB	2
	.DW	MDADDR1
	.DB	2
	.DW	AdInPtA
	.DB	2
	.DW	CrPsPtr
	.DB	2
	.DW	LPosPtr
	.DB	2
	.DW	PatsPtr
	.DB	2
	.DW	MODADDR
	.DB	2
	.DW	AdInPtB
	.DB	2
	.DW	AdInPtC
	.DB	2
	.DW	Delay
	.DB	1
	.DW	AddToEn
	.DB	1
	.DW	Env_Del
	.DB	1
	.DW	ESldAdd
	.DB	2
	.DW	$FFFF
	.DB	0
;
CTX_SAVE:
	LD	HL,VARS
	LD	DE,(CTX_VPTR)
	LD	BC,PTX_CTXSIZ
	LDIR
	LD	IX,PTX_PATCHTBL
	LD	DE,(CTX_PPTR)
CTX_SLP:
	LD	L,(IX+0)
	LD	H,(IX+1)
	LD	A,H
	CP	$FF
	JR	NZ,CTX_SHAVE
	LD	A,L
	CP	$FF
	RET	Z
CTX_SHAVE:
	LD	C,(IX+2)
	LD	B,0
	LDIR
	LD	BC,3
	ADD	IX,BC
	JR	CTX_SLP
;
CTX_LOAD:
	LD	HL,(CTX_VPTR)
	LD	DE,VARS
	LD	BC,PTX_CTXSIZ
	LDIR
	LD	IX,PTX_PATCHTBL
	LD	HL,(CTX_PPTR)
CTX_LLP:
	LD	E,(IX+0)
	LD	D,(IX+1)
	LD	A,D
	CP	$FF
	JR	NZ,CTX_LHAVE
	LD	A,E
	CP	$FF
	RET	Z
CTX_LHAVE:
	LD	C,(IX+2)
	LD	B,0
	LDIR
	LD	BC,3
	ADD	IX,BC
	JR	CTX_LLP

;===============================================================================
; TurboSound-packed PT3 support ("PT3! <off> PT3! <len> 02 TS" footer)
;===============================================================================
;
PT3SIG0	.EQU	'P'
PT3SIG1	.EQU	'T'
PT3SIG2	.EQU	'3'
PT3SIG3	.EQU	'!'
TSSIG0	.EQU	'T'
TSSIG1	.EQU	'S'
;
; Scan loaded (padded) PT3 data for the TurboSound footer.
; Sets TSFLAG non-zero and records TS_OFF2/TS_LEN2 if found.
;
TS_DETECT:
	XOR	A
	LD	(TSFLAG),A
	LD	HL,(LOADBYTES)
	LD	DE,16
	OR	A
	SBC	HL,DE
	RET	C
	LD	B,H
	LD	C,L			; BC = bytes_to_scan
	LD	IX,MDLADDR
TS_DLP:
	LD	A,(IX+0)
	CP	PT3SIG0
	JP	NZ,TS_DNXT
	LD	A,(IX+1)
	CP	PT3SIG1
	JP	NZ,TS_DNXT
	LD	A,(IX+2)
	CP	PT3SIG2
	JP	NZ,TS_DNXT
	LD	A,(IX+3)
	CP	PT3SIG3
	JP	NZ,TS_DNXT
	; check second PT3! at +6
	LD	A,(IX+6)
	CP	PT3SIG0
	JP	NZ,TS_DNXT
	LD	A,(IX+7)
	CP	PT3SIG1
	JP	NZ,TS_DNXT
	LD	A,(IX+8)
	CP	PT3SIG2
	JP	NZ,TS_DNXT
	LD	A,(IX+9)
	CP	PT3SIG3
	JP	NZ,TS_DNXT
	; check marker "02TS" at +12
	LD	A,(IX+12)
	CP	'0'
	JP	NZ,TS_DNXT
	LD	A,(IX+13)
	CP	'2'
	JP	NZ,TS_DNXT
	LD	A,(IX+14)
	CP	TSSIG0
	JP	NZ,TS_DNXT
	LD	A,(IX+15)
	CP	TSSIG1
	JP	NZ,TS_DNXT
	; validate candidate offset equals off2 + len2
	LD	E,(IX+4)		; DE = off2
	LD	D,(IX+5)
	LD	L,(IX+10)		; HL = len2
	LD	H,(IX+11)
	ADD	HL,DE			; HL = off2 + len2
	LD	A,H
	OR	L
	JP	Z,TS_DNXT		; reject zero-size relation
	PUSH	HL			; save off2 + len2
	PUSH	IX
	POP	BC			; BC = candidate absolute address
	LD	H,B
	LD	L,C			; HL = candidate absolute address
	LD	DE,MDLADDR
	OR	A
	SBC	HL,DE			; HL = candidate file-relative offset
	EX	DE,HL			; DE = candidate offset
	POP	HL			; HL = off2 + len2
	OR	A
	SBC	HL,DE
	JP	NZ,TS_DNXT
	; record module2 offset and length
	LD	E,(IX+4)
	LD	D,(IX+5)
	LD	(TS_OFF2),DE
	LD	E,(IX+10)
	LD	D,(IX+11)
	LD	(TS_LEN2),DE
	LD	A,$FF
	LD	(TSFLAG),A
	RET
TS_DNXT:
	INC	IX
	DEC	BC
	LD	A,B
	OR	C
	JP	NZ,TS_DLP
	RET
