;
; VGM runtime wrappers (goVGM playback loop + control handling).
; Extracted from vibetune.asm without behavior changes.
;
goVGM:
	CALL	VGM_VALIDATE_IMAGE	; fail fast if VGM image is truncated
	CALL	VGM_MMU_SELFTEST	; fail fast if MMU read/cache sanity checks fail
	JP	NZ,ERRVGMMMU

	; Probe AY chip ports into TS_PORTS1/TS_PORTS2 (same as TurboSound PT3)
	ISHBIOS
	JR	NZ,goVGM_portsfb	; HBIOS mode: skip direct probe for AY
	CALL	TS_PORTS_SETUP_IMPL	; populates TS_PORTS1 and TS_PORTS2
goVGM_portsfb:
	; If TS_PORTS1 is zero (e.g. HBIOS mode), seed it from PORTS so AY
	; writes don't go to port 0.
	LD	HL,(TS_PORTS1)
	LD	A,H
	OR	L
	JR	NZ,goVGM_fdly
	LD	HL,(PORTS)		; fallback: copy active PORTS word
	LD	(TS_PORTS1),HL

goVGM_fdly:
	LD	BC,$F8F0		; HBIOS SYSGET/CPUINFO
	RST	08			; L := CPU index/code
	LD	A,L
	CALL	VGM_SETFDELAY
goVGM_fd_done:

	; Mark this track as VGM so EXIT skips the PT3 MUTE call
	LD	A,$FF
	LD	(VGMFLAG),A

	; Compute stream start as 24-bit logical offset from file base.
	CALL	VGM_GET_STREAM_START	; returns C:HL
	LD	(vgmpos),HL
	LD	A,C
	LD	(vgmpos+2),A

	; Initialise delay counter
	LD	HL,0
	LD	(vgmdly),HL
	XOR	A
	LD	(VGMKEYCHK),A		; poll keyboard every 32 loops (responsive, low overhead)

	; Print VGM metadata block before "Playing..."
	LD	A,(UI_ACTIVE)
	OR	A
	JR	NZ,goVGM_meta0
	LD	A,(INFOLINE)
	OR	A
	JR	Z,goVGM_meta1
	CALL	CRLF2
	JR	goVGM_meta0
goVGM_meta1:
	CALL	CRLF
goVGM_meta0:
	CALL	PRTVGMMETA

	; Print "Playing..." (deferred hardware info already shown by PRTPLAYINFO)
	CALL	PRTPLAYMSG		; "Playing..."

	; Flush any stale key presses
	LD	A,(ALLMD)
	OR	A
	JR	NZ,goVGM_flush
	LD	A,(LOOPTRKMD)
	OR	A
	JR	Z,goVGM_lp
goVGM_flush:
	CALL	FLUSHKEYS

;-----------------------------------------------------------------------
; Main VGM playback loop
;-----------------------------------------------------------------------
goVGM_lp:
	CALL	VGM_PLAY_FRAME		; process commands until next wait
	JP	Z,goVGM_done		; Z = end of stream (no loop)

	; Check for keypress every 32 loops.
	LD	A,(VGMKEYCHK)
	DEC	A
	AND	01FH
	LD	(VGMKEYCHK),A
	JP	NZ,goVGM_nodelay
	LD	D,1
	CALL	PLAYBACK_PLAY_STEP
	LD	A,B
	OR	A
	JP	Z,goVGM_nodelay
	CP	2
	JP	Z,goVGM_pause_wait
	JP	goVGM_exit_mute

goVGM_pause_toggle:
	CALL	KEY_TOGGLE_PAUSE
	JP	NZ,goVGM_pause_wait
	JP	goVGM_nodelay
goVGM_pause_wait:
	LD	D,$81
	CALL	PLAYBACK_PAUSE_STEP
	LD	A,B
	OR	A
	JP	Z,goVGM_pause_yield
	CP	2
	JR	Z,goVGM_pause_off
	JP	goVGM_exit_mute
goVGM_pause_yield:
	CALL	WAITQ
	JR	goVGM_pause_wait
goVGM_pause_off:
	CALL	KEY_PAUSE_OFF
	JP	NZ,goVGM_exit_mute
	JP	goVGM_nodelay

goVGM_nodelay:
	LD	A,(vgmfdcyc)
	OR	A
	JR	Z,goVGM_nodelay_base
	LD	B,A
	LD	A,(vgmfdpos)
	INC	A
	CP	B
	JR	C,goVGM_nodelay_posok
	XOR	A
goVGM_nodelay_posok:
	LD	(vgmfdpos),A
	LD	C,A
	LD	A,(vgmfdlo)
	CP	C
	JR	Z,goVGM_nodelay_base
	JR	C,goVGM_nodelay_base
	LD	A,(vgmfdly0)
	DEC	A
	LD	(vgmfdly),A
	JR	goVGM_nodelay_apply
goVGM_nodelay_base:
	LD	A,(vgmfdly0)
	LD	(vgmfdly),A
goVGM_nodelay_apply:
	CALL	VGM_APPLY_DELAY
	JP	goVGM_lp

goVGM_done:
	; End of stream reached normally
goVGM_exit_mute:
	CALL	VGM_MUTE_ALL		; Silence all hardware
	JP	EXIT

;
; Validate loaded VGM size against the header EOF offset (bytes 0x04..0x07).
; Expected file size is EOF offset + 4 bytes (32-bit value).
; If expected size exceeds 64K, or loaded bytes are smaller than expected,
; the file is truncated/corrupt for our in-memory playback model.
;


