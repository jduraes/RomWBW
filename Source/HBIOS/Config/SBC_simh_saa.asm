;
;==================================================================================================
;   ROMWBW CUSTOM BUILD: SBC SIMH + SAA1099 DRIVER (PRE-FLASH SMOKE TEST)
;==================================================================================================
;
; INHERITS SBC_simh_std AND ENABLES THE SAA1099 SOUND DRIVER.
; THE SAA1099 HARDWARE IS NOT EMULATED BY SIMH; THE DRIVER IS WRITE-ONLY
; AND REGISTERS UNCONDITIONALLY, SO THIS BUILD VERIFIES THE DRIVER DOES
; NOT CRASH/HANG HBIOS INIT (BRICK PROTECTION FOR REAL FLASHES).
;
; BUILD:  Source\HBIOS\Build.cmd SBC simh_saa sbc_simhsaa
; RUN:    Tools\simh\Sim.cmd sbc_simhsaa
;
#INCLUDE "Config/SBC_simh_std.asm"
;
SAAENABLE	.SET	TRUE		; SAA: ENABLE SAA1099 SOUND DRIVER (SMOKE TEST)
SAABASE		.SET	$75		; SAA: MATCHES RE-JUMPERED CARD ($75/$74, Z180-SAFE)
