# hbconfig - RomWBW HBIOS configuration tool

Menu-driven editor for RomWBW board configs, per the design agreed in
[RomWBW issue #722](https://github.com/wwarthen/RomWBW/issues/722)
(RULES.md / SPEC.md in that issue).  **Developed with AI assistance
(Claude)**, per Wayne's approval in the issue ("applications exception").

Optional tool: the normal build never runs it and does not need it.
Hand-edited configs keep working exactly as before.

## Build

- Windows: `Build.cmd` (needs MinGW-w64 gcc on PATH) -> `hbconfig.exe`
- Linux/macOS: `make` (any C11 compiler)

## Use

Run from the `Source/HBIOS` directory (or pass a full path):

```
hbconfig -menu  SCZ180 sc126_std       ; interactive menuconfig-style editor
hbconfig -show  Config/SCZ180_sc126_std.asm
hbconfig -check Config/SCZ180_sc126_std.asm
hbconfig -write Config/SCZ180_sc126_std.asm CTCENABLE=TRUE UARTCNT=2
```

- `-show` prints every setting differing from `cfg_MASTER.asm`, with the
  effective value, the master value, and the file that set it.
- `-check` evaluates every `;@DEPENDS` rule (RULES.md section 4).  A
  TRUE/FALSE setting is checked only when on; anything else always.
  Exit status is non-zero when a rule breaks or a tag is bad.
- `-write` applies `NAME=VALUE` edits per SPEC.md section 7: values are
  replaced in-place in the file's own `.SET` lines (rest of line kept),
  settings set back to their inherited value have their `.SET` lines
  removed, and new settings are appended in the house layout with the
  master comment.  Everything else stays byte-identical (including line
  endings and blank lines).  All writes go through a temp file + rename.
- `-menu` edits in memory and writes on `s`; it never touches
  `cfg_MASTER.asm` or `cfg_<platform>.asm`.

## Tests

```
bash tests/run-corpus.sh    ; parse all in-tree HBIOS configs
bash tests/test-tags.sh     ; ;@DEPENDS engine fixtures
bash tests/test-write.sh    ; writer fixtures + byte-identical round-trip
                            ; over all 58 in-tree configs (git stays clean)
```

## Status / known limitations

- M1-M5 functional.  Upstream `cfg_MASTER.asm` carries no `;@DEPENDS` /
  `;@HELP` tags yet, so `-check` passes trivially on in-tree configs;
  seeding the tags is the natural follow-up upstream PR.
- Pick lists group by name prefix only; the spec's contiguous-group rule
  (`;` line separates two lists with the same prefix) is not enforced,
  and lists cap at 32 options.
- The menu shows every master setting; "relevant" filtering (SPEC.md
  section 4) covers local settings, enabled drivers, and session edits.
