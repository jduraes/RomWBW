;
; VGM runtime: goVGM (validate, CPU delay setup, playback loop, sample-based key poll).
;
goVGM:
	CALL	VGM_VALIDATE_IMAGE	; header / stream bounds vs loaded image

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
	RST	08			; L := MHz index, DE := KHz (see SYS_GETCPUINFO)
	LD	(VGMTMPKHZ),DE
	LD	A,L
	LD	(VGMTMPMHZ),A
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
	XOR	A
	LD	(VGMRDERR),A		; clear stream read-error latch before playback

	; Initialise delay counter
	LD	HL,0
	LD	(vgmdly),HL
	XOR	A
	LD	(VGMSAMPACC),A
	LD	(VGMSAMPACC+1),A
	LD	(VGMSAMPACC+2),A

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
	JP	goVGM_nodelay

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
	CALL	VGM_STRETCH_VGMDLY
	; Key/pause poll on a fixed sample timeline (~4410 samples ~= 0.1 s @ 44.1 kHz)
	; so poll spacing tracks vgmdly instead of "every N VGM waits".
	LD	HL,(vgmdly)
	LD	A,H
	OR	L
	JR	Z,goVGM_nd_noacc
	LD	DE,(VGMSAMPACC)
	LD	A,(VGMSAMPACC+2)
	ADD	HL,DE
	ADC	A,0
	LD	(VGMSAMPACC),HL
	LD	(VGMSAMPACC+2),A
goVGM_nd_acloop:
	LD	HL,(VGMSAMPACC)
	LD	A,(VGMSAMPACC+2)
	OR	A
	JR	NZ,goVGM_nd_sub4410
	PUSH	HL
	LD	DE,4410
	OR	A
	SBC	HL,DE
	POP	HL
	JR	C,goVGM_nd_noacc
goVGM_nd_sub4410:
	LD	HL,(VGMSAMPACC)
	LD	A,(VGMSAMPACC+2)
	LD	DE,4410
	OR	A
	SBC	HL,DE
	SBC	A,0
	LD	(VGMSAMPACC),HL
	LD	(VGMSAMPACC+2),A
	LD	D,1
	CALL	PLAYBACK_PLAY_STEP
	LD	A,B
	OR	A
	JR	Z,goVGM_nd_acloop
	CP	2
	JP	Z,goVGM_pause_wait
	JP	goVGM_exit_mute
goVGM_nd_noacc:
	; Constant inner-byte delay (no dither): avoids subtle tempo wobble from
	; alternating vgmfdly0 vs vgmfdly0-1 across frame boundaries.
	LD	A,(vgmfdly0)
	LD	(vgmfdly),A
	CALL	VGM_APPLY_DELAY
	JP	goVGM_lp

goVGM_done:
	; End of stream reached normally
goVGM_exit_mute:
	CALL	VGM_MUTE_ALL		; Silence all hardware
	JP	EXIT

;
; Validate VGM header (EOF field sanity, stream start vs loaded image).
; Physical loaded size (VGMLOADSZ) is authoritative; header EOF may overshoot.
;

