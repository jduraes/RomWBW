;===============================================================================
; VGM Player Module for VibeTune
;===============================================================================
; Ported from VGMPLAY.ASM by J.B. Langston, Marco Maccaferri, Ed Brindley
; Adapted for RomWBW VibeTune by J.M. Duraes
;===============================================================================

;------------------------------------------------------------------------------
; VGM stream position helpers (24-bit file offsets in vgmpos[2:0]).
;------------------------------------------------------------------------------

; Read byte at vgmpos and advance vgmpos by 1.
; Out: A = byte
VGM_RD_NEXT:
	PUSH	BC
	PUSH	DE
	LD	HL,(vgmpos)
	LD	A,(vgmpos+2)
	PUSH	HL
	PUSH	AF
	CALL	VGM_MMU_READ_AT
	LD	E,A
	POP	AF
	LD	B,A
	POP	HL
	INC	HL
	JR	NZ,VGM_RD_NEXT0
	INC	B
VGM_RD_NEXT0:
	LD	(vgmpos),HL
	LD	A,B
	LD	(vgmpos+2),A
	LD	A,E
	POP	DE
	POP	BC
	RET

; Add A (0..255) to vgmpos.
VGM_POS_ADD_A:
	LD	E,A
	LD	D,0
	LD	HL,(vgmpos)
	ADD	HL,DE
	LD	A,(vgmpos+2)
	ADC	A,0
	LD	(vgmpos),HL
	LD	(vgmpos+2),A
	RET

; Add C:DE (24-bit) to vgmpos.
; In: C = high byte, DE = low word.
VGM_POS_ADD_CDE:
	LD	HL,(vgmpos)
	ADD	HL,DE
	LD	A,(vgmpos+2)
	ADC	A,C
	LD	(vgmpos),HL
	LD	(vgmpos+2),A
	RET

; Force vgmpos to end-of-image to safely terminate further parsing.
VGM_POS_SET_END:
	LD	A,(VGMMMUMD)
	OR	A
	JR	Z,VGM_POS_SET_END0
	LD	A,(VGMLOADSZ)
	LD	(vgmpos),A
	LD	A,(VGMLOADSZ+1)
	LD	(vgmpos+1),A
	LD	A,(VGMLOADSZ+2)
	LD	(vgmpos+2),A
	RET
VGM_POS_SET_END0:
	LD	HL,(LOADBYTES)
	LD	(vgmpos),HL
	XOR	A
	LD	(vgmpos+2),A
	RET

;------------------------------------------------------------------------------
; VGM skip helpers for unsupported commands.
; In: A = command byte, vgmpos points to first command parameter.
; Out: vgmpos advanced past command payload.
;------------------------------------------------------------------------------

VGM_SKIP_UNK:
	CP	67H			; 0x67: data block
	JR	Z,VGM_SKIP_67
	CP	68H			; 0x68: PCM RAM write (12 bytes)
	JR	Z,VGM_SKIP_68
	CP	0E0H			; 0xE0: seek offset (4 bytes)
	JR	Z,VGM_SKIP_4
	CP	0C0H			; 0xC0-0xDF: usually 3-byte payload
	JR	NC,VGM_SKIP_3
	CP	0B0H			; 0xB0-0xBF: usually 2-byte payload
	JR	NC,VGM_SKIP_2
	CP	0A1H			; 0xA1-0xAF: usually 2-byte payload
	JR	NC,VGM_SKIP_2
	CP	90H
	JR	C,VGM_SKIP_RANGE_50_6F
	CP	96H
	JR	C,VGM_SKIP_4
	JR	VGM_SKIP_1		; conservative fallback for 0x96-0x9F
VGM_SKIP_RANGE_50_6F:
	CP	50H			; 0x50-0x5F writes are register+data
	JR	NC,VGM_SKIP_2
	CP	40H
	JR	NC,VGM_SKIP_1
	CP	30H
	JR	NC,VGM_SKIP_1
	JR	VGM_SKIP_1
VGM_SKIP_1:
	LD	A,1
	CALL	VGM_POS_ADD_A
	RET
VGM_SKIP_2:
	LD	A,2
	CALL	VGM_POS_ADD_A
	RET
VGM_SKIP_3:
	LD	A,3
	CALL	VGM_POS_ADD_A
	RET
VGM_SKIP_4:
	LD	A,4
	CALL	VGM_POS_ADD_A
	RET
VGM_SKIP_68:
	LD	A,12
	CALL	VGM_POS_ADD_A
	RET
VGM_SKIP_67:
	; Format: 67 66 tt ss ss ss ss [data...]
	CALL	VGM_RD_NEXT		; marker (0x66)
	CALL	VGM_RD_NEXT		; type
	CALL	VGM_RD_NEXT
	LD	E,A			; size byte 0
	CALL	VGM_RD_NEXT
	LD	D,A			; size byte 1
	CALL	VGM_RD_NEXT
	LD	C,A			; size byte 2
	CALL	VGM_RD_NEXT		; size byte 3
	OR	A
	JR	Z,VGM_SKIP_67_OK
	CALL	VGM_POS_SET_END		; unsupported 32-bit length -> clamp to end
	RET
VGM_SKIP_67_OK:
	CALL	VGM_POS_ADD_CDE
	RET

;===============================================================================
; VGM_PLAY_FRAME - Process one frame of VGM commands
;===============================================================================
; Processes command stream until a wait command is encountered.
; Returns NZ when a wait has been loaded into vgmdly.
; Returns Z when stream ends without loop.
;===============================================================================
VGM_PLAY_FRAME:
VGM_NEXT:
	CALL	VGM_RD_NEXT
	CP	66H			; end / loop
	JR	NZ,VGM_NEXT1
	CALL	VGM_MMU_SYNC_HDR
	LD	A,(vgmdata + 1CH)	; loop offset (relative to 0x1C)
	LD	E,A
	LD	A,(vgmdata + 1DH)
	LD	D,A
	LD	A,(vgmdata + 1EH)
	LD	C,A
	LD	A,(vgmdata + 1FH)
	OR	C
	OR	D
	OR	E
	RET	Z			; no loop offset -> end of stream
	LD	A,(vgmdata + 1FH)
	OR	A
	RET	NZ			; unsupported >24-bit loop offset -> end
	LD	HL,001CH
	ADD	HL,DE
	LD	A,C
	ADC	A,0
	RET	C			; overflow beyond 24-bit
	LD	(vgmpos),HL
	LD	(vgmpos+2),A
	JR	VGM_NEXT

VGM_NEXT1:
	CP	4FH			; Game Gear stereo (ignored)
	JR	NZ,VGM_OPL2
	LD	A,1
	CALL	VGM_POS_ADD_A
	JR	VGM_NEXT

VGM_OPL2:
	CP	5AH			; OPL2 write
	JR	Z,VGM_OPL_B1
	CP	5EH			; OPL3 bank 1 write
	JR	Z,VGM_OPL_B1
	CP	5FH			; OPL3 bank 2 write
	JR	NZ,VGM_PSG
	LD	C,OPL3ADDR2
	JR	VGM_OPL_DO
VGM_OPL_B1:
	LD	C,OPL3ADDR1
VGM_OPL_DO:
	CALL	VGM_RD_NEXT		; register
	LD	E,A
	OUT	(C),A
	PUSH	BC
	LD	B,3
	DJNZ	$
	POP	BC
	CALL	VGM_RD_NEXT		; data
	LD	D,A
	LD	A,E
	SUB	43H
	JR	C,VGM_OPL_NBOOST
	CP	13H
	JR	NC,VGM_OPL_NBOOST
	AND	07H
	CP	03H
	JR	NC,VGM_OPL_NBOOST
	LD	A,D
	AND	0C0H			; keep KSL, clear attenuation for carriers
	JR	VGM_OPL_WDATA
VGM_OPL_NBOOST:
	LD	A,D
VGM_OPL_WDATA:
	INC	C			; data port = addr port + 1
	OUT	(C),A
	JP	VGM_NEXT

VGM_PSG:
	CP	50H			; SN76489 primary
	JR	NZ,VGM_PSG2
	CALL	VGM_RD_NEXT
	OUT	(PSGREG),A
	JP	VGM_NEXT

VGM_PSG2:
	CP	30H			; SN76489 secondary
	JR	NZ,VGM_YM2151
	CALL	VGM_RD_NEXT
	OUT	(PSG2REG),A
	JP	VGM_NEXT

VGM_YM2151:
	CP	054H			; YM2151 primary write
	JR	NZ,VGM_YM2151_2
	CALL	VGM_RD_NEXT		; register
	LD	D,A
	LD	A,(YM2151SELV)
	LD	C,A
	LD	A,D
	OUT	(C),A
	CALL	VGM_RD_NEXT		; data
	LD	D,A
	LD	A,(YM2151DATV)
	LD	C,A
	LD	A,D
	OUT	(C),A
	JP	VGM_NEXT

VGM_YM2151_2:
	CP	0A4H			; YM2151 secondary write
	JR	NZ,VGM_AY
	LD	A,(YM2151SEL2V)
	OR	A
	JR	Z,VGM_YM2151_2_SKIP
	CALL	VGM_RD_NEXT		; register
	LD	D,A
	LD	A,(YM2151SEL2V)
	LD	C,A
	LD	A,D
	OUT	(C),A
	CALL	VGM_RD_NEXT		; data
	LD	D,A
	LD	A,(YM2151DAT2V)
	LD	C,A
	LD	A,D
	OUT	(C),A
	JP	VGM_NEXT
VGM_YM2151_2_SKIP:
	LD	A,2
	CALL	VGM_POS_ADD_A
	JP	VGM_NEXT

VGM_AY:
	CP	0A0H			; AY register/data write
	JR	NZ,VGM_WAITNN
	CALL	VGM_RD_NEXT		; register (bit7 selects chip2)
	BIT	7,A
	JR	Z,VGM_AY1
	AND	7FH
	LD	C,A
	LD	DE,(TS_PORTS2)		; E=RSEL2, D=RDAT2
	LD	A,C
	LD	C,E
	OUT	(C),A
	CALL	VGM_RD_NEXT		; data
	LD	C,D
	OUT	(C),A
	JP	VGM_NEXT
VGM_AY1:
	LD	C,A
	LD	DE,(TS_PORTS1)		; E=RSEL, D=RDAT
	LD	A,C
	LD	C,E
	OUT	(C),A
	CALL	VGM_RD_NEXT		; data
	LD	C,D
	OUT	(C),A
	JP	VGM_NEXT

VGM_WAITNN:
	CP	61H			; wait nn samples
	JR	NZ,VGM_WAIT60
	CALL	VGM_RD_NEXT
	LD	E,A
	CALL	VGM_RD_NEXT
	LD	D,A
	LD	L,E
	LD	H,D
	LD	(vgmdly),HL
	LD	A,1
	OR	A
	RET

VGM_WAIT60:
	CP	62H			; wait 735 samples
	JR	NZ,VGM_WAIT50
	LD	HL,735
	LD	(vgmdly),HL
	LD	A,1
	OR	A
	RET

VGM_WAIT50:
	CP	63H			; wait 882 samples
	JR	NZ,VGM_WAIT1
	LD	HL,882
	LD	(vgmdly),HL
	LD	A,1
	OR	A
	RET

VGM_WAIT1:
	CP	70H			; 0x70-0x7F => wait 1..16
	JR	C,VGM_SKIP_CMD
	CP	80H
	JR	NC,VGM_SKIP_CMD
	SUB	6FH
	LD	L,A
	LD	H,0
	LD	(vgmdly),HL
	LD	A,1
	OR	A
	RET

VGM_SKIP_CMD:
	CALL	VGM_SKIP_UNK
	JP	VGM_NEXT

;===============================================================================
; VGM_APPLY_DELAY - Burn CPU cycles to match VGM sample rate (~44.1 KHz)
;===============================================================================
VGM_APPLY_DELAY:
	LD	HL,(vgmdly)
VGM_DELAY_LOOP:
	LD	A,(vgmfdly)
	LD	B,A
	DJNZ	$
	DEC	HL
	LD	A,H
	OR	L
	JR	NZ,VGM_DELAY_LOOP
	RET

;===============================================================================
; VGM_BOOST_VOLUME - Maximise OPL carrier operator output level
;===============================================================================
; Input:  A = OPL register, E = data byte
; Output: E = boosted data (attenuation bits cleared, KSL preserved)
;===============================================================================
VGM_BOOST_VOLUME:
	CP	43H
	JR	Z,VGM_DO_BOOST
	CP	44H
	JR	Z,VGM_DO_BOOST
	CP	45H
	JR	Z,VGM_DO_BOOST
	CP	4BH
	JR	Z,VGM_DO_BOOST
	CP	4CH
	JR	Z,VGM_DO_BOOST
	CP	4DH
	JR	Z,VGM_DO_BOOST
	CP	53H
	JR	Z,VGM_DO_BOOST
	CP	54H
	JR	Z,VGM_DO_BOOST
	CP	55H
	JR	Z,VGM_DO_BOOST
	RET
VGM_DO_BOOST:
	PUSH	HL
	LD	A,E
	AND	0C0H
	LD	E,A
	POP	HL
	RET

;===============================================================================
; VGM_MUTE_ALL - Silence all sound hardware used during VGM playback
;===============================================================================
VGM_MUTE_ALL:
	; Mute SN76489 channels (primary chip)
	LD	A,9FH
	OUT	(PSGREG),A
	LD	A,0BFH
	OUT	(PSGREG),A
	LD	A,0DFH
	OUT	(PSGREG),A
	LD	A,0FFH
	OUT	(PSGREG),A
	; Secondary SN76489 (if present)
	LD	A,9FH
	OUT	(PSG2REG),A
	LD	A,0BFH
	OUT	(PSG2REG),A
	LD	A,0DFH
	OUT	(PSG2REG),A
	LD	A,0FFH
	OUT	(PSG2REG),A

	; Mute AY volume registers 8, 9, 10 (both chips)
	LD	DE,(TS_PORTS1)		; E=RSEL, D=RDAT
	LD	HL,(TS_PORTS2)		; L=RSEL2, H=RDAT2
	LD	B,3
	LD	A,8
VGM_MUTE_LOOP:
	PUSH	AF
	LD	C,E
	OUT	(C),A
	LD	C,L
	OUT	(C),A
	XOR	A
	LD	C,D
	OUT	(C),A
	LD	C,H
	OUT	(C),A
	POP	AF
	INC	A
	DJNZ	VGM_MUTE_LOOP

	; Key-off all OPL3 channels (0xB0-0xB8 on both banks)
	LD	C,0B0H
VGM_OPL_KEYOFF:
	LD	A,C
	OUT	(OPL3ADDR1),A
	PUSH	BC
	LD	B,3
	DJNZ	$
	POP	BC
	XOR	A
	OUT	(OPL3DATA1),A
	LD	A,C
	OUT	(OPL3ADDR2),A
	PUSH	BC
	LD	B,3
	DJNZ	$
	POP	BC
	XOR	A
	OUT	(OPL3DATA2),A
	INC	C
	LD	A,C
	CP	0B9H
	JR	NZ,VGM_OPL_KEYOFF

	; Clear remaining OPL3 registers (both banks)
	LD	BC,0100H		; B=count(256), C=start register
VGM_OPL3_RESET:
	LD	A,C
	OUT	(OPL3ADDR1),A
	PUSH	BC
	LD	B,3
	DJNZ	$
	POP	BC
	XOR	A
	OUT	(OPL3DATA1),A
	LD	A,C
	OUT	(OPL3ADDR2),A
	PUSH	BC
	LD	B,3
	DJNZ	$
	POP	BC
	XOR	A
	OUT	(OPL3DATA2),A
	INC	C
	DJNZ	VGM_OPL3_RESET

	; YM2151 key-off + max attenuation
	LD	A,(YM2151SELV)
	OR	A
	RET	Z			; YM2151 unmapped
	LD	B,8
	LD	E,0
VGM_YM_KO:
	LD	A,008H
	LD	D,A
	LD	A,(YM2151SELV)
	LD	C,A
	LD	A,D
	OUT	(C),A
	LD	A,E
	LD	D,A
	LD	A,(YM2151DATV)
	LD	C,A
	LD	A,D
	OUT	(C),A
	LD	A,20
VGM_YM_KD:
	DEC	A
	JR	NZ,VGM_YM_KD
	INC	E
	DJNZ	VGM_YM_KO
	LD	E,060H
	LD	B,020H
VGM_YM_TL:
	LD	A,E
	LD	D,A
	LD	A,(YM2151SELV)
	LD	C,A
	LD	A,D
	OUT	(C),A
	LD	A,07FH
	LD	D,A
	LD	A,(YM2151DATV)
	LD	C,A
	LD	A,D
	OUT	(C),A
	INC	E
	DJNZ	VGM_YM_TL
	RET