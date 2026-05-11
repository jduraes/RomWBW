;
;==================================================================================================
;   ROMWBW BUILD SETTINGS FOR SBC+SIMH VIBETUNE VALIDATION
;==================================================================================================
;
; This build is intended for simulator-only VibeTune validation where no real
; sound hardware is present. It forces an AY device in HBIOS so VTUNE --HBIOS
; can execute playback code paths.
;
#INCLUDE "Config/SBC_simh_std.asm"
;
APP_BNKS	.SET	8		; reserve app banks explicitly for VTUNE MMU tests
AY38910ENABLE	.SET	TRUE		; AY: enable AY-3-8910 / YM2149 driver
AYMODE		.SET	AYMODE_MSX	; AY: use MSX-style ports for consistency
AY_FORCE	.SET	TRUE		; AY: bypass hardware auto-detect in simulator
