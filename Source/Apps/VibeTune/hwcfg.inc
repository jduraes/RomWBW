;
; Hardware/config helpers extracted from vibetune.asm.
; Includes YM2151 runtime port map and HBIOS sound port enumeration/config.
;
YM2151_PORTCFG:
	LD	A,(YM2151MAP)
	OR	A
	LD	A,YM2151_PRIMARY_SEL
	LD	C,YM2151_PRIMARY_DAT
	JR	Z,YM2151_PORTCFG_SET
	LD	A,YM2151_ALT_SEL
	LD	C,YM2151_ALT_DAT
YM2151_PORTCFG_SET:
	LD	(YM2151SELV),A
	LD	A,C
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
	JR	Z,HBGM_NONE
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
	CP	PSG_MSX_RSEL
	JR	NZ,HBGM_C50
	LD	A,1
	JR	HBGM_SETBIT
HBGM_C50:
	CP	PSG_COLECO_RSEL
	JR	NZ,HBGM_CD8
	LD	A,2
	JR	HBGM_SETBIT
HBGM_CD8:
	CP	PSG_RCEB_RSEL
	JR	Z,HBGM_SET_RCEB
	CP	PSG_RCEB_Z180_RSEL
	JR	NZ,HBGM_CD1
HBGM_SET_RCEB:
	LD	A,4
	JR	HBGM_SETBIT
HBGM_CD1:
	CP	PSG_RCMF_RSEL
	JR	Z,HBGM_SET_RCMF
	CP	PSG_RCMF_Z180_RSEL
	JR	NZ,HBGM_NXT
HBGM_SET_RCMF:
	LD	A,8
HBGM_SETBIT:
	LD	C,A
	LD	A,(HBGM_MASK)
	OR	C
	LD	(HBGM_MASK),A
HBGM_NXT:
	LD	A,(HBGM_IDX)
	INC	A
	LD	(HBGM_IDX),A
	LD	B,A
	LD	A,(HBGM_CNT)
	CP	B
	JR	NZ,HBGM_LP
	LD	A,(HBGM_MASK)
	JR	HBGM_DONE
HBGM_NONE:
	XOR	A
HBGM_DONE:
	POP	HL
	POP	DE
	POP	BC
	OR	A			; set flags
	RET
HBGM_CNT	.DB	0
HBGM_IDX	.DB	0
HBGM_MASK	.DB	0
;
; Configure PSG ports from HBIOS sound enumeration.
; Preference order when multiple are present: MSX, then Coleco, then RC/EB, then RC/MF.
; Returns Z on success, NZ on failure.
;
HB_SND_AUTOCFG:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	CALL	HB_SND_GETMASK
	JP	Z,HBSA_FAIL
	LD	B,A			; B = mask (preserve before A is modified below)
	;
	; Ensure SLOWIO/NORMIO helpers are inert during probing
	LD	A,PORT_NONE
	LD	(Z180),A
	LD	(ACR),A
	LD	(ACRVAL),A
	;
	; HBIOS enumeration is the primary source, but on some systems a second
	; AY can exist without being enumerated. If HBIOS reports MSX only,
	; do a robust direct probe for Coleco (PSG_COLECO_RSEL/PSG_COLECO_RDAT,
	; read at PSG_COLECO_RIN) so it can
	; still be used as secondary/fallback when present.
	;
	BIT	1,B				; already know Coleco?
	JR	NZ,HBSA_PREF
	BIT	0,B				; only try probe if MSX exists
	JR	Z,HBSA_PREF
	PUSH	BC
	LD	HL,PSG_COLECO_PORTW	; Coleco RDAT:RSEL packed word
	LD	A,PSG_COLECO_RIN	; readback port
	CALL	PROBE_AY_IMPL
	POP	BC
	JR	NZ,HBSA_PREF
	SET	1,B				; found Coleco
;
HBSA_PREF:
	;
	; Choose preferred ports when multiple are present:
	; MSX, then Coleco, then RC/EB, then RC/MF.
	;
	BIT	0,B
	JR	NZ,HBSA_DO_MSX
	BIT	1,B
	JR	NZ,HBSA_DO_COLECO
	BIT	2,B
	JR	NZ,HBSA_DO_RCEB
	BIT	3,B
	JR	NZ,HBSA_DO_RCMF
	JP	HBSA_FAIL
	;
	; Record current platform id in active config
	;
HBSA_SETPLT:
	LD	A,(CURPLT)
	LD	(PLT),A
	RET
HBSA_DO_MSX:
	CALL	HBSA_SETPLT
	LD	HL,HWSTR_MSX
	LD	A,(CURPLT)
	CP	27
	JR	NZ,HBSA_DO_MSX0
	LD	HL,HWSTR_RCMSX
HBSA_DO_MSX0:
	LD	A,PSG_MSX_RSEL
	LD	D,PSG_MSX_RDAT
	LD	E,PSG_MSX_RIN
	JR	HBSA_APPLY
HBSA_DO_COLECO:
	LD	A,PSG_COLECO_RSEL
	LD	D,PSG_COLECO_RDAT
	LD	E,PSG_COLECO_RIN
	LD	HL,HWSTR_COLECO
	JR	HBSA_APPLY
HBSA_DO_RCEB:
	CALL	HBSA_SETPLT
	LD	HL,HWSTR_RCEB
	LD	A,(CURPLT)
	CP	PLT_SCZ180
	JR	Z,HBSA_RCEB_Z180
	CP	PLT_RCZ180
	JR	Z,HBSA_RCEB_Z180
	LD	A,PSG_RCEB_RSEL
	LD	D,PSG_RCEB_RDAT
	LD	E,PSG_RCEB_RIN
	JR	HBSA_APPLY
HBSA_RCEB_Z180:
	LD	A,PSG_RCEB_Z180_RSEL
	LD	D,PSG_RCEB_Z180_RDAT
	LD	E,PSG_RCEB_Z180_RIN
	PUSH	AF			; save RSEL before clobbering A for Z180
	LD	A,Z180_RCZ180
	LD	(Z180),A
	POP	AF
	JR	HBSA_APPLY
HBSA_DO_RCMF:
	CALL	HBSA_SETPLT
	LD	HL,HWSTR_RCMF
	LD	A,(CURPLT)
	CP	PLT_SCZ180
	JR	Z,HBSA_RCMF_Z180
	CP	PLT_RCZ180
	JR	Z,HBSA_RCMF_Z180
	LD	A,PSG_RCMF_RSEL
	LD	D,PSG_RCMF_RDAT
	LD	E,PSG_RCMF_RIN
	JR	HBSA_APPLY
HBSA_RCMF_Z180:
	LD	A,PSG_RCMF_Z180_RSEL
	LD	D,PSG_RCMF_Z180_RDAT
	LD	E,PSG_RCMF_Z180_RIN
	PUSH	AF			; save RSEL before clobbering A for Z180
	LD	A,Z180_RCZ180
	LD	(Z180),A
	POP	AF
HBSA_APPLY:
	LD	(RSEL),A
	LD	A,D
	LD	(RDAT),A
	LD	A,E
	LD	(RIN),A
HBSA_DESC:
	LD	(DESC),HL
	XOR	A
	JR	HBSA_RET
HBSA_FAIL:
	OR	$FF
HBSA_RET:
	POP	HL
	POP	DE
	POP	BC
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
	; Prefer MSX + COLECO
	BIT	0,B
	JR	Z,HBS2_TRY_MSXRC
	BIT	1,B
	JR	Z,HBS2_TRY_MSXRC
	LD	HL,PSG_MSX_PORTW
	LD	DE,TSSTR_MSX
	LD	BC,PSG_COLECO_PORTW
	LD	A,2
	JP	HBS2_SET_PAIR
HBS2_TRY_MSXRC:
	; MSX + RC/EB
	BIT	0,B
	JR	Z,HBS2_TRY_COLECORC
	BIT	2,B
	JR	Z,HBS2_TRY_MSXMF
	LD	HL,PSG_MSX_PORTW
	LD	DE,TSSTR_MSX
	CALL	HB_RCEB_PORTW
	XOR	A
	JP	HBS2_SET_PAIR
HBS2_TRY_MSXMF:
	; MSX + RC/MF
	BIT	0,B
	JR	Z,HBS2_TRY_COLECORC
	BIT	3,B
	JR	Z,HBS2_TRY_COLECORC
	LD	HL,PSG_MSX_PORTW
	LD	DE,TSSTR_MSX
	LD	BC,PSG_RCMF_PORTW
	; NOTE: TSSTR_RC represents generic RC ports; MF uses D1/D0 too.
	XOR	A
	JP	HBS2_SET_PAIR
HBS2_TRY_COLECORC:
	; COLECO + RC/EB
	BIT	1,B
	JR	Z,HBS2_TRY_COLECOMF
	BIT	2,B
	JR	Z,HBS2_TRY_COLECOMF
	LD	HL,PSG_COLECO_PORTW
	LD	DE,TSSTR_COLECO
	CALL	HB_RCEB_PORTW
	XOR	A
	JP	HBS2_SET_PAIR
HBS2_TRY_COLECOMF:
	; COLECO + RC/MF
	BIT	1,B
	JR	Z,HBS2_TRY_RCTWO
	BIT	3,B
	JR	Z,HBS2_TRY_RCTWO
	LD	HL,PSG_COLECO_PORTW
	LD	DE,TSSTR_COLECO
	LD	BC,PSG_RCMF_PORTW
	XOR	A
	JP	HBS2_SET_PAIR
HBS2_TRY_RCTWO:
	; RC/EB + RC/MF
	BIT	2,B
	JR	Z,HBS2_FAIL
	BIT	3,B
	JR	Z,HBS2_FAIL
	; Z180 EB/MF share the same data port (60H); one physical AY on SC126/RCZ180.
	LD	A,(CURPLT)
	CP	PLT_SCZ180
	JR	Z,HBS2_FAIL
	CP	PLT_RCZ180
	JR	Z,HBS2_FAIL
	CALL	HB_RCEB_PORTW
	LD	DE,TSSTR_RC
	PUSH	BC
	LD	A,(CURPLT)
	CP	PLT_SCZ180
	JR	Z,HBS2_RCMF_Z180
	CP	PLT_RCZ180
	JR	Z,HBS2_RCMF_Z180
	LD	BC,PSG_RCMF_PORTW
	JR	HBS2_RCTWO_SET
HBS2_RCMF_Z180:
	LD	BC,PSG_RCMF_Z180_PORTW
HBS2_RCTWO_SET:
	POP	HL
	XOR	A
	JP	HBS2_SET_PAIR
;
; Commit a successful dual-PSG pair from HBIOS enumeration.
; IN: HL=port1, DE=desc1, BC=port2, A=desc2 selector (0=RC, 1=MSX, 2=COLECO)
;
HBS2_SET_PAIR:
	LD	(TS_PORTS1),HL
	LD	(TS_DESC1),DE
	PUSH	AF			; save desc2 selector (LD H,B destroys A)
	LD	H,B
	LD	L,C
	LD	(TS_PORTS2),HL
	POP	AF
	CP	1
	JR	Z,HBS2_SET_PAIR_MSX
	CP	2
	JR	Z,HBS2_SET_PAIR_COLECO
	LD	DE,TSSTR_RC
	JR	HBS2_SET_PAIR_DONE
HBS2_SET_PAIR_MSX:
	LD	DE,TSSTR_MSX
	JR	HBS2_SET_PAIR_DONE
HBS2_SET_PAIR_COLECO:
	LD	DE,TSSTR_COLECO
HBS2_SET_PAIR_DONE:
	LD	(TS_DESC2),DE
	XOR	A
	RET
HBS2_FAIL:
	OR	$FF
	RET
;

; Return BC = RC/EB packed ports for current platform (RDAT:RSEL).
HB_RCEB_PORTW:
	LD	A,(CURPLT)
	CP	PLT_SCZ180
	JR	Z,HB_RCEB_PORTW_Z
	CP	PLT_RCZ180
	JR	Z,HB_RCEB_PORTW_Z
	LD	BC,PSG_RCEB_PORTW
	RET
HB_RCEB_PORTW_Z:
	LD	BC,PSG_RCEB_Z180_PORTW
	RET

; Return BC = RC/MF packed ports for current platform (RDAT:RSEL).
HB_RCMF_PORTW:
	LD	A,(CURPLT)
	CP	PLT_SCZ180
	JR	Z,HB_RCMF_PORTW_Z
	CP	PLT_RCZ180
	JR	Z,HB_RCMF_PORTW_Z
	LD	BC,PSG_RCMF_PORTW
	RET
HB_RCMF_PORTW_Z:
	LD	BC,PSG_RCMF_Z180_PORTW
	RET

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
	; Activate card if applicable (match Tune.com probe sequence)
	CALL	SLOWIO
	LD	B,0			; ensure 8-bit port addressing via BC
	LD	A,(ACR)		; Get ACR port address (if any)
	LD	C,A			; Copy to C for I/O later
	INC	A			; $FF -> $00 & set flags
	JR	Z,PROBE_IMPL		; If no ACR, skip ahead
	LD	A,(ACRVAL)	; Value to activate card
	OUT	(C),A		; Write value to ACR
;
PROBE_IMPL:
	; Test for hardware (sound chip detection)
	; Use Tune-compatible probe in the config-table fallback path.
	LD	HL,(PORTS)		; HL = RDAT:RSEL
	LD	A,(RIN)			; A = RIN
	CALL	PROBE_TUNE_IMPL
	JP	Z,MAT			; Hardware matched!
	JR	CFGSEL_IMPL		; Keep trying

; Tune-compatible AY probe (HL=RDAT:RSEL, A=RIN). Returns Z on success.
; Matches Source/Apps/Tune/tune.asm PROBE (write $AA to R2, read back via RIN).
PROBE_TUNE_IMPL:
	DI
	PUSH	AF			; save RIN
	LD	E,L			; E := RSEL
	LD	D,H			; D := RDAT
	LD	C,E
	LD	A,2
	OUT	(C),A
	LD	C,D
	LD	A,$AA
	OUT	(C),A
	POP	AF
	PUSH	AF
	LD	C,A			; RIN port
	IN	A,(C)
	CP	$AA
	PUSH	AF
	CALL	NORMIO
	POP	AF
	EI
	RET

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

; Probe packed RDAT:RSEL ports (HL) with read port A=RIN. Returns Z on success.
TS_PROBE_PORTW:
	CALL	SLOWIO
	JP	PROBE_TUNE_IMPL

; Try HL as chip 2 if distinct from TS_PORTS1 and hardware responds.
; A = RIN, DE = description string. Returns Z on success.
TS_TRY_CAND:
	LD	C,A			; preserve RIN (SBC/ADD destroy A)
	LD	BC,(TS_PORTS1)
	OR	A
	SBC	HL,BC
	JR	Z,TS_TRY_CAND_FAIL
	ADD	HL,BC
	LD	A,C
	CALL	TS_PROBE_PORTW
	JR	NZ,TS_TRY_CAND_FAIL
	; Same data port (high byte) means one physical AY, not a second chip.
	LD	A,H
	LD	BC,(TS_PORTS1)
	CP	B
	JR	Z,TS_TRY_CAND_FAIL
	LD	(TS_PORTS2),HL
	LD	(TS_DESC2),DE
	XOR	A
	RET
TS_TRY_CAND_FAIL:
	OR	$FF
	RET

; Probe for a second PSG distinct from TS_PORTS1. Returns Z if found.
TS_FIND_CHIP2:
	; Coleco
	LD	HL,PSG_COLECO_PORTW
	LD	DE,TSSTR_COLECO
	LD	A,PSG_COLECO_RIN
	CALL	TS_TRY_CAND
	RET	Z

	; RC/MF (platform-aware ports)
	CALL	HB_RCMF_PORTW
	LD	H,B
	LD	L,C
	LD	DE,TSSTR_RC
	LD	A,(CURPLT)
	CP	PLT_SCZ180
	JR	Z,TS_FC2_MFZ
	CP	PLT_RCZ180
	JR	Z,TS_FC2_MFZ
	LD	A,PSG_RCMF_RIN
	JR	TS_FC2_MF
TS_FC2_MFZ:
	LD	A,PSG_RCMF_Z180_RIN
TS_FC2_MF:
	CALL	TS_TRY_CAND
	RET	Z

	; MSX
	LD	HL,PSG_MSX_PORTW
	LD	DE,TSSTR_MSX
	LD	A,PSG_MSX_RIN
	CALL	TS_TRY_CAND
	RET	Z

	OR	$FF
	RET

; Probe for two AY cards for TurboSound playback.
; Sets TS_DUALHW non-zero only when two distinct port sets are found.
; Single-chip systems keep TS_DUALHW clear (play chip-1 stream only).
TS_PORTS_SETUP_IMPL:
	XOR	A
	LD	(TS_DUALHW),A
	LD	(TS_PORTS2),A
	LD	(TS_PORTS2+1),A
	LD	(TS_DESC2),A
	LD	(TS_DESC2+1),A
	CALL	HB_SND_GET2
	JR	NZ,TS_SETUP_FB
	LD	HL,(TS_PORTS1)
	LD	BC,(TS_PORTS2)
	OR	A
	SBC	HL,BC
	JR	Z,TS_SETUP_FB		; same ports twice is not dual hardware
	CALL	TS_VERIFY_DUAL_PORTS
	JR	NZ,TS_SETUP_FB
	JR	TS_SETUP_DUAL
TS_SETUP_FB:
	LD	HL,(PORTS)
	LD	(TS_PORTS1),HL
	LD	DE,(DESC)
	LD	(TS_DESC1),DE
	CALL	TS_FIND_CHIP2
	JR	Z,TS_SETUP_DUAL
	XOR	A
	RET
TS_SETUP_DUAL:
	LD	A,$FF
	LD	(TS_DUALHW),A
	XOR	A
	RET

; Require two distinct data ports (packed word high byte = RDAT).
; Returns Z if valid dual hardware, NZ otherwise.
TS_VERIFY_DUAL_PORTS:
	LD	HL,(TS_PORTS1)
	LD	BC,(TS_PORTS2)
	LD	A,H
	CP	B
	RET	NZ
	OR	$FF
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



