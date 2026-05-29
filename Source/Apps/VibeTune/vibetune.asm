;===============================================================================
; VIBETUNE - Play PT2/PT3/MYM/VGM sound files (including TurboSound variants)
;
;===============================================================================
;
;	Original (TUNE.COM) Author:  Wayne Warthen (wwarthen@gmail.com)
;   Variation into VibeTune: Joao Miguel Duraes (jduraes@gmail.com)
;
;	This application is an evolution of Wayne's TUNE.COM (as of rev 3.6)
;_______________________________________________________________________________
;
; Usage:
;   VTUNE <filename> [additional options - check binary]
;
;   <filename> of sound file to load and play
;   Filename extension determines file type (.PT2, .PT3, .MYM or .VGM)
;
; Notes:
;   - Supports AY-3-8910, YM2149, etc.
;   - Plays PT2, PT3, MYM and VGM format files.
;   - Max Z80 CPU clock is about 8MHz or sound chip will not handle speed.
;   - Higher CPU clock speeds are possible on Z180 because extra I/O
;     wait states are added during I/O to sound chip.
;   - Uses hardware timer support on systems that support a timer.  Otherwise,
;     a delay loop calibrated to CPU speed is used.
;   - Delay loop is calibrated to CPU speed, but it does not compensate for
;     time variations in each quark loop resulting from data decompression.
;     An average quark processing time is assumed in each loop.
;   - Most sound files originally targeted MSX or ZX Spectrum which used
;     1.7897725 MHz and 1.773400 MHz respectively for the PSG clock.  For best 
;     sound playback, PSG should be run at approx. this clock rate.
;_______________________________________________________________________________
;
; Change Log:
;
;   Changes prior to these dates will reside in TUNE.COM
; 
;   2026-04-08 [JMD] Branched out of TUNE into VIBETUNE as of TUNE.COM v3.2 for RomWBW
;					 The App will... to-do
;   2026-04-09 [JMD] Add VGM file format support (AY-3-8910 single/dual chip, OPL2/OPL3, SN76489)
;                    Dual-AY VGM reuses TS_PORTS1/TS_PORTS2 identical to TurboSound PT3
;_______________________________________________________________________________
;
;===============================================================================
; Main program
;===============================================================================
;
#include	"../../ver.inc"
#include	"hbios.inc"
#include	"cpm.inc"
#include	"macros.inc"
#include	"ports.inc"
;
; Local hbios.inc is minimal; define additional equates we need here.
BF_SYSGET_SNDCNT	.EQU	$50		; SYSGET subfunction: sound unit count
BC_SYSGET_SNDCNT	.EQU	(BF_SYSGET * 256) + BF_SYSGET_SNDCNT
BF_SNDQ_DEV		.EQU	4		; query: return device type and IO ports
BF_SYSGETBNK		.EQU	$F3		; HBIOS: get current bank
BF_SYSSETCPY		.EQU	$F4		; HBIOS: configure inter-bank copy
BF_SYSBNKCPY		.EQU	$F5		; HBIOS: perform inter-bank copy
BF_SYSGET_APPBNKS	.EQU	$F5		; SYSGET subfunction: app bank info (C with B=BF_SYSGET)
BC_SYSGET_APPBNKS	.EQU	(BF_SYSGET * 256) + BF_SYSGET_APPBNKS
BF_SYSGET_BNKINFO	.EQU	$F2		; SYSGET: D/E = BIOS/user bank ids (RomWBW hbios)
BC_SYSGET_BNKINFO	.EQU	(BF_SYSGET * 256) + BF_SYSGET_BNKINFO
BF_SYSPEEK		.EQU	$FA		; HBIOS: read byte from bank D at HL -> E
HCB_LOC			.EQU	$100		; HBIOS control block base in BIOS bank (RomWBW)
HCB_BIDAPP0		.EQU	$E0		; offset: first app RAM bank id
HCB_APP_BNKS		.EQU	$E1		; offset: app bank count
PLMAX			.EQU	128		; max files in internal playlist
;
HEAPEND			.EQU	$C000	; End of heap storage
;
TYPPT2			.EQU	1		; FILTYP value for PT2 sound file
TYPPT3			.EQU	2		; FILTYP value for PT3 sound file
TYPMYM			.EQU	3		; FILTYP value for MYM sound file
TYPVGM			.EQU	4		; FILTYP value for VGM sound file
;
PORTS_AUTO		.EQU	0		; AUTO select audio chip ports
PORTS_MSX		.EQU	1		; force MSX audio chip ports
PORTS_RC		.EQU	2		; force RCBUS audio chip ports
PORTS_COLECO	.EQU	3		; force Coleco-style AY ports (50H/51H)

; Shared key action identifiers (decoded by keyctl.inc helpers)
KEYACT_NONE		.EQU	0
KEYACT_ESC		.EQU	1
KEYACT_LOOPTRK	.EQU	2
KEYACT_LOOPPLY	.EQU	3
KEYACT_REDRAW	.EQU	4
KEYACT_PREV		.EQU	5
KEYACT_NEXT		.EQU	6
KEYACT_NAV		.EQU	7

; Shared terminal config (TERM.CFG) constants/aliases for termcfg.inc
bdos			.EQU	BDOS
dma_default	.EQU	$0080
CFGF_ANSI	.EQU	$01
CFGVER			.EQU	1
CFG_DFL_ROWS	.EQU	24
CFG_DFL_COLS	.EQU	80
CFG_MIN_ROWS	.EQU	8
CFG_MAX_ROWS	.EQU	50
CFG_MIN_COLS	.EQU	20
CFG_MAX_COLS	.EQU	150
TCFG_ORG_ROW	.EQU	5
TCFG_ORG_COL	.EQU	5
UI_ROW_BANNER	.EQU	1
UI_ROW_MODE	.EQU	2
UI_ROW_INFO	.EQU	4
UI_ROW_INFO2	.EQU	5
UI_ROW_META1	.EQU	6
UI_ROW_META2	.EQU	7
UI_ROW_PLAY	.EQU	8
UI_ROW_PLHDR	.EQU	10
UI_ROW_PLLIST	.EQU	10
;
; HIGH SPEED CPU CONTROL
;
SBCV2004	.EQU	0		; ENABLE SBC-V2-004 HALF CLOCK DIVIDER
CPUFAMZ180	.EQU	1		; ENABLE Z180 WAIT STATE MANAGEMENT
;
;Conditional assembly - use  -D switch on TASM or uz80as assembler to control
_ZX		.EQU    0		; 1) Version of ROUT (ZX or MSX standards)
_MSX		.EQU    0
_WBW		.EQU    0
HBIOS		.EQU    0
#IFDEF ZX
_ZX		.SET	1
#ELSE
#IFDEF MSX
_MSX		.SET	1
#ELSE
_WBW		.SET	1

#ENDIF
#ENDIF

CurPosCounter	.EQU	0	; 2) Current position counter at (START+11)
ACBBAC			.EQU	0	; 3) Allow channels allocation bits at (START+10)
LoopChecker		.EQU	1	; 4) Allow loop checking and disabling
Id				.EQU	1	; 5) Insert official identificator
; VTBANREL: debug build token only (bNNN). Revision stays literal v0.1 in MSGBAN.
#DEFINE VTBANREL "b170"

	.ORG	$0100
;
	CALL	CLI_PREP
	CALL	HEAPENDB_INIT		; load ceiling before banner / any VGM sizing
	CALL	CLI_HAVE_CREDITS_SWITCH
	LD	A,(CREDMD)
	OR	A
	JR	Z,STARTUP_BANNER
	PRTCRLF
	PRTSTRDE(MSGBAN)
	CALL	CRLF
	CALL	CRLF
	PRTSTRDE(MSGCRED)
	CALL	CRLF
	JP	0

STARTUP_BANNER:
	PRTCRLF
	PRTSTRDE(MSGBAN)		; Print to banner message
	CALL	PRTCPUKHZBAN		; Print detected CPU speed in MHz
	CALL	CRLF			; newline after banner
	CALL	CLI_HAVE_ALL_SWITCH
	CALL	CLI_HAVE_LOOP_SWITCH
	CALL	CLI_HAVE_CONFIG_SWITCH
	CALL	TCFG_INIT

	CALL	CLI_ABRT_IF_OPT_FIRST
	CALL	CLI_PORTS
	CALL	CLI_HAVE_HBIOS_SWITCH
	CALL	CLI_HAVE_DELAY_SWITCH
	CALL	CLI_HAVE_YM2151_SWITCH
	CALL	YM2151_PORTCFG
	CALL	CLI_OCTAVE_ADJST
	CALL	UI_SETUP

	LD	A,(CONFIGMD)
	OR	A
	JR	Z,CONTINUE0
	CALL	TCFG_CONFIG
	JP	0

CONTINUE0:
	;
	LD	A,(ALLMD)
	OR	A
	JR	NZ,CONTINUE
	LD	A,(CLIBUF)
	OR	A
	JP	Z,ERRCMD
	;
	; If no filename is provided, exit immediately with usage.
	; Some environments leave the FCB filename field as NULs instead of spaces.
	LD	A,(FCB+1)
	OR	A
	JP	Z,ERRCMD
	CP	' '
	JP	Z,ERRCMD
	;
	JP	CONTINUE

CONTINUE:
	; Check BIOS and version
	CALL	IDBIO			; Identify hardware BIOS
	CP	1					; RomWBW HBIOS?
	JP	NZ, ERRBIO			; If not, handle BIOS error
	LD	A, RMJ << 4 | RMN	; Expected HBIOS ver
	CP	D					; Compare with result above
	JP	NZ, ERRBIO			; Handle BIOS error
	LD	A, L				; Platform id to A
	LD	(CURPLT),A			; Save as current platform id

	LD	A, (HBIOSMD)
	OR	A
	JP	NZ, TSTTIMER		; skip hardware check if using hbios

	LD	A, (USEPORTS)		; get ports option
	LD	HL,MSXPORTS			; assume MSX
	CP	PORTS_MSX			; use MSX?
	JR	Z,FORCE
	LD	HL,RCPORTS			; assume RC
	CP	PORTS_RC			; use RC?
	JR	Z,FORCE
	LD	HL,COLECOPORTS		; assume Coleco AY ports
	CP	PORTS_COLECO		; use Coleco?
	JR	Z,FORCE
	JP	AUTOSEL_IMPL		; otherwise do auto select

FORCE:
	LD	BC,CFGSIZ		; Size of one entry
	LD	DE,CFG			; Active config structure
	LDIR				; Update active config structure
	JR	MAT				; Continue

MAT:
	; Hardware matched!
	;
	; NOTE: Do not print hardware/mode info here anymore.
	; We defer printing until after the file is loaded so we can
	; suppress the single-chip description for TurboSound files.
	;
;
TSTTIMER:
	;
	; Probe timer and set WMOD, but do not print anything here.
	; Output is deferred until after file load.
	;
	CALL	PROBETIMER
;
	; Get CPU speed & type from RomWBW HBIOS and compute quark delay factor
	LD	B,$F8			; HBIOS SYSGET function 0xF8
	LD	C,$F0			; CPUINFO subfunction 0xF0
	RST	08				; Do it, DE := CPU speed in KHz
	SRL	D				; Divide by 2
	RR	E				; ... for delay factor
	EX	DE,HL			; Move result to HL
	LD	(QDLY),HL		; Save result as quark delay factor
	LD	(QDLY0),HL		; Save pristine base quark delay
;
	; Clear heap storage
	LD	HL,HEAP				; Point to heap start
	XOR	A					; A := zero
	LD	(HEAP),A			; Clear first byte of heap
	LD	DE,HEAP+1			; Set dest to next byte
	LD	BC,HEAPEND-HEAP-1	; Size of heap except first byte
	LDIR					; Propagate zero to rest of heap
;
	; If -list is selected, enumerate supported files once into a playlist.
	LD	A,(ALLMD)
	OR	A
	JR	NZ,PLAYALL_INIT
	CALL	SINGLE_FCBSAVE
	JR	PLAYNEXT
PLAYALL_INIT:
	CALL	PLAYLIST_INIT
	CALL	PLAYLIST_ENUM_ALL
	LD	A,(PLCNT)
	OR	A
	JP	Z,ERRALL
	CALL	PLAYLIST_SNAPSHOT
	LD	DE,MSGPLFULL
	CALL	PRTSTR
	CALL	CRLF
	JR	PLAYNEXT
;
PLAYNEXT:
	XOR	A
	LD	(STOPREQ),A
	LD	(SKIPREQ),A
	LD	(PREVREQ),A
	LD	(NAVREQ),A
	LD	(DELREQ),A
	LD	(PAUSEMD),A
	LD	(DELCNT),A
	LD	HL,(QDLY0)
	LD	(QDLY),HL
	LD	A,(ALLMD)
	OR	A
	JR	Z,PLAYNEXT_SINGLE
	CALL	PLAYLIST_LOAD_FCB
	CALL	PLAYLIST_SET_FILTYP
	CALL	CLI_ABRT_UNSUPPFILTYP
	JP	_LD0
;
PLAYNEXT_SINGLE:
	LD	A,(LOOPTRKMD)
	OR	A
	JR	Z,PLAYNEXT_SINGLE0
	CALL	SINGLE_FCBRESTORE
PLAYNEXT_SINGLE0:
	; Check sound filename (must be .PT2, .PT3, .MYM, .VGM)
	LD	A,(FCB+1)		; Get first char of filename
	CP	' '				; Compare to blank
	JP	Z,ERRCMD		; If so, missing filename
	LD	A,(FCB+9)		; If the filetype
	CP	' '				; is blanks
	JR	NZ,HASEXT		; then assume
	LD	A,'P'			; type PT3.
	LD	(FCB+9),A
	LD	A,'T'			; Fill in
	LD	(FCB+10),A		; the file
	LD	A,'3'			; extension
	LD	(FCB+11),A		; and the
	LD	C,TYPPT3		; file type
	JR	_SET
HASEXT	LD	A,(FCB+9)	; Extension char 1
	CP	'P'				; Check for 'P'
	JP	NZ,CHKMYM		; If not, check for MYM extension
	LD	A,(FCB+10)		; Extension char 2
	CP	'T'				; Check for 'T'
	JP	NZ,ERRNAM		; If not, bad file extension
	LD	A,(FCB+11)		; Extension char 3
	LD	C,TYPPT2		; Assume PT2 file type
	CP	'2'				; Check for '2'
	JR	Z,_SET			; If so, commit file type value
	LD	C,TYPPT3		; Assume PT3 file type
	CP	'3'				; Check for '3'
	JR	Z,_SET			; If so, commit file type value
	JP	ERRNAM			; Anything else is a bad file extension
CHKMYM	LD	A,(FCB+9)	; Extension char 1
	CP	'M'				; Check for 'M'
	JP	NZ,CHKVGM		; If not, check for VGM extension
	LD	A,(FCB+10)		; Extension char 2
	CP	'Y'				; Check for 'Y'
	JP	NZ,ERRNAM		; If not, bad file extension
	LD	A,(FCB+11)		; Extension char 3
	LD	C,TYPMYM		; Assume MYM file type
	CP	'M'				; Check for 'M'
	JR	Z,_SET			; If so, commit file type value
	JP	ERRNAM			; Anything else is a bad file extension
CHKVGM	LD	A,(FCB+9)	; Extension char 1
	CP	'V'				; Check for 'V'
	JP	NZ,ERRNAM		; If not, unsupported extension
	LD	A,(FCB+10)		; Extension char 2
	CP	'G'				; Check for 'G'
	JP	NZ,ERRNAM
	LD	A,(FCB+11)		; Extension char 3
	LD	C,TYPVGM		; Assume VGM file type
	CP	'M'				; Check for 'M'
	JR	Z,_SET			; If so, commit file type value
	JP	ERRNAM
_SET	LD	A,C			; Get file type value
	LD	(FILTYP),A		; Save file type value
;
	CALL	CLI_ABRT_UNSUPPFILTYP

	; Load sound file
_LD0	LD	C,15			; CPM Open File function
	LD	DE,FCB			; FCB
	CALL	BDOS			; Do it
	INC	A			; Test for error $FF
	JP	Z,ERRFIL		; Handle file error
;
	LD	A,(FILTYP)		; Get file type
	CP	TYPVGM			; VGM file?
	JR	Z,_LDVGM			; If so, use banked loader path
	LD	HL,MDLADDR		; Assume load address
	LD	(DMA),HL		; ... for PTx files
	CP	TYPMYM			; MYM file?
	JR	NZ,_LDCLR		; If not, all set
	LD	HL,rows			; Otherwise, load address
	LD	(DMA),HL		; ... for MYM files
	JR	_LDCLR
;
_LDVGM	LD	HL,PLSRCHBUF		; Fixed DMA buffer for VGM banked loading
	LD	(DMA),HL
	JR	_LDCLR
;
_LDCLR	XOR	A			; reset load byte counter
	LD	(LOADBYTES),A
	LD	(LOADBYTES+1),A
	LD	(VGMMMUMD),A
	LD	(VGMWINVAL),A
	LD	(VGMWSTRM),A
	LD	(VGMLOADSZ),A
	LD	(VGMLOADSZ+1),A
	LD	(VGMLOADSZ+2),A
	LD	(vgmpos),A
	LD	(vgmpos+1),A
	LD	(vgmpos+2),A
	LD	(VGMRDERR),A
	LD	A,(FILTYP)
	CP	TYPVGM
	JP	Z,VGM_LOAD_VGM
;
_LD	LD	HL,(DMA)		; Get load address
	PUSH	HL			; Save it
	LD	DE,128			; Bump by size of
	ADD	HL,DE			; ... one record
	LD	(DMA),HL		; Save for next loop
	LD	A,(HEAPENDB)	; A := dynamic page limit (BDOS - 1 page)
	CP	H				; Check to see if limit hit
	JP	Z,ERRSIZ		; Handle size error
	POP	DE				; Restore current DMA to DE
	LD	C,26			; CPM Set DMA function
	CALL	BDOS		; Read next 128 bytes
;
	LD	C,20			; CPM Read Sequential function
	LD	DE,FCB			; FCB
	CALL	BDOS		; Read next 128 bytes
	OR	A				; Set flags to check EOF
	JP	NZ,_LDX			; Non-zero is EOF (JR range to _LDX)
	; successful read, count bytes loaded (128 at a time)
	LD	HL,(LOADBYTES)
	LD	DE,128
	ADD	HL,DE
	LD	(LOADBYTES),HL
	JR	_LD			; Load loop
;
; Parse expected VGM file size (EOF offset + 4) from PLSRCHBUF into VGMEXP (LE).
; CY if unsupported (EOF high byte non-zero) or zero size.
;
VGM_PARSE_HDR_EXP:
	LD	A,(PLSRCHBUF+7)
	OR	A
	SCF
	RET	NZ
	LD	HL,(PLSRCHBUF+4)
	LD	A,(PLSRCHBUF+6)
	LD	C,A
	XOR	A
	LD	DE,4
	ADD	HL,DE
	LD	A,C
	ADC	A,0
	LD	(VGMEXP),HL
	PUSH	HL
	LD	HL,VGMEXP
	INC	HL
	INC	HL
	LD	(HL),A
	POP	HL
	OR	H
	OR	L
	SCF
	RET	Z
	OR	A
	RET
;
; Max bytes loadable from vgmdata upward without crossing HEAPENDB (_LD rule).
; Out: 24-bit LE in VGMCAP (high byte 0).
;
VGM_MAX_LINEAR:
	XOR	A
	LD	(VGMCAP+2),A
	LD	DE,vgmdata
	LD	BC,0
VGM_MXL_LP:
	LD	HL,128
	ADD	HL,DE
	LD	A,(HEAPENDB)
	CP	H
	JR	Z,VGM_MXLX
	LD	D,H
	LD	E,L
	LD	HL,128
	ADD	HL,BC
	LD	B,H
	LD	C,L
	JR	VGM_MXL_LP
VGM_MXLX:
	LD	H,B
	LD	L,C
	LD	(VGMCAP),HL
	RET
;
; From CP/M page 0: high byte of BDOS vector at 7; load stops one page below.
HEAPENDB_INIT:
	LD	A,(7)
	DEC	A
	LD	(HEAPENDB),A
	RET
;
; Note: CP/M 2 does not provide a portable "bytes free in TPA" query. RomWBW
; HBIOS SYS_GETMEMINFO (E=32KB RAM bank count) is installed RAM, not free RAM
; after BDOS/CCP/this program. Do not synthesize a "Free RAM" banner value.
;
; VGM load: first sector in PLSRCHBUF. If header size fits in TPA, load linearly
; into vgmdata; else close/reopen and bank-load into MMU app RAM.
;
VGM_LOAD_VGM:
	LD	DE,PLSRCHBUF
	LD	C,26
	CALL	BDOS
	LD	C,20
	LD	DE,FCB
	CALL	BDOS
	OR	A
	JP	NZ,ERRVGMTR		; 0=sector read OK; NZ=EOF/error (empty/unreadable)
	CALL	VGM_PARSE_HDR_EXP
	JP	C,ERRVGMTR
	CALL	VGM_MAX_LINEAR
	LD	A,(VGMEXP+2)
	OR	A
	JR	NZ,VGM_LV_BANK
	LD	HL,(VGMEXP)
	LD	DE,(VGMCAP)
	LD	A,H
	CP	D
	JR	C,VGM_LV_LINEAR
	JR	NZ,VGM_LV_BANK
	LD	A,L
	CP	E
	JR	C,VGM_LV_LINEAR
	JR	NZ,VGM_LV_BANK
VGM_LV_LINEAR:
	LD	HL,PLSRCHBUF
	LD	DE,vgmdata
	LD	BC,128
	LDIR
	LD	HL,128
	LD	(VGMLOADSZ),HL
	XOR	A
	LD	(VGMLOADSZ+2),A
	LD	(LOADBYTES),HL
	LD	HL,vgmdata
	LD	DE,128
	ADD	HL,DE
	LD	(DMA),HL
VGM_LL1:
	LD	HL,(DMA)
	PUSH	HL
	LD	DE,128
	ADD	HL,DE
	LD	A,(HEAPENDB)
	CP	H
	JP	Z,ERRSIZ
	POP	DE
	LD	C,26
	CALL	BDOS
	LD	C,20
	LD	DE,FCB
	CALL	BDOS
	OR	A
	JR	NZ,VGM_LOAD_LINEAR_DONE
	LD	HL,(LOADBYTES)
	LD	DE,128
	ADD	HL,DE
	LD	(LOADBYTES),HL
	CALL	VGM_LOADSZ_ADD_128
	LD	HL,(DMA)
	LD	DE,128
	ADD	HL,DE
	LD	(DMA),HL
	JR	VGM_LL1
VGM_LOAD_LINEAR_DONE:
	XOR	A
	LD	(VGMWSTRM),A
	LD	A,$FF
	LD	(VGMWINVAL),A
	JP	_LDX
VGM_LV_BANK:
	; Probe read above consumed logical record 0 and left it in PLSRCHBUF.
	; Do not close/reopen here: some BDOS stacks return EOF on the first
	; sequential read after reopen, which leaves VGMLOADSZ wrong and trips
	; VGM_VALIDATE_IMAGE (stream start vs loaded size).
;
VGM_LOAD_MMU:
	CALL	VGM_MMU_INIT
	JP	NZ,ERRVGMINIT
	LD	DE,PLSRCHBUF		; VGM DMA buffer (fixed 128-byte record)
	LD	C,26			; CPM Set DMA function (once for fixed buffer)
	CALL	BDOS
	; Bank 0..127 from probe sector; FCB already points at record 1.
	CALL	VGM_MMU_WRITE_REC
	JP	NZ,ERRVGMAX
	LD	HL,(LOADBYTES)
	LD	DE,128
	ADD	HL,DE
	LD	(LOADBYTES),HL
	CALL	VGM_LOADSZ_ADD_128
	CALL	VGM_MMU_VERIFY_LAST_REC
	JP	NZ,ERRVGMVF
;
VGM_LOAD_MMU1:
	LD	C,20			; CPM Read Sequential function
	LD	DE,FCB			; FCB
	CALL	BDOS			; Read next 128 bytes
	OR	A			; Set flags to check EOF
	JR	NZ,VGM_LOAD_MMU_DONE	; Non-zero is EOF
	CALL	VGM_MMU_WRITE_REC	; write one 128-byte record into app banks
	JP	NZ,ERRVGMAX		; fail if app-bank capacity exceeded
	LD	HL,(LOADBYTES)
	LD	DE,128
	ADD	HL,DE
	LD	(LOADBYTES),HL
	CALL	VGM_LOADSZ_ADD_128
	CALL	VGM_MMU_VERIFY_LAST_REC	; MMU readback vs PLSRCHBUF (post-write)
	JP	NZ,ERRVGMVF
	JR	VGM_LOAD_MMU1
;
VGM_LOAD_MMU_DONE:
	XOR	A
	LD	(VGMWSTRM),A
	LD	(VGMWINVAL),A		; header window not filled until LOAD_WIN0
	CALL	VGM_MMU_LOAD_WIN0	; copy file bytes [0..127] into vgmdata
	JP	C,ERRVGMRD_PRI
	JP	_LDX
;
_LDX	LD	C,16			; CPM Close File function
	LD	DE,FCB			; FCB
	CALL	BDOS			; Do it
	CALL	META_SNAPSHOT		; preserve title/artist for stable redraw
;
	LD	A,(ALLMD)
	OR	A
	JR	Z,_LDX0
	LD	A,(PLSHOWN)
	OR	A
	JR	NZ,_LDX0
	CALL	SHOWPLSTATUS
	LD	A,$FF
	LD	(PLSHOWN),A
_LDX0:
	XOR	A
	LD	(TS_CHIP1_PORTS),A
	LD	(TS_CHIP1_PORTS+1),A
	CALL	UI_CLEAR_TRACK_BLOCK
	; Post-load: print hardware / TurboSound info
	CALL	PRTPLAYINFO
	;
	LD	A,(FILTYP)		; Get file type
	CP	TYPPT3			; PT3?
	JR	Z,GOPT3			; If so, do it
	CP	TYPMYM			; MYM?
	JP	Z,gomym			; If so, do it
	CP	TYPVGM			; VGM?
	JP	Z,goVGM			; If so, do it
	JP	ERRNAM			; This should never happen

#include "ptx_runtime.inc"

#include "mym_runtime.inc"

#include "vgm_runtime.inc"

VGM_VALIDATE_IMAGE:
	CALL	VGM_MMU_SYNC_HDR
	LD	A,(vgmdata + 04H)	; EOF offset byte 0
	ADD	A,4					; expected size = eof + 4
	LD	E,A
	LD	A,(vgmdata + 05H)	; EOF offset byte 1
	ADC	A,0
	LD	D,A
	LD	A,(vgmdata + 06H)	; EOF offset byte 2
	ADC	A,0
	LD	C,A
	LD	A,(vgmdata + 07H)	; EOF offset byte 3
	ADC	A,0
	LD	B,A
	LD	A,B
	OR	A
	; Header allows large EOF; real VGMs are typically ~15-100KB (well under 300KB).
	JP	NZ,ERRVGMTR			; >16MB not supported in this MMU model
	; Do not require loaded bytes >= header EOF: many rips have EOF past real
	; length; PC players use physical file size. We bound playback by VGMLOADSZ.
VGM_VAL_OK:
	CALL	VGM_GET_STREAM_START	; C:HL = first command-stream byte offset
	LD	A,(VGMLOADSZ+2)
	CP	C
	JP	C,ERRVGMTR		; stream start above image (high byte)
	JR	NZ,VGM_VAL_STROK
	LD	A,(VGMLOADSZ+1)
	CP	H
	JP	C,ERRVGMTR
	JR	NZ,VGM_VAL_STROK
	LD	A,(VGMLOADSZ)
	CP	L
	JP	C,ERRVGMTR
	JP	Z,ERRVGMTR		; stream start == image size (no bytes to read)
VGM_VAL_STROK:
	RET
;
; Return command-stream start as C:HL (24-bit offset from file base).
; For v1.00 files with stream offset 0, default is 0x000040.
;
VGM_GET_STREAM_START:
	CALL	VGM_MMU_SYNC_HDR
	LD	A,(vgmdata + 34H)	; stream offset byte 0
	LD	E,A
	LD	A,(vgmdata + 35H)	; stream offset byte 1
	LD	D,A
	LD	A,(vgmdata + 36H)	; stream offset byte 2
	LD	C,A
	LD	A,(vgmdata + 37H)	; stream offset byte 3
	OR	A
	JR	NZ,VGM_GSS_DFL		; unsupported high byte => use safe default
	LD	A,E
	OR	D
	OR	C
	JR	NZ,VGM_GSS_OFS
VGM_GSS_DFL:
	LD	HL,0040H			; v1.00 default command stream start
	LD	C,0
	RET
VGM_GSS_OFS:
	LD	HL,0034H			; offset is relative to header byte 0x34
	ADD	HL,DE
	LD	A,C
	ADC	A,0
	LD	C,A
	RET
;
; Ensure header bytes at vgmdata+00..7F match file offset 0..7F (MMU mode).
; If VGMWINVAL is set, RAM already matches banks (primed at load); skip a
; second BNKCPY — post-BDOS CLOSE the copy can fail even when data is fine.
; Returns with A = first header byte in vgmdata (unused by most callers).
;
VGM_MMU_SYNC_HDR:
	LD	A,(VGMMMUMD)
	OR	A
	RET	Z
	LD	A,(VGMWINVAL)
	OR	A
	JR	NZ,VGM_MMU_SYNC_HDR_RAMOK
	CALL	VGM_MMU_LOAD_WIN0
	JP	C,ERRVGMRD_HDR
VGM_MMU_SYNC_HDR_RAMOK:
	LD	A,(vgmdata)
	OR	A				; NC, A = first header byte
	RET
;
; Copy VGM logical bytes [0..127] from app banks into vgmdata (one BNKCPY).
; Returns NC on success, CY on failure.
;
VGM_MMU_LOAD_WIN0:
	XOR	A
	LD	HL,0
	CALL	VGM_OFF_TO_BNK
	RET	C
	LD	(VGMTMPBNK),A
	LD	(VGMTMPADR),HL
	CALL	VGM_MMU_SYNC_CURBNK
	LD	B,BF_SYSSETCPY
	LD	A,(VGMTMPBNK)
	LD	C,A
	LD	E,C
	LD	A,(VGMCURBNK)
	LD	D,A
	LD	HL,128
	RST	08
	OR	A
	JR	NZ,VGM_MMU_LOAD_WIN0_FAIL
	LD	B,BF_SYSBNKCPY
	LD	HL,(VGMTMPADR)
	LD	DE,vgmdata
	RST	08
	OR	A
	JR	NZ,VGM_MMU_LOAD_WIN0_FAIL
	LD	A,$FF
	LD	(VGMWINVAL),A
	OR	A
	RET
VGM_MMU_LOAD_WIN0_FAIL:
	SCF
	RET
;
; If SYSGET app-banks is unavailable (older HBIOS), fill H/L/E like SYS_GETAPPBNKS
; using BNKINFO + SYS_PEEK into the HCB (same idea as HB_APPBOOT in hbios.asm).
; Out: H=first app bank, L=count, E=$80 (32KB pages). Returns Z and A=0 on success.
;
VGM_MMU_TRY_HCB_APPBNKS:
	LD	BC,BC_SYSGET_BNKINFO
	RST	08
	OR	A
	RET	NZ
	LD	A,D
	LD	(VGMTMPBNK),A		; BIOS bank for SYS_PEEK (RST may clobber D)
	LD	B,BF_SYSPEEK
	LD	D,A
	LD	HL,HCB_LOC + HCB_BIDAPP0
	RST	08
	OR	A
	RET	NZ
	LD	A,E
	LD	(TMP),A
	LD	A,(VGMTMPBNK)
	LD	D,A
	LD	B,BF_SYSPEEK
	LD	HL,HCB_LOC + HCB_APP_BNKS
	RST	08
	OR	A
	RET	NZ
	LD	L,E
	LD	A,(TMP)
	LD	H,A
	LD	E,$80
	XOR	A
	RET
;
; Initialize VGM MMU state.
; Returns Z on success, NZ on failure.
;
VGM_MMU_INIT:
	LD	B,BF_SYSGETBNK		; determine current app bank id
	RST	08
	OR	A
	RET	NZ
	LD	A,C
	LD	(VGMCURBNK),A
	LD	BC,BC_SYSGET_APPBNKS	; query app-bank allocation
	RST	08
	OR	A
	JR	Z,VGM_MMU_INIT_GOTAPP
	CALL	VGM_MMU_TRY_HCB_APPBNKS
	OR	A
	RET	NZ
VGM_MMU_INIT_GOTAPP:
	LD	A,L
	OR	A
	JR	Z,VGM_MMU_INIT_FAIL	; no app banks available
	LD	A,E
	CP	$80
	JR	NZ,VGM_MMU_INIT_FAIL	; this implementation assumes 32KB app banks
	LD	A,H
	LD	(VGMAPPBNK0),A
	LD	A,L
	LD	(VGMAPPBNKC),A
	; Same rule as mmutest/mmulib MMU_INIT: never use the executing bank as
	; BNKCPY destination storage. If we run in the first app bank, shift the
	; storage base up by one bank (must still have at least one bank left).
	LD	A,(VGMCURBNK)
	LD	B,A
	LD	A,(VGMAPPBNK0)
	LD	C,A
	CP	B
	JR	Z,VGM_MMU_INIT_SHIFT0
	LD	A,B
	CP	C
	JR	C,VGM_MMU_INIT_OKBNK
	LD	A,(VGMAPPBNK0)
	LD	D,A
	LD	A,(VGMAPPBNKC)
	ADD	A,D
	DEC	A
	CP	B
	JR	C,VGM_MMU_INIT_OKBNK
	JR	Z,VGM_MMU_INIT_OKBNK
	JR	VGM_MMU_INIT_FAIL
VGM_MMU_INIT_SHIFT0:
	LD	A,(VGMAPPBNKC)
	DEC	A
	JR	Z,VGM_MMU_INIT_FAIL
	LD	(VGMAPPBNKC),A
	LD	A,(VGMAPPBNK0)
	INC	A
	LD	(VGMAPPBNK0),A
VGM_MMU_INIT_OKBNK:
	XOR	A
	LD	(VGMWINVAL),A
	LD	(VGMWSTRM),A
	LD	A,$FF
	LD	(VGMMMUMD),A
	XOR	A
	RET
VGM_MMU_INIT_FAIL:
	OR	$FF
	RET
;
; Refresh VGMCURBNK from HBIOS invocation bank (HB_INVBNK). Call before each
; SETCPY/BNKCPY pair: BDOS and other RST $08 users can leave a different bank
; active than at VGM_MMU_INIT, so stale VGMCURBNK breaks src/dst bank ids.
;
VGM_MMU_SYNC_CURBNK:
	LD	B,BF_SYSGETBNK
	RST	08
	LD	A,C
	LD	(VGMCURBNK),A
	OR	A			; clear CY for callers (RST flag hygiene)
	RET
;
; Write one 128-byte DMA record from VGMDMABUF to banked VGM storage.
; Uses current VGMLOADSZ as the destination logical offset.
; Returns Z on success, NZ on failure.
;
VGM_MMU_WRITE_REC:
	LD	A,(VGMLOADSZ+2)
	LD	HL,(VGMLOADSZ)
	CALL	VGM_OFF_TO_BNK
	JR	NC,VGM_MMU_WRITE_REC0
	OR	$FF
	RET
VGM_MMU_WRITE_REC0:
	LD	(VGMTMPBNK),A
	LD	(VGMTMPADR),HL
	CALL	VGM_MMU_SYNC_CURBNK	; BDOS/HBIOS may have changed inv bank vs init
	LD	B,BF_SYSSETCPY
	LD	A,(VGMTMPBNK)		; destination = app bank for logical offset
	LD	C,A
	LD	A,(VGMCURBNK)		; source = current running bank (DMA buffer)
	LD	E,A
	LD	D,C
	LD	HL,128
	RST	08
	OR	A
	RET	NZ
	LD	B,BF_SYSBNKCPY
	LD	HL,PLSRCHBUF			; source address in current bank
	LD	DE,(VGMTMPADR)		; destination address in app bank
	RST	08
	OR	A
	RET
;
; Add 128 bytes to 24-bit VGMLOADSZ.
;
VGM_LOADSZ_ADD_128:
	LD	A,(VGMLOADSZ)
	ADD	A,128
	LD	(VGMLOADSZ),A
	RET	NC
	LD	A,(VGMLOADSZ+1)
	INC	A
	LD	(VGMLOADSZ+1),A
	RET	NZ
	LD	A,(VGMLOADSZ+2)
	INC	A
	LD	(VGMLOADSZ+2),A
	RET
;
; After each 128-byte record is written and VGMLOADSZ updated, BNKCPY the
; whole sector back into vgmdata (same geometry as VGM_MMU_LOAD_WIN0) and
; compare to PLSRCHBUF. One 128-byte copy avoids per-byte SETCPY edge cases
; and matches the load path; VGM_MMU_SYNC_CURBNK keeps dest bank current.
; Returns Z on match, NZ on mismatch or copy error.
;
VGM_MMU_VERIFY_LAST_REC:
	LD	HL,(VGMLOADSZ)
	LD	A,(VGMLOADSZ+2)
	OR	A
	LD	DE,128
	SBC	HL,DE
	SBC	A,0
	LD	(VGMVRBAS),HL
	LD	(VGMVRBAS+2),A
	CALL	VGM_MMU_SYNC_CURBNK
	LD	HL,(VGMVRBAS)
	LD	A,(VGMVRBAS+2)
	CALL	VGM_OFF_TO_BNK
	JR	C,VGM_VRF_FAIL
	LD	(VGMTMPBNK),A
	LD	(VGMTMPADR),HL
	LD	B,BF_SYSSETCPY
	LD	A,(VGMTMPBNK)
	LD	C,A
	LD	E,C
	LD	A,(VGMCURBNK)
	LD	D,A
	LD	HL,128
	RST	08
	OR	A
	JR	NZ,VGM_VRF_FAIL
	LD	B,BF_SYSBNKCPY
	LD	HL,(VGMTMPADR)
	LD	DE,vgmdata
	RST	08
	OR	A
	JR	NZ,VGM_VRF_FAIL
	LD	HL,vgmdata
	LD	DE,PLSRCHBUF
	LD	B,128
VGM_VRF_LP:
	LD	A,(DE)
	CP	(HL)
	JR	NZ,VGM_VRF_FAIL
	INC	HL
	INC	DE
	DJNZ	VGM_VRF_LP
	XOR	A
	RET
VGM_VRF_FAIL:
	OR	$FF
	RET
;
; Convert 24-bit logical VGM offset to app bank + 15-bit bank address.
; In:  A = offset byte 2, HL = offset bytes 1:0
; Out: A = bank id, HL = in-bank address (0x0000..0x7FFF), CY clear on success
;      CY set on out-of-range bank index.
;
VGM_OFF_TO_BNK:
	LD	D,A
	LD	A,D
	ADD	A,A					; offset bit15..22 -> bank index bits0..7
	LD	C,A
	LD	A,H
	AND	80H
	JR	Z,VGM_OFF_TO_BNK0
	INC	C						; include offset bit15
VGM_OFF_TO_BNK0:
	LD	A,(VGMAPPBNKC)
	CP	C
	JR	Z,VGM_OFF_TO_BNK_FAIL
	JR	C,VGM_OFF_TO_BNK_FAIL
	LD	A,(VGMAPPBNK0)
	ADD	A,C
	LD	C,A
	LD	A,H
	AND	7FH
	LD	H,A
	LD	A,C
	OR	A						; clear carry
	RET
VGM_OFF_TO_BNK_FAIL:
	SCF
	RET
;
; Check whether B:HL is strictly inside [0, VGMLOADSZ).
; In:  B = offset byte 2, HL = offset bytes 1:0
; Out: CY clear when in range, CY set when out of range.
;
VGM_OFF_INRANGE:
	LD	A,(VGMLOADSZ+2)
	CP	B
	JR	C,VGM_OFF_INRANGE_FAIL
	JR	NZ,VGM_OFF_INRANGE_OK
	LD	A,(VGMLOADSZ+1)
	CP	H
	JR	C,VGM_OFF_INRANGE_FAIL
	JR	NZ,VGM_OFF_INRANGE_OK
	LD	A,(VGMLOADSZ)
	CP	L
	JR	C,VGM_OFF_INRANGE_FAIL
	JR	Z,VGM_OFF_INRANGE_FAIL
VGM_OFF_INRANGE_OK:
	OR	A						; clear carry
	RET
VGM_OFF_INRANGE_FAIL:
	SCF
	RET
;
; Read byte at logical VGM offset A:HL.
; Offsets 0..127 are served from RAM vgmdata (same bytes as VGM_MMU_LOAD_WIN0);
; avoids SYS_PEEK/HBX_PEEK issues for the common case (stream often starts at 0x40).
; Offset >= 128: 128-byte BNKCPY window into VGMWINBUF (same engine as verify),
; tagged by logical base in VGMWBASE; SYS_PEEK fails on some RC2014 builds.
; VGMVRBAS holds aligned logical block start while filling (reuse after load).
; Returns NC with data in A on success; CY set and A=0 on out-of-range or error.
;
VGM_MMU_READ_AT:
	LD	B,A
	LD	A,L
	LD	(VGMRDLOW),A
	CALL	VGM_OFF_INRANGE
	JR	NC,VGM_MMU_READ_AT1
	XOR	A
	SCF
	RET
VGM_MMU_READ_AT1:
	LD	A,(VGMRDLOW)
	LD	L,A
	LD	A,(VGMMMUMD)
	OR	A
	JR	Z,VGM_READ_LIN
	LD	A,B
	OR	A
	JR	NZ,VGM_MMU_READ_SLOW
	LD	A,H
	OR	A
	JR	NZ,VGM_MMU_READ_SLOW
	LD	A,L
	CP	80H
	JR	NC,VGM_MMU_READ_SLOW
	LD	DE,vgmdata
	ADD	HL,DE
	LD	A,(HL)
	OR	A
	RET
VGM_READ_LIN:
	LD	A,B
	OR	A
	JP	NZ,VGM_MMU_READ_AT_FAIL
	LD	DE,vgmdata
	ADD	HL,DE
	JP	C,VGM_MMU_READ_AT_FAIL
	LD	A,(HL)
	OR	A
	RET
VGM_MMU_READ_SLOW:
	LD	C,B			; C = offset byte 2
	LD	E,L
	LD	A,E
	AND	7FH
	LD	(VGMTMPIDX),A
	LD	E,A
	LD	A,L
	SUB	E
	LD	L,A
	LD	A,H
	SBC	A,0
	LD	H,A
	LD	A,C
	SBC	A,0
	LD	(VGMVRBAS),HL
	LD	(VGMVRBAS+2),A
	LD	A,(VGMWSTRM)
	OR	A
	JR	Z,VGM_MMU_RD_SLFILL
	LD	A,(VGMVRBAS)
	LD	HL,VGMWBASE
	CP	(HL)
	JR	NZ,VGM_MMU_RD_SLFILL
	INC	HL
	LD	A,(VGMVRBAS+1)
	CP	(HL)
	JR	NZ,VGM_MMU_RD_SLFILL
	INC	HL
	LD	A,(VGMVRBAS+2)
	CP	(HL)
	JR	NZ,VGM_MMU_RD_SLFILL
	LD	A,(VGMTMPIDX)
	LD	E,A
	LD	D,0
	LD	HL,VGMWINBUF
	ADD	HL,DE
	LD	A,(HL)
	OR	A
	RET
; When the 128-byte stream window misses, BNKCPY refills VGMWINBUF. That cost is
; paid inside command decode (before VGM_APPLY_DELAY), so wall time wobbles vs the
; fixed per-sample DJNZ loop — a BPM meter often shows narrow swing on bank lines.
VGM_MMU_RD_SLFILL:
	LD	HL,(VGMVRBAS)
	LD	A,(VGMVRBAS+2)
	CALL	VGM_OFF_TO_BNK
	JR	C,VGM_MMU_READ_AT_FAIL
	LD	(VGMTMPBNK),A
	LD	(VGMTMPADR),HL
	CALL	VGM_MMU_SYNC_CURBNK
	LD	B,BF_SYSSETCPY
	LD	A,(VGMTMPBNK)
	LD	C,A
	LD	E,C
	LD	A,(VGMCURBNK)
	LD	D,A
	LD	HL,128
	RST	08
	OR	A
	JR	NZ,VGM_MMU_READ_AT_FAIL
	LD	B,BF_SYSBNKCPY
	LD	HL,(VGMTMPADR)
	LD	DE,VGMWINBUF
	RST	08
	OR	A
	JR	NZ,VGM_MMU_READ_AT_FAIL
	LD	HL,(VGMVRBAS)
	LD	A,(VGMVRBAS+2)
	LD	(VGMWBASE),HL
	LD	(VGMWBASE+2),A
	LD	A,$FF
	LD	(VGMWSTRM),A
	LD	A,(VGMTMPIDX)
	LD	E,A
	LD	D,0
	LD	HL,VGMWINBUF
	ADD	HL,DE
	LD	A,(HL)
	OR	A
	RET
VGM_MMU_READ_AT_FAIL:
	XOR	A
	LD	(VGMWINVAL),A
	LD	(VGMWSTRM),A
	SCF
	RET
;
EXIT	LD	A,(SKIPREQ)		; mute all cards immediately on track navigation
	OR	A
	JR	NZ,EXITMALL
	LD	A,(PREVREQ)
	OR	A
	JR	NZ,EXITMALL
	LD	A,(NAVREQ)
	OR	A
	JR	Z,EXIT0
EXITMALL:
	CALL	VGM_MUTE_ALL
EXIT0:
	LD	A,(VGMFLAG)
	OR	A
	JR	NZ,EXITX		; VGM: already muted by VGM_MUTE_ALL
	LD	A,(TSFLAG)
	OR	A
	JR	Z,EXITN
	LD	A,(TS_DUALHW)
	OR	A
	JR	Z,EXITN
	CALL	TS_MUTE			; Mute both chips
	JR	EXITX
EXITN	CALL	START+8		; Mute audio
EXITX
	;CALL	NORMCPU
	;CALL	CRLF2			; Formatting
	LD	DE,MSGEND			; Default completion message
	LD	A,(STOPREQ)
	OR	A
	JR	NZ,EXITX2
	LD	A,(ALLMD)
	OR	A
	JR	NZ,EXITXALL
	LD	A,(LOOPTRKMD)
	OR	A
	JR	Z,EXITX2
	LD	DE,MSGLOOP			; Single-file loop restart
	JR	EXITX2
EXITXALL:
	LD	A,(PREVREQ)
	OR	A
	JR	Z,EXITXALL0
	LD	DE,MSGPREV			; user requested previous track
	JR	EXITX2
EXITXALL0:
	LD	A,(SKIPREQ)
	OR	A
	JR	NZ,EXITXALL0A
	LD	A,(LOOPTRKMD)
	OR	A
	JR	Z,EXITXALL0A
	LD	DE,MSGLOOP			; track loop in playlist mode
	JR	EXITX2
EXITXALL0A:
	LD	A,(PLIDX)
	INC	A
	LD	B,A
	LD	A,(PLCNT)
	CP	B
	JR	Z,EXITXALL_LAST
	LD	DE,MSGNEXT			; another queued track remains
	JR	EXITX2
EXITXALL_LAST:
	LD	A,(LOOPPLMD)
	OR	A
	JR	Z,EXITX2			; no loop at end -> Done
	LD	DE,MSGLOOP			; playlist wrap in loop mode
EXITX2:
	CALL	PRTSTR			; Print message
	CALL	CRLF			; Formatting
	LD	A,(ALLMD)
	OR	A
	JR	Z,EXITS
	LD	A,(STOPREQ)
	OR	A
	JR	NZ,EXITP
	LD	A,(NAVREQ)
	OR	A
	JR	Z,EXITNAV0
	LD	A,(DELREQ)
	OR	A
	JR	Z,EXITNAVR0
	XOR	A
	LD	(DELREQ),A
	JP	PLAYNEXT		; _LDX0 will call SHOWPLSTATUS (PLSHOWN=0 from PLAYLIST_INIT)
EXITNAVR0:
	CALL	UI_UPDATE_MARKER_DELTA
	JP	PLAYNEXT
EXITNAV0:
	LD	A,(PREVREQ)
	OR	A
	JR	Z,EXITALLNXT
	LD	A,(PLIDX)
	LD	(PLIDXOLD),A
	CALL	PLAYLIST_PREV
	JR	Z,EXITP
	CALL	UI_UPDATE_MARKER_DELTA
	JP	PLAYNEXT
	JR	EXITP
EXITALLNXT:
	LD	A,(SKIPREQ)
	OR	A
	JR	NZ,EXITALLNXT0
	LD	A,(LOOPTRKMD)
	OR	A
	JR	Z,EXITALLNXT0
	JP	PLAYNEXT			; replay current track
EXITALLNXT0:
	LD	A,(PLIDX)
	LD	(PLIDXOLD),A
	CALL	PLAYLIST_ADVANCE
	JR	Z,EXITALLWRAP
	CALL	UI_UPDATE_MARKER_DELTA
	JP	PLAYNEXT

EXITALLWRAP:
	LD	A,(LOOPPLMD)
	OR	A
	JR	Z,EXITP
	CALL	PLAYLIST_RESTORE
	CALL	UI_UPDATE_MARKER_DELTA
	JP	PLAYNEXT
EXITS:
	LD	A,(STOPREQ)
	OR	A
	JR	NZ,EXITP
	LD	A,(LOOPTRKMD)
	OR	A
	JR	Z,EXITP
	JP	PLAYNEXT
EXITP:
	CALL	UI_EXIT_TO_PROMPT
	JP	0					; Exit the easy way

;
; Configure runtime YM2151 ports from CLI switch selection.
; YM2151MAP = 0 => 0xDE/0xDF, YM2151MAP = 1 => 0xFE/0xFF.
;
#include "hwcfg.inc"

#include "timing.inc"
#include "strings.inc"
#include "keyctl.inc"
#include "playback_core.inc"
#include "cli.inc"
#include "printing.inc"
#include "termcfg.inc"
#include "vgm_player.inc"

TCFG_INIT:
	CALL	cfg_defaults
	CALL	cfg_load
	RET

TCFG_CONFIG:
	CALL	FLUSHKEYS
	CALL	TCFG_CLRHOME
	CALL	TCFG_COL_HDR
	LD	DE,MSGCFGMODE
	CALL	PRTSTR
	CALL	TCFG_COL_RST
	CALL	CRLF2

	CALL	TCFG_SHOW_STATUS
	CALL	TCFG_ASK_TERM
	CALL	TCFG_ASK_ANSI

	LD	A,(cfg_term)
	OR	A
	JR	NZ,TCFG_CONFIG_TUNE
	LD	A,(cfg_flags)
	AND	CFGF_ANSI
	JR	Z,TCFG_CONFIG_SAVE
TCFG_CONFIG_TUNE:
	CALL	TCFG_SIZE_TUNE

TCFG_CONFIG_SAVE:
	CALL	cfg_save
	CALL	TCFG_CLRHOME
	CALL	TCFG_COL_OK
	LD	DE,MSGCFGSAVED
	CALL	PRTSTR
	CALL	TCFG_COL_RST
	CALL	CRLF
	CALL	TCFG_SHOW_SUMMARY
	CALL	CRLF2
	CALL	FLUSHKEYS
	RET

TCFG_SHOW_STATUS:
	LD	A,(cfg_found)
	OR	A
	JR	Z,TCFG_SHOW_STATUS0
	LD	DE,MSGCFGFOUND
	CALL	PRTSTR
	CALL	CRLF
	JR	TCFG_SHOW_STATUS1
TCFG_SHOW_STATUS0:
	LD	DE,MSGCFGDEFAULT
	CALL	PRTSTR
	CALL	CRLF
TCFG_SHOW_STATUS1:
	CALL	TCFG_SHOW_SUMMARY
	CALL	CRLF2
	RET

TCFG_SHOW_SUMMARY:
	LD	DE,MSGCFGTERM
	CALL	PRTSTR
	CALL	TCFG_SHOW_TERM
	CALL	CRLF
	LD	DE,MSGCFGANSI
	CALL	PRTSTR
	LD	A,(cfg_flags)
	AND	CFGF_ANSI
	LD	DE,MSGNO
	JR	Z,TCFG_SHOW_SUMMARY0
	LD	DE,MSGYES
TCFG_SHOW_SUMMARY0:
	CALL	PRTSTR
	CALL	CRLF
	LD	DE,MSGCFGSIZE
	CALL	PRTSTR
	LD	A,(cfg_cols)
	CALL	PRTDECB
	LD	A,' '
	CALL	PRTCHR
	LD	A,'x'
	CALL	PRTCHR
	LD	A,' '
	CALL	PRTCHR
	LD	A,(cfg_rows)
	CALL	PRTDECB
	RET

TCFG_SHOW_TERM:
	LD	A,(cfg_term)
	CP	1
	JR	Z,TCFG_SHOW_TERM1
	CP	2
	JR	Z,TCFG_SHOW_TERM2
	LD	DE,MSGTERMPLAIN
	JR	TCFG_SHOW_TERM3
TCFG_SHOW_TERM1:
	LD	DE,MSGTERMVT
	JR	TCFG_SHOW_TERM3
TCFG_SHOW_TERM2:
	LD	DE,MSGTERMANSI
TCFG_SHOW_TERM3:
	JP	PRTSTR

TCFG_ASK_TERM:
TCFG_ASK_TERM0:
	CALL	TCFG_COL_PRM
	LD	DE,MSGTERMMENU
	CALL	PRTSTR
	CALL	CRLF
	LD	DE,MSGTERMPROMPT
	CALL	PRTSTR
	CALL	TCFG_SHOW_TERM
	LD	DE,MSGPROMPTEND
	CALL	PRTSTR
	CALL	TCFG_COL_RST
	CALL	TCFG_GETCH
	CP	13
	JR	Z,TCFG_ASK_TERM_KEEP
	PUSH	AF
	CALL	PRTCHR
	CALL	CRLF
	POP	AF
	CALL	TCFG_UPCASE
	CP	'P'
	JR	Z,TCFG_ASK_TERM_PLAIN
	CP	'V'
	JR	Z,TCFG_ASK_TERM_VT
	CP	'A'
	JR	Z,TCFG_ASK_TERM_ANSI
	JR	TCFG_ASK_TERM0
TCFG_ASK_TERM_KEEP:
	CALL	CRLF
	RET
TCFG_ASK_TERM_PLAIN:
	XOR	A
	LD	(cfg_term),A
	RET
TCFG_ASK_TERM_VT:
	LD	A,1
	LD	(cfg_term),A
	RET
TCFG_ASK_TERM_ANSI:
	LD	A,2
	LD	(cfg_term),A
	RET

TCFG_ASK_ANSI:
TCFG_ASK_ANSI0:
	CALL	TCFG_COL_PRM
	LD	DE,MSGANSIPROMPT
	CALL	PRTSTR
	LD	A,(cfg_flags)
	AND	CFGF_ANSI
	LD	DE,MSGNO
	JR	Z,TCFG_ASK_ANSI1
	LD	DE,MSGYES
TCFG_ASK_ANSI1:
	CALL	PRTSTR
	LD	DE,MSGPROMPTEND
	CALL	PRTSTR
	CALL	TCFG_COL_RST
	CALL	TCFG_GETCH
	CP	13
	JR	Z,TCFG_ASK_ANSI_KEEP
	PUSH	AF
	CALL	PRTCHR
	CALL	CRLF
	POP	AF
	CALL	TCFG_UPCASE
	CP	'Y'
	JR	Z,TCFG_ASK_ANSI_YES
	CP	'N'
	JR	Z,TCFG_ASK_ANSI_NO
	JR	TCFG_ASK_ANSI0
TCFG_ASK_ANSI_KEEP:
	CALL	CRLF
	RET
TCFG_ASK_ANSI_YES:
	LD	A,(cfg_flags)
	OR	CFGF_ANSI
	LD	(cfg_flags),A
	RET
TCFG_ASK_ANSI_NO:
	LD	A,(cfg_flags)
	AND	0FFH-CFGF_ANSI
	LD	(cfg_flags),A
	RET

TCFG_SIZE_TUNE:
	CALL	TCFG_CLRHOME
	LD	DE,MSGTUNETITLE
	CALL	PRTSTR
	CALL	CRLF
	LD	DE,MSGTUNEKEYS
	CALL	PRTSTR
	CALL	CRLF
	XOR	A
	LD	(TCFG_PREV_COLS),A
	LD	(TCFG_PREV_ROWS),A
	CALL	TCFG_SIZE_REFRESH

	LD	B,4
	LD	C,1
	CALL	TCFG_ANSI_AT
TCFG_SIZE_TUNE0:
	LD	B,4
	LD	C,1
	CALL	TCFG_ANSI_AT
	CALL	TCFG_SIZE_GETKEY
	CP	27
	JP	Z,TCFG_SIZE_EXIT
	CP	'a'
	JP	Z,TCFG_SIZE_COL_DEC
	CP	'd'
	JP	Z,TCFG_SIZE_COL_INC
	CP	'w'
	JP	Z,TCFG_SIZE_ROW_DEC
	CP	's'
	JP	Z,TCFG_SIZE_ROW_INC
	JP	TCFG_SIZE_TUNE0

TCFG_SIZE_GETKEY:
	CALL	TCFG_GETCH
	CP	27
	RET	NZ
	CALL	TCFG_GETCH_TO
	OR	A
	JR	Z,TCFG_SIZE_GETKEY_ESC
	CP	'['
	JR	Z,TCFG_SIZE_GETKEY_SEQ
	CP	'O'
	JR	Z,TCFG_SIZE_GETKEY_SEQ
	LD	A,27
	RET

TCFG_SIZE_GETKEY_SEQ:
TCFG_SIZE_GETKEY_SEQ0:
	CALL	TCFG_GETCH_TO
	OR	A
	JR	Z,TCFG_SIZE_GETKEY_ESC
	CP	'0'
	JR	C,TCFG_SIZE_GETKEY_SEQ1
	CP	3AH
	JR	C,TCFG_SIZE_GETKEY_SEQ0
	CP	3BH
	JR	Z,TCFG_SIZE_GETKEY_SEQ0
	CP	3FH
	JR	Z,TCFG_SIZE_GETKEY_SEQ0

TCFG_SIZE_GETKEY_SEQ1:
	CP	'A'
	JR	Z,TCFG_SIZE_GETKEY_UP
	CP	'B'
	JR	Z,TCFG_SIZE_GETKEY_DOWN
	CP	'C'
	JR	Z,TCFG_SIZE_GETKEY_RIGHT
	CP	'D'
	JR	Z,TCFG_SIZE_GETKEY_LEFT
	CP	40H
	JR	C,TCFG_SIZE_GETKEY_SEQ0
	CP	7FH
	JR	C,TCFG_SIZE_GETKEY_NONE
	JR	TCFG_SIZE_GETKEY_SEQ0

TCFG_SIZE_GETKEY_NONE:
	XOR	A
	RET

TCFG_SIZE_GETKEY_UP:
	LD	A,'w'
	RET

TCFG_SIZE_GETKEY_DOWN:
	LD	A,'s'
	RET

TCFG_SIZE_GETKEY_RIGHT:
	LD	A,'d'
	RET

TCFG_SIZE_GETKEY_LEFT:
	LD	A,'a'
	RET

TCFG_SIZE_GETKEY_ESC:
	LD	A,27
	RET

TCFG_GETCH_TO:
	LD	B,32
TCFG_GETCH_TO0:
	CALL	GETKEY
	RET	NZ
	DJNZ	TCFG_GETCH_TO0
	XOR	A
	RET

TCFG_SIZE_EXIT:
	CALL	FLUSHKEYS
	CALL	TCFG_CLRHOME
	RET

TCFG_SIZE_COL_DEC:
	LD	A,(cfg_cols)
	CP	CFG_MIN_COLS
	JP	Z,TCFG_SIZE_TUNE0
	CALL	TCFG_SIZE_SNAPSHOT
	LD	A,(cfg_cols)
	DEC	A
	LD	(cfg_cols),A
	CALL	TCFG_SIZE_REFRESH
	JP	TCFG_SIZE_TUNE0

TCFG_SIZE_COL_INC:
	LD	A,(cfg_cols)
	CP	CFG_MAX_COLS
	JP	Z,TCFG_SIZE_TUNE0
	CALL	TCFG_SIZE_SNAPSHOT
	LD	A,(cfg_cols)
	INC	A
	LD	(cfg_cols),A
	CALL	TCFG_SIZE_REFRESH
	JP	TCFG_SIZE_TUNE0

TCFG_SIZE_ROW_DEC:
	LD	A,(cfg_rows)
	CP	CFG_MIN_ROWS
	JP	Z,TCFG_SIZE_TUNE0
	CALL	TCFG_SIZE_SNAPSHOT
	LD	A,(cfg_rows)
	DEC	A
	LD	(cfg_rows),A
	CALL	TCFG_SIZE_REFRESH
	JP	TCFG_SIZE_TUNE0

TCFG_SIZE_ROW_INC:
	LD	A,(cfg_rows)
	CP	CFG_MAX_ROWS
	JP	Z,TCFG_SIZE_TUNE0
	CALL	TCFG_SIZE_SNAPSHOT
	LD	A,(cfg_rows)
	INC	A
	LD	(cfg_rows),A
	CALL	TCFG_SIZE_REFRESH
	JP	TCFG_SIZE_TUNE0

TCFG_SIZE_SNAPSHOT:
	LD	A,(cfg_cols)
	LD	(TCFG_PREV_COLS),A
	LD	A,(cfg_rows)
	LD	(TCFG_PREV_ROWS),A
	RET

TCFG_SIZE_REFRESH:
	CALL	TCFG_SIZE_SHOW_CURR
	LD	A,(TCFG_PREV_COLS)
	OR	A
	JR	Z,TCFG_SIZE_REFRESH0
	LD	A,(TCFG_PREV_ROWS)
	OR	A
	JR	Z,TCFG_SIZE_REFRESH0
	LD	A,(cfg_cols)
	LD	B,A
	LD	A,(TCFG_PREV_COLS)
	CP	B
	CALL	NZ,TCFG_SIZE_UPDATE_COLS
	LD	A,(cfg_rows)
	LD	B,A
	LD	A,(TCFG_PREV_ROWS)
	CP	B
	CALL	NZ,TCFG_SIZE_UPDATE_ROWS
	CALL	TCFG_DRAW_SCALES
	JR	TCFG_SIZE_REFRESH1
TCFG_SIZE_REFRESH0:
	CALL	TCFG_DRAW_GRID
	JR	TCFG_SIZE_REFRESH2
TCFG_SIZE_REFRESH1:
TCFG_SIZE_REFRESH2:
	CALL	TCFG_SIZE_SNAPSHOT
	RET

TCFG_SIZE_SHOW_CURR:
	LD	B,3
	LD	C,1
	CALL	TCFG_ANSI_AT
	CALL	TCFG_EL2
	LD	B,3
	LD	C,1
	CALL	TCFG_ANSI_AT
	LD	DE,MSGTUNECURR
	CALL	PRTSTR
	LD	A,(cfg_cols)
	CALL	PRTDECB
	LD	A,' '
	CALL	PRTCHR
	LD	A,'x'
	CALL	PRTCHR
	LD	A,' '
	CALL	PRTCHR
	LD	A,(cfg_rows)
	CALL	PRTDECB
	LD	DE,MSGTUNEMAX
	CALL	PRTSTR
	RET

TCFG_SIZE_UPDATE_COLS:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	A,(TCFG_PREV_COLS)
	LD	D,A			; old cols
	LD	A,(cfg_cols)
	LD	E,A			; new cols
	CP	D
	JR	C,TCFG_SIZE_UCOLS_DEC

	; expanding width: old C becomes '-', new endpoint gets C
	LD	B,TCFG_ORG_ROW
	LD	A,D
	ADD	A,TCFG_ORG_COL - 1
	LD	C,A
	CALL	TCFG_ANSI_AT
	LD	A,'-'
	CALL	PRTCHR

	LD	A,E
	CALL	TCFG_SIZE_IS_DECADE
	JR	Z,TCFG_SIZE_UCOLS_INC0
	LD	B,TCFG_ORG_ROW - 1
	LD	A,E
	ADD	A,TCFG_ORG_COL - 1
	LD	C,A
	CALL	TCFG_ANSI_AT
	LD	A,E
	CALL	PRTDECB
TCFG_SIZE_UCOLS_INC0:
	JR	TCFG_SIZE_UCOLS_SETC

TCFG_SIZE_UCOLS_DEC:
	; shrinking width: erase old C endpoint, new endpoint gets C
	LD	B,TCFG_ORG_ROW
	LD	A,D
	ADD	A,TCFG_ORG_COL - 1
	LD	C,A
	CALL	TCFG_ANSI_AT
	LD	A,' '
	CALL	PRTCHR

	LD	A,D
	CALL	TCFG_SIZE_IS_DECADE
	JR	Z,TCFG_SIZE_UCOLS_SETC
	LD	B,TCFG_ORG_ROW - 1
	LD	A,D
	ADD	A,TCFG_ORG_COL - 1
	LD	C,A
	CALL	TCFG_ANSI_AT
	LD	A,' '
	CALL	PRTCHR
	CALL	PRTCHR
	CALL	PRTCHR

TCFG_SIZE_UCOLS_SETC:
	LD	B,TCFG_ORG_ROW
	LD	A,E
	ADD	A,TCFG_ORG_COL - 1
	LD	C,A
	CALL	TCFG_ANSI_AT
	LD	A,'C'
	CALL	PRTCHR

	; move X marker horizontally
	LD	A,(TCFG_PREV_ROWS)
	ADD	A,TCFG_ORG_ROW - 1
	LD	B,A
	LD	A,D
	ADD	A,TCFG_ORG_COL - 1
	LD	C,A
	CALL	TCFG_ANSI_AT
	LD	A,' '
	CALL	PRTCHR
	LD	A,(cfg_rows)
	ADD	A,TCFG_ORG_ROW - 1
	LD	B,A
	LD	A,E
	ADD	A,TCFG_ORG_COL - 1
	LD	C,A
	CALL	TCFG_ANSI_AT
	LD	A,'X'
	CALL	PRTCHR

	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

TCFG_SIZE_UPDATE_ROWS:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	A,(TCFG_PREV_ROWS)
	LD	D,A			; old rows
	LD	A,(cfg_rows)
	LD	E,A			; new rows
	CP	D
	JR	C,TCFG_SIZE_UROWS_DEC

	; expanding height: old R becomes '|', new endpoint gets R
	LD	A,D
	ADD	A,TCFG_ORG_ROW - 1
	LD	B,A
	LD	C,TCFG_ORG_COL
	CALL	TCFG_ANSI_AT
	LD	A,'|'
	CALL	PRTCHR

	LD	A,E
	CALL	TCFG_SIZE_IS_DECADE
	JR	Z,TCFG_SIZE_UROWS_INC0
	LD	A,E
	ADD	A,TCFG_ORG_ROW - 1
	LD	B,A
	LD	C,1
	CALL	TCFG_ANSI_AT
	LD	A,E
	CALL	PRTDECB
TCFG_SIZE_UROWS_INC0:
	JR	TCFG_SIZE_UROWS_SETR

TCFG_SIZE_UROWS_DEC:
	; shrinking height: erase old R endpoint, new endpoint gets R
	LD	A,D
	ADD	A,TCFG_ORG_ROW - 1
	LD	B,A
	LD	C,TCFG_ORG_COL
	CALL	TCFG_ANSI_AT
	LD	A,' '
	CALL	PRTCHR

	LD	A,D
	CALL	TCFG_SIZE_IS_DECADE
	JR	Z,TCFG_SIZE_UROWS_SETR
	LD	A,D
	ADD	A,TCFG_ORG_ROW - 1
	LD	B,A
	LD	C,1
	CALL	TCFG_ANSI_AT
	LD	A,' '
	CALL	PRTCHR
	CALL	PRTCHR
	CALL	PRTCHR

TCFG_SIZE_UROWS_SETR:
	LD	A,E
	ADD	A,TCFG_ORG_ROW - 1
	LD	B,A
	LD	C,TCFG_ORG_COL
	CALL	TCFG_ANSI_AT
	LD	A,'R'
	CALL	PRTCHR

	; move X marker vertically
	LD	A,D
	ADD	A,TCFG_ORG_ROW - 1
	LD	B,A
	LD	A,(TCFG_PREV_COLS)
	ADD	A,TCFG_ORG_COL - 1
	LD	C,A
	CALL	TCFG_ANSI_AT
	LD	A,' '
	CALL	PRTCHR
	LD	A,E
	ADD	A,TCFG_ORG_ROW - 1
	LD	B,A
	LD	A,(cfg_cols)
	ADD	A,TCFG_ORG_COL - 1
	LD	C,A
	CALL	TCFG_ANSI_AT
	LD	A,'X'
	CALL	PRTCHR

	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

TCFG_SIZE_IS_DECADE:
	; IN: A=value, OUT: NZ if value is an exact multiple of 10, else Z
	CP	10
	JR	C,TCFG_SIZE_IS_DEC0
TCFG_SIZE_IS_DEC1:
	SUB	10
	JR	Z,TCFG_SIZE_IS_DEC2
	JR	NC,TCFG_SIZE_IS_DEC1
TCFG_SIZE_IS_DEC0:
	XOR	A
	RET
TCFG_SIZE_IS_DEC2:
	LD	A,1
	RET

TCFG_DRAW_SCALES:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; top ruler labels (1, then decades)
	LD	B,TCFG_ORG_ROW - 1
	LD	C,1
	CALL	TCFG_ANSI_AT
	CALL	TCFG_EL2

	LD	B,TCFG_ORG_ROW - 1
	LD	C,TCFG_ORG_COL
	CALL	TCFG_ANSI_AT
	LD	A,'1'
	CALL	PRTCHR

	LD	D,10
TCFG_DRAW_SCALES_TOP:
	LD	A,(cfg_cols)
	CP	D
	JR	C,TCFG_DRAW_SCALES_LEFT
	LD	B,TCFG_ORG_ROW - 1
	LD	A,D
	ADD	A,TCFG_ORG_COL - 1
	LD	C,A
	CALL	TCFG_ANSI_AT
	LD	A,D
	PUSH	DE
	CALL	PRTDECB
	POP	DE
	LD	A,D
	ADD	A,10
	LD	D,A
	JR	TCFG_DRAW_SCALES_TOP

	; left ruler labels (decades only)
TCFG_DRAW_SCALES_LEFT:
	LD	D,10
TCFG_DRAW_SCALES_LEFT0:
	LD	A,D
	CP	CFG_MAX_ROWS + 1
	JR	NC,TCFG_DRAW_SCALES_DONE

	LD	A,D
	ADD	A,TCFG_ORG_ROW - 1
	LD	B,A
	LD	C,1
	CALL	TCFG_ANSI_AT
	LD	A,' '
	CALL	PRTCHR
	CALL	PRTCHR
	CALL	PRTCHR

	LD	A,(cfg_rows)
	CP	D
	JR	C,TCFG_DRAW_SCALES_LEFT1
	LD	A,D
	ADD	A,TCFG_ORG_ROW - 1
	LD	B,A
	LD	C,1
	CALL	TCFG_ANSI_AT
	LD	A,D
	CALL	PRTDECB

TCFG_DRAW_SCALES_LEFT1:
	LD	A,D
	ADD	A,10
	LD	D,A
	JR	TCFG_DRAW_SCALES_LEFT0

TCFG_DRAW_SCALES_DONE:
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

TCFG_CLEAR_SCALE:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; clear top ruler line so removed column decades disappear
	LD	B,TCFG_ORG_ROW - 1
	LD	C,1
	CALL	TCFG_ANSI_AT
	CALL	TCFG_EL2

	; clear left ruler gutter on full tuning height
	LD	D,TCFG_ORG_ROW
TCFG_CLEAR_SCALE0:
	LD	A,D
	CP	TCFG_ORG_ROW + CFG_MAX_ROWS
	JR	NC,TCFG_CLEAR_SCALE1
	LD	B,A
	LD	C,1
	CALL	TCFG_ANSI_AT
	LD	A,' '
	CALL	PRTCHR
	CALL	PRTCHR
	CALL	PRTCHR
	CALL	PRTCHR
	INC	D
	JR	TCFG_CLEAR_SCALE0
TCFG_CLEAR_SCALE1:
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

TCFG_DRAW_GRID:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	CALL	TCFG_CLEAR_SCALE

	LD	B,TCFG_ORG_ROW
	LD	C,TCFG_ORG_COL
	CALL	TCFG_ANSI_AT
	LD	A,'+'
	CALL	PRTCHR

	LD	D,2
TCFG_HLINE_LOOP:
	LD	A,(cfg_cols)
	CP	D
	JR	C,TCFG_HLINE_DONE
	LD	B,TCFG_ORG_ROW
	LD	A,D
	ADD	A,TCFG_ORG_COL - 1
	LD	C,A
	CALL	TCFG_ANSI_AT
	LD	A,'-'
	CALL	PRTCHR
	INC	D
	JR	TCFG_HLINE_LOOP
TCFG_HLINE_DONE:

	LD	D,2
TCFG_VLINE_LOOP:
	LD	A,(cfg_rows)
	CP	D
	JR	C,TCFG_VLINE_DONE
	LD	A,D
	ADD	A,TCFG_ORG_ROW - 1
	LD	B,A
	LD	C,TCFG_ORG_COL
	CALL	TCFG_ANSI_AT
	LD	A,'|'
	CALL	PRTCHR
	INC	D
	JR	TCFG_VLINE_LOOP
TCFG_VLINE_DONE:

	LD	B,TCFG_ORG_ROW - 1
	LD	C,TCFG_ORG_COL
	CALL	TCFG_ANSI_AT
	LD	A,'1'
	CALL	PRTCHR

	LD	B,TCFG_ORG_ROW
	LD	C,TCFG_ORG_COL - 1
	CALL	TCFG_ANSI_AT
	LD	A,'1'
	CALL	PRTCHR

	LD	D,10
TCFG_TOP_SCALE_LOOP:
	LD	A,(cfg_cols)
	CP	D
	JR	C,TCFG_TOP_SCALE_DONE
	LD	B,TCFG_ORG_ROW - 1
	LD	A,D
	ADD	A,TCFG_ORG_COL - 1
	LD	C,A
	CALL	TCFG_ANSI_AT
	LD	A,D
	PUSH	DE
	CALL	PRTDECB
	POP	DE
	LD	A,D
	ADD	A,10
	JR	C,TCFG_TOP_SCALE_DONE
	LD	D,A
	JR	TCFG_TOP_SCALE_LOOP
TCFG_TOP_SCALE_DONE:

	LD	D,10
TCFG_LEFT_SCALE_LOOP:
	LD	A,(cfg_rows)
	CP	D
	JR	C,TCFG_LEFT_SCALE_DONE
	LD	A,D
	ADD	A,TCFG_ORG_ROW - 1
	LD	B,A
	LD	C,1
	CALL	TCFG_ANSI_AT
	LD	A,D
	PUSH	DE
	CALL	PRTDECB
	POP	DE
	LD	A,D
	ADD	A,10
	JR	C,TCFG_LEFT_SCALE_DONE
	LD	D,A
	JR	TCFG_LEFT_SCALE_LOOP
TCFG_LEFT_SCALE_DONE:

	LD	B,TCFG_ORG_ROW
	LD	A,(cfg_cols)
	ADD	A,TCFG_ORG_COL - 1
	LD	C,A
	CALL	TCFG_ANSI_AT
	LD	A,'C'
	CALL	PRTCHR

	LD	A,(cfg_rows)
	ADD	A,TCFG_ORG_ROW - 1
	LD	B,A
	LD	C,TCFG_ORG_COL
	CALL	TCFG_ANSI_AT
	LD	A,'R'
	CALL	PRTCHR

	LD	A,(cfg_rows)
	ADD	A,TCFG_ORG_ROW - 1
	LD	B,A
	LD	A,(cfg_cols)
	ADD	A,TCFG_ORG_COL - 1
	LD	C,A
	CALL	TCFG_ANSI_AT
	LD	A,'X'
	CALL	PRTCHR

	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

TCFG_ANSI_AT:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	A,27
	CALL	PRTCHR
	LD	A,'['
	CALL	PRTCHR
	PUSH	BC
	LD	A,B
	CALL	PRTDECB
	LD	A,3BH
	CALL	PRTCHR
	POP	BC
	LD	A,C
	CALL	PRTDECB
	LD	A,'H'
	CALL	PRTCHR
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

TCFG_GETCH:
	CALL	GETKEY
	OR	A
	JR	Z,TCFG_GETCH
	RET

TCFG_UPCASE:
	CP	'a'
	RET	C
	CP	'z'+1
	RET	NC
	SUB	32
	RET

TCFG_CLRHOME:
	PUSH	AF
	LD	A,(cfg_term)
	OR	A
	JR	NZ,TCFG_CLRHOME1
	LD	A,(cfg_flags)
	AND	CFGF_ANSI
	JR	Z,TCFG_CLRHOME0
TCFG_CLRHOME1:
	LD	DE,TCFG_SEQ_CLR
	CALL	PRTSTR
TCFG_CLRHOME0:
	POP	AF
	RET

TCFG_COL_HDR:
	LD	DE,TCFG_SEQ_CYAN
	JP	TCFG_EMIT

TCFG_COL_PRM:
	LD	DE,TCFG_SEQ_YEL
	JP	TCFG_EMIT

TCFG_COL_OK:
	LD	DE,TCFG_SEQ_GRN
	JP	TCFG_EMIT

TCFG_COL_RST:
	LD	DE,TCFG_SEQ_RST
	JP	TCFG_EMIT

TCFG_EMIT:
	PUSH	AF
	LD	A,(cfg_flags)
	AND	CFGF_ANSI
	JR	Z,TCFG_EMIT0
	CALL	PRTSTR
TCFG_EMIT0:
	POP	AF
	RET

PRTPLAYMSG:
	LD	A,(UI_ACTIVE)
	OR	A
	JR	Z,PRTPLAYMSG0
	CALL	UI_ENSURE_INIT
	LD	B,UI_ROW_PLAY
	CALL	UI_CLR_ROW
	LD	B,UI_ROW_PLAY
	LD	C,1
	CALL	TCFG_ANSI_AT
	CALL	TCFG_COL_OK
	LD	DE,MSGPLY
	CALL	PRTSTR
	CALL	TCFG_COL_RST
	RET
PRTPLAYMSG0:
	LD	A,13
	CALL	PRTCHR
	CALL	TCFG_COL_OK
	LD	DE,MSGPLY
	CALL	PRTSTR
	CALL	TCFG_COL_RST
	RET

PRTPAUSEMSG:
	LD	A,(UI_ACTIVE)
	OR	A
	JR	Z,PRTPAUSEMSG0
	CALL	UI_ENSURE_INIT
	LD	B,UI_ROW_PLAY
	CALL	UI_CLR_ROW
	LD	B,UI_ROW_PLAY
	LD	C,1
	CALL	TCFG_ANSI_AT
	CALL	TCFG_COL_PRM
	LD	DE,MSGPAUSE
	CALL	PRTSTR
	CALL	TCFG_COL_RST
	RET
PRTPAUSEMSG0:
	LD	A,13
	CALL	PRTCHR
	CALL	TCFG_COL_PRM
	LD	DE,MSGPAUSE
	CALL	PRTSTR
	CALL	TCFG_COL_RST
	RET

PRTDELETEMSG:
	LD	A,(UI_ACTIVE)
	OR	A
	JR	Z,PRTDELETEMSG0
	CALL	UI_ENSURE_INIT
	LD	B,UI_ROW_PLAY
	CALL	UI_CLR_ROW
	LD	B,UI_ROW_PLAY
	LD	C,1
	CALL	TCFG_ANSI_AT
	CALL	TCFG_COL_PRM
	LD	DE,MSGDELING
	CALL	PRTSTR
	CALL	PLAYLIST_PRINT_SELECTED_NAME
	CALL	TCFG_COL_RST
	RET
PRTDELETEMSG0:
	LD	A,13
	CALL	PRTCHR
	CALL	TCFG_COL_PRM
	LD	DE,MSGDELING
	CALL	PRTSTR
	CALL	PLAYLIST_PRINT_SELECTED_NAME
	CALL	TCFG_COL_RST
	RET

UI_SETUP:
	XOR	A
	LD	(UI_ACTIVE),A
	LD	(UI_INIT),A
	LD	A,(ALLMD)
	OR	A
	RET	Z
	LD	A,(cfg_term)
	OR	A
	JR	NZ,UI_SETUP1
	LD	A,(cfg_flags)
	AND	CFGF_ANSI
	RET	Z

UI_SETUP1:
	LD	A,$FF
	LD	(UI_ACTIVE),A
	RET

UI_ENSURE_INIT:
	LD	A,(UI_ACTIVE)
	OR	A
	RET	Z
	LD	A,(UI_INIT)
	OR	A
	RET	NZ
	CALL	TCFG_CLRHOME
	CALL	TCFG_COL_HDR
	LD	B,UI_ROW_BANNER
	LD	C,1
	CALL	TCFG_ANSI_AT
	LD	DE,MSGBAN
	CALL	PRTSTR
	CALL	TCFG_COL_PRM
	LD	B,UI_ROW_MODE
	LD	C,1
	CALL	TCFG_ANSI_AT
	LD	DE,MSGPLFULL
	CALL	PRTSTR
	CALL	TCFG_COL_RST
	LD	A,$FF
	LD	(UI_INIT),A
	RET

UI_CLR_ROW:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	C,1
	CALL	TCFG_ANSI_AT
	CALL	TCFG_EL2
	LD	C,1
	CALL	TCFG_ANSI_AT
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

TCFG_EL2:
	PUSH	AF
	LD	A,(cfg_term)
	OR	A
	JR	NZ,TCFG_EL21
	LD	A,(cfg_flags)
	AND	CFGF_ANSI
	JR	Z,TCFG_EL20
TCFG_EL21:
	LD	DE,TCFG_SEQ_EL2
	CALL	PRTSTR
TCFG_EL20:
	POP	AF
	RET

UI_CLEAR_PLAYLIST:
	PUSH	AF
	PUSH	BC
	LD	A,UI_ROW_PLLIST
	LD	B,A
UI_CLEAR_PLAYLIST1:
	LD	A,(cfg_rows)
	CP	B
	JR	C,UI_CLEAR_PLAYLIST2
	CALL	UI_CLR_ROW
	INC	B
	JR	UI_CLEAR_PLAYLIST1
UI_CLEAR_PLAYLIST2:
	POP	BC
	POP	AF
	RET

UI_CALC_COLS:
	LD	A,(cfg_cols)
	LD	B,0
UI_CALC_COLS1:
	CP	16			; tile width: 1 marker+8 name+1 dot+3 ext+3 gap
	JR	C,UI_CALC_COLS2
	SUB	16
	INC	B
	JR	UI_CALC_COLS1
UI_CALC_COLS2:
	LD	A,B
	OR	A
	JR	NZ,UI_CALC_COLS3
	INC	A
UI_CALC_COLS3:
	LD	(UI_PLCOLS),A
	RET

UI_EXIT_TO_PROMPT:
	LD	A,(UI_ACTIVE)
	OR	A
	RET	Z
	CALL	UI_CALC_COLS
	LD	A,(PLCNT)
	OR	A
	JR	NZ,UI_EXIT_TO_PROMPT1
	LD	A,UI_ROW_PLLIST + 1
	JR	UI_EXIT_TO_PROMPT4
UI_EXIT_TO_PROMPT1:
	LD	E,A			; E = remaining entries
	LD	A,(UI_PLCOLS)
	LD	D,A			; D = entries per row
	LD	B,0			; B = rows used
UI_EXIT_TO_PROMPT2:
	INC	B
	LD	A,E
	SUB	D
	JR	C,UI_EXIT_TO_PROMPT3
	LD	E,A
	JR	UI_EXIT_TO_PROMPT2
UI_EXIT_TO_PROMPT3:
	LD	A,UI_ROW_PLLIST
	ADD	A,B			; last playlist row
	INC	A			; one blank line below playlist
	INC	A			; looping status line
	INC	A			; one blank line below looping status
UI_EXIT_TO_PROMPT4:
	LD	D,A			; D = target row
	LD	A,(cfg_rows)
	CP	D
	JR	NC,UI_EXIT_TO_PROMPT5
	LD	D,A			; clamp to visible screen
UI_EXIT_TO_PROMPT5:
	LD	B,D
	LD	C,1
	CALL	TCFG_ANSI_AT
	CALL	TCFG_COL_RST
	RET

UI_CLEAR_TRACK_BLOCK:
	LD	A,(UI_ACTIVE)
	OR	A
	RET	Z
	CALL	UI_ENSURE_INIT
	LD	B,UI_ROW_INFO
UI_CLEAR_TRACK_BLOCK1:
	CALL	UI_CLR_ROW
	LD	A,B
	CP	UI_ROW_PLAY
	RET	Z
	INC	B
	JR	UI_CLEAR_TRACK_BLOCK1

UI_UPDATE_MARKER_DELTA:
	LD	A,(UI_ACTIVE)
	OR	A
	RET	Z
	LD	A,(PLIDXOLD)
	LD	D,' '
	CALL	UI_DRAW_PL_ENTRY
	LD	A,(PLIDX)
	LD	D,'>'
	CALL	UI_DRAW_PL_ENTRY
	RET

UI_DRAW_PL_ENTRY:
	; IN: A = playlist index, D = marker char (' ' or '>')
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	A,(UI_ACTIVE)
	OR	A
	JR	Z,UI_DRAW_PL_ENTRYX
	LD	A,D
	LD	(UI_MARK),A
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	(UI_IDXTMP),A
	CALL	UI_CALC_COLS
	LD	A,(UI_IDXTMP)
	LD	E,A			; remainder/index working value
	XOR	A
	LD	D,A			; row offset
	LD	A,(UI_PLCOLS)
	LD	L,A			; entries per row
UI_DRAW_PL_ENTRY1:
	LD	A,E
	CP	L
	JR	C,UI_DRAW_PL_ENTRY2
	SUB	L
	LD	E,A
	INC	D
	JR	UI_DRAW_PL_ENTRY1
UI_DRAW_PL_ENTRY2:
	LD	A,UI_ROW_PLLIST
	ADD	A,D
	LD	B,A			; row
	LD	A,(cfg_rows)
	CP	B
	JR	C,UI_DRAW_PL_ENTRYX
	LD	A,E
	ADD	A,A
	ADD	A,A
	ADD	A,A
	ADD	A,A			; *16
	INC	A			; column origin is 1
	LD	C,A
	CALL	TCFG_ANSI_AT
	LD	A,(UI_MARK)
	CP	'>'
	JR	NZ,UI_DRAW_PL_ENTRY3
	CALL	TCFG_COL_PRM
UI_DRAW_PL_ENTRY3:
	LD	A,(UI_MARK)
	CALL	PRTCHR
	LD	A,(UI_IDXTMP)
	CALL	PLAYLIST_PTR_FROM_A
	INC	HL
	LD	B,8
UI_DRAW_PL_ENTRY4:
	LD	A,(HL)
	INC	HL
	CALL	PRTCHR
	DJNZ	UI_DRAW_PL_ENTRY4
	LD	A,'.'
	CALL	PRTCHR
	LD	B,3
UI_DRAW_PL_ENTRY5:
	LD	A,(HL)
	INC	HL
	CALL	PRTCHR
	DJNZ	UI_DRAW_PL_ENTRY5
	LD	B,3
UI_DRAW_PL_ENTRY6:
	LD	A,' '
	CALL	PRTCHR
	DJNZ	UI_DRAW_PL_ENTRY6
	LD	A,(UI_MARK)
	CP	'>'
	JR	NZ,UI_DRAW_PL_ENTRYX
	CALL	TCFG_COL_RST
UI_DRAW_PL_ENTRYX:
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

#include "playlist_core.inc"

SINGLE_FCBSAVE:
	LD	A,(SNGFCBINI)
	OR	A
	RET	NZ
	LD	HL,FCB
	LD	DE,SNGFCBSAV
	LD	BC,36
	LDIR
	LD	A,$FF
	LD	(SNGFCBINI),A
	RET
;
SINGLE_FCBRESTORE:
	LD	A,(SNGFCBINI)
	OR	A
	RET	Z
	LD	HL,SNGFCBSAV
	LD	DE,FCB
	LD	BC,36
	LDIR
	RET
;
;
; Enumerate HBIOS sound devices to detect which PSG port sets exist.
; Returns A=mask, Z if any recognized ports were found.
; Mask bits:
;   bit0: MSX (A0/A1/A2)
;   bit1: COLECO (50/51/52)
;   bit2: RC/EB (D8/D0/D8)
;   bit3: RC/MF (D1/D0/D0)
;
#include "meta_print.inc"

#include "vgm_hw.inc"
#include "ts_runtime.inc"
;
; Identify active BIOS.  RomWBW HBIOS=1, UNA UBIOS=2, else 0
;
IDBIO:
;
	; Check for UNA (UBIOS)
	LD	A,($FFFD)	; fixed location of UNA API vector
	CP	$C3		; jp instruction?
	JR	NZ,IDBIO1	; if not, not UNA
	LD	HL,($FFFE)	; get jp address
	LD	A,(HL)		; get byte at target address
	CP	$FD		; first byte of UNA push ix instruction
	JR	NZ,IDBIO1	; if not, not UNA
	INC	HL		; point to next byte
	LD	A,(HL)		; get next byte
	CP	$E5		; second byte of UNA push ix instruction
	JR	NZ,IDBIO1	; if not, not UNA, check others
;
	LD	BC,$04FA	; UNA: get BIOS date and version
	RST	08		; DE := ver, HL := date
;
	LD	A,2		; UNA BIOS id = 2
	RET			; and done
;
IDBIO1:
	; Check for RomWBW (HBIOS)
	LD	HL,($FFFC)	; HL := HBIOS ident location
	LD	A,'W'		; First byte of ident
	CP	(HL)		; Compare
	JR	NZ,IDBIO2	; Not HBIOS
	INC	HL		; Next byte of ident
	LD	A,~'W'		; Second byte of ident
	CP	(HL)		; Compare
	JR	NZ,IDBIO2	; Not HBIOS
;
	LD	B,BF_SYSVER	; HBIOS: VER function
	LD	C,0		; required reserved value
	RST	08		; DE := version, L := platform id
;
	LD	A,1		; HBIOS BIOS id = 1
	RET			; and done
;
IDBIO2:
	; No idea what this is
	XOR	A		; Setup return value of 0
	RET			; and done
;
SLOWIO:
#IF (CPUFAMZ180)
	LD A,(Z180)	; Z180 base I/O port
	CP $FF		; Check for no value
	RET Z		; Bail out if no value
	ADD A,$32	; Apply offset of DCNTL register
	LD C,A		; And put it in C
	LD B,0		; MSB for 16-bit I/O
	IN A,(C)	; Get current value
	LD (DCSAV),A	; Save it to restore later
	OR %00110000	; Force slow operation (I/O W/S=3)
	OUT (C),A	; And update DCNTL
#ENDIF
#IF (SBCV2004)
	LD A,8		; sbc-v2-004 change to
	OUT (112),A	; half clock speed
#ENDIF
	RET
;
;	RESTORE I/O SPEED FOR FAST CPU'S
;
NORMIO:
#IF (CPUFAMZ180)
	LD A,(Z180)	; Z180 base I/O port
	CP $FF		; Check for no value
	RET Z		; Bail out if no value
	ADD A,$32	; Apply offset of DCNTL register
	LD C,A		; And put it in C
	LD B,0		; MSB for 16-bit I/O
	LD A,(DCSAV)	; Get saved DCNTL value
	OUT (C),A	; And restore it
#ENDIF
#IF (SBCV2004)
	LD A,0		; sbc-v2-004 change to
	OUT (112),A	; normal clock speed
#ENDIF
	RET
;
ERRBIO:	; Invalid BIOS or version
	LD	DE,MSGBIO
	JR	ERR
;
ERRPLT:	; Invalid BIOS or version
	LD	DE,MSGPLT
	JR	ERR
;
ERRHW:	; Hardware error, sound chip not detected
	LD	DE,MSGHW
	JR	ERR
;
ERRCMD:	; Command error, display usage info
	CALL	CRLF			; blank line after banner
	LD	DE,MSGUSE
	JR	ERR1
;
ERRNAM:	; Missing or invalid filename parameter
	LD	DE,MSGNAM
	JR	ERR
;
ERRFIL:	; Error opening sound file
	LD	DE,MSGFIL
	JR	ERR
;
ERRALL:	; -list selected but no supported files found
	LD	DE,MSGALL
	JR	ERR
;
ERRSIZ:	; Sound file is too large for memory
	LD	DE,MSGSIZ
	JR	ERR

ERRVGMTR:	; VGM file is truncated versus header EOF size
	LD	DE,MSGVGMTR
	JR	ERR
;
ERRVGMINIT:	; MMU init / app-bank discovery failed (old HBIOS, no banks, etc.)
	LD	DE,MSGVGMINIT
	JR	ERR
;
ERRVGMAX:	; Banked image larger than app-bank storage
	LD	DE,MSGVGMAX
	JR	ERR
;
; VGM MMU read failures (distinct messages for hardware diagnosis)
ERRVGMRD_PRI:	; LOAD_WIN0 at end of banked load (prime vgmdata)
	LD	DE,MSGVGMRD_PRI
	JR	ERR
ERRVGMRD_HDR:	; LOAD_WIN0 inside VGM_MMU_SYNC_HDR (header reload)
	LD	DE,MSGVGMRD_HDR
	JR	ERR
ERRVGMRD_STR:	; VGM_RD_NEXT_EX / command stream read
	LD	DE,MSGVGMRD_STR
	JR	ERR
;
ERRVGMVF:	; MMU readback after write did not match DMA buffer
	LD	DE,MSGVGMVF
	JR	ERR
;
ERR:	; print error string and return error signal
	LD	A,(ALLMD)
	OR	A
	JR	Z,ERR0
	CALL	PLAYLIST_ERR_STATUS	; append error beside Playing... and continue playlist
	LD	A,$FF
	LD	(SKIPREQ),A
	JP	EXIT
ERR0:
	CALL	CRLF2		; print newline
;
ERR1:	; without the leading crlf
	CALL	PRTSTR		; print error string
;
ERR2:	; without the string
	CALL	CRLF		; print newline
	JP	0		; fast exit

; In playlist mode, append current-track error info on the Playing line.
; IN: DE -> error message string
PLAYLIST_ERR_STATUS:
	PUSH	AF
	PUSH	BC
	PUSH	HL
	PUSH	DE			; save error string pointer
	CALL	PRTPLAYMSG
	LD	A,' '
	CALL	PRTCHR
	LD	A,'['
	CALL	PRTCHR
	CALL	PRTFCB83
	LD	A,']'
	CALL	PRTCHR
	LD	A,' '
	CALL	PRTCHR
	POP	DE			; restore error string pointer
	CALL	PRTSTR
	POP	HL
	POP	BC
	POP	AF
	RET
;
CFGTBL:	;			PLT		RSEL			RDAT			RIN			Z180		ACR		ACRVAL
;	; DESC
	.DB	$01,	PSG_SCG_RSEL,		PSG_SCG_RDAT,		PSG_SCG_RIN,	Z180_NONE,	ACR_SCG,	ACRVAL_NONE	; SBC W/ SCG
	.DW	HWSTR_SCG
;
	.DB	$04,	PSG_N8_RSEL,		PSG_N8_RDAT,		PSG_N8_RIN,	Z180_N8,	ACR_NONE,	ACRVAL_NONE	; N8 W/ ONBOARD PSG
	.DW	HWSTR_N8
;
	.DB	$05,	PSG_SCG_RSEL,		PSG_SCG_RDAT,		PSG_SCG_RIN,	Z180_N8,	ACR_SCG,	ACRVAL_NONE	; MK4 W/ SCG
	.DW	HWSTR_SCG
;
	.DB	$07,	PSG_RCEB_RSEL,		PSG_RCEB_RDAT,		PSG_RCEB_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; RCZ80 W/ RC SOUND MODULE (EB)
	.DW	HWSTR_RCEB
;
	.DB	$07,	PSG_MSX_RSEL,		PSG_MSX_RDAT,		PSG_MSX_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; RCZ80 W/ RC SOUND MODULE (MSX)
	.DW	HWSTR_RCMSX
;
	.DB	$07,	PSG_RCMF_RSEL,		PSG_RCMF_RDAT,		PSG_RCMF_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; RCZ80 W/ RC SOUND MODULE (MF)
	.DW	HWSTR_RCMF
;
	.DB	$07,	PSG_LINC_RSEL,		PSG_LINC_RDAT,		PSG_LINC_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; RCZ80 W/ LINC SOUND MODULE
	.DW	HWSTR_LINC
;
	.DB	$07,	PSG_COLECO_RSEL,	PSG_COLECO_RDAT,	PSG_COLECO_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; RCZ80/SC720 W/ RC SOUND MODULE (COLECO)
	.DW	HWSTR_COLECO
;
	.DB	$08,	PSG_RCEB_Z180_RSEL,	PSG_RCEB_Z180_RDAT,	PSG_RCEB_Z180_RIN,	Z180_RCZ180,	ACR_NONE,	ACRVAL_NONE	; RCZ180 W/ RC SOUND MODULE (EB)
	.DW	HWSTR_RCEB
;
	.DB	$08,	PSG_MSX_RSEL,		PSG_MSX_RDAT,		PSG_MSX_RIN,	Z180_RCZ180,	ACR_NONE,	ACRVAL_NONE	; RCZ180 W/ RC SOUND MODULE (MSX)
	.DW	HWSTR_RCMSX
;
	.DB	$08,	PSG_RCMF_Z180_RSEL,	PSG_RCMF_Z180_RDAT,	PSG_RCMF_Z180_RIN,	Z180_RCZ180,	ACR_NONE,	ACRVAL_NONE	; RCZ180 W/ RC SOUND MODULE (MF)
	.DW	HWSTR_RCMF
;
	.DB	$08,	PSG_LINC_RSEL,		PSG_LINC_RDAT,		PSG_LINC_RIN,	Z180_RCZ180,	ACR_NONE,	ACRVAL_NONE	; RCZ180 W/ LINC SOUND MODULE
	.DW	HWSTR_LINC
;
	.DB	$08,	PSG_COLECO_RSEL,	PSG_COLECO_RDAT,	PSG_COLECO_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; RCZ180 W/ RC SOUND MODULE (COLECO)
	.DW	HWSTR_COLECO
;
	.DB	$09,	PSG_RCEB_RSEL,		PSG_RCEB_RDAT,		PSG_RCEB_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; EZZ80 W/ RC SOUND MODULE (EB)
	.DW	HWSTR_RCEB
;
	.DB	$09,	PSG_MSX_RSEL,		PSG_MSX_RDAT,		PSG_MSX_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; EZZ80 W/ RC SOUND MODULE (MSX)
	.DW	HWSTR_RCMSX
;
	.DB	$09,	PSG_RCMF_RSEL,		PSG_RCMF_RDAT,		PSG_RCMF_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; EZZ80 W/ RC SOUND MODULE (MF)
	.DW	HWSTR_RCMF
;
	.DB	$09,	PSG_LINC_RSEL,		PSG_LINC_RDAT,		PSG_LINC_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; EZZ80 W/ LINC SOUND MODULE
	.DW	HWSTR_LINC
;
	.DB	$09,	PSG_COLECO_RSEL,	PSG_COLECO_RDAT,	PSG_COLECO_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; EZZ80 W/ RC SOUND MODULE (COLECO)
	.DW	HWSTR_COLECO
;
	.DB	$0A,	PSG_RCEB_Z180_RSEL,	PSG_RCEB_Z180_RDAT,	PSG_RCEB_Z180_RIN,	Z180_RCZ180,	ACR_NONE,	ACRVAL_NONE	; SCZ180 W/ RC SOUND MODULE (EB)
	.DW	HWSTR_RCEB
;
	.DB	$0A,	PSG_MSX_RSEL,		PSG_MSX_RDAT,		PSG_MSX_RIN,	Z180_RCZ180,	ACR_NONE,	ACRVAL_NONE	; SCZ180 W/ RC SOUND MODULE (MS6)
	.DW	HWSTR_RCMSX
;
	.DB	$0A,	PSG_RCMF_Z180_RSEL,	PSG_RCMF_Z180_RDAT,	PSG_RCMF_Z180_RIN,	Z180_RCZ180,	ACR_NONE,	ACRVAL_NONE	; SCZ180 W/ RC SOUND MODULE (MF)
	.DW	HWSTR_RCMF
;
	.DB	$0A,	PSG_LINC_RSEL,		PSG_LINC_RDAT,		PSG_LINC_RIN,	Z180_RCZ180,	ACR_NONE,	ACRVAL_NONE	; SCZ180 W/ LINC SOUND MODULE
	.DW	HWSTR_LINC
;
	.DB	$0A,	PSG_COLECO_RSEL,	PSG_COLECO_RDAT,	PSG_COLECO_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; SCZ80 W/ RC SOUND MODULE (COLECO)
	.DW	HWSTR_COLECO
;
	.DB	$0B,	PSG_RCEB_RSEL,		PSG_RCEB_RDAT,		PSG_RCEB_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; RCZ280 W/ RC SOUND MODULE (EB)
	.DW	HWSTR_RCEB
;
	.DB	$0B,	PSG_MSX_RSEL,		PSG_MSX_RDAT,		PSG_MSX_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; RCZ280 W/ RC SOUND MODULE (MSX)
	.DW	HWSTR_RCMSX
;
	.DB	$0B,	PSG_RCMF_RSEL,		PSG_RCMF_RDAT,		PSG_RCMF_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; RCZ280 W/ RC SOUND MODULE (MF)
	.DW	HWSTR_RCMF
;
	.DB	$0B,	PSG_LINC_RSEL,		PSG_LINC_RDAT,		PSG_LINC_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; RCZ280 W/ LINC SOUND MODULE
	.DW	HWSTR_LINC
;
	.DB	$0B,	PSG_COLECO_RSEL,	PSG_COLECO_RDAT,	PSG_COLECO_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; RCZ280 W/ RC SOUND MODULE (COLECO)
	.DW	HWSTR_COLECO
;
	.DB	13,	PSG_MBC_RSEL,		PSG_MBC_RDAT,		PSG_MBC_RIN,	Z180_NONE,	ACR_MBC,	ACRVAL_ENABLE	; MBC
	.DW	HWSTR_MBC
;
	.DB	17,	PSG_DUO_RSEL,		PSG_DUO_RDAT,		PSG_DUO_RIN,	Z180_NONE,	ACR_DUO,	ACRVAL_ENABLE	; DUODYNE
	.DW	HWSTR_DUO
;
	.DB	18,	PSG_MSX_RSEL,		PSG_MSX_RDAT,		PSG_MSX_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; HEATH H8
	.DW	HWSTR_HEATH
;
	.DB	22,	PSG_NABU_RSEL,		PSG_NABU_RDAT,		PSG_NABU_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; NABU
	.DW	HWSTR_NABU
;
	.DB	27,	PSG_RCEB_RSEL,		PSG_RCEB_RDAT,		PSG_RCEB_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; RC2014 W/ RC SOUND MODULE (EB)
	.DW	HWSTR_RCEB
;
	.DB	27,	PSG_MSX_RSEL,		PSG_MSX_RDAT,		PSG_MSX_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; RC2014 W/ RC SOUND MODULE (MSX)
	.DW	HWSTR_RCMSX
;
	.DB	27,	PSG_RCMF_RSEL,		PSG_RCMF_RDAT,		PSG_RCMF_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; RC2014 W/ RC SOUND MODULE (MF)
	.DW	HWSTR_RCMF
;
	.DB	27,	PSG_COLECO_RSEL,	PSG_COLECO_RDAT,	PSG_COLECO_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; RC2014 W/ RC SOUND MODULE (COLECO)
	.DW	HWSTR_COLECO
;
CFGSIZ	.EQU	9			; 7 DB fields + 1 DW description pointer
;
	.DB	$FF					; END OF TABLE MARKER
;
; The following are table entries (like above), but not part of auto
; detection searching.  The command-line options select them.
;
MSXPORTS:
	.DB	$FF,	PSG_MSX_RSEL,		PSG_MSX_RDAT,		ACR_NONE,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; GENERIC MSX
	.DW	HWSTR_MSX
;
RCPORTS:
	.DB	$FF,	PSG_RCEB_RSEL,		PSG_RCEB_RDAT,		ACR_NONE,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; GENERIC RC
	.DW	HWSTR_RC
;
COLECOPORTS:
	.DB	$FF,	PSG_COLECO_RSEL,	PSG_COLECO_RDAT,	PSG_COLECO_RIN,	Z180_NONE,	ACR_NONE,	ACRVAL_NONE	; GENERIC COLECO AY PORTS
	.DW	HWSTR_COLECO
;
CFG:		; ACTIVE CONFIG VALUES (FROM SELECTED CFGTBL ENTRY)
PLT		.DB	0	; RomWBW HBIOS platform id
PORTS:
RSEL		.DB	0	; Register selection port
RDAT		.DB	0	; Register data port
RIN		.DB	0	; Register input port
Z180		.DB	0	; Z180 base I/O port
ACR		.DB	0	; Aux Ctrl Reg I/O port (ACR)
ACRVAL		.DB	0	; ACR sound enable value
DESC		.DW	0	; Hardware description string adr
;
CURPLT		.DB	0	; Current platform id reported by HBIOS
QDLY		.DW	0	; quark delay factor
QDLY0		.DW	0	; base quark delay factor (reset before each song)
WMOD		.DB	0	; delay mode, non-zero to use timer
DCSAV		.DB	0	; for saving original Z180 DCNTL value
CCRSAV		.DB	0	; for saving original Z180 CCR value
CMRSAV		.DB	0	; for saving original Z180 CMR value
;
DMA		.DW	0	; Working DMA
FILTYP		.DB	0	; Sound file type (TYPPT2, TYPPT3, TYPMYM)
LOADBYTES	.DW	0	; bytes loaded (padded to 128-byte CP/M records)
;
; TurboSound PT3 (packed dual-module) state
TSFLAG		.DB	0	; non-zero if a TS footer was detected
TS_DUALHW	.DB	0	; non-zero if two distinct AY chips are present
TSSET1		.DB	0	; SETUP byte snapshot (instance 1)
TSSET2		.DB	0	; SETUP byte snapshot (instance 2)
TS_OFF2		.DW	0	; module #2 offset from start of file
TS_LEN2		.DW	0	; module #2 length
TS_PORTS1	.DW	0	; chip 1 ports (RDAT:RSEL)
TS_PORTS2	.DW	0	; chip 2 ports (RDAT:RSEL)
TS_CHIP1_PORTS	.DW	0	; chip 1 ports frozen at first setup (PORTS changes during TS play)
TS_DESC1	.DW	0	; chip 1 port description string
TS_DESC2	.DW	0	; chip 2 port description string
INFOLINE	.DB	0	; non-zero if a hardware/mode line was printed
VGMFLAG	.DB	0	; non-zero while VGM is the active player
VGMMMUMD	.DB	0	; non-zero when VGM MMU banking is active
VGMCURBNK	.DB	0	; current execution bank id
VGMAPPBNK0	.DB	0	; first application bank assigned by HBIOS
VGMAPPBNKC	.DB	0	; number of contiguous application banks
VGMTMPBNK	.DB	0	; temp selected bank for copy/read operations
VGMLOADSZ	.DB	0,0,0	; loaded VGM size (24-bit, record-padded)
VGMWBASE	.DB	0,0,0	; stream: logical base of VGMWINBUF; verify uses own math
VGMWINVAL	.DB	0	; zero=vgmdata header invalid, non-zero=primed
VGMRDERR	.DB	0	; non-zero: VGM_MMU_READ_AT failed in stream reader
VGMVRBAS	.DB	0,0,0	; verify: record base; stream read: temp align scratch
VGMRDLOW	.DB	0	; low offset byte scratch for read path
VGMTMPADR	.DW	0	; in-bank address scratch
VGMWSTRM	.DB	0	; non-zero: VGMWINBUF valid for VGMWBASE logical block
VGMTMPIDX	.DB	0	; byte index 0..127 in current stream window
VGMWINBUF	.FILL	128,0	; MMU stream read: 128-byte copy from app banks
VGMEXP		.DB	0,0,0	; loader temp: expected VGM size from header (24-bit LE)
VGMCAP		.DB	0,0,0	; loader temp: MMU app-bank capacity (24-bit LE)
vgmpos		.DB	0,0,0	; byte offset into VGM data stream (24-bit)
vgmdly		.DW	0	; remaining sample-delay count
vgmfdly	.DB	12	; copy of vgmfdly0 for display / parity with older paths
vgmfdly0	.DB	12	; inner DJNZ count per outer round (VGM_APPLY_DELAY)
vgmfdlo	.DB	1	; outer rounds per VGM sample (>=1; product with vgmfdly0 sets tempo)
vgmfdcyc	.DB	0	; legacy (unused)
VGMTMPKHZ	.DW	0	; SYSGET/CPUINFO KHz (saved for VGM delay calibration)
VGMTMPMHZ	.DB	0	; SYSGET/CPUINFO integer MHz index for VGMCLKTBL
VGMSAMPACC	.DB	0,0,0	; VGM sample timeline for key poll (LE, mod ~0.1s)
VGMCHIPFLG	.DB	0	; detected VGM chips from header clocks (bitmask)
VGMDUALFLG	.DB	0	; detected VGM dual-chip markers (bitmask)
VGMPRNSEP	.DB	0	; non-zero once first VGM chip token was printed
HEAPENDB	.DB	$C0	; runtime load ceiling page (updated at startup to BDOS-1)
YM2151MAP	.DB	0	; YM2151 port map: 0=DE/DF (0xFF-0x20), 1=FE/FF
YM2151SELV	.DB	0DEH	; YM2151 register-select port (runtime)
YM2151DATV	.DB	0DFH	; YM2151 data port (runtime)
YM2151SEL2V	.DB	0	; secondary YM2151 register-select port (runtime)
YM2151DAT2V	.DB	0	; secondary YM2151 data port (runtime)
;
; Context save/restore pointers
CTX_VPTR	.DW	0
CTX_PPTR	.DW	0
;
TMP		.DB	0	; work around use of undocumented Z80

HBIOSMD		.DB	0	; NON-ZERO IF USING HBIOS SOUND DRIVER, ZERO OTHERWISE
DELAYMD		.DB	0	; FORCE DELAY MODE IF TRUE (NON-ZERO)
OCTAVEADJ	.DB	0	; AMOUNT TO ADJUST OCTAVE UP OR DOWN
CONFIGMD	.DB	0	; NON-ZERO TO ENTER TERM.CFG EDIT MODE
CREDMD		.DB	0	; NON-ZERO TO PRINT CREDITS AND EXIT
ALLMD		.DB	0	; NON-ZERO TO ENUMERATE/PLAY ALL SUPPORTED FILES
LOOPTRKMD	.DB	0	; NON-ZERO TO LOOP CURRENT TRACK
LOOPPLMD	.DB	0	; NON-ZERO TO LOOP WHOLE PLAYLIST
PAUSEMD		.DB	0	; NON-ZERO WHILE PLAYBACK IS PAUSED
DELCNT		.DB	0	; CONSECUTIVE DELETE KEY PRESS COUNTER
DELPAUSAV	.DB	0	; SAVED PAUSE STATE FOR DELETE CONFIRM CANCEL
DELIDX		.DB	0	; SAVED INDEX OF ENTRY SELECTED FOR DELETE
STOPREQ		.DB	0	; NON-ZERO IF USER ABORTED WITH KEYPRESS
SKIPREQ		.DB	0	; NON-ZERO IF USER REQUESTED SKIP TO NEXT TRACK
PREVREQ		.DB	0	; NON-ZERO IF USER REQUESTED PREVIOUS TRACK
NAVREQ		.DB	0	; NON-ZERO IF USER REQUESTED MATRIX NAV TRACK CHANGE
DELREQ		.DB	0	; NON-ZERO IF NAVREQ WAS TRIGGERED BY DELETE REFRESH
PLSHOWN		.DB	0	; NON-ZERO AFTER INITIAL PLAYLIST RENDER IN -list MODE
UI_ACTIVE	.DB	0	; NON-ZERO FOR ANSI FIXED-SCREEN PLAYLIST UI
UI_INIT		.DB	0	; NON-ZERO AFTER UI STATIC SECTIONS DRAWN
UI_PLCOLS	.DB	1	; PLAYLIST CELLS PER ROW (16-CHAR CELLS)
UI_ROWCUR	.DB	0	; WORK: CURRENT PLAYLIST ROW
UI_COLCUR	.DB	0	; WORK: CURRENT PLAYLIST COLUMN
UI_COLUSED	.DB	0	; WORK: COLUMNS USED IN CURRENT ROW
UI_MARK		.DB	0	; WORK: ENTRY MARKER CHAR
UI_IDXTMP	.DB	0	; WORK: PLAYLIST INDEX FOR DELTA TILE DRAW
TCFG_PREV_COLS	.DB	0	; WORK: PRIOR WIDTH FOR TUNE SIZE PREVIEW REDRAW
TCFG_PREV_ROWS	.DB	0	; WORK: PRIOR HEIGHT FOR TUNE SIZE PREVIEW REDRAW
PLM_KEY		.DB	0	; WORK: WASD KEY FOR PLAYLIST MATRIX MOVE
PLM_ROW		.DB	0	; WORK: CURRENT TARGET ROW FOR WASD MOVE
PLM_COL		.DB	0	; WORK: CURRENT TARGET COLUMN FOR WASD MOVE
PLM_ROWS		.DB	0	; WORK: TOTAL PLAYLIST ROWS
PLM_ROWST	.DB	0	; WORK: CURRENT ROW START INDEX
PLM_ROWLEN	.DB	0	; WORK: CURRENT ROW LENGTH
PLCNT		.DB	0	; NUMBER OF FILES IN PLAYLIST
PLCNT0		.DB	0	; SNAPSHOT OF PLAYLIST COUNT FOR LOOP RESTART
PLIDX		.DB	0	; CURRENT PLAYLIST INDEX
PLIDXOLD	.DB	0	; PREVIOUS PLAYLIST INDEX FOR DELTA MARKER UPDATE
PLAYLIST	.FILL	(PLMAX * 12),0	; ARRAY OF FCB ENTRIES (DRIVE+11)
PLAYLIST0	.FILL	(PLMAX * 12),0	; SNAPSHOT OF ORIGINAL PLAYLIST ENTRIES
SNGFCBINI	.DB	0	; NON-ZERO WHEN SINGLE-FILE FCB SNAPSHOT IS INITIALIZED
SNGFCBSAV	.FILL	36,0		; SAVED STARTUP FCB FOR SINGLE-FILE LOOP RESTART
PLSRCHBUF	.FILL	128,0		; DMA BUFFER FOR DIR SEARCH
METATITLE	.EQU	PLSRCHBUF
METAARTIST	.EQU	PLSRCHBUF+$20
PLSRCHFCB	.FILL	36,0		; SEARCH FCB FOR PLAYLIST ENUM PATTERN
CLIBUF		.FILL	129,0		; NUL-TERMINATED COPY OF COMMAND TAIL
CLITOK		.FILL	13,0		; WORK BUFFER FOR FCB/TAIL TOKEN RECONCILIATION

USEPORTS	.DB	0	; AUDIO CHIP PORT SELECTION MODE
;
; VGM hardware port constants (fixed addresses)
; Primary AY uses dynamic TS_PORTS1; secondary AY uses TS_PORTS2
OPL3ADDR1	.EQU	OPL3_BANK1_ADDR	; OPL3 bank 1 register select
OPL3DATA1	.EQU	OPL3_BANK1_DATA	; OPL3 bank 1 data
OPL3ADDR2	.EQU	OPL3_BANK2_ADDR	; OPL3 bank 2 register select
OPL3DATA2	.EQU	OPL3_BANK2_DATA	; OPL3 bank 2 data
PSGREG		.EQU	SN76489_PRIMARY	; SN76489 PSG (primary chip, RCBUS SNMODE_RC)
PSG2REG		.EQU	SN76489_SECONDARY	; SN76489 PSG (secondary chip, RCBUS SNMODE_RC)
YM2151SEL	.EQU	YM2151_PRIMARY_SEL	; YM2151 register select (primary, board mapped at 0xFF-0x20)
YM2151DAT	.EQU	YM2151_PRIMARY_DAT	; YM2151 data write (primary)
YM2151SEL2	.EQU	YM2151_SECONDARY_SEL	; YM2151 register select (secondary, undefined on RCBUS)
YM2151DAT2	.EQU	YM2151_SECONDARY_DAT	; YM2151 data write (secondary, undefined on RCBUS)

MSGBAN:
	.DB	"VibeTune Player for RomWBW v0.1", VTBANREL, ", 29-May-2026",0
MSGCPUMHZ	.DB	"CPU Speed: ",0
MSGMHZ		.DB	" MHz",0
MSGVGMCOM	.DB	", ",0
MSGVGMUNK	.DB	"VGM hardware",0
MSGVGMOPL2	.DB	"YM3812/OPL2",0
MSGVGMOPL3	.DB	"YMF262/OPL3",0
MSGVGMAY	.DB	"AY-3-8910/YM2149",0
MSGVGMPSG	.DB	"SN76489",0
MSGVGMPSG2	.DB	"2xSN76489",0
MSGVGM2151	.DB	"YM2151/OPM",0
MSGUSE		.DB	"Usage: VTUNE <filename>.[PT2|PT3|MYM|VGM] [-msx|-rc|-coleco] [-delay]"
			.DB	" [--hbios] [+tn|-tn] [-list] [-loop] [-config] [-credits]",0
MSGCRED		.DB	"Copyright (C) 2026, Wayne Warthen, GNU GPL v3",13,10
			.DB	"PTxPlayer Copyright (C) 2004-2007 S.V.Bulba",13,10
			.DB	"MYMPlay by Marq/Lieves!Tuore",13,10
			.DB	"VGMPLAY code by J.B. Langston, Marco Maccaferri, Ed Brindley",13,10
			.DB	"TurboSound support, VGM integration and factorisation by Joao Miguel Duraes/fackie",0
MSGBIO		.DB	"Incompatible BIOS or version, "
			.DB	"HBIOS v", '0' + RMJ, ".", '0' + RMN, " required",0
MSGPLT		.DB	"Hardware error, system not supported!",0
MSGHW		.DB	"Hardware error, sound chip not detected!",0
MSGNAM		.DB	"Sound filename invalid (must be .PT2, .PT3, .MYM, or .VGM)",0
MSGFIL		.DB	"Sound file not found!",0
MSGALL		.DB	"No .PT2/.PT3/.MYM/.VGM files found in current directory!",0
MSGSIZ		.DB	"Sound file too large to load!",0
MSGVGMTR	.DB	"VGM file appears truncated/corrupt (header size > loaded size)",0
MSGVGMINIT	.DB	"VGM: app-bank setup failed (update RomWBW HBIOS or add APP banks)",0
MSGVGMAX	.DB	"VGM: exceeds RomWBW app-bank pool (BNKCPY APP slice), not total machine RAM.",13,10
			.DB	"  Fix: custom HBIOS config with more APP_BNKS or smaller RAM disk, then rebuild ROM.",0
MSGVGMRD_PRI	.DB	"VGM MMU: prime header failed (LOAD_WIN0 after load)",0
MSGVGMRD_HDR	.DB	"VGM MMU: header reload failed (LOAD_WIN0 in SYNC_HDR)",0
MSGVGMRD_STR	.DB	"VGM MMU: stream read failed (128B window / RD_NEXT)",0
MSGVGMVF	.DB	"VGM MMU load verify failed (readback mismatch)",0
MSGTSHB		.DB	"TurboSound PT3 not supported with --HBIOS",0
MSGTSHW		.DB	"TurboSound PT3 requires two AY cards at A0H/A1H and 50H/51H (readback at +2)",0
MSGTSDET	.DB	"TurboSound (2x AY-3-8910) file detected",0
MSGTSPRE	.DB	"Playing on ",0
MSGTSAND	.DB	" and ",0
MSGTSPST	.DB	" Ports",0
MSGHBIOS	.DB	"HBIOS sound driver",0
MSGTIM		.DB	", timer mode",0
MSGDLY		.DB	", delay mode",0
MSGPLFULL	.DB	"Keys: Esc=quit, (N)ext, (P)revious, WASD=navigate, (R)edraw (slow), (l/L)oop track/plist",0
MSGPLNONE	.DB	" (none)",0
MSGCURINF	.DB	"Current track:",0
MSGPLY		.DB	"Playing...",0
MSGPAUSE	.DB	"Paused - press spacebar to resume",0
MSGDELING	.DB	"Deleting ",0
MSGNEXT		.DB	" Next track",0
MSGPREV		.DB	" Previous track",0
MSGSKIP		.DB	" Skipping",0
MSGLOOP		.DB	" Looping from start",0
MSGLOOPSTAT	.DB	"Looping Status: ",0
MSGLOOPOFF	.DB	"Off",0
MSGLOOPTRK	.DB	"Track",0
MSGLOOPPLAY	.DB	"Playlist",0
MSGDELQ1	.DB	"Are you sure you want to delete ",0
MSGDELQ2	.DB	"? (Y/N)",0
MSGEND		.DB	" Done",0
MSGERR		.DB	"App Error", 0
MSGCFGMODE	.DB	"Configuration mode (-config)",0
MSGCFGFOUND	.DB	"Loaded existing TERM.CFG:",0
MSGCFGDEFAULT	.DB	"No TERM.CFG found, using built-in defaults:",0
MSGCFGSAVED	.DB	"Saved TERM.CFG",0
MSGCFGTERM	.DB	"  Term type: ",0
MSGCFGANSI	.DB	"  ANSI colour: ",0
MSGCFGSIZE	.DB	"  Size: ",0
MSGTERMMENU	.DB	"Term type? P=plain, V=VTxxx, A=ANSI",0
MSGTERMPROMPT	.DB	"Choice [Enter keeps ",0
MSGANSIPROMPT	.DB	"ANSI colour? Y/N [Enter keeps ",0
MSGPROMPTEND	.DB	"]: ",0
MSGTERMPLAIN	.DB	"plain",0
MSGTERMVT	.DB	"VTxxx",0
MSGTERMANSI	.DB	"ANSI",0
MSGYES		.DB	"yes",0
MSGNO		.DB	"no",0
MSGTUNETITLE	.DB	"Adjust visible limits until C, R, and X are just visible.",0
MSGTUNEKEYS	.DB	"Adjustment Keys: a/d for columns, w/s for rows (or arrow keys), Esc save+quit",0
MSGTUNECURR	.DB	"Current size: ",0
MSGTUNEMAX	.DB	" (max: 150 x 50)   ",0
TCFG_SEQ_CLR	.DB	27,'[','2','J',27,'[','H',0
TCFG_SEQ_EL2	.DB	27,'[','2','K',0
TCFG_SEQ_CYAN	.DB	27,'[','3','6','m',0
TCFG_SEQ_YEL	.DB	27,'[','3','3','m',0
TCFG_SEQ_GRN	.DB	27,'[','3','2','m',0
TCFG_SEQ_RST	.DB	27,'[','0','m',0
;
HWSTR_SCG		.DB	"SCG ECB Board",0
HWSTR_N8		.DB	"N8 Onboard Sound",0
HWSTR_RCEB		.DB	"RCBus Sound Module (EB)",0
HWSTR_RCMSX		.DB	"RCBus Sound Module (MSX)",0
HWSTR_RCMF		.DB	"RCBus Sound Module (MF)",0
HWSTR_LINC		.DB	"Z50 LiNC Sound Module",0
HWSTR_MBC		.DB	"NHYODYNE Sound Module",0
HWSTR_DUO		.DB	"DUODYNE Sound Module",0
HWSTR_NABU		.DB	"NABU Onboard Sound",0
HWSTR_HEATH		.DB	"HEATH H8 MSX Module",0
HWSTR_MSX		.DB	"MSX Standard Ports (A0H/A1H)",0
HWSTR_RC		.DB	"RCBus Standard Ports (D8H/D0H)",0
HWSTR_COLECO	.DB	"RCBus Coleco AY Ports (50H/51H)",0
;
; Short port descriptions for TurboSound output
;
TSSTR_MSX		.DB	"MSX Standard (A0H/A1H)",0
TSSTR_RC		.DB	"RCBus Standard (D8H/D0H)",0
TSSTR_COLECO	.DB	"Coleco AY (50H/51H)",0

MSGUNSUP		.DB	"MYM files not supported with HBIOS yet!\r\n", 0

MSGSONGNAME     .DB     "Song name: ", 0
MSGARTIST       .DB     "by:        ", 0
MSGFROM		.DB	" from: ",0
MSGVGMGD3		.DB	"(VGM GD3 tag optional)",0
VGMCLKTBL:	.DB	1		; 1MHz
		.DB	3		; 2MHz
		.DB	0		; 3MHz
		.DB	7		; 4MHz (+1)
		.DB	0		; 5MHz
		.DB	9		; 6MHz (+1)
		.DB	10		; 7 MHz / 7.3728 MHz (+1)
		.DB	11		; 8MHz (+1)
		.DB	0		; 9MHz
		.DB	15		; 10MHz (+1)
		.DB	0		; 11MHz
		.DB	17		; 12MHz (+1)
		.DB	0		; 13MHz
		.DB	0		; 14MHz
		.DB	0		; 15MHz
		.DB	23		; 16MHz (+1)
		.DB	0		; 17MHz
		.DB	0		; 18MHz
		.DB	0		; 19MHz
		.DB	0		; 20MHz
;
;===============================================================================
; PTx Player Routines
;===============================================================================
;
;Universal PT2 and PT3 player for ZX Spectrum and MSX
;(c)2004-2007 S.V.Bulba <vorobey@mail.khstu.ru>
;http://bulba.untergrund.net (http://bulba.at.kz)


;Features
;--------
;-Can be compiled at any address (i.e. no need rounding ORG
; address).
;-Variables (VARS) can be located at any address (not only after
;code block).
;-INIT subprogram checks PT3-module version and rightly
; generates both note and volume tables outside of code block
; (in VARS).
;-Two portamento (spc. command 3xxx) algorithms (depending of
; PT3 module version).
;-New 1.XX and 2.XX special command behaviour (only for PT v3.7
; and higher).
;-Any Tempo value are accepted (including Tempo=1 and Tempo=2).
;-Fully compatible with Ay_Emul PT3 and PT2 players codes.
;-See also notes at the end of this source code.

;Limitations
;-----------
;-Can run in RAM only (self-modified code is used).
;-PT2 position list must be end by $FF marker only.

;Warning!!! PLAY subprogram can crash if no module are loaded
;into RAM or INIT subprogram was not called before.

;Call MUTE or INIT one more time to mute sound after stopping
;playing

	;ORG $C000
;Test codes (commented)
;	LD A,2 ;PT2,ABC,Looped
;	LD (START+10),A
;	CALL START
;	EI
;_LP	HALT
;	CALL START+5
;	XOR A
;	IN A,($FE)
;	CPL
;	AND 15
;	JR Z,_LP
;	JR START+8

TonA	.EQU 0
TonB	.EQU 2
TonC	.EQU 4
Noise	.EQU 6
Mixer	.EQU 7
AmplA	.EQU 8
AmplB	.EQU 9
AmplC	.EQU 10
Env	.EQU 11
EnvTp	.EQU 13

;ChannelsVars
;	STRUCT	CHP
;reset group
PsInOr	.EQU 0
PsInSm	.EQU 1
CrAmSl	.EQU 2
CrNsSl	.EQU 3
CrEnSl	.EQU 4
TSlCnt	.EQU 5
CrTnSl	.EQU 6
TnAcc	.EQU 8
COnOff	.EQU 10
;reset group

OnOffD	.EQU 11

;IX for PTDECOD here (+12)
OffOnD	.EQU 12
OrnPtr	.EQU 13
SamPtr	.EQU 15
NNtSkp	.EQU 17
Note	.EQU 18
SlToNt	.EQU 19
Env_En	.EQU 20
Flags	.EQU 21
 ;Enabled - 0,SimpleGliss - 2
TnSlDl	.EQU 22
TSlStp	.EQU 23
TnDelt	.EQU 25
NtSkCn	.EQU 27
Volume	.EQU 28
;	ENDS
CHP	.EQU 29

;Entry and other points

START
	LD HL,MDLADDR
	JR INIT
	JP PLAY
	JR MUTE
SETUP	.DB 0 ;set bit0, if you want to play without looping
	     ;(optional);
	     ;set bit1 for PT2 and reset for PT3 before
	     ;calling INIT;
	     ;bits2-3: %00-ABC, %01 ACB, %10 BAC (optional);
	     ;bits4-6 are not used
	     ;bit7 is set each time, when loop point is passed
	     ;(optional)
#IF CurPosCounter
CurPos	.DB 0 ;for visualization only (i.e. no need for playing)
#ENDIF

;Identifier
	.IF Id
	.DB	"=Uni PT2 and PT3 Player r.", VTBANREL, "="
	.ENDIF

	.IF LoopChecker
CHECKLP	LD HL,SETUP
	SET 7,(HL)
	BIT 0,(HL)
	RET Z
	POP HL
	LD HL,DelyCnt
	INC (HL)
	LD HL,ChanA+NtSkCn
	INC (HL)
	.ENDIF

MUTE	ISHBIOS
	JR	NZ,MUTEVIAHBIOS

	XOR A
	LD B,14
	LD HL,AYREGS
MUTE1	LD (HL),A
	INC HL
	DJNZ MUTE1
	;XOR A
	;LD H,A
	;LD L,A
	;LD (AYREGS+AmplA),A
	;LD (AYREGS+AmplB),HL
	JP ROUT

MUTEVIAHBIOS:
	LD	B,BF_SNDRESET
	LD	C,0
	RST	08
	RET

INIT
;HL - AddressOfModule
	LD A,(START+10)
	AND 2
	JR NZ,INITPT2

	CALL SETMDAD
	PUSH HL
	LD DE,100
	ADD HL,DE
	LD A,(HL)
	LD (Delay),A
	PUSH HL
	POP IX
	ADD HL,DE
	LD (CrPsPtr),HL
	LD E,(IX+102-100)
	INC HL

#IF CurPosCounter
	LD A,L
	LD (PosSub+1),A
#ENDIF

	ADD HL,DE
	LD (LPosPtr),HL
	POP DE
	LD L,(IX+103-100)
	LD H,(IX+104-100)
	ADD HL,DE
	LD (PatsPtr),HL
	LD HL,169
	ADD HL,DE
	LD (OrnPtrs),HL
	LD HL,105
	ADD HL,DE
	LD (SamPtrs),HL
	LD A,(IX+13-100) ;EXTRACT VERSION NUMBER
	SUB $30
	JR C,L20
	CP 10
	JR C,L21
L20	LD A,6
L21	LD (Version),A
	PUSH AF ;VolTable version
	CP 4
	LD A,(IX+99-100) ;TONE TABLE NUMBER
	RLA
	AND 7
	PUSH AF ;NoteTable number
	LD HL,(e_-SamCnv-2)*256+$18
	LD (SamCnv),HL
	LD A,$BA
	LD (OrnCP),A
	LD (SamCP),A
	LD A,$7B
	LD (OrnLD),A
	LD (SamLD),A
	LD A,$87
	LD (SamClc2),A
	LD BC,PT3PD
	LD HL,0
	LD DE,PT3EMPTYORN
	JR INITCOMMON

INITPT2	LD A,(HL)
	LD (Delay),A
	PUSH HL
	PUSH HL
	PUSH HL
	INC HL
	INC HL
	LD A,(HL)
	INC HL
	LD (SamPtrs),HL
	LD E,(HL)
	INC HL
	LD D,(HL)
	POP HL
	AND A
	SBC HL,DE
	CALL SETMDAD
	POP HL
	LD DE,67
	ADD HL,DE
	LD (OrnPtrs),HL
	LD E,32
	ADD HL,DE
	LD C,(HL)
	INC HL
	LD B,(HL)
	LD E,30
	ADD HL,DE
	LD (CrPsPtr),HL
	LD E,A
	INC HL

#IF CurPosCounter
	LD A,L
	LD (PosSub+1),A
#ENDIF

	ADD HL,DE
	LD (LPosPtr),HL
	POP HL
	ADD HL,BC
	LD (PatsPtr),HL
	LD A,5
	LD (Version),A
	PUSH AF
	LD A,2
	PUSH AF
	LD HL,$51CB
	LD (SamCnv),HL
	LD A,$BB
	LD (OrnCP),A
	LD (SamCP),A
	LD A,$7A
	LD (OrnLD),A
	LD (SamLD),A
	LD A,$80
	LD (SamClc2),A
	LD BC,PT2PD
	LD HL,$8687
	LD DE,PT2EMPTYORN

INITCOMMON

	LD (PTDECOD+1),BC
	LD (PsCalc),HL
	PUSH DE

;note table data depacker
;(c) Ivan Roshin
	CALL	TS_DEPACK_TP

#IF LoopChecker
	LD HL,SETUP
	RES 7,(HL)

  #IF CurPosCounter
	INC HL
	LD (HL),A
  #ENDIF

#ELSE

  #IF CurPosCounter
	LD (CurPos),A
  #ENDIF

#ENDIF

	LD HL,VARS
	LD (HL),A
	LD DE,VARS+1
	LD BC,VAR0END-VARS-1
	LDIR
	LD (AdInPtA),HL ;ptr to zero
	INC A
	LD (DelyCnt),A
	LD HL,$F001 ;H - Volume, L - NtSkCn
	LD (ChanA+NtSkCn),HL
	LD (ChanB+NtSkCn),HL
	LD (ChanC+NtSkCn),HL
	POP HL
	LD (ChanA+OrnPtr),HL
	LD (ChanB+OrnPtr),HL
	LD (ChanC+OrnPtr),HL

	POP AF
	CALL	TS_NTVT_START
	JP	ROUT

; Depack shared tone table (T_PACK -> T1_).
TS_DEPACK_TP:
	LD	DE,T_PACK
	LD	BC,T1_+(2*49)-1
TP_0	LD	A,(DE)
	INC	DE
	CP	15*2
	JR	NC,TP_1
	LD	H,A
	LD	A,(DE)
	LD	L,A
	INC	DE
	JR	TP_2
TP_1	PUSH	DE
	LD	D,0
	LD	E,A
	ADD	HL,DE
	ADD	HL,DE
	POP	DE
TP_2	LD	A,H
	LD	(BC),A
	DEC	BC
	LD	A,L
	LD	(BC),A
	DEC	BC
	SUB	($F8*2) & $FF
	JR	NZ,TP_0
	RET

; TurboSound: rebuild VT_/NT_ for the module at MODADDR after CTX_LOAD.
; No-op unless TS_DUALHW (SC126 single-AY uses normal PT3, not this path).
TS_REBUILD_NTVT:
	LD	A,(TS_DUALHW)
	OR	A
	RET	Z
	LD	HL,(MODADDR)
	LD	BC,PT3PD
	XOR	A
	LD	H,A
	LD	L,A
	LD	DE,PT3EMPTYORN
	LD	(PTDECOD+1),BC
	LD	(PsCalc),HL
	PUSH	DE
	CALL	TS_DEPACK_TP
	CALL	TS_NTVT_PREP
	CALL	TS_NTVT_START
	RET

TS_NTVT_PREP:
	LD	HL,(MODADDR)
	LD	DE,13
	ADD	HL,DE
	LD	A,(HL)
	SUB	$30
	JR	C,TS_NTP_V6
	CP	10
	JR	C,TS_NTP_VOK
TS_NTP_V6:
	LD	A,6
TS_NTP_VOK:
	PUSH	AF
	CP	4
	LD	HL,(MODADDR)
	LD	DE,99
	ADD	HL,DE
	LD	A,(HL)
	RLA
	AND	7
	PUSH	AF
	RET

;NoteTableCreator (c) Ivan Roshin
;A - NoteTableNumber*2+VersionForNoteTable
;(xx1b - 3.xx..3.4r, xx0b - 3.4x..3.6x..VTII1.0)

TS_NTVT_START:
	LD HL,NT_DATA
	PUSH DE
	LD D,B
	ADD A,A
	LD E,A
	ADD HL,DE
	LD E,(HL)
	INC HL
	SRL E
	SBC A,A
	AND $A7 ;$00 (NOP) or $A7 (AND A)
	LD (L3),A
	EX DE,HL
	POP BC ;BC=T1_
	ADD HL,BC

	LD A,(DE)
	ADD A,T_ & $FF
	LD C,A
	ADC A,T_/256
	SUB C
	LD B,A
	PUSH BC
	LD DE,NT_
	PUSH DE

	LD B,12
	LD IX,TMP		; +WW
L1	PUSH BC
	LD C,(HL)
	INC HL
	PUSH HL
	LD B,(HL)

	PUSH DE
	EX DE,HL
	LD DE,23
	;LD IXH,8		; -WW
	LD (IX),8		; +WW

L2	SRL B
	RR C
L3	.DB $19	;AND A or NOP
	LD A,C
	ADC A,D	;=ADC 0
	LD (HL),A
	INC HL
	LD A,B
	ADC A,D
	LD (HL),A
	ADD HL,DE
	;DEC IXH		; -WW
	DEC (IX)		; +WW
	JR NZ,L2

	POP DE
	INC DE
	INC DE
	POP HL
	INC HL
	POP BC
	DJNZ L1

	POP HL
	POP DE

	LD A,E
	CP TCOLD_1 & $FF
	JR NZ,CORR_1
	LD A,$FD
	LD (NT_+$2E),A

CORR_1	LD A,(DE)
	AND A
	JR Z,TC_EXIT
	RRA
	PUSH AF
	ADD A,A
	LD C,A
	ADD HL,BC
	POP AF
	JR NC,CORR_2
	DEC (HL)
	DEC (HL)
CORR_2	INC (HL)
	AND A
	SBC HL,BC
	INC DE
	JR CORR_1

TC_EXIT

	POP AF

;VolTableCreator (c) Ivan Roshin
;A - VersionForVolumeTable (0..4 - 3.xx..3.4x;
			   ;5.. - 2.x,3.5x..3.6x..VTII1.0)

	CP 5
	LD HL,$11
	LD D,H
	LD E,H
	LD A,$17
	JR NC,M1
	DEC L
	LD E,L
	XOR A
M1      LD (M2),A

	LD IX,VT_+16

	LD C,$F
INITV2  PUSH HL

	ADD HL,DE
	EX DE,HL
	SBC HL,HL

	LD B,$10
INITV1  LD A,L
M2      .DB $7D
	LD A,H
	ADC A,0
	LD (IX),A
	INC IX
	ADD HL,DE
	DJNZ INITV1

	POP HL
	LD A,E
	CP $77
	JR NZ,M3
	INC E
M3      DEC C
	JR NZ,INITV2

TS_NTVT_END:
	RET

SETMDAD	LD (MODADDR),HL
	LD (MDADDR1),HL
	LD (MDADDR2),HL
	RET

PTDECOD JP $C3C3

;PT2 pattern decoder
PD2_SAM	CALL SETSAM
	JR PD2_LOOP

PD2_EOff LD (IX-12+Env_En),A
	JR PD2_LOOP

PD2_ENV	LD (IX-12+Env_En),16
	LD (AYREGS+EnvTp),A
	LD A,(BC)
	INC BC
	LD L,A
	LD A,(BC)
	INC BC
	LD H,A
	LD (EnvBase),HL
	JR PD2_LOOP

PD2_ORN	CALL SETORN
	JR PD2_LOOP

PD2_SKIP INC A
	LD (IX-12+NNtSkp),A
	JR PD2_LOOP

PD2_VOL	RRCA
	RRCA
	RRCA
	RRCA
	LD (IX-12+Volume),A
	JR PD2_LOOP

PD2_DEL	CALL C_DELAY
	JR PD2_LOOP

PD2_GLIS SET 2,(IX-12+Flags)
	INC A
	LD (IX-12+TnSlDl),A
	LD (IX-12+TSlCnt),A
	LD A,(BC)
	INC BC
        LD (IX-12+TSlStp),A
	ADD A,A
	SBC A,A
        LD (IX-12+TSlStp+1),A
	SCF
	JR PD2_LP2

PT2PD	AND A

PD2_LP2	EX AF,AF'

PD2_LOOP LD A,(BC)
	INC BC
	ADD A,$20
	JR Z,PD2_REL
	JR C,PD2_SAM
	ADD A,96
	JR C,PD2_NOTE
	INC A
	JR Z,PD2_EOff
	ADD A,15
	JP Z,PD_FIN
	JR C,PD2_ENV
	ADD A,$10
	JR C,PD2_ORN
	ADD A,$40
	JR C,PD2_SKIP
	ADD A,$10
	JR C,PD2_VOL
	INC A
	JR Z,PD2_DEL
	INC A
	JR Z,PD2_GLIS
	INC A
	JR Z,PD2_PORT
	INC A
	JR Z,PD2_STOP
	LD A,(BC)
	INC BC
	LD (IX-12+CrNsSl),A
	JR PD2_LOOP

PD2_PORT RES 2,(IX-12+Flags)
	LD A,(BC)
	INC BC
	INC BC ;ignoring precalc delta to right sound
	INC BC
	SCF
	JR PD2_LP2

PD2_STOP LD (IX-12+TSlCnt),A
	JR PD2_LOOP

PD2_REL	LD (IX-12+Flags),A
	JR PD2_EXIT

PD2_NOTE LD L,A
	LD A,(IX-12+Note)
	LD (PrNote+1),A
	LD (IX-12+Note),L
	XOR A
	LD (IX-12+TSlCnt),A
	SET 0,(IX-12+Flags)
	EX AF,AF'
	JR NC,NOGLIS2
	BIT 2,(IX-12+Flags)
	JR NZ,NOPORT2
	LD (LoStep),A
	ADD A,A
	SBC A,A
	EX AF,AF'
	LD H,A
	LD L,A
	INC A
	CALL SETPORT
NOPORT2	LD (IX-12+TSlCnt),1
NOGLIS2	XOR A


PD2_EXIT LD (IX-12+PsInSm),A
	LD (IX-12+PsInOr),A
	LD (IX-12+CrTnSl),A
	LD (IX-12+CrTnSl+1),A
	JP PD_FIN

;PT3 pattern decoder
PD_OrSm	LD (IX-12+Env_En),0
	CALL SETORN
PD_SAM_	LD A,(BC)
	INC BC
	RRCA

PD_SAM	CALL SETSAM
	JR PD_LOOP

PD_VOL	RRCA
	RRCA
	RRCA
	RRCA
	LD (IX-12+Volume),A
	JR PD_LP2

PD_EOff	LD (IX-12+Env_En),A
	LD (IX-12+PsInOr),A
	JR PD_LP2

PD_SorE	DEC A
	JR NZ,PD_ENV
	LD A,(BC)
	INC BC
	LD (IX-12+NNtSkp),A
	JR PD_LP2

PD_ENV	CALL SETENV
	JR PD_LP2

PD_ORN	CALL SETORN
	JR PD_LOOP

PD_ESAM	LD (IX-12+Env_En),A
	LD (IX-12+PsInOr),A
	CALL NZ,SETENV
	JR PD_SAM_

PT3PD	LD A,(IX-12+Note)
	LD (PrNote+1),A
	LD L,(IX-12+CrTnSl)
	LD H,(IX-12+CrTnSl+1)
	LD (PrSlide+1),HL

PD_LOOP	LD DE,$2010
PD_LP2	LD A,(BC)
	INC BC
	ADD A,E
	JR C,PD_OrSm
	ADD A,D
	JR Z,PD_FIN
	JR C,PD_SAM
	ADD A,E
	JR Z,PD_REL
	JR C,PD_VOL
	ADD A,E
	JR Z,PD_EOff
	JR C,PD_SorE
	ADD A,96
	JR C,PD_NOTE
	ADD A,E
	JR C,PD_ORN
	ADD A,D
	JR C,PD_NOIS
	ADD A,E
	JR C,PD_ESAM
	ADD A,A
	LD E,A
	LD HL,SPCCOMS-$20E0
	ADD HL,DE
	LD E,(HL)
	INC HL
	LD D,(HL)
	PUSH DE
	JR PD_LOOP

PD_NOIS	LD (Ns_Base),A
	JR PD_LP2

PD_REL	RES 0,(IX-12+Flags)
	JR PD_RES

PD_NOTE	LD (IX-12+Note),A
	SET 0,(IX-12+Flags)
	XOR A

PD_RES	LD (PDSP_+1),SP
	LD SP,IX
	LD H,A
	LD L,A
	PUSH HL
	PUSH HL
	PUSH HL
	PUSH HL
	PUSH HL
	PUSH HL
PDSP_	LD SP,$3131

PD_FIN	LD A,(IX-12+NNtSkp)
	LD (IX-12+NtSkCn),A
	RET

C_PORTM LD A,(BC)
	INC BC
;SKIP PRECALCULATED TONE DELTA (BECAUSE
;CANNOT BE RIGHT AFTER PT3 COMPILATION)
	INC BC
	INC BC
	EX AF,AF'
	LD A,(BC) ;SIGNED TONE STEP
	INC BC
	LD (LoStep),A
	LD A,(BC)
	INC BC
	AND A
	EX AF,AF'
	LD L,(IX-12+CrTnSl)
	LD H,(IX-12+CrTnSl+1)

;Set portamento variables
;A - Delay; A' - Hi(Step); ZF' - (A'=0); HL - CrTnSl

SETPORT	RES 2,(IX-12+Flags)
	LD (IX-12+TnSlDl),A
	LD (IX-12+TSlCnt),A
	PUSH HL
	LD DE,NT_
	LD A,(IX-12+Note)
	LD (IX-12+SlToNt),A
	ADD A,A
	LD L,A
	LD H,0
	ADD HL,DE
	LD A,(HL)
	INC HL
	LD H,(HL)
	LD L,A
	PUSH HL
PrNote	LD A,$3E
	LD (IX-12+Note),A
	ADD A,A
	LD L,A
	LD H,0
	ADD HL,DE
	LD E,(HL)
	INC HL
	LD D,(HL)
	POP HL
	SBC HL,DE
	LD (IX-12+TnDelt),L
	LD (IX-12+TnDelt+1),H
	POP DE
Version .EQU $+1
	LD A,$3E
	CP 6
	JR C,OLDPRTM ;Old 3xxx for PT v3.5-
PrSlide	LD DE,$1111
	LD (IX-12+CrTnSl),E
	LD (IX-12+CrTnSl+1),D
LoStep	.EQU $+1
OLDPRTM	LD A,$3E
	EX AF,AF'
	JR Z,NOSIG
	EX DE,HL
NOSIG	SBC HL,DE
	JP P,SET_STP
	CPL
	EX AF,AF'
	NEG
	EX AF,AF'
SET_STP	LD (IX-12+TSlStp+1),A
	EX AF,AF'
	LD (IX-12+TSlStp),A
	LD (IX-12+COnOff),0
	RET

C_GLISS	SET 2,(IX-12+Flags)
	LD A,(BC)
	INC BC
	LD (IX-12+TnSlDl),A
	AND A
	JR NZ,GL36
	LD A,(Version) ;AlCo PT3.7+
	CP 7
	SBC A,A
	INC A
GL36	LD (IX-12+TSlCnt),A
	LD A,(BC)
	INC BC
	EX AF,AF'
	LD A,(BC)
	INC BC
	JR SET_STP

C_SMPOS	LD A,(BC)
	INC BC
	LD (IX-12+PsInSm),A
	RET

C_ORPOS	LD A,(BC)
	INC BC
	LD (IX-12+PsInOr),A
	RET

C_VIBRT	LD A,(BC)
	INC BC
	LD (IX-12+OnOffD),A
	LD (IX-12+COnOff),A
	LD A,(BC)
	INC BC
	LD (IX-12+OffOnD),A
	XOR A
	LD (IX-12+TSlCnt),A
	LD (IX-12+CrTnSl),A
	LD (IX-12+CrTnSl+1),A
	RET

C_ENGLS	LD A,(BC)
	INC BC
	LD (Env_Del),A
	LD (CurEDel),A
	LD A,(BC)
	INC BC
	LD L,A
	LD A,(BC)
	INC BC
	LD H,A
	LD (ESldAdd),HL
	RET

C_DELAY	LD A,(BC)
	INC BC
	LD (Delay),A
	RET

SETENV	LD (IX-12+Env_En),E
	LD (AYREGS+EnvTp),A
	LD A,(BC)
	INC BC
	LD H,A
	LD A,(BC)
	INC BC
	LD L,A
	LD (EnvBase),HL
	XOR A
	LD (IX-12+PsInOr),A
	LD (CurEDel),A
	LD H,A
	LD L,A
	LD (CurESld),HL
C_NOP	RET

SETORN	ADD A,A
	LD E,A
	LD D,0
	LD (IX-12+PsInOr),D
OrnPtrs .EQU $+1
	LD HL,$2121
	ADD HL,DE
	LD E,(HL)
	INC HL
	LD D,(HL)
MDADDR2 .EQU $+1
	LD HL,$2121
	ADD HL,DE
	LD (IX-12+OrnPtr),L
	LD (IX-12+OrnPtr+1),H
	RET

SETSAM	ADD A,A
	LD E,A
	LD D,0
SamPtrs .EQU $+1
	LD HL,$2121
	ADD HL,DE
	LD E,(HL)
	INC HL
	LD D,(HL)
MDADDR1	.EQU $+1
	LD HL,$2121
	ADD HL,DE
	LD (IX-12+SamPtr),L
	LD (IX-12+SamPtr+1),H
	RET

;ALL 16 ADDRESSES TO PROTECT FROM BROKEN PT3 MODULES
SPCCOMS .DW C_NOP
	.DW C_GLISS
	.DW C_PORTM
	.DW C_SMPOS
	.DW C_ORPOS
	.DW C_VIBRT
	.DW C_NOP
	.DW C_NOP
	.DW C_ENGLS
	.DW C_DELAY
	.DW C_NOP
	.DW C_NOP
	.DW C_NOP
	.DW C_NOP
	.DW C_NOP
	.DW C_NOP

CHREGS	XOR A
	LD (Ampl),A
	BIT 0,(IX+Flags)
	PUSH HL
	JP Z,CH_EXIT
	LD (CSP_+1),SP
	LD L,(IX+OrnPtr)
	LD H,(IX+OrnPtr+1)
	LD SP,HL
	POP DE
	LD H,A
	LD A,(IX+PsInOr)
	LD L,A
	ADD HL,SP
	INC A
		;PT2	PT3
OrnCP	INC A	;CP E	CP D
	JR C,CH_ORPS
OrnLD	.DB 1	;LD A,D	LD A,E
CH_ORPS	LD (IX+PsInOr),A
	LD A,(IX+Note)
	ADD A,(HL)
	JP P,CH_NTP
	XOR A
CH_NTP	CP 96
	JR C,CH_NOK
	LD A,95
CH_NOK	ADD A,A
	EX AF,AF'
	LD L,(IX+SamPtr)
	LD H,(IX+SamPtr+1)
	LD SP,HL
	POP DE
	LD H,0
	LD A,(IX+PsInSm)
	LD B,A
	ADD A,A
SamClc2	ADD A,A ;or ADD A,B for PT2
	LD L,A
	ADD HL,SP
	LD SP,HL
	LD A,B
	INC A
		;PT2	PT3
SamCP	INC A	;CP E	CP D
	JR C,CH_SMPS
SamLD	.DB 1	;LD A,D	LD A,E
CH_SMPS	LD (IX+PsInSm),A
	POP BC
	POP HL

;Convert PT2 sample to PT3
		;PT2		PT3
SamCnv	POP HL  ;BIT 2,C	JR e_
	POP HL
	LD H,B
	JR NZ,$+8
	EX DE,HL
	AND A
	SBC HL,HL
	SBC HL,DE
	LD D,C
	RR C
	SBC A,A
	CPL
	AND $3E
	RR C
	RR B
	AND C
	LD C,A
	LD A,B
	RRA
	RRA
	RR D
	RRA
	AND $9F
	LD B,A

e_	LD E,(IX+TnAcc)
	LD D,(IX+TnAcc+1)
	ADD HL,DE
	BIT 6,B
	JR Z,CH_NOAC
	LD (IX+TnAcc),L
	LD (IX+TnAcc+1),H
CH_NOAC EX DE,HL
	EX AF,AF'
	ADD A,NT_ & $FF
	LD L,A
	ADC A,NT_/256
	SUB L
	LD H,A
	LD SP,HL
	POP HL
	ADD HL,DE
	LD E,(IX+CrTnSl)
	LD D,(IX+CrTnSl+1)
	ADD HL,DE
CSP_	LD SP,$3131
	EX (SP),HL
	XOR A
	OR (IX+TSlCnt)
	JR Z,CH_AMP
	DEC (IX+TSlCnt)
	JR NZ,CH_AMP
	LD A,(IX+TnSlDl)
	LD (IX+TSlCnt),A
	LD L,(IX+TSlStp)
	LD H,(IX+TSlStp+1)
	LD A,H
	ADD HL,DE
	LD (IX+CrTnSl),L
	LD (IX+CrTnSl+1),H
	BIT 2,(IX+Flags)
	JR NZ,CH_AMP
	LD E,(IX+TnDelt)
	LD D,(IX+TnDelt+1)
	AND A
	JR Z,CH_STPP
	EX DE,HL
CH_STPP SBC HL,DE
	JP M,CH_AMP
	LD A,(IX+SlToNt)
	LD (IX+Note),A
	XOR A
	LD (IX+TSlCnt),A
	LD (IX+CrTnSl),A
	LD (IX+CrTnSl+1),A
CH_AMP	LD A,(IX+CrAmSl)
	BIT 7,C
	JR Z,CH_NOAM
	BIT 6,C
	JR Z,CH_AMIN
	CP 15
	JR Z,CH_NOAM
	INC A
	JR CH_SVAM
CH_AMIN	CP -15
	JR Z,CH_NOAM
	DEC A
CH_SVAM	LD (IX+CrAmSl),A
CH_NOAM	LD L,A
	LD A,B
	AND 15
	ADD A,L
	JP P,CH_APOS
	XOR A
CH_APOS	CP 16
	JR C,CH_VOL
	LD A,15
CH_VOL	OR (IX+Volume)
	ADD A,VT_ & $FF
	LD L,A
	ADC A,VT_/256
	SUB L
	LD H,A
	LD A,(HL)
CH_ENV	BIT 0,C
	JR NZ,CH_NOEN
	OR (IX+Env_En)
CH_NOEN	LD (Ampl),A
	BIT 7,B
	LD A,C
	JR Z,NO_ENSL
	RLA
	RLA
	SRA A
	SRA A
	SRA A
	ADD A,(IX+CrEnSl) ;SEE COMMENT BELOW
	BIT 5,B
	JR Z,NO_ENAC
	LD (IX+CrEnSl),A
NO_ENAC	LD HL,AddToEn
	ADD A,(HL) ;BUG IN PT3 - NEED WORD HERE
	LD (HL),A
	JR CH_MIX
NO_ENSL RRA
	ADD A,(IX+CrNsSl)
	LD (AddToNs),A
	BIT 5,B
	JR Z,CH_MIX
	LD (IX+CrNsSl),A
CH_MIX	LD A,B
	RRA
	AND $48
CH_EXIT	LD HL,AYREGS+Mixer
	OR (HL)
	RRCA
	LD (HL),A
	POP HL
	XOR A
	OR (IX+COnOff)
	RET Z
	DEC (IX+COnOff)
	RET NZ
	XOR (IX+Flags)
	LD (IX+Flags),A
	RRA
	LD A,(IX+OnOffD)
	JR C,CH_ONDL
	LD A,(IX+OffOnD)
CH_ONDL	LD (IX+COnOff),A
	RET

PLAY    XOR A
	LD (AddToEn),A
	LD (AYREGS+Mixer),A
	DEC A
	LD (AYREGS+EnvTp),A
	LD HL,DelyCnt
	DEC (HL)
	JP NZ,PL2
	LD HL,ChanA+NtSkCn
	DEC (HL)
	JR NZ,PL1B
AdInPtA .EQU $+1
	LD BC,$0101
	LD A,(BC)
	AND A
	JR NZ,PL1A
	LD D,A
	LD (Ns_Base),A
CrPsPtr .EQU $+1
	LD HL,$2121
	INC HL
	LD A,(HL)
	INC A
	JR NZ,PLNLP

#IF LoopChecker
	CALL CHECKLP
#ENDIF

LPosPtr .EQU $+1
	LD HL,$2121
	LD A,(HL)
	INC A
PLNLP	LD (CrPsPtr),HL
	DEC A
		;PT2		PT3
PsCalc	DEC A	;ADD A,A	NOP
	DEC A	;ADD A,(HL)	NOP
	ADD A,A
	LD E,A
	RL D

#IF CurPosCounter
	LD A,L
PosSub	SUB $D6
	LD (CurPos),A
#ENDIF

PatsPtr .EQU $+1
	LD HL,$2121
	ADD HL,DE
MODADDR	.EQU $+1
	LD DE,$1111
	LD (PSP_+1),SP
	LD SP,HL
	POP HL
	ADD HL,DE
	LD B,H
	LD C,L
	POP HL
	ADD HL,DE
	LD (AdInPtB),HL
	POP HL
	ADD HL,DE
	LD (AdInPtC),HL
PSP_	LD SP,$3131
PL1A	LD IX,ChanA+12
	CALL PTDECOD
	LD (AdInPtA),BC

PL1B	LD HL,ChanB+NtSkCn
	DEC (HL)
	JR NZ,PL1C
	LD IX,ChanB+12
AdInPtB	.EQU $+1
	LD BC,$0101
	CALL PTDECOD
	LD (AdInPtB),BC

PL1C	LD HL,ChanC+NtSkCn
	DEC (HL)
	JR NZ,PL1D
	LD IX,ChanC+12
AdInPtC	.EQU $+1
	LD BC,$0101
	CALL PTDECOD
	LD (AdInPtC),BC

Delay	.EQU $+1
PL1D	LD A,$3E
	LD (DelyCnt),A

PL2	LD IX,ChanA
	LD HL,(AYREGS+TonA)
	CALL CHREGS
	LD (AYREGS+TonA),HL
	LD A,(Ampl)
	LD (AYREGS+AmplA),A
	LD IX,ChanB
	LD HL,(AYREGS+TonB)
	CALL CHREGS
	LD (AYREGS+TonB),HL
	LD A,(Ampl)
	LD (AYREGS+AmplB),A
	LD IX,ChanC
	LD HL,(AYREGS+TonC)
	CALL CHREGS
	LD (AYREGS+TonC),HL

	LD HL,(Ns_Base_AddToNs)
	LD A,H
	ADD A,L
	LD (AYREGS+Noise),A

AddToEn .EQU $+1
	LD A,$3E
	LD E,A
	ADD A,A
	SBC A,A
	LD D,A
	LD HL,(EnvBase)
	ADD HL,DE
	LD DE,(CurESld)
	ADD HL,DE
	LD (AYREGS+Env),HL

	XOR A
	LD HL,CurEDel
	OR (HL)
	JR Z,ROUT
	DEC (HL)
	JR NZ,ROUT
Env_Del	.EQU $+1
	LD A,$3E
	LD (HL),A
ESldAdd	.EQU $+1
	LD HL,$2121
	ADD HL,DE
	LD (CurESld),HL

ROUT
#IF ACBBAC
	LD A,(SETUP)
	AND 12
	JR Z,ABC
	ADD A,CHTABLE
	LD E,A
	ADC A,CHTABLE/256
	SUB E
	LD D,A
	LD B,0
	LD IX,AYREGS
	LD HL,AYREGS
	LD A,(DE)
	INC DE
	LD C,A
	ADD HL,BC
	LD A,(IX+TonB)
	LD C,(HL)
	LD (IX+TonB),C
	LD (HL),A
	INC HL
	LD A,(IX+TonB+1)
	LD C,(HL)
	LD (IX+TonB+1),C
	LD (HL),A
	LD A,(DE)
	INC DE
	LD C,A
	ADD HL,BC
	LD A,(IX+AmplB)
	LD C,(HL)
	LD (IX+AmplB),C
	LD (HL),A
	LD A,(DE)
	INC DE
	LD (RxCA1),A
	XOR 8
	LD (RxCA2),A
	LD HL,AYREGS+Mixer
	LD A,(DE)
	AND (HL)
	LD E,A
	LD A,(HL)
RxCA1	LD A,(HL)
	AND %010010
	OR E
	LD E,A
	LD A,(HL)
	AND %010010
RxCA2	OR E
	OR E
	LD (HL),A
ABC
#ENDIF

#IF _ZX
	XOR A
	LD DE,$FFBF
	LD BC,$FFFD
	LD HL,AYREGS
LOUT	OUT (C),A
	LD B,E
	OUTI
	LD B,D
	INC A
	CP 13
	JR NZ,LOUT
	OUT (C),A
	LD A,(HL)
	AND A
	RET M
	LD B,E
	OUT (C),A
	RET
#ENDIF

#IF _MSX
;MSX version of ROUT (c)Dioniso
	XOR A
	LD C,$A0
	LD HL,AYREGS
LOUT	OUT (C),A
	INC C
	OUTI
	DEC C
	INC A
	CP 13
	JR NZ,LOUT
	OUT (C),A
	LD A,(HL)
	AND A
	RET M
	INC C
	OUT (C),A
	RET
#ENDIF

#IF _WBW
	ISHBIOS
	JR	NZ, PLAYVIAHBIOS

	DI
	CALL 	SLOWIO
	LD 	DE, (PORTS)	; D := RDAT, E := RSEL
	XOR 	A		; START WITH REG 0
	LD 	C, E		; POINT TO ADDRESS PORT
	LD 	HL, AYREGS	; START OF VALUE LIST
LOUT	OUT 	(C), A		; SELECT REGISTER
	LD 	C, D		; POINT TO DATA PORT

	; UGLINESS FOR NABU!  WE NEED TO KEEP BIT 7 = 0, AND BIT 6 = 1
	; FOR PSG REG 7
	CP	7		; PSG REG 7?
	JR	NZ,LOUT1	; SKIP SPECIAL PROCESSING
	PUSH	AF		; SAVE AF
	LD	A,(HL)		; GET VALUE BYTE
	AND	%00111111	; FIX BITS 6 & 7
	OR	%01000000	; ... FOR NABU!
	OUT	(C),A		; SEND THE FIXED VALUE
	DEC	B		; SIMULATE THE RESET		
	INC	HL		; ... OF OUTI
	POP	AF		; RESTORE AF
	JR	LOUT1A		; RESUME LOOP
	
LOUT1	OUTI			; WRITE (HL) TO DATA PORT, BUMP HL
LOUT1A	LD 	C, E		; POINT TO ADDRESS PORT
	INC 	A		; NEXT REGISTER
	CP 	13		; REG 13?
	JR 	NZ, LOUT	; IF NOT, LOOP
	OUT 	(C), A		; SELECT REGISTER 13
	LD 	A, (HL)		; GET VALUE FOR REGISTER 13
	AND 	A		; SET FLAGS
	JP 	M, LOUT2	; IF BIT 7 SET, RETURN W/O WRITING VALUE
	LD 	C, D		; SELECT DATA PORT
	OUT 	(C), A		; WRITE VALUE TO REGISTER 13

LOUT2	CALL 	NORMIO
	EI
	RET			; AND DONE

PLAYVIAHBIOS:
;	CHANNEL 0
	LD	HL, AYREGS + AmplA
	LD	DE, AYREGS + TonA
	LD	B, 0
	CALL	PLAYNOTE
;
;	CHANNEL 1
	LD	HL, AYREGS + AmplB
	LD	DE, AYREGS + TonB
	LD	B, 1
	CALL	PLAYNOTE

;	CHANNEL 2
	LD	HL, AYREGS + AmplC
	LD	DE, AYREGS + TonC
	LD	B, 2
	JP	PLAYNOTE

PLAYNOTE:
	PUSH	BC			; CHANNEL IN B
	PUSH	DE			; PERIOD ADDR IN DE

	LD	A, (HL)
	ADD	A,A			; GET 4-BIT
	ADD	A,A			; VOLUME 0-15
	ADD	A,A			; AND CONVERT
	ADD	A,A			; TO HBIOS
	LD	L, A                    ; RANGE 0-255
	LD	BC, (BF_SNDVOL*256)+0	; SET VOLUME
	RST	08
;
	POP	HL			; RESTORE PERIOD ADDR
	LD	A, (HL)			; DEVICE 0
	INC	HL
	LD	H, (HL)
	LD	L, A
	LD	A, H       		; GET 12-BIT ONE PERIOD
	AND	$0F			; MASK OFF HIGH
	LD	H, A                    ; NIBBLE

	LD	A, (OCTAVEADJ)
	OR	A
	JR	Z, PLAYNOTE3		; NO OCTAVE ADJUSTMENT
	BIT	7, A
	JR	Z, PLAYNOTE2		; OCTAVE DOWN ADJUSTMENT

PLAYNOTE1:
	ADD	HL, HL			; MULTIPLE BY 2 FOR EACH OCTAVE
	INC	A
	JR	NZ, PLAYNOTE1
	JR	PLAYNOTE3

PLAYNOTE2:
	SRL	H			; DIVIDE BY 2 FOR EACH OCTAVE
	RR	L
	DEC	A
	JR	NZ, PLAYNOTE2

PLAYNOTE3
	LD	BC, (BF_SNDPRD*256)+0	; SET PERIOD
	RST	08
;
	POP	DE			; RESTORE CHANNEL IN D (FROM B)
	LD	BC, (BF_SNDPLAY*256)+0	; PLAY
	RST	08

	RET

#ENDIF

#IF ACBBAC
CHTABLE	.EQU $-4
	.DB 4,5,15,%001001,0,7,7,%100100
#ENDIF

NT_DATA	.DB (T_NEW_0-T1_)*2
	.DB TCNEW_0-T_
	.DB (T_OLD_0-T1_)*2+1
	.DB TCOLD_0-T_
	.DB (T_NEW_1-T1_)*2+1
	.DB TCNEW_1-T_
	.DB (T_OLD_1-T1_)*2+1
	.DB TCOLD_1-T_
	.DB (T_NEW_2-T1_)*2
	.DB TCNEW_2-T_
	.DB (T_OLD_2-T1_)*2
	.DB TCOLD_2-T_
	.DB (T_NEW_3-T1_)*2
	.DB TCNEW_3-T_
	.DB (T_OLD_3-T1_)*2
	.DB TCOLD_3-T_

T_

TCOLD_0	.DB $00+1,$04+1,$08+1,$0A+1,$0C+1,$0E+1,$12+1,$14+1
	.DB $18+1,$24+1,$3C+1,0
TCOLD_1	.DB $5C+1,0
TCOLD_2	.DB $30+1,$36+1,$4C+1,$52+1,$5E+1,$70+1,$82,$8C,$9C
	.DB $9E,$A0,$A6,$A8,$AA,$AC,$AE,$AE,0
TCNEW_3	.DB $56+1
TCOLD_3	.DB $1E+1,$22+1,$24+1,$28+1,$2C+1,$2E+1,$32+1,$BE+1,0
TCNEW_0	.DB $1C+1,$20+1,$22+1,$26+1,$2A+1,$2C+1,$30+1,$54+1
	.DB $BC+1,$BE+1,0
TCNEW_1 .EQU TCOLD_1
TCNEW_2	.DB $1A+1,$20+1,$24+1,$28+1,$2A+1,$3A+1,$4C+1,$5E+1
	.DB $BA+1,$BC+1,$BE+1,0

PT3EMPTYORN .EQU $-1
	.DB 1,0

;first 12 values of tone tables (packed)

T_PACK	.DB $06EC*2/256,$06EC*2
	.DB $0755-$06EC
	.DB $07C5-$0755
	.DB $083B-$07C5
	.DB $08B8-$083B
	.DB $093D-$08B8
	.DB $09CA-$093D
	.DB $0A5F-$09CA
	.DB $0AFC-$0A5F
	.DB $0BA4-$0AFC
	.DB $0C55-$0BA4
	.DB $0D10-$0C55
	.DB $066D*2/256,$066D*2
	.DB $06CF-$066D
	.DB $0737-$06CF
	.DB $07A4-$0737
	.DB $0819-$07A4
	.DB $0894-$0819
	.DB $0917-$0894
	.DB $09A1-$0917
	.DB $0A33-$09A1
	.DB $0ACF-$0A33
	.DB $0B73-$0ACF
	.DB $0C22-$0B73
	.DB $0CDA-$0C22
	.DB $0704*2/256,$0704*2
	.DB $076E-$0704
	.DB $07E0-$076E
	.DB $0858-$07E0
	.DB $08D6-$0858
	.DB $095C-$08D6
	.DB $09EC-$095C
	.DB $0A82-$09EC
	.DB $0B22-$0A82
	.DB $0BCC-$0B22
	.DB $0C80-$0BCC
	.DB $0D3E-$0C80
	.DB $07E0*2/256,$07E0*2
	.DB $0858-$07E0
	.DB $08E0-$0858
	.DB $0960-$08E0
	.DB $09F0-$0960
	.DB $0A88-$09F0
	.DB $0B28-$0A88
	.DB $0BD8-$0B28
	.DB $0C80-$0BD8
	.DB $0D60-$0C80
	.DB $0E10-$0D60
	.DB $0EF8-$0E10
;
;Release 0 steps:
;02/27/2005
;Merging PT2 and PT3 players; debug
;02/28/2005
;debug; optimization
;03/01/2005
;Migration to SjASM; conditional assembly (ZX, MSX and
;visualization)
;03/03/2005
;SETPORT subprogram (35 bytes shorter)
;03/05/2005
;fixed CurPosCounter error
;03/06/2005
;Added ACB and BAC channels swapper (for Spectre); more cond.
;assembly keys; optimization
;Release 1 steps:
;04/15/2005
;Removed loop bit resetting for no loop build (5 bytes shorter)
;04/30/2007
;New 1.xx and 2.xx interpretation for PT 3.7+.

;Tests in IMMATION TESTER V1.0 by Andy Man/POS
;(for minimal build)
;Module name/author	Min tacts	Max tacts
;PT3 (a little slower than standalone player)
;Spleen/Nik-O		1720		9368
;Chuta/Miguel		1720		9656
;Zhara/Macros		4536		8792
;PT2 (more slower than standalone player)
;Epilogue/Nik-O		3928		10232
;NY tHEMEs/zHenYa	3848		9208
;GUEST 4/Alex Job	2824		9352
;KickDB/Fatal Snipe	1720		9880

;Size (minimal build for ZX Spectrum):
;Code block $7B9 bytes
;Variables $21D bytes (can be stripped)
;Size in RAM $7B9+$21D=$9D6 (2518) bytes

;Notes:
;Pro Tracker 3.4r can not be detected by header, so PT3.4r tone
;tables realy used only for modules of 3.3 and older versions.
;
;===============================================================================
; MYM Player Routines
;===============================================================================
;
; MYMPLAY - Player for MYM-tunes
; MSX-version by Marq/Lieves!Tuore & Fit 30.1.2000
;
; 1.2.2000  - Added the disk loader. Thanks to Yzi & Plaque for examples.
; 7.2.2000  - Removed one unpack window -> freed 1.7kB memory
;
; Source suitable for Table-driven assembler (TASM), sorry all
; Devpac freaks :v/

FRAG    .equ    128     ; Fragment size
REGS    .equ    14      ; Number of PSG registers
FBITS   .equ    7       ; Bits needed to store fragment offset
;
mymini  exx                     ; Starting values for procedure readbits
        ld      e,1
        ld      d,0
        ld      hl,data
        exx

        ld      hl,uncomp+FRAG  ; Starting values for the playing variables
        ld      (dest1),hl
        ld      (dest2),hl
        ld      (psource),hl
        ld      a,FRAG
        ld      (played),a
        ld      hl,0
        ld      (prows),hl
;
; *** Unpack a fragment. Returns IY=new playing position for VBI
extract:
        ld      a,0
regloop:
        push    af
        ld      c,a
        ld      b,0
        ld      hl,regbits      ; D=Bits in this PSG register
        add     hl,bc
        ld      d,(hl)
        ld      hl,current      ; E=Current value of a PSG register
        add     hl,bc
        ld      e,(hl)

        ld      bc,FRAG*3
        ld      hl,(dest1)      ; IX=Destination 1
        ld      ix,(dest1)
        add     hl,bc
        ld      (dest1),hl
        ld      hl,(dest2)      ; HL=Destination 2
        push    hl
        add     hl,bc
        ld      (dest2),hl
        pop     hl

        ex      af,af'
        ld      a,FRAG          ; AF'=fragment end counter
        ex      af,af'
        ld      a,1             ; Get fragment bit
        call    readbits
        or      a
        jr      nz,compfrag     ; 1=Compressed fragment, 0=Unchanged

        ld      b,FRAG          ; Unchanged fragment: just set all to E
sweep:  ld      (hl),e
        inc     hl
        ld      (ix),e
        inc     ix
        djnz    sweep
        jp      nextreg

compfrag:                       ; Compressed fragment
        ld      a,1
        call    readbits
        or      a
        jr      nz,notprev      ; 0=Previous register value, 1=raw/compressed

        ld      (hl),e          ; Unchanged register
        inc     hl
        ld      (ix),e
        inc     ix
        ex      af,af'
        dec     a
        ex      af,af'
        jp      nextbit

notprev:
        ld      a,1
        call    readbits
        or      a
        jr      z,packed        ; 0=compressed data, 1=raw data

        ld      a,d             ; Raw data, read regbits[i] bits
        call    readbits
        ld      e,a
        ld      (hl),a
        inc     hl
        ld      (ix),a
        inc     ix
        ex      af,af'
        dec     a
        ex      af,af'
        jp      nextbit

packed: ld      a,FBITS         ; Reference to previous data:
        call    readbits        ; Read the offset
        ld      c,a
        ld      a,FBITS         ; Read the number of bytes
        call    readbits
        ld      b,a

        push    hl
        push    bc
        ld      bc,-FRAG
        add     hl,bc
        pop     bc
        ld      a,b
        ld      b,0
        add     hl,bc
        ld      b,a
        push    hl
        pop     iy              ; IY=source address
        pop     hl

        inc     b
copy:   ld      a,(iy)          ; Copy from previous data
        inc     iy
        ld      e,a             ; Set current value
        ld      (hl),a
        inc     hl
        ld      (ix),a
        inc     ix
        ex      af,af'
        dec     a
        ex      af,af'
        djnz    copy

nextbit:
        ex      af,af'          ; If AF'=0 then fragment is done
        ld      c,a
        ex      af,af'
        ld      a,c
        or      a
        jp      nz,compfrag

nextreg:
        pop     af
        ld      b,0             ; Save the current value of PSG reg
        ld      c,a
        push    hl
        ld      hl,current
        add     hl,bc
        ld      (hl),e
        pop     hl

        inc     a               ; Check if all registers are done
        cp      REGS
        jp      nz,regloop

        or      a               ; Check if dest2 must be wrapped
        ld      bc,rows
        sbc     hl,bc
        jr      nz,nowrap

        ld      ix,FRAG+uncomp
        ld      hl,FRAG+uncomp
        ld      iy,(2*FRAG)+uncomp
        jr      endext

nowrap: ld      ix,uncomp
        ld      hl,(2*FRAG)+uncomp
        ld      iy,(FRAG)+uncomp

endext: ld      (dest1),ix
        ld      (dest2),hl

        ld      bc,FRAG         ; Check end-of-file. Clumsy :v/
        ld      hl,(prows)
        add     hl,bc
        ld      (prows),hl
        ld      bc,(rows)
        or      a
        sbc     hl,bc

;        jr      c,noend         ; If rows>played rows then exit
;        exx                     ; Otherwise restart
;        ld      e,1
;        ld      d,0
;        ld      hl,data
;        exx
;        ld      hl,0
;        ld      (prows),hl

noend:  ret

; *** Reads A bits from data, returns bits in A
readbits:
        exx
        ld      b,a
        ld      c,0

onebit: sla     c               ; Get one bit at a time
        rrc     e
        jr      nc,nonew        ; Wrap the AND value
        ld      d,(hl)
        inc     hl

nonew:  ld      a,e
        and     d
        jr      z,zero
        inc     c
zero:   djnz    onebit

        ld      a,c
        exx
        ret

; *** Update PSG registers
upsg:
	ISHBIOS
	JR	Z, upsg0
	ERRWITHMSG(MSGERR)

upsg0:
	di
	call	SLOWIO

upsg1:	ld	hl,(psource)
	ld	de,(PORTS)	; E := RSEL, D := RDAT
        xor     a

psglp:	ld	c, e		; C := RSEL
	out	(c), a		; Select register
	ld	c, d		; C := RDAT
	
	; ugliness for nabu!  we need to keep bit 7 = 0, and bit 6 = 1
	; for psg reg 7
	cp	7		; psg reg 7?
	jr	nz,psglp1	; if not, skip special processing
	push	af		; save af
	ld	a,(hl)		; get value byte
	and	%00111111	; fix bits 6 & 7
	or	%01000000	; ... for NABU!
	out	(c),a		; send the fixed value
	dec	b		; simulate the rest
	inc	hl		; ... of outi
	pop	af		; restore af
	jr	psglp2		; resume loop

psglp1:	outi			; Set register value
psglp2:	inc	a		; Next register

        ld      bc, (3 * FRAG) - 1   ; Bytes to skip before next reg-1
        add     hl, bc		; Update HL
        cp      REGS-1          ; Check for next to last register?
        jr      nz,psglp        ; If not, loop

        ld      a, $FF		; Prepare to check for $FF value
        cp      (hl)            ; If last reg (13) is $FF
        jr      z, notrig	; ... then don't output
        ld      a, 13		; Register 13
	ld	c, e		; C := RSEL
	out	(c), a		; Select register
	ld	c, d		; C := RDAT
        outi			; Set register value

notrig:	ld      hl,(psource)
        inc     hl
        ld      (psource),hl
        ld      a,(played)
        or      a
        jr      z,endint
        dec     a
        ld      (played),a

endint:	call	NORMIO
	ei
	ret			; And done

; *** Program data
played	.db	0       	; VBI counter
dest1	.dw	0       	; Uncompress destination 1
dest2	.dw	0       	; - " -                  2
psource	.dw	0       	; Playing offset for the VB-player
prows	.dw	0       	; Rows played so far

; Bits per PSG register
regbits	.db	8,4,8,4,8,4,5,8,5,5,5,8,8,8
; Current values of PSG registers
current	.db	0,0,0,0,0,0,0,0,0,0,0,0,0,0
;
;===============================================================================
;===============================================================================
; PTx/MYM Shared Heap Storage
;===============================================================================
;===============================================================================
;
; Note that two different storage layouts are defined below.  One for PTx and
; one for MYM.  They share the same storage area starting at the HEAP marker,
; but only one defintion will be active depending on the type of file
; being played.
;
HEAP	.EQU	$
;
;===============================================================================
; PTx Player Storage
;===============================================================================
;
	.ORG	HEAP
;
;vars from here can be stripped
;you can move VARS to any other address

VARS

ChanA	.DS	CHP
ChanB	.DS	CHP
ChanC	.DS	CHP

;GlobalVars
DelyCnt	.DS	1
CurESld	.DS	2
CurEDel	.DS	1
Ns_Base_AddToNs
Ns_Base	.DS	1
AddToNs	.DS	1

AYREGS

VT_	.DS	256	;CreatedVolumeTableAddress

EnvBase	.EQU	VT_+14

T1_	.EQU	VT_+16	;Tone tables data depacked here

T_OLD_1	.EQU	T1_
T_OLD_2	.EQU	T_OLD_1+24
T_OLD_3	.EQU	T_OLD_2+24
T_OLD_0	.EQU	T_OLD_3+2
T_NEW_0	.EQU	T_OLD_0
T_NEW_1	.EQU	T_OLD_1
T_NEW_2	.EQU	T_NEW_0+24
T_NEW_3	.EQU	T_OLD_3

PT2EMPTYORN	.EQU VT_+31	;1,0,0 sequence

NT_	.DS	192	;CreatedNoteTableAddress

;local var
Ampl	.EQU	AYREGS+AmplC

VAR0END	.EQU	VT_+16 ;INIT zeroes from VARS to VAR0END-1

VARSEND .EQU	$
;
; Reserve context buffers for TurboSound-packed PT3 playback.
; We only need to save/restore the dynamic state region, not the full tables.
; Dynamic region ends at VAR0END (= VT_+16).
;
PTX_CTXSIZ .EQU	VAR0END - VARS
TS_CTXTMPL_VARS	.DS	PTX_CTXSIZ
TS_CTXTMPL_PATCH	.DS	PTX_PATCHSZ
TS_CTX1_VARS	.DS	PTX_CTXSIZ
TS_CTX1_PATCH	.DS	PTX_PATCHSZ
TS_CTX2_VARS	.DS	PTX_CTXSIZ
TS_CTX2_PATCH	.DS	PTX_PATCHSZ

MDLADDR .EQU	$
vgmdata .EQU	MDLADDR		; VGM data stream loaded here (same as PT3 load address)
;
;===============================================================================
; MYM Player Storage
;===============================================================================
;
	.ORG	HEAP
; Reserve room for uncompressed data
uncomp:
	.DS	(3*FRAG*REGS)

; The tune is stored here
rows:
	.DS	2	; WORD value
data:
;
;===============================================================================
	.END



















