;
; HBCONFIG TEST FIXTURE - bad tag (expect exit 1, 1 bad tag)
;
#INCLUDE "fx_std.asm"
;
BADTAGEG    .SET    TRUE        ; unknown name in tag ;@DEPENDS NO_SUCH_SETTING = 1
