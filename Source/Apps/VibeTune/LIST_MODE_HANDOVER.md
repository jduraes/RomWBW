# VibeTune handover — single-file PT3 crash (May 2026)

**Build under test:** working tree **v0.1b183** (this session's diagnostic builds; NOT reverted).
**Supersedes** the prior "restore to b170" plan — current sources contain b181 DI/EI + b182/b183 diagnostics described below.
**Hardware:** SC126, RCBus Sound Module (EB), **timer mode**, CPU 18.432 MHz, ANSI terminal, drive F3.

## User-visible goal

- Single-file **`vtune attack`** and **`vtune rl2wof`** must play on SC126 like the reference player does.
- Reference: **Tune.COM v3.16 (5-Feb-2026)** plays `rl2wof` fine on the *same* SC126 (user-confirmed). VibeTune shares Tune's Bulba PT2/PT3 core.
- Vortex Tracker II PT3 headers are valid; **do not reject them**.

## Current symptom (b183)

| File | Size/ver | b183 result |
|------|----------|-------------|
| `attack.pt3` | 2302 B, v6, nPos=20, loop=19, patTbl@222 | **plays fine**, then ` Done` (no visible "Playing…" — overwritten by in-place clear) |
| `rl2wof.pt3` | 4096 B, v7, nPos=26, loop=0, patTbl@228 | ` Done`, **no audio, no crash** (was a hard hang/crash in b180/b181) |

## LEADING ROOT-CAUSE HYPOTHESIS (new this session — verify next)

**Single-file PT3 is routing through the TurboSound path `PTXINITT`, not the Tune-style `PTXINITN`.**

Evidence: `DBG_DUMP_STATE` (which ends in `JP 0`) was placed inside **`PTXINITN`** (`ptx_runtime.inc:59`). If reached, the program would exit to CP/M. **attack still plays** ⇒ `PTXINITN` is never reached ⇒ both files fall through to **`PTXINITT`** (`ptx_runtime.inc:49`). Reaching `PTXINITT` requires **`TSFLAG`≠0 AND `TS_DUALHW`≠0** (dispatch at `ptx_runtime.inc:38–48`).

So on this single-AY SC126, single-file PT3 plays via `TS_INIT` / `TS_PLAYQUARK` (dual-instance machinery). attack survives that path; `rl2wof` does not. This — not the shared core — is the divergence from Tune.

**Next diagnostic step:** move the dump to **before** the TS branch (after `PRTSONGMETA`, ~`ptx_runtime.inc:37`) and also print `TSFLAG` and `TS_DUALHW`, then `JP 0`. Confirm both non-zero. Then fix whichever is wrongly set:
- `TSFLAG` set by **`TS_DETECT`** (`ts_runtime.inc:246`) — scans loaded module for footer `PT3!<off2>PT3!<len2>02TS`; on match sets `TSFLAG`/`TS_OFF2`/`TS_LEN2`. Could **false-match** inside plain-PT3 data of `rl2wof`/`attack`.
- `TS_DUALHW` set in **`hwcfg.inc:546` / `:617`** (hardware probe; "two distinct port sets"). Should stay 0 on single-AY EB. (b163 previously fixed a "false dual TS on SC126" — possible regression.)

Goal of fix: single-AY single-file PT3 must use **`PTXINITN`** (`CALL START` → `START+5` loop), identical to Tune.

## Confirmed facts (do not re-litigate)

- **Player core is byte-identical to Tune** (verified by normalized diff): `INIT`, tone depacker `TS_DEPACK_TP`, `TS_NTVT_START` (note+vol tables, stack-balanced), decoder `PTDECOD`→`CHREGS`→`SETSAM/SETORN` (637 lines), `PLAY`, `ROUT`, data tables `T_PACK`/`NT_DATA`. The only diff was cosmetic (`SPCCOMS-$20E0` == `SPCCOMS+$FF20-$2000`).
- **`rl2wof` is valid PT3** and **loads fully**: `MDLADDR=0x5EFA`, ends `0x6EFA`; `HEAP=VARS=0x5AFA`, `HEAPEND=0xC000`. Stack/BDOS are high — **no stack/module collision**.
- **Load is not truncated** (32×128 = 4096; ceiling check `HEAPEND>>8`=0xC0 never hit).
- `PT3_SANITIZE_BUF` is a **no-op** for a single file (`PREVLOADBYTES=0`).
- INIT completes (metadata correct; "Playing…" reached) — the failure is at/after the first quark **on the TS path**.

## Rejected / ruled out this session (with why)

- **Interrupt-during-SP-swap corruption** — *disproven*. b181 added `DI`/`EI` around all three module-borrow `SP`-swaps; `rl2wof` behavior was **unchanged**. (Edits still in tree at `PLAY`/`PSP_`, `CHREGS`/`CSP_`, `PD_RES`/`PDSP_` in `vibetune.asm`.) Decide: keep as harmless hardening or revert for strict Tune parity.
- **Truncated load / heap ceiling** — ruled out (full 4096 B loads).
- **Stack/BDOS collision** — ruled out by addresses (module top 0x6EFA ≪ stack).
- **Player-core difference / version-7 handling** — ruled out (byte-identical, version path identical).
- **Module-data corruption by wrapper** (`META_SNAPSHOT`, `_LDX0` clears) — those only read the module / touch low data-section vars, not the module body.
- (Historical, prior session) Rejecting Vortex headers; forcing delay mode on SC126; `PRTPLAYMSG` reorder (b180); SETUP bit7/bit0 loop hack (b180) — all rejected/ineffective.

## Diagnostic instrumentation TO REMOVE before any release build

- `ptx_runtime.inc` (in `PTXINITN`): line `CALL DBG_DUMP_STATE`.
- `vibetune.asm` (after `INIT_RUNTIME_FLAGS`): `DBG_SPSAV .DW 0`, routine `DBG_DUMP_STATE` (ends `JP 0`), and strings `DBGTAG/DBGMA/DBGLB/DBGEND/DBGSP/DBGHE/DBGPP/DBGP0`.
- Note: with `JP 0` present, **playback never runs** from `PTXINITN`; this is only why we proved the path.

## Build / agent rules

- Before `Build.cmd`: bump `#DEFINE VTBANREL "bNNN"` (now **b183**) and keep `MSGBAN` date `dd-MMM-yyyy` (current OS date) in `vibetune.asm` only. Do **not** add version/date logic to `Build.cmd`.
- Do **not** touch RomWBW-wide release files (`Source/ver.inc`, root notes).
- Do not `CALL START` on resume (restarts song). Do not change `Build.cmd`/TASM flags unless asked.
- `Build.cmd` assembles with TASM (0 errors expected), copies `vtune.com` + `Tunes\*` to the deploy target the user runs from (banner confirms the running build).

## Key files / symbols

- Dispatch & loop: `ptx_runtime.inc` — `GOPTX` (TS branch 38–48), `PTXINITT` (49), `PTXINITN` (55), `PTXLP` (84+).
- TS detect/init: `ts_runtime.inc` — `TS_DETECT` (246, sets `TSFLAG`), `TS_INIT`, `TS_PLAYQUARK`.
- HW probe: `hwcfg.inc` — `TS_DUALHW` set at 546/617.
- Core player: `vibetune.asm` — `START`(3506)/`INIT`(3562), `PLAY`(~4600), `CHREGS`(~4400), `ROUT`(~4760), tables `NT_DATA`/`T_PACK`(~4990).
- Load/dispatch: `vibetune.asm` — `_LD0`/`_LD`(373–435), `_LDX`/`_LDX0`(663–735), `BUF_IS_PTX`(758).
- Reference: `..\Tune\tune.asm` / `..\Tune\tune.com` (v3.16) — same-era apples-to-apples.

## Open / verify on hardware

- [ ] Confirm `TSFLAG` and `TS_DUALHW` values for single-file PT3 on SC126 (move dump before TS branch).
- [ ] Fix so single-AY single-file PT3 takes `PTXINITN`; re-test `attack` + `rl2wof` (+ larger `Sanxion.pt3` 12465 B).
- [ ] Remove DBG instrumentation; decide on b181 DI/EI keep-vs-revert.
- [ ] Then revisit `-list` mode (arrow nav, space pause, Esc) on SC126/RC2014.
