;
; Hardware IO port configuration - single source of truth for all music engine IO.
;
; Organized by hardware platform and music engine chip.
;
PORT_NONE		.EQU	0FFH		; generic "not present" sentinel for optional ports/fields

;=============================================================================
; AY-3-8910 (PSG) Port Sets — one for each supported hardware variant
;=============================================================================

; MSX Standard Ports
PSG_MSX_RSEL	.EQU	0A0H		; register select
PSG_MSX_RDAT	.EQU	0A1H		; register data
PSG_MSX_RIN		.EQU	0A2H		; register input (readback)

; Coleco Standard Ports (also MSX Coleco cartridge variant)
PSG_COLECO_RSEL	.EQU	050H
PSG_COLECO_RDAT	.EQU	051H
PSG_COLECO_RIN	.EQU	052H

; RC2014/EB6 Sound Module Ports
PSG_RCEB_RSEL	.EQU	0D8H
PSG_RCEB_RDAT	.EQU	0D0H
PSG_RCEB_RIN	.EQU	0D8H

; RC2014/MF Sound Module Ports
PSG_RCMF_RSEL	.EQU	0D1H
PSG_RCMF_RDAT	.EQU	0D0H
PSG_RCMF_RIN	.EQU	0D0H

;=============================================================================
; YM2151 (OPM) Port Sets — two variants depending on board mapping
;=============================================================================

; YM2151 Primary Mapping (board at 0xFF-0x20 range)
YM2151_PRIMARY_SEL		.EQU	0DEH	; register select
YM2151_PRIMARY_DAT		.EQU	0DFH	; data write

; YM2151 Alternate Mapping (0xFF-0x20 remapped)
YM2151_ALT_SEL			.EQU	0FEH	; alternate register select
YM2151_ALT_DAT			.EQU	0FFH	; alternate data write

; Secondary YM2151 (undefined on RCBUS, reserved for future use)
YM2151_SECONDARY_SEL	.EQU	000H	; not defined on current hardware
YM2151_SECONDARY_DAT	.EQU	YM2151_SECONDARY_SEL	; not defined on current hardware

;=============================================================================
; OPL3 (YM3526/YM3812) Port Set — FIXED for all platforms
;=============================================================================

OPL3_BANK1_ADDR	.EQU	090H
OPL3_BANK1_DATA	.EQU	091H
OPL3_BANK2_ADDR	.EQU	092H
OPL3_BANK2_DATA	.EQU	093H

;=============================================================================
; SN76489 (PSG variant) Port Set — FIXED for RC2014 systems
;=============================================================================

SN76489_PRIMARY		.EQU	0FFH	; RCBUS SNMODE_RC primary chip
SN76489_SECONDARY	.EQU	0FBH	; RCBUS SNMODE_RC secondary chip

;=============================================================================
; AY-3-8910 (PSG) Additional Platform Port Sets
;=============================================================================

; SBC/MK4 SCG (Sound Card Grand) Ports
PSG_SCG_RSEL	.EQU	09AH		; register select
PSG_SCG_RDAT	.EQU	09BH		; register data
PSG_SCG_RIN		.EQU	09AH		; register input (same port as RSEL on SCG)

; Nhyodyne N8 Onboard PSG Ports
PSG_N8_RSEL		.EQU	09CH
PSG_N8_RDAT		.EQU	09DH
PSG_N8_RIN		.EQU	09CH

; RC2014/EB6 with Z180 port offset (RCZ180 / SCZ180)
PSG_RCEB_Z180_RSEL	.EQU	068H
PSG_RCEB_Z180_RDAT	.EQU	060H
PSG_RCEB_Z180_RIN	.EQU	068H

; RC2014/MF with Z180 port offset (RCZ180 / SCZ180)
PSG_RCMF_Z180_RSEL	.EQU	061H
PSG_RCMF_Z180_RDAT	.EQU	060H
PSG_RCMF_Z180_RIN	.EQU	060H

; LINC Sound Module Ports
PSG_LINC_RSEL	.EQU	033H
PSG_LINC_RDAT	.EQU	032H
PSG_LINC_RIN	.EQU	032H

; MBC Ports (RIN reads back from RSEL port, unlike MSX standard)
PSG_MBC_RSEL	.EQU	0A0H		; same address as MSX RSEL
PSG_MBC_RDAT	.EQU	0A1H		; same address as MSX RDAT
PSG_MBC_RIN		.EQU	0A0H		; differs from MSX (A2); reads back via RSEL

; Duodyne Ports
PSG_DUO_RSEL	.EQU	0A4H
PSG_DUO_RDAT	.EQU	0A5H
PSG_DUO_RIN		.EQU	0A4H

; NABU Ports
PSG_NABU_RSEL	.EQU	041H
PSG_NABU_RDAT	.EQU	040H
PSG_NABU_RIN	.EQU	040H

;=============================================================================
; Packed RDAT:RSEL port words — used in LD HL/BC/DE for TurboSound port setup
; Layout: high byte = RDAT, low byte = RSEL  (matches PORTS memory layout)
;=============================================================================

PSG_MSX_PORTW    .EQU    PSG_MSX_RDAT * 256 + PSG_MSX_RSEL          ; $A1A0 (MSX standard)
PSG_COLECO_PORTW .EQU    PSG_COLECO_RDAT * 256 + PSG_COLECO_RSEL    ; $5150 (Coleco standard)
PSG_RCEB_PORTW   .EQU    PSG_RCEB_RDAT * 256 + PSG_RCEB_RSEL        ; $D0D8 (RC2014/EB6)
PSG_RCMF_PORTW   .EQU    PSG_RCMF_RDAT * 256 + PSG_RCMF_RSEL        ; $D0D1 (RC2014/MF)
PSG_RCEB_Z180_PORTW .EQU PSG_RCEB_Z180_RDAT * 256 + PSG_RCEB_Z180_RSEL ; $6068 (RCZ180/SCZ180 EB)
PSG_RCMF_Z180_PORTW .EQU PSG_RCMF_Z180_RDAT * 256 + PSG_RCMF_Z180_RSEL ; $6061 (RCZ180/SCZ180 MF)

; RomWBW HBIOS platform ids (from hbios.inc)
PLT_RCZ180		.EQU	8
PLT_SCZ180		.EQU	10

;=============================================================================
; Z180 Wait-State Register Base Port (CFGTBL field 5)
;=============================================================================

Z180_NONE		.EQU	PORT_NONE	; no Z180 wait-state register (standard Z80)
Z180_N8			.EQU	040H		; Nhyodyne N8VDP Z180 base
Z180_RCZ180		.EQU	0C0H		; RCZ180 / SCZ180 base

;=============================================================================
; ACR (Auxiliary Control Register) Port and Enable Values (CFGTBL fields 6-7)
;=============================================================================

ACR_NONE		.EQU	PORT_NONE	; no ACR / field unused
ACR_SCG			.EQU	09CH		; SBC / MK4 SCG ACR port
ACR_MBC			.EQU	0A2H		; MBC ACR port
ACR_DUO			.EQU	0A6H		; Duodyne ACR port
ACRVAL_NONE		.EQU	PORT_NONE	; ACRVAL field unused
ACRVAL_ENABLE	.EQU	0FEH		; value written to ACR to enable sound output
