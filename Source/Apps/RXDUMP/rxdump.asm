;
; RXDUMP.ASM - Console RX sniffer for RomWBW
;
; Diagnostic tool: dumps every byte arriving on the console as [XX] hex
; for ~90 seconds, then exits.  Intended to run chained after a file
; transfer on the Z-System multiple command line, e.g.:
;
;   zmd r;rxdump
;
; so that anything the sending terminal emits after the transfer is
; captured instead of landing in the CCP command line buffer.
;
; Pure BDOS I/O, non-blocking (BDOS 6, E=FF).  Does not touch the UART.
;
; Build:  TASM -80 -b rxdump.asm rxdump.com
;

BDOS	.EQU	5

	.ORG	100H

START:
	LD	DE,MSGBAN
	LD	C,9
	CALL	BDOS

	; Get CPU speed in MHz from HBIOS (SYSGET 0xF8, CPUINFO 0xF0)
	LD	BC,0F8F0H
	RST	08H
	JR	NZ,NOSPD	; error -> use default
	LD	A,L
	OR	A
	JR	NZ,SETSPD
NOSPD:	LD	A,10		; default 10 MHz
SETSPD:	LD	(MHZ),A

	LD	HL,0
	LD	(SLICES),HL

MAIN:	; one 100ms slice
	LD	D,100
SLICE:	CALL	POLL		; drain & dump any received chars
	LD	A,(MHZ)
	CALL	W1MS		; wait ~1ms
	DEC	D
	JR	NZ,SLICE

	LD	HL,(SLICES)
	INC	HL
	LD	(SLICES),HL

	LD	A,L		; heartbeat '.' every 16 slices (~1.6s)
	AND	0FH
	CALL	Z,DOT

	LD	A,H		; done after 900 slices (0x384) = ~90s
	CP	3
	JR	C,MAIN
	LD	A,L
	CP	84H
	JR	C,MAIN

	LD	DE,MSGEND
	LD	C,9
	CALL	BDOS
	JP	0		; warm boot

;
; Read console without echo until empty, dump each byte as [XX]
;
POLL:	LD	E,0FFH
	LD	C,6		; BDOS direct console I/O, input
	CALL	BDOS
	OR	A
	RET	Z		; no character pending
	LD	B,A		; save char
	LD	E,'['
	LD	C,2
	CALL	BDOS
	LD	A,B
	CALL	PHEX		; print two hex digits
	LD	E,']'
	LD	C,2
	CALL	BDOS
	JR	POLL

;
; Print A as two hex digits via BDOS 2
;
PHEX:	PUSH	AF
	RRCA
	RRCA
	RRCA
	RRCA
	CALL	PNIB
	POP	AF
PNIB:	AND	0FH
	CP	10
	JR	C,PNIB1
	ADD	A,'A'-10-'0'
PNIB1:	ADD	A,'0'
	LD	E,A
	LD	C,2
	JP	BDOS

;
; Print a heartbeat dot
;
DOT:	LD	E,'.'
	LD	C,2
	JP	BDOS

;
; Wait ~1ms; A = CPU speed in MHz
;
W1MS:	LD	B,A
W1MS1:	LD	C,63		; ~1000 T-states per MHz
W1MS2:	DEC	C
	JR	NZ,W1MS2
	DJNZ	W1MS1
	RET

MSGBAN:	.DB	"RXDUMP: watching console input for 90 seconds",13,10,'$'
MSGEND:	.DB	"DONE",13,10,'$'

MHZ:	.DB	0
SLICES:	.DW	0

	.END
