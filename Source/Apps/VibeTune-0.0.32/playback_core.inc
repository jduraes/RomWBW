;
; Playback core dispatcher stubs.
; These wrappers provide a stable module boundary while key-control internals
; remain in keyctl.inc during incremental refactor.
;

; Shared key poll entry point.
; In:  D bit7 = 0 play, 1 pause
; Out: B/C contract from KEY_POLL_CORE
PLAYBACK_POLL_ACTION:
	JP	KEY_POLL_CORE

; Shared action dispatch entry point.
; In:  A = KEYACT_*, E = mapped nav key
;      D bit7 = 0 play, 1 pause
;      D bit0 = 0 PTX/MYM metadata, 1 VGM metadata
; Out: B = 0 continue loop, 1 exit loop
PLAYBACK_HANDLE_ACTION:
	JP	KEY_HANDLE_ACTION

; Shared pause-loop step handler.
; In:  D bit7 = 1 (pause context), D bit0 = metadata mode
; Out: B = 0 continue paused loop, B = 2 resume playback, B = 3 exit playback
PLAYBACK_PAUSE_STEP:
	CALL	PLAYBACK_POLL_ACTION
	LD	A,B
	OR	A
	RET	Z
	CP	1
	JR	Z,PLAYBACK_PAUSE_STEP_RESUME
	CP	2
	JR	NZ,PLAYBACK_PAUSE_STEP_ACT
	CALL	KEY_DELETE_ATTEMPT
	JR	Z,PLAYBACK_PAUSE_STEP_NONE
	LD	B,3
	RET
PLAYBACK_PAUSE_STEP_ACT:
	LD	A,C
	CALL	PLAYBACK_HANDLE_ACTION
	LD	A,B
	OR	A
	JR	Z,PLAYBACK_PAUSE_STEP_NONE
	LD	B,3
	RET
PLAYBACK_PAUSE_STEP_RESUME:
	CALL	KEY_PAUSE_OFF
	JR	NZ,PLAYBACK_PAUSE_STEP_EXIT
	LD	B,2
	RET
PLAYBACK_PAUSE_STEP_EXIT:
	LD	B,3
	RET
PLAYBACK_PAUSE_STEP_NONE:
	XOR	A
	LD	B,A
	RET

; Shared normal-play loop step handler.
; In:  D bit7 = 0 (play context), D bit0 = metadata mode
; Out: B = 0 continue playback loop, B = 2 enter pause loop, B = 3 exit playback
PLAYBACK_PLAY_STEP:
	CALL	PLAYBACK_POLL_ACTION
	LD	A,B
	OR	A
	RET	Z
	CP	1
	JR	Z,PLAYBACK_PLAY_STEP_PAUSE
	CP	2
	JR	NZ,PLAYBACK_PLAY_STEP_NONDEL
	CALL	KEY_DELETE_ATTEMPT
	JR	Z,PLAYBACK_PLAY_STEP_NONE
	LD	B,3
	RET
PLAYBACK_PLAY_STEP_NONDEL:
	CP	4
	JR	NZ,PLAYBACK_PLAY_STEP_ACT
	CALL	KEY_SET_STOPREQ
	LD	B,3
	RET
PLAYBACK_PLAY_STEP_ACT:
	LD	A,C
	CALL	PLAYBACK_HANDLE_ACTION
	LD	A,B
	OR	A
	JR	Z,PLAYBACK_PLAY_STEP_NONE
	LD	B,3
	RET
PLAYBACK_PLAY_STEP_PAUSE:
	CALL	KEY_TOGGLE_PAUSE
	JR	NZ,PLAYBACK_PLAY_STEP_TO_PAUSE
	JR	PLAYBACK_PLAY_STEP_NONE
PLAYBACK_PLAY_STEP_TO_PAUSE:
	LD	B,2
	RET
PLAYBACK_PLAY_STEP_NONE:
	XOR	A
	LD	B,A
	RET
