;
; HBCONFIG TEST FIXTURE - broken rules (expect exit 1, 2 broken)
;
#INCLUDE "fx_std.asm"
;
FOOENABLE   .SET    TRUE      ; FOO on but neither BAR nor BAZ
BARENABLE   .SET    FALSE
BAZENABLE   .SET    FALSE
