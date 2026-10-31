; Shared local macro shorthands for VibeTune source modules.
; Keep common one-line expansions centralized for readability and consistency.
#DEFINE ISHBIOS			LD	A, (HBIOSMD) \\ OR A
#DEFINE PRTSTRDE(X)		LD	DE, X \\ CALL PRTSTR
#DEFINE PRTCRLF			CALL	CRLF
#DEFINE ERRWITHMSG(X)	LD	DE, X \\ JP ERR
