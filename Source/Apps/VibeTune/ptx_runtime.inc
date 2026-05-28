;
; PTX runtime wrappers (PT2/PT3 init, play loop, pause/key handling).
; Extracted from vibetune.asm without behavior changes.
;
GOPT2	LD	A,2			; SETUP value to PT2 sound files
	LD	(START+10),A	; Save it
	; Avg TS / quark for PT2 files has *not* been measured!!!
	LD	DE,185			; Avg TS / quark = 7400, so 185 delay loops
	JR	GOPTX			; Play PTx file

GOPT3	LD	A,0			; SETUP value to PT3 sound files
	LD	(START+10),A	; Save it
	LD	DE,185			; Avg TS / quark = 7400, so 185 delay loops
	JR	GOPTX			; Play PTx file

GOPTX
	LD	HL,(QDLY)		; Get basic quark delay
	OR	A				; Clear carry
	SBC	HL,DE			; Adjust for file type
	LD	(QDLY),HL		; Save updated quark delay factor

	LD	A,(UI_ACTIVE)
	OR	A
	JR	NZ,GOPTXSP2
	LD	A,(INFOLINE)	; spacing before song metadata
	OR	A
	JR	Z,GOPTXSP1
	CALL	CRLF2
	JR	GOPTXSP2
GOPTXSP1:
	CALL	CRLF
GOPTXSP2:
	CALL	PRTSONGMETA		; Print song metadata block
;
	; TurboSound-packed PT3 init (dual hardware only)
	LD	A,(TSFLAG)
	OR	A
	JR	Z,PTXINITN
	CALL	TS_PORTS_SETUP_IMPL
	LD	A,(TS_DUALHW)
	OR	A
	JR	Z,PTXINITN		; one AY: play module 1 via normal PT3
	ISHBIOS
	JR	Z,PTXINITT			; TurboSound requires direct I/O
	ERRWITHMSG(MSGTSHB)
PTXINITT:
	CALL	TS_ADJTIM_IMPL	; adjust delay timing for TS
	CALL	TS_INIT			; init both PT3 instances
	JR	PTXSTART
PTXINITN:
	CALL	START			; Do initialization
;
PTXSTART:
	LD	A,(ALLMD)
	OR	A
	JR	NZ,PTXSTARTF
	LD	A,(LOOPTRKMD)
	OR	A
	JR	Z,PTXSTART0
PTXSTARTF:
	CALL	FLUSHKEYS
PTXSTART0:
	CALL	VT_APPLY_DLY_BIAS	; delay-mode Z80 tempo trim
	CALL	PRTPLAYMSG		; Playing message
;
PTXLP:	LD	A,(TSFLAG)
	OR	A
	JR	Z,PTXLP_NORM
	LD	A,(TS_DUALHW)
	OR	A
	JR	Z,PTXLP_NORM
	CALL	TS_PLAYQUARK	; Play one quark on both chips
	LD	A,(TSSET1)
	BIT	7,A
	JR	Z,PTXLP_KEY
	LD	A,(TSSET2)
	BIT	7,A
	JP	NZ,EXIT				; done when both instances indicate loop point passed
	JR	PTXLP_KEY
PTXLP_NORM:
	CALL	START+5		; Play one quark
	LD	A,(START+10)	; Get setup byte
	BIT	7,A				; Check bit 7 (loop point passed)
	JP	NZ,EXIT			; Bail out when done playing
PTXLP_KEY:
	LD	D,0
	CALL	PLAYBACK_PLAY_STEP
	LD	A,B
	OR	A
	JP	Z,PTXLP_KEY1
	CP	2
	JP	Z,PTXLP_PAUSE_WAIT
	JP	EXIT
PTXLP_PAUSE_TOGGLE:
	CALL	KEY_TOGGLE_PAUSE
	JP	NZ,PTXLP_PAUSE_WAIT
	JP	PTXLP_KEY1
PTXLP_PAUSE_WAIT:
	LD	D,$80
	CALL	PLAYBACK_PAUSE_STEP
	LD	A,B
	OR	A
	JP	Z,PTXLP_PAUSE_WAIT1
	CP	2
	JR	Z,PTXLP_PAUSE_OFF
	JP	EXIT
PTXLP_PAUSE_WAIT1:
	CALL	WAITQ
	JR	PTXLP_PAUSE_WAIT
PTXLP_PAUSE_OFF:
	CALL	KEY_PAUSE_OFF
	JP	NZ,EXIT
	JP	PTXLP_KEY1
PTXLP_KEY1:
	CALL	WAITQ		; Wait one quark period
	JP	PTXLP			; Loop for next quark
;
