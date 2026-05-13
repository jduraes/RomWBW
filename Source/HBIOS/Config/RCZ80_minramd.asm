;
;==================================================================================================
;   RCZ80: same drivers/options as RCZ80_std, 64KB RAM disk + large APP pool
;==================================================================================================
;
; Keeps the MD RAM drive (2 banks = 64KB) so CP/M automount drive letters match RCZ80_std.
; RAMD_BNKS = RAMBANKS - APP_BNKS - RAM_BNKS_RSVD (16 - 9 - 5 = 2 banks).
;
; Output images use 8.3 basename rcz80min.rom / .upd / .com (see Build.ps1).
;
; Build (from RomWBW Source directory):
;   BuildROM.cmd RCZ80 minramd
; or from Source\HBIOS:
;   Build.cmd RCZ80 minramd
;
#DEFINE PLATFORM_NAME	"RCBus Z80, 64KB RAM disk + large APP pool", " [", CONFIG, "]"
#DEFINE AUTO_CMD	""		; AUTO CMD WHEN BOOT_TIMEOUT IS ENABLED
#DEFINE DEFSERCFG	SER_115200_8N1 | SER_RTS	; DEFAULT SERIAL CONFIGURATION
;
#INCLUDE "cfg_RCZ80.asm"
;
#INCLUDE "Config/RCZ80_std_postcfg.asm"
;
APP_BNKS	.SET	9		; 9 APP banks -> RAMD_BNKS=2 (64KB RAM disk)
