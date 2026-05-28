
;
; Wait for quark play time.  Can use hardware timer if
; supported by hardware or simple delay loop otherwise.
; Delay loop requires QDLY to be pre-set to to achieve
; optimal 20ms wait time.
;
WAITQ	LD	A,(WMOD)		; Get delay mode
	OR	A			; Set flags
	JR	Z,DLY			; Delay mode
;
	; Timer loop
	CALL	TIM2			; Read timer LSB into A
	LD	C,A			; Init prev value
TIM1	PUSH	BC			; Save prev value
	CALL	TIM2			; Read timer LSB into A
	POP	BC			; Recover prev value
	CP	C			; Compare to prev
	RET	NZ			; Done if changed
	JR	TIM1			; Else, loop
;
TIM2	LD	B,$F8			; BIOS SYSGET function
	LD	C,$D0			; TIMER sub-function
	RST	08			; Call BIOS
	LD	A,L			; MSB to A
	RET				; Return to loop
;
	; Delay spin loop (40 tstates per loop)
DLY	LD	BC,(QDLY)		; Load quark delay factor
DLY1	DEC	BC              	; [6]
	NOP				; [4]
	NOP				; [4]
	NOP				; [4]
	NOP				; [4]
	LD	A,B             	; [4]
	OR	C               	; [4]
	JP	NZ,DLY1			; [10]
	RET

;
; Test for timer running to determine if it can be used for delay
; Return string message in DE
; Assigned (WMOD) with 0 if no hardware time, 1 if hardware timer found
; If -DELAY on command line, force delay mode
;
PROBETIMER:
	LD	A,(DELAYMD)		; GET COMMAND LINE DELAY FLAG
	OR	A			; TEST IT
	LD	A,0			; ASSUME NO TIMER
	LD	DE,MSGDLY		; DELAY MODE MESSAGE
	JR	NZ,SETDLY		; IF TRUE, DONE
	LD	B,BF_SYSGET		; HBIOS: GET function
	LD	C,$D0			; TIMER subfunction
	RST	08			; DE:HL := current tick count
	LD	A,L			; DE:HL == 0?
	OR	H
	OR	E
	OR	D
	LD	A,0			; Assume no timer
	LD	DE,MSGDLY		; Delay mode msg
	JR	Z,SETDLY		; If tick count is zero, no timer active
	LD	A,$FF			; Value for timer active
	LD	DE,MSGTIM		; Timer mode msg
SETDLY:
	LD	(WMOD),A		; Save wait mode
	RET

;
; Delay-mode tempo trim for Z80 systems without a hardware quark timer.
; Subtracts a small fixed bias from QDLY so playback matches timer-mode tempo.
; Timer mode (WMOD != 0) is unchanged.
;
VT_DLY_BIAS	.EQU	52		; ~2% at 7.3 MHz (~2650 delay loops)

VT_APPLY_DLY_BIAS:
	LD	A,(WMOD)
	OR	A
	RET	NZ
	LD	HL,(QDLY)
	LD	DE,VT_DLY_BIAS
	OR	A
	SBC	HL,DE
	JP	PE,VT_APPLY_DLY_BIAS_OK
	LD	HL,0
VT_APPLY_DLY_BIAS_OK:
	LD	(QDLY),HL
	RET

;
; Get a keystroke from CPM
;
GETKEY	LD	C,6		; BDOS direct I/O
	LD	E,$FF		; Get character if available
	CALL	BDOS	; Call BDOS
	OR	A			; Set flags, Z set if no key
	RET				; Done

; Print detected CPU speed in MHz (X.YYY) below the startup banner.
; Uses HBIOS SYSGET/CPUINFO (BC=$F8F0), DE := KHz.
PRTCPUKHZBAN:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	CALL	CRLF
	LD	DE,MSGCPUMHZ
	CALL	PRTSTR
	LD	BC,$F8F0
	RST	08
	EX	DE,HL

	; Integer MHz = KHz / 1000 in B, remainder KHz in HL.
	LD	B,0
PRTCPUSPD_DIV1000:
	LD	A,H
	CP	03H
	JR	C,PRTCPUSPD_DIV1000_DONE
	JR	NZ,PRTCPUSPD_DIV1000_SUB
	LD	A,L
	CP	0E8H
	JR	C,PRTCPUSPD_DIV1000_DONE
PRTCPUSPD_DIV1000_SUB:
	LD	A,L
	SUB	0E8H
	LD	L,A
	LD	A,H
	SBC	A,03H
	LD	H,A
	INC	B
	JR	PRTCPUSPD_DIV1000
PRTCPUSPD_DIV1000_DONE:

	LD	A,B
	CALL	PRTDECB
	LD	A,'.'
	CALL	PRTCHR

	; Hundreds digit of remainder (0..999)
	LD	A,0
PRTCPUSPD_DIV100:
	LD	B,A
	LD	A,H
	OR	A
	JR	NZ,PRTCPUSPD_DIV100_SUB
	LD	A,L
	CP	100
	JR	C,PRTCPUSPD_DIV100_DONE
PRTCPUSPD_DIV100_SUB:
	LD	A,L
	SUB	100
	LD	L,A
	LD	A,H
	SBC	A,0
	LD	H,A
	LD	A,B
	INC	A
	JR	PRTCPUSPD_DIV100
PRTCPUSPD_DIV100_DONE:
	LD	A,B
	ADD	A,'0'
	CALL	PRTCHR

	; Tens digit of remainder (0..99)
	LD	A,0
PRTCPUSPD_DIV10:
	LD	B,A
	LD	A,L
	CP	10
	JR	C,PRTCPUSPD_DIV10_DONE
	SUB	10
	LD	L,A
	LD	A,B
	INC	A
	JR	PRTCPUSPD_DIV10
PRTCPUSPD_DIV10_DONE:
	LD	A,B
	ADD	A,'0'
	CALL	PRTCHR

	; Ones digit of remainder
	LD	A,L
	ADD	A,'0'
	CALL	PRTCHR

	LD	DE,MSGMHZ
	CALL	PRTSTR
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

;
; Drain any pending console keypresses (used to clear command-enter residue).
;
FLUSHKEYS:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
FLUSHKEYS1:
	CALL	GETKEY
	JR	Z,FLUSHKEYS2
	JR	FLUSHKEYS1
FLUSHKEYS2:
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET
;
; Print the wait mode suffix based on WMOD
;   WMOD == 0  -> delay mode
;   WMOD != 0  -> timer mode
;
PRTWMOD:
	LD	A,(WMOD)
	OR	A
	JR	Z,PRTWMOD_DLY
	LD	DE,MSGTIM
	JR	PRTWMOD_P
PRTWMOD_DLY:
	LD	DE,MSGDLY
PRTWMOD_P:
	JP	PRTSTR
