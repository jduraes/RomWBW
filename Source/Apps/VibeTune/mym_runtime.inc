;
; MYM runtime wrappers (init, decode/play loop, pause/key handling).
; Extracted from vibetune.asm without behavior changes.
;
gomym
	LD	A,(UI_ACTIVE)
	OR	A
	JR	NZ,gomym0
	CALL	CRLF2			; Formatting
gomym0
	CALL	PRTPLAYMSG		; Playing message
	ld	hl,(QDLY)			; Get basic quark delay
	or	a					; Clear carry
	ld	de,125				; Avg TS / quark = ~5000, so 125 delay loops
	sbc	hl,de				; Adjust for file type
	ld	(QDLY),hl			; Save updated quark delay factor
	;ld	bc,(rows)
	;call	PRTHEXWORD
	call	mymini			; Initialize player
        call    extract 	; Unpack the first fragment
mymlp	call	extract
	jp	nc,EXIT				; CF clear at end of tune
waitvb	call	WAITQ
	call	upsg			; Update PSG registers
	ld	d,0
	call	PLAYBACK_PLAY_STEP
	ld	a,b
	or	a
	jp	z,waitvb1
	cp	2
	jp	z,mymkey_pause_wait
	jp	EXIT
mymkey_pause_toggle:
	call	KEY_TOGGLE_PAUSE
	jp	nz,mymkey_pause_wait
	jp	waitvb1
mymkey_pause_wait:
	ld	d,$80
	call	PLAYBACK_PAUSE_STEP
	ld	a,b
	or	a
	jp	z,mymkey_pause_wait1
	cp	2
	jr	z,mymkey_pause_off
	jp	EXIT
mymkey_pause_wait1:
	call	WAITQ
	jr	mymkey_pause_wait
mymkey_pause_off:
	call	KEY_PAUSE_OFF
	jp	nz,EXIT
	jp	waitvb1
waitvb1
	ld      a,(played)		; Wait until VBI has played a fragment
        or      a
        jp      nz,waitvb
        ld      (psource),iy
        ld      a,FRAG
        ld      (played),a
	;call	PRTDOT
	jp	mymlp
;
