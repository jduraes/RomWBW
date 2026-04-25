;
; Hardware/config helpers extracted from vibetune.asm.
; Includes YM2151 runtime port map and HBIOS sound port enumeration/config.
;
YM2151_PORTCFG:
	LD	A,(YM2151MAP)
	OR	A
	JR	Z,YM2151_PORTCFG_DE
	LD	A,0FEH
	LD	(YM2151SELV),A
	LD	A,0FFH
	LD	(YM2151DATV),A
	XOR	A
	LD	(YM2151SEL2V),A
	LD	(YM2151DAT2V),A
	RET
YM2151_PORTCFG_DE:
	LD	A,0DEH
	LD	(YM2151SELV),A
	LD	A,0DFH
	LD	(YM2151DATV),A
	XOR	A
	LD	(YM2151SEL2V),A
	LD	(YM2151DAT2V),A
	RET


HB_SND_GETMASK:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	;
	LD	BC,BC_SYSGET_SNDCNT
	RST	08
	LD	A,E
	OR	A
	JP	Z,HBGM_NONE
	LD	(HBGM_CNT),A
	XOR	A
	LD	(HBGM_IDX),A
	XOR	A
	LD	(HBGM_MASK),A
HBGM_LP:
	LD	A,(HBGM_IDX)
	LD	C,A					; sound unit number
	LD	B,BF_SNDQUERY
	LD	E,BF_SNDQ_DEV		; request device type + ports
	RST	08
	OR	A
	JR	NZ,HBGM_NXT
	;
	; For AY, query-dev returns ports in DE: D=RSEL, E=RDAT
	; We use RSEL as the base identifier for known mappings.
	LD	A,D			; RSEL
	CP	$A0
	JR	NZ,HBGM_C50
	LD	A,(HBGM_MASK)
	OR	1
	LD	(HBGM_MASK),A
	JR	HBGM_NXT
HBGM_C50:
	CP	$50
	JR	NZ,HBGM_CD8
	LD	A,(HBGM_MASK)
	OR	2
	LD	(HBGM_MASK),A
	JR	HBGM_NXT
HBGM_CD8:
	CP	$D8
	JR	NZ,HBGM_CD1
	LD	A,(HBGM_MASK)
	OR	4
	LD	(HBGM_MASK),A
	JR	HBGM_NXT
HBGM_CD1:
	CP	$D1
	JR	NZ,HBGM_NXT
	LD	A,(HBGM_MASK)
	OR	8
	LD	(HBGM_MASK),A
	JR	NZ,HBGM_NXT
HBGM_NXT:
	LD	A,(HBGM_IDX)
	INC	A
	LD	(HBGM_IDX),A
	LD	B,A
	LD	A,(HBGM_CNT)
	CP	B
	JR	NZ,HBGM_LP
	LD	A,(HBGM_MASK)
	OR	A
	JR	Z,HBGM_NONE
	;
	POP	HL
	POP	DE
	POP	BC
	LD	A,(HBGM_MASK)
	OR	A			; set flags
	RET
HBGM_NONE:
	POP	HL
	POP	DE
	POP	BC
	XOR	A
	OR	A			; Z set
	RET
HBGM_CNT	.DB	0
HBGM_IDX	.DB	0
HBGM_MASK	.DB	0
;
; Configure PSG ports from HBIOS sound enumeration.
; Preference order when multiple are present: Coleco, then MSX, then RC/EB, then RC/MF.
; Returns Z on success, NZ on failure.
;
HB_SND_AUTOCFG:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	CALL	HB_SND_GETMASK
	JP	Z,HBSA_FAIL
	LD	B,A			; B = mask (preserve before A is modified below)
	;
	; Ensure SLOWIO/NORMIO helpers are inert during probing
	LD	A,$FF
	LD	(Z180),A
	LD	(ACR),A
	LD	(ACRVAL),A
	;
	; HBIOS enumeration is the primary source, but on some systems a second
	; AY can exist without being enumerated. If HBIOS reports MSX only,
	; do a robust direct probe for Coleco ($50/$51, read at $52) and prefer
	; it when present.
	;
	BIT	1,B				; already know Coleco?
	JR	NZ,HBSA_PREF
	BIT	0,B				; only try probe if MSX exists
	JR	Z,HBSA_PREF
	PUSH	BC
	LD	HL,$5150		; RDAT=51, RSEL=50
	LD	A,$52			; readback
	CALL	PROBE_AY_IMPL
	POP	BC
	JR	NZ,HBSA_PREF
	SET	1,B				; found Coleco
;
HBSA_PREF:
	;
	; Choose preferred ports when multiple are present:
	; Coleco, then MSX, then RC/EB, then RC/MF.
	;
	BIT	1,B
	JR	NZ,HBSA_DO_COLECO
	BIT	0,B
	JR	NZ,HBSA_DO_MSX
	BIT	2,B
	JR	NZ,HBSA_DO_RCEB
	BIT	3,B
	JR	NZ,HBSA_DO_RCMF
	JR	HBSA_FAIL
	;
	; Record current platform id in active config
	;
HBSA_SETPLT:
	LD	A,(CURPLT)
	LD	(PLT),A
	RET
HBSA_DO_MSX:
	CALL	HBSA_SETPLT
HBSA_CONT:
	LD	A,$A0
	LD	(RSEL),A
	LD	A,$A1
	LD	(RDAT),A
	LD	A,$A2
	LD	(RIN),A
	LD	A,(CURPLT)
	CP	27
	JR	Z,HBSA_MSX_RC2014
	LD	HL,HWSTR_MSX
	JR	HBSA_DESC
HBSA_MSX_RC2014:
	LD	HL,HWSTR_RCMSX
	JR	HBSA_DESC
HBSA_DO_COLECO:
	LD	A,$50
	LD	(RSEL),A
	LD	A,$51
	LD	(RDAT),A
	LD	A,$52
	LD	(RIN),A
	LD	HL,HWSTR_COLECO
	JR	HBSA_DESC
HBSA_DO_RCEB:
	LD	A,$D8
	LD	(RSEL),A
	LD	A,$D0
	LD	(RDAT),A
	LD	A,$D8
	LD	(RIN),A
	LD	HL,HWSTR_RCEB
	JR	HBSA_DESC
HBSA_DO_RCMF:
	LD	A,$D1
	LD	(RSEL),A
	LD	A,$D0
	LD	(RDAT),A
	LD	A,$D0
	LD	(RIN),A
	LD	HL,HWSTR_RCMF
HBSA_DESC:
	LD	(DESC),HL
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	XOR	A
	RET
HBSA_FAIL:
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	OR	$FF
	RET
;
; Configure two distinct PSGs for TurboSound using HBIOS enumeration.
; Returns Z on success, NZ if fewer than two recognized PSG port sets found.
;
HB_SND_GET2:
	CALL	HB_SND_GETMASK
	JP	Z,HBS2_FAIL
	LD	B,A			; B = mask
	;
	; Prefer COLECO + MSX
	BIT	1,B
	JR	Z,HBS2_TRY_MSXRC
	BIT	0,B
	JR	Z,HBS2_TRY_MSXRC
	LD	HL,$5150
	LD	(TS_PORTS1),HL
	LD	DE,TSSTR_COLECO
	LD	(TS_DESC1),DE
	LD	HL,$A1A0
	LD	(TS_PORTS2),HL
	LD	DE,TSSTR_MSX
	LD	(TS_DESC2),DE
	XOR	A
	RET
HBS2_TRY_MSXRC:
	; MSX + RC/EB
	BIT	0,B
	JR	Z,HBS2_TRY_COLECORC
	BIT	2,B
	JR	Z,HBS2_TRY_MSXMF
	LD	HL,$A1A0
	LD	(TS_PORTS1),HL
	LD	DE,TSSTR_MSX
	LD	(TS_DESC1),DE
	LD	HL,$D0D8
	LD	(TS_PORTS2),HL
	LD	DE,TSSTR_RC
	LD	(TS_DESC2),DE
	XOR	A
	RET
HBS2_TRY_MSXMF:
	; MSX + RC/MF
	BIT	0,B
	JR	Z,HBS2_TRY_COLECORC
	BIT	3,B
	JR	Z,HBS2_TRY_COLECORC
	LD	HL,$A1A0
	LD	(TS_PORTS1),HL
	LD	DE,TSSTR_MSX
	LD	(TS_DESC1),DE
	LD	HL,$D0D1
	; NOTE: TSSTR_RC represents generic RC ports; MF uses D1/D0 too.
	LD	HL,$D0D1
	LD	(TS_PORTS2),HL
	LD	DE,TSSTR_RC
	LD	(TS_DESC2),DE
	XOR	A
	RET
HBS2_TRY_COLECORC:
	; COLECO + RC/EB
	BIT	1,B
	JR	Z,HBS2_TRY_COLECOMF
	BIT	2,B
	JR	Z,HBS2_TRY_COLECOMF
	LD	HL,$5150
	LD	(TS_PORTS1),HL
	LD	DE,TSSTR_COLECO
	LD	(TS_DESC1),DE
	LD	HL,$D0D8
	LD	(TS_PORTS2),HL
	LD	DE,TSSTR_RC
	LD	(TS_DESC2),DE
	XOR	A
	RET
HBS2_TRY_COLECOMF:
	; COLECO + RC/MF
	BIT	1,B
	JR	Z,HBS2_TRY_RCTWO
	BIT	3,B
	JR	Z,HBS2_TRY_RCTWO
	LD	HL,$5150
	LD	(TS_PORTS1),HL
	LD	DE,TSSTR_COLECO
	LD	(TS_DESC1),DE
	LD	HL,$D0D1
	LD	(TS_PORTS2),HL
	LD	DE,TSSTR_RC
	LD	(TS_DESC2),DE
	XOR	A
	RET
HBS2_TRY_RCTWO:
	; RC/EB + RC/MF
	BIT	2,B
	JR	Z,HBS2_FAIL
	BIT	3,B
	JR	Z,HBS2_FAIL
	LD	HL,$D0D8
	LD	(TS_PORTS1),HL
	LD	DE,TSSTR_RC
	LD	(TS_DESC1),DE
	LD	HL,$D0D1
	LD	(TS_PORTS2),HL
	LD	DE,TSSTR_RC
	LD	(TS_DESC2),DE
	XOR	A
	RET
HBS2_FAIL:
	OR	$FF
	RET
;

; Auto-select PSG hardware from HBIOS or config table scan.
AUTOSEL_IMPL:
	; Prefer HBIOS sound enumeration for auto selection. This avoids
	; relying on PSG register readback behavior for detection.
	CALL	HB_SND_AUTOCFG
	JR	NZ,AUTOSEL_FBK
	JP	MAT				; success: CFG populated, skip config table scan
AUTOSEL_FBK:
	LD	HL,CFGTBL		; Point to start of config table
CFGSEL_IMPL:
	LD	A,$FF			; End of table marker
	CP	(HL)			; Compare
	JP	Z,ERRHW			; Bail out if no more configs to try
;
	LD	BC,CFGSIZ		; Size of one entry
	LD	DE,CFG			; Active config structure
	LDIR				; Update active config structure
;
	LD	A,(CURPLT)		; Get current running platform id
	LD	E,A				; Put in E
	LD	A,(PLT)			; Get platform id of loaded config
	CP	E				; Equal?
	JR	NZ,CFGSEL_IMPL		; If no match keep trying
;
	; Activate card if applicable
	LD	B,0			; ensure 8-bit port addressing via BC
	LD	A,(ACR)		; Get ACR port address (if any)
	LD	C,A			; Copy to C for I/O later
	INC	A			; $FF -> $00 & set flags
	JR	Z,PROBE_IMPL		; If no ACR, skip ahead
	CALL	SLOWIO		; Slow down I/O for the activation write
	LD	A,(ACRVAL)	; Value to activate card
	OUT	(C),A		; Write value to ACR
	CALL	NORMIO		; Restore I/O speed
;
PROBE_IMPL:
	; Test for hardware (sound chip detection)
	; Use PROBE_AY_IMPL to avoid false positives from floating-bus echo behavior.
	LD	HL,(PORTS)		; HL = RDAT:RSEL
	LD	A,(RIN)			; A = RIN
	CALL	PROBE_AY_IMPL
	JP	Z,MAT			; Hardware matched!
	JR	CFGSEL_IMPL		; Keep trying

; Generic probe for an AY on ports (HL=RDAT:RSEL, A=RIN)
; Returns Z on success, NZ on failure.
PROBE_AY_IMPL:
	; Probe for an AY/YM PSG on the given ports.
	;
	; IMPORTANT: Avoid false positives when no device is present.
	; Many systems will read back the last value on the data bus ("floating bus"),
	; which can make naive write-then-read probes succeed.
	;
	; Strategy:
	; - Write two registers with distinct values.
	; - "Poison" the bus by writing a different value to RSEL before each read.
	; - Read back only from the intended read port:
	;     - If RIN == RDAT, read from RDAT (2-port designs).
	;     - Otherwise, read from RIN (dedicated readback at base+2).
	;
	DI
	PUSH	AF			; save RIN in A
	CALL	SLOWIO
	POP	AF
	LD	E,L			; E := RSEL
	LD	D,H			; D := RDAT
	LD	L,A			; L := RIN
	LD	B,0			; ensure 8-bit port addressing via BC
	;
	; Write R2 = 55h
	LD	C,E
	LD	A,2
	OUT	(C),A
	LD	C,D
	LD	A,$55
	OUT	(C),A
	;
	; Write R3 = AAh
	LD	C,E
	LD	A,3
	OUT	(C),A
	LD	C,D
	LD	A,$AA
	OUT	(C),A
	;
	; Decide read port: H := (RIN == RDAT) ? RDAT : RIN
	LD	A,L
	CP	D
	JR	Z,PRBAYI_RDAT
	LD	H,L
	JR	PRBAYI_RSEL2
PRBAYI_RDAT:
	LD	H,D
	;
	; Read R2, expect 55h
PRBAYI_RSEL2:
	LD	C,E
	LD	A,0			; poison bus (and selection)
	OUT	(C),A
	LD	A,2
	OUT	(C),A
	LD	C,H
	IN	A,(C)
	CP	$55
	JR	NZ,PRBAYI_FAIL
	;
	; Read R3, expect AAh
	LD	C,E
	LD	A,0			; poison bus
	OUT	(C),A
	LD	A,3
	OUT	(C),A
	LD	C,H
	IN	A,(C)
	CP	$AA
	JR	NZ,PRBAYI_FAIL
	;
	CALL	NORMIO
	EI
	XOR	A			; success, Z set
	RET
PRBAYI_FAIL:
	CALL	NORMIO
	EI
	OR	$FF			; failure, NZ set
	RET

; Probe for the two AY cards expected for TurboSound playback.
TS_PORTS_SETUP_IMPL:
	;
	; Prefer HBIOS enumeration to find two distinct PSG port sets.
	;
	CALL	HB_SND_GET2
	RET	Z
	;
	; Fallback: use current PORTS as chip #1 and pick a different known port set
	; without relying on readback.
	;
	LD	HL,(PORTS)		; HL = chip1 ports (RDAT:RSEL)
	LD	(TS_PORTS1),HL
	LD	DE,TSSTR_MSX
	LD	BC,$A1A0
	OR	A
	SBC	HL,BC
	JR	Z,TS_SETD1_IMPL
	LD	DE,TSSTR_COLECO
	ADD	HL,BC			; restore HL
	LD	BC,$5150
	OR	A
	SBC	HL,BC
	JR	Z,TS_SETD1_IMPL
	LD	DE,TSSTR_RC
TS_SETD1_IMPL:
	LD	(TS_DESC1),DE
	;
	; Choose chip2 by excluding chip1
	LD	HL,(TS_PORTS1)
	LD	DE,$5150
	OR	A
	SBC	HL,DE
	JR	Z,TS_FBK2_MSX_IMPL
	LD	HL,$5150
	LD	(TS_PORTS2),HL
	LD	DE,TSSTR_COLECO
	LD	(TS_DESC2),DE
	RET
TS_FBK2_MSX_IMPL:
	LD	HL,$A1A0
	LD	(TS_PORTS2),HL
	LD	DE,TSSTR_MSX
	LD	(TS_DESC2),DE
	RET

; Adjust timing in delay mode to compensate for extra TS work.
; In timer mode, the timer gate already keeps playback on tempo.
TS_ADJTIM_IMPL:
	LD	A,(WMOD)		; timer mode?
	OR	A
	RET	NZ			; if timer mode, no adjustment
	;
	; Tune delay for TS (empirically): QDLY := QDLY * 97 / 128
	; This is 3/4 (96/128) plus 1/128.
	;
	LD	HL,(QDLY)		; base delay count
	LD	B,H
	LD	C,L			; BC = base
	;
	; DE = base/4
	LD	H,B
	LD	L,C
	SRL	H
	RR	L
	SRL	H
	RR	L
	EX	DE,HL
	;
	; HL = 3/4 base
	LD	H,B
	LD	L,C
	OR	A			; clear carry
	SBC	HL,DE
	;
	; HL = 3/4 base + base/128
	PUSH	HL			; save 3/4 base
	LD	H,B
	LD	L,C
	LD	A,7
TS_ADJ2_IMPL:
	SRL	H
	RR	L
	DEC	A
	JR	NZ,TS_ADJ2_IMPL		; HL = base/128
	POP	DE
	ADD	HL,DE
	LD	(QDLY),HL
	RET

TS_SETPORTS1_IMPL:
	LD	HL,(TS_PORTS1)
	LD	(PORTS),HL
	RET

TS_SETPORTS2_IMPL:
	LD	HL,(TS_PORTS2)
	LD	(PORTS),HL
	RET



