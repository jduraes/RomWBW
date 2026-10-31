# VibeTune Handover

**Branch: `saa1099` — build v0.1.42 (19-Oct-2026)** — RomWBW live-source embed (junction).

## Session Delta (2026-10-19, RomWBW embed)

- **Goal:** RomWBW Apps builds always use this repo’s sources; keep copying `.COM` into `RomWBW/Binary/Apps` when built from here.
- **Change:** `Build.cmd` / `Makefile` dual-context path detect (`../../../Tools` when under `Source/Apps/VibeTune`, else `../RomWBW/Tools`). `-dVT_IN_ROMWBW` selects Apps-relative `#include`s (`../../ver.inc`, `../Tune/cpm.inc`, …) vs sibling `../RomWBW/Source/...`. Replaced RomWBW’s duplicate `Source/Apps/VibeTune` tree with a junction to this checkout. Registered `VibeTune` in RomWBW `Source/Apps` Build.cmd / Clean.cmd / Makefile. RomWBW `.gitignore` now ignores `Source/Apps/VibeTune/`; old vendored paths removed from RomWBW index (`git rm --cached`, not committed).
- **Version:** v0.1.42. Verified: sibling `Build.cmd` and junction `Source/Apps/VibeTune\Build.cmd` both TASM 0 errors → `Binary/Apps`. No SIMH/hardware run.

**Branch: `saa1099` — build v0.1.40 (18-Oct-2026)** — Empty-file error + classic-layout PT3 support.

## Session Delta (2026-10-18, empty file + classic PT3)

- **Fix 1 — empty files:** a 0-byte PT3 could pass LOAD_MUSIC_FILE (BDOS quirk: first read reports success with stale DMA) and die later as "invalid tune structure". Now: after open, FCB extent-0 record count (FCB_WORK+15) == 0 → new `ERR_FILE_EMPTY` → `Error: empty file.`; the post-loop size==0 case also returns ERR_FILE_EMPTY instead of ERR_FILE_READ. Playlist reload path skips silently as before.
- **Fix 2 — classic PT3 layout** (30-byte plain name at +0, signature at $1E): `VALIDATE_PTX_STRUCTURE` and `ENGINE_INIT_PTX` now try Vortex/ProTracker signatures at +0 first (compilation library files unchanged), then at $1E. The 16-byte printable-prefix gate was fatal for classic files — removed entirely (signature match is the real check; PTX_PRINTABLE_PREFIX and IS_PRINTABLE_ASCII deleted as dead code, ~55 B recovered).
- **Metadata:** `META_SNAPSHOT` re-matches the loaded module at +0; no match → classic: title = 30-byte name field at +0 (padded to 32, sanitised), author blanked (classic layout carries no reliable author field — nothing fabricated). Compilation-layout display unchanged.
- **Engine compatibility verified by source inspection (no SIMH, no board):** Bulba INIT reads header fields at module+99/100/102/103-104/105/169 — all past the $1E signature region, so classic files init identically. PT2-vs-PT3 select reads the SETUP byte (BULBA_START+10, which VibeTune forces to PT3) — NOT module+10, so name-field text cannot flip the engine into PT2 mode. One caveat: the engine's version digit comes from module+13, which in classic files is name text; non-digit → safe default Version=6 (what PT3.6 files use anyway), but a classic file with a digit as the 14th name char would select that volume-table version.
- **Desk-check (rule 6):** match routines clobber only A/DE/HL and callers reload all three; META classic path writes exactly 30+2 bytes into the 32-byte METATITLE; ERR_FILE_EMPTY flows through the existing START_LOAD_FAIL dispatch with A intact; no PUSH/POP or flag-contract changes.
- **Version:** v0.1.40 (vtune.com **14,641 B**, +78 vs v0.1.39). TASM 0 errors x2. **Not hardware-tested (bridge down):** local Tunes/*.pt3 are all compilation-layout — regression-check those plus a real classic file from the SC126's F3:.

**Branch: `saa1099` — build v0.1.39 (18-Oct-2026)** — Fix: lowercase `l` was upcased by the console-input path, making it trigger playlist loop instead of track loop.

## Session Delta (2026-10-18, l/L case fix)

- **Symptom:** pressing lowercase `l` toggled playlist loop (uppercase `L` behavior); track loop toggle unreachable from the keyboard.
- **Root cause:** `MAIN_POLL_BDOS` runs `CALL TO_UPPER` on every polled key before dispatch (needed so N/P/WASD etc. match both cases), which converted `l` → `L`; the dispatch `CP 'l'` was then dead code.
- **Fix:** skip the upcase for `l` specifically (`CP 'l'` / `JR Z, MAIN_KEY_GOT` before `CALL TO_UPPER`). All other keys keep case-insensitive matching. Desk-check: flags — `CP 'l'` sets Z only when matched; the `JR Z` consumes it; the non-match path falls into TO_UPPER whose RET flags are the pre-existing dispatch contract. Registers: A preserved through both paths.
- **Version:** v0.1.39 (vtune.com **14,563 B**). TASM 0 errors x2. No SIMH/hardware run — verify on iron: `l` = track loop, `L` = playlist loop, same key again = off; n/p/wasd/arrows unaffected.

## Session Delta (2026-10-18, nav regression hotfix)

- **Symptom (v0.1.37 regression):** in `-list` mode WASD, N/P, and arrows did nothing whenever the player was idle (NAV_DEBOUNCE=0); nav only worked mid-settle.
- **Root cause:** the factored `NAV_PREP` helper returned with flags from `NAV_SAVE_IF_IDLE`'s `OR A` on NAV_DEBOUNCE — Z when idle — so the callers' `JP Z, MAIN_LOOP_NODELAY` (meant for "no tracks", flags straight from `TRACK_COUNT_TEST` in the inline original) fired on every idle nav key. Classic flags-across-call bug: rule-6 desk-check verified registers but not the flag contract.
- **Fix (keeps the helper, +8 B):** NAV_PREP now returns A=TRACK_COUNT with NZ preserved via PUSH AF/POP AF around the save+snapshot; MAIN_NEXT/MAIN_PREV reload `TRACK_SELECTED` into A (they previously consumed the snapshot value NAV_PREP left in A). MAIN_NAV_GO needed no change (reloads UI_IDXTMP anyway).
- **Re-audited the other v0.1.37 helpers for the same class:** PRSTRL (CRLF preserves AF), GET_STATE_MSG (callers ignore flags), UI_CLR_ROW_HOME (identical inline sequence), IS_KNOWN_SWITCH_TOKEN (Z survives POP BC), SCAN_CMDLINE_SWITCHES (caller ignores flags), SET_CONFIG_TBL_HL (flag tail unchanged) — all clean.
- **Version:** v0.1.38 (vtune.com **14,559 B**). TASM 0 errors x2. No SIMH/hardware run — verify on iron: `-list` WASD/arrows/N/P nav while playing, paused, and idle.

**Branch: `saa1099` — build v0.1.37 (18-Oct-2026)** — Binary-size pass: 15,527 -> 14,551 B (-976, no behaviour change).

## Session Delta (2026-10-18, size optimisation)

- **Goal:** shrink vtune.com (15,527 B) without destabilising the ear-approved playback/mute paths. Landed at **14,551 B** (-976 B). 13 KB was never reachable without removing features; ~14.2 KB would have required touching proven playback/TS code — declined.
- **Analysis (TASM lst label spans + binary n-gram dup scan):** code 0x100-0x3300 ~12.7 KB; string table ~2.5 KB (biggest soft target); player glue (0B87-12FC, ~1.9 KB), ANSI UI ~1.8 KB, main-loop/key dispatch ~2.4 KB, TS plumbing ~1.1 KB, SAA backend ~1.2 KB. Heap (.DS past HEAP, incl. 864 B TS contexts + 448 B AYREGS) is NOT in the binary. No `tim:`/frames= debug block exists in current sources (already gone); no dead routines found (14 candidate "dead" labels all turned out to be fall-through entries).
- **String trims (-581 B):** help text 826->~450 B (terser; keys line deduped into shared MSG_PLKEYS, also the ANSI footer text); Z180 warn 320->194 B; credits 184->157 B (attribution kept); TSSTR_COLECO/TSSTR_RC merged into HW_DESC_* (identical port info); shorter delete/error/tag strings; help PSG-port lines merged into one two-line entry.
- **Code dedup (-395 B):** PRSTRL = PRTSTR+CRLF (12 sites); GET_STATE_MSG (3 identical Playing/Paused selectors); UI_CLR_ROW_HOME (5 sites; UI_CLR_ROW already preserves BC); NAV_PREP (3 nav-key preambles); PRINT_SONG_META_PLAIN reuses UI_PRT_META32; IS_KNOWN_SWITCH_TOKEN + SCAN_CMDLINE_SWITCHES table-driven (SWITCH_TOKEN_TABLE / SCAN_SW_TABLE); "Valid switches:" now printed from the token table (PRINT_SWITCH_LIST) so the list can never drift from the parser; SET_CONFIG_MSX/RC/EB_Z180/COLECO table-driven (4-port entries: chip2 $A2/$A3 on MSX preserved, EB sets Z180_IO_BASE=$C0, DE preserved via PUSH/POP to keep the original clobber contract).
- **Desk-check (rule 6):** no PUSH/POP imbalance; helpers only clobber A (+DE where noted); flags-dependent code (ansiui UI_DRAW_STATE flag-across-CALL trick) deliberately untouched; call sites re-checked for register expectations.
- **NOT touched (constraint 1):** START_EXIT_SILENCE, PSG_MUTE_ROUT, TS_MUTE_BOTH_HARDWARE, TSMOD_SELECT call sites, the O-toggle (MAIN_OUTPUT_TOGGLE/MAIN_OUT_TO_SAA), TS topology restore, all engine/timing code. `git diff` contains zero removed lines matching silence/mute patterns. Esc-exit mute and O-toggle mute paths are byte-identical.
- **Rejected:** moving zero-init emitted vars to the heap (~50 B) — TS_TOPOLOGY/TSOFF2 etc. would be re-zeroed by per-reload HEAP_CLEAR; SAA shadow-table packing (~50 B) — playback-critical.
- **Verification:** TASM 0 errors x2, sizes checked after each batch (15,527 -> 14,946 -> 14,812 -> 14,744 -> 14,602 -> 14,551). No SIMH (rule 5), no hardware run — needs an iron pass: playback AY+SAA, Esc-exit silence, O-toggle, `-help`/`-credits`/unknown-switch output, `-list` nav (N/P/arrows/Delx3/R), vtunecfg unchanged.

**Branch: `saa1099` — build v0.1.36 (18-Oct-2026)** — Second card = SAA no longer forces dual-card TS topology.

## Session Delta (2026-10-18, O-alternate orthogonality fix)

- **Symptom (regression from v0.1.35):** declaring second card = SAA1099 (the O-toggle alternate) required TS topology = dual-card, which suppressed the user's AVR-module TurboSound playback (`AY_CARD_TO_TS2` rejects id 5 → `TS_DUALHW`=0 → single chip).
- **Root cause (vtunecfg):** `TCFG_ASK_CARD2` was only invoked under dual-card topology, and `TCFG_ASK_TS_AUTO`/`TCFG_ASK_TS_MOD` actively zeroed `CFG_CARD2` — the only way to keep byte 7 = 5 was to force byte 5 = dual-card.
- **Fix (vtunecfg):** second card = SAA is now orthogonal to TS topology. New `TCFG_ASK_OUTALT` prompt (S=SAA1099, N=none) runs for auto/module topologies; normalizes a stale non-SAA `CFG_CARD2` (leftover dual-card second AY) to none. Auto/module TS answers no longer zero `CFG_CARD2`. Summary prints a new `  O alternate:` line when a non-dual topology has card2=5.
- **Fix (vtune, heal for v0.1.35-written CFGs):** `TS_PORTS_SETUP_AY` now treats dual-card topology + card2 = SAA (5) as the AVR-module probe — card2=5 can never be a TS second AY, so the reinterpretation is safe; no need to re-run vtunecfg to recover module playback. (Re-running vtunecfg and answering the TS prompt cleans the CFG anyway.)
- **Desk-check (rule 6):** `TCFG_ASK_OUTALT` mirrors `TCFG_ASK_TS` (same clobber set; caller preserves nothing). vtune insertion reloads A from `CFG_AY_CARD2` after the topology compares; `TS_PORTS_CFG_DUAL` reloads it again itself. No PUSH/POP or flag-across-call changes.
- **Version:** v0.1.36. Build: TASM 0 errors x2 (vtune.com + vtunecfg.com). No SIMH (rule 5), no hardware run — verify on iron: CFG TS=M + O alternate=S → AVR-module TS dual playback intact, `O` toggles to SAA and back.

**Branch: `saa1099` — build v0.1.35 (18-Oct-2026)** — O toggle gated both directions; SAA accepted as CFG second card.

## Session Delta (2026-10-18, O-toggle symmetric gating)

- **Why:** v0.1.34 allowed AY->SAA unconditionally (writes to $74/$75 into the void when no SAA fitted) while SAA->AY required a known AY. User wants both directions gated.
- **Rule now:** `O` toggles only when both sides are known. AY known = existing startup detect chain (`OUT_AY_AV`, CLI/CFG/HBIOS/probe, not the bare MSX fallback). SAA known = explicitly configured (`OUT_SAA_AV`): `-saa`, or VTUNE.CFG primary (byte 6) or second card (byte 7) = 5 — the chip is write-only, no probe possible. Refusal shows the same "Output: no alternate output available" note and changes nothing.
- **CFG/vtunecfg:** byte 7 now accepts 5 = SAA1099 as an O-toggle alternate (clamps `CP 5` -> `CP 6` in both `vtune` DETECT_DISP_C2 and `vtunecfg` CFG_LOAD_C2). It is never a TS second chip — `AY_CARD_TO_TS2` still rejects id 5, so a dual-card TS config with second=SAA plays single AY. vtunecfg second-card menu accepts `S` (same-card guard rejects S==S); primary menu's stale `$FF/$FE` SAA ports corrected to `$75/$74`.
- **New code:** `OUT_COMPUTE_SAA_AV` (called at DETECT_HARDWARE_CONFIG entry; SAAMD/CFG bytes only, clobbers A only); gate added to `MAIN_OUT_TO_SAA`; new emitted var `OUT_SAA_AV` (default 1 = not known). Desk-checked per rule 6; no SIMH (rule 5); no hardware run.
- **Version:** v0.1.35 (vtune.com **15,517 B**, vtunecfg.com 4,548 B). Build: TASM 0 errors x2.

**Branch: `saa1099` — build v0.1.34 (18-Oct-2026)** — O key toggles live output AY <-> SAA1099.

## Session Delta (2026-10-18, live output toggle)

- **Feature:** pressing `O` mid-song switches audio output between the AY/YM path and the SAA1099 (A/B the same track on both chips, position kept).
- **How:** `SAAMD` is now a live runtime flag (it was already the per-frame dispatch in `PSG_ROUT_BLOCK`); `MAIN_OUTPUT_TOGGLE` (new, in the main key dispatch) mutes the chip being left via `START_EXIT_SILENCE`, flips `SAAMD`, swaps `HW_CONFIG_DESC` <-> new `ALT_HW_DESC` (so the `Hardware:` line follows the live chip), mutes the target, and queues a deferred status (`STATUS_OUT_AY/SAA/NONE` — plain mode prints an `Output:` line after WAITQ; ANSI UI repaints the row-7 hardware value via new `UI_OUT_HW_ROW`, or shows the note on the State footer row when refused).
- **Availability gating:** the SAA is write-only (no probe), so AY->SAA is always allowed. SAA->AY requires an AY source found at startup: `-saa`/CFG-card-5 mode now also runs the normal AY detect chain (new `DETECT_HW_AY_KNOWN`, same CLI->CFG->HBIOS->probe->fallback order as `DETECT_HW_AY`) and records the outcome in `OUT_AY_AV`; bare MSX fallback = not known = `O` prints "Output: no alternate output available" and changes nothing.
- **TurboSound:** toggling to SAA with a dual-AY topology in force saves `TS_TOPOLOGY` in `OUT_SAVED_TOPO` and forces the module plumbing (existing SAA 3+3 mapping); toggling back restores it. So dual AY <-> single SAA (3+3), as specced. Started-in-SAA mode keeps module topology on the AY side (AVR module assumed there). `TS_PORTS_SETUP` SAA branch now seeds `TS_PORT1_*` from `PSG_PLAY_*` so the AY side has sane ports after a toggle (they were zero in SAA mode).
- **Also:** help/keys strings updated (embedded `-help` keys line + ANSI `MSG_PLKEYS` + README), stale `$FF/$FE` comments corrected to `$75/$74`. One `JR` -> `JP` widening in `PRINT_DEFERRED_STATUS` (range).
- **Register desk-check (rule 6):** new handlers clobber freely from the key dispatch (no preserved regs there); `OUT_SWAP_DESC` uses only HL/DE; `PDS_OUT_NONE` UI path mirrors the `MAIN_DEL_PROMPT` footer-row pattern (B=row preserved across `UI_CLR_ROW`); `PRINT_DEFERRED_STATUS` chain order unchanged in effect (distinct codes).
- **Version:** v0.1.34 (vtune.com **15,476 B**). Build: TASM 0 errors x2. No SIMH (rule 5), no hardware run — toggle untested on iron; verify `vtune -saa -list` and plain AY start, `O` both ways, TS file dual AY <-> SAA 3+3, and refusal note with no AY.

**Branch: `master` — build v0.1.1 (14-Sep-2026)** — Digit-leading filenames open correctly.

## Session Delta (2026-09-14, leading-digit FCB)

- **Symptom:** `vtune 06lookin` → file not found; same file as `mmm.pt3` played fine. FF/FE on TS tracks OK (CFG module).
- **Cause:** `BUILD_FCB_SKIP_USER_SPEC` consumed leading digits even without a trailing `:`, so `06LOOKIN` became `6LOOKIN` / wrong name.
- **Fix:** Only strip a ZPM3 user prefix when digits are followed by `:` (e.g. `3:SONG`); otherwise keep digits in the 8.3 name.
- **Version:** v0.1.1. **Deploy:** `A1:VTUNE.COM`. **Verify:** `F6: vtune 06lookin` opens `06LOOKIN.PT3`.

**Branch: `master` — build v0.1.0 (12-Sep-2026)** — First 0.1.x release.

## Session Delta (2026-09-12, promote v0.1.0)

- **Why:** Explicit promote from 0.0.289 after TS auto Hi-Z fix + ANSI playlist hardening.
- **Change:** `VT_VERSION` → `0.1.0`; rebuild; GitHub release ZIP (`vtune.com`, `vtunecfg.com`, `Tunes/`); SC126 `A1:` deploy.
- **Credits:** Thanks to Bruce Hall for iterating/testing stubborn ANSI playlist display and key-handling bugs.
- **Version:** v0.1.0.

**Branch: `master` — build v0.0.289 (12-Sep-2026)** — Auto TS no longer promotes Hi-Z to AVR module.

## Session Delta (2026-09-12, auto TS false FF/FE)

- **Symptom:** SC126 + single MSX-mode KC89C72, CFG auto/auto, TS file `RL2WOFTS.PT3` reported `TurboSound 0xFF/0xFE chip select in use` instead of Single-Card.
- **Cause:** `TS_PORTS_AUTO_MODULE` treated failed AY readback (Hi-Z) as dual-AVR module. Write-only clones look identical to the module.
- **Fix:** Auto only enables dual via HBIOS second AY; AVR module requires `-tsm` / CFG module. Removed `TS_PORTS_AUTO_MODULE`. Updated `vtunecfg` prompt, README, `docs/TurboSound-Module.md`.
- **Version:** v0.0.289. **Deploy:** `A1:VTUNE.COM` (+ `VTUNECFG.COM` prompt text). **Verify:** auto/auto + `rl2wofts` → Single-Card / chip-1 only.

**Branch: `master` — build v0.0.288 (09-Sep-2026)** — README refreshed to match player/config.

## Session Delta (2026-09-09, README refresh)

- **Why:** README still described v0.0.228 and pre-optimisation playlist/config behaviour.
- **Change:** Succinct rewrite: v0.0.288, default no-MYM usage, settle-then-reload nav, in-memory `R`, `vtunecfg` interactive + one-shot, OS-agnostic list keys. No binary rebuild.
- **Version:** v0.0.288 (docs only).

**Branch: `optimisation` — build v0.0.288 (08-Sep-2026)** — Hold-arrow: drain queued nav, paint marker once.

## Session Delta (2026-09-08, hold-arrow choke)

- **Symptom:** Hold arrow >~3s: scrolling "chokes"; longer hold → worse; recovers 3–5s after release. Fast taps OK. CP/M 2.2 and ZPM3.
- **Cause:** One CSI/marker-paint/WAITQ per frame. Auto-repeat (~30 Hz × 3-byte CSI) fills the UART/HBIOS FIFO; after release the backlog is replayed one paint at a time.
- **Fix:** `NAV_DRAIN_PENDING` consumes queued arrow/WASD/N/P/CSI (cap 128), advances `TRACK_SELECTED` only; one `UI_UPDATE_MARKER_DELTA` per burst. Non-nav byte stashed in `PENDING_KEY`.
- **Version:** v0.0.288 (**13,962 B**).

## Session Delta (2026-09-08, CP/M 2.2 leftover Esc on quit)

- **Symptom:** v0.0.286 first/fast arrows OK on CP/M 2.2; Esc quit left `A>^[` (CCP echoing Esc from `kbchar`).
- **Cause:** PRTCHR used BDOS fn 2. On 2.2 that calls `CONBRK`, which BIOS-CONINs a ready key into `kbchar`. Quit paints ANSI (`UI_EXIT_TO_PROMPT`) then `Done...` after `FLUSH_KEYS`; a second Esc (repeat / still in UART) was stolen and fn 6 could not drain it.
- **Fix:** PRTCHR uses fn 6 direct out (no CONBRK; portable — ASCII/ANSI never hits 2.2/3.x fn-6 sentinels). `FLUSH_KEYS` again after `Done...` before BDOS reset. Same PRTCHR change in `vtunecfg`.
- **Version:** v0.0.287 (**13,718 B**). **Deploy:** CP/M 2.2 `A3:VTUNE.COM`. **Verify:** `-list` Down then Esc → `Done...` / clean `A>` (no `^[`).

## Session Delta (2026-09-08, CP/M 2.2 first-arrow / leftover '[')

- **Report:** Other RC2014+SIO2+Tera Term user: first `-list` cursor key ignored, orphan `[` after quit, hold-arrow crash. Only under **CP/M 2.2**. Fine on ZPM3 / CP/M 3 / ZDOS on the same machine. Their BDOS fn 1 (CONIN) test always gets `27 91 65` for Up — CP/M is not eating Esc.
- **Cause:** CSI helpers (`UI_ESC_GETCH` / `_NB`, `TCFG_GETCH_TO`) called CONST (fn 11) then Direct I/O (fn 6). CP/M 2.2 CONST/`CONBRK` steals a ready byte into the 1-char `kbchar` lookahead; fn 6 talks to BIOS and never sees it. Esc is consumed, `[` stuck in `kbchar` (CCP prints it on quit), `A` may arrive as WASD. CP/M 3-family BDOS shares one console queue, so the mix worked there.
- **Fix:** Poll with fn 6 `E=FFh` only (counted non-blocking spin). Do not use fn 11 on the key path. Same change in `vtunecfg`.
- **Version:** v0.0.286 (**13,715 B**). **Deploy:** CP/M 2.2 `A:VTUNE.COM` user 0 and user 3. **Verify (this machine, CP/M 2.2):** `-list` first Down CSI moved ATTACK→LOUBOUTN and loaded; Right→RECOLL; Esc quit to a clean `A>` (no leftover `[`).

## Session Delta (2026-09-05, N/P stayed paused)

- **Symptom:** Arrows after playing-nav resume play; N/P left State: Paused.
- **Cause:** `MAIN_NEXT`/`MAIN_PREV` always wrote `NAV_SAVED_STATE` from current `PLAY_STATE`. First N mutes→`PLAY_PAUSED`; key-repeat/second N saved paused and clobbered `PLAY_PLAYING`.
- **Fix:** Shared `NAV_SAVE_IF_IDLE` (skip save while `NAV_DEBOUNCE` active) used by N/P and arrow `MAIN_NAV_GO`.
- **Version:** v0.0.285 (**13,731 B**). **Deploy:** `A1:VTUNE.COM`.

## Session Delta (2026-09-05, playing nav double-step)

- **Symptom:** Single arrows while playing: right×2, left no-op, down+right; then plays wrong track. Pause browse OK.
- **Cause:** Playing settle set `PLAY_STATE=0` (`PLAY_STOPPED`). Debounce fall-through hit end-of-track advance (`INC` selection) every frame — same as grid-right.
- **Fix:** Playing nav enters `PLAY_PAUSED` (mute) like real pause; while debounce still counting, `JP MAIN_LOOP` (never track-end). `NAV_SAVED_STATE` stays PLAY_PLAYING for reload.
- **Version:** v0.0.284 (**13,734 B**). **Deploy:** `A1:VTUNE.COM`.

## Session Delta (2026-09-05, unify playing/pause hold-nav)

- **Request:** Hold arrow/WASD must never reload — marker only until key release + settle, same as pause mode.
- **Fix:** Single `MAIN_NAV_DEFER` path with `NAV_DEBOUNCE_LEN` for both; playing still mutes/stops ticks on first move. Removed short `PLAY_NAV_DEBOUNCE_LEN`.
- **Version:** v0.0.283 (**13,730 B**). **Deploy:** `A1:VTUNE.COM`.

## Session Delta (2026-09-05, hold-Down while playing killed bridge)

- **Symptom:** Hold Down while playing changed track once; rc2014bridge on COM10 then died (and RC2014).
- **Cause:** Playing nav did an immediate full disk reload per key. CSI sticky/`B` auto-repeat queued another reload as soon as `FLUSH_KEYS` returned → reload+ANSI storm on the shared serial link.
- **Fix:** Playing nav mutes, moves marker, short settle, one reload; preserve `NAV_SAVED_STATE` during settle; clear CSI sticky after reload.
- **Version:** v0.0.282 (**13,744 B**).

## Session Delta (2026-09-05, hold-Up → Left sticky)

- **Symptom:** v0.0.280 still: hold Up → one up, then left.
- **Cause:** Esc-rearm was insufficient — auto-repeat likely delivers bare `A` after the first full `ESC [ A`. Bare `A` is WASD Left.
- **Fix:** `CSI_ARROW_STICKY` + TTL: after any CSI arrow, bare `A/B/C/D` map to CSI Up/Down/Right/Left (not WASD) until idle TTL or another key.
- **Version:** v0.0.281 (**13,715 B**). **Deploy:** `A1:VTUNE.COM`.

## Session Delta (2026-09-05, hold-arrow → left)

- **Symptom:** Paused at late tracks, hold Up: moves up once, then scrolls left.
- **Cause:** Hold-repeat `ESC [ A ESC [ A…`; next Esc eaten as CSI final → swallowed; orphan `[` ignored; bare `A` dispatched as WASD Left.
- **Fix:** CSI/SS3 final Esc rearms assembler (`UI_ESC_FIN_REARM` → `UI_ESC_TRY_BODY`); stray `[` stays in CSI; main-loop orphan `[` → spin for final (`MAIN_ESC_ORPHAN_CSI`).
- **Version:** v0.0.280 (**13,603 B**). **Deploy:** `A1:VTUNE.COM`.

## Session Delta (2026-09-05, R position-dependent delay)

- **Symptom:** R on late list entries (e.g. LAID) took ~2.5s before redraw; early entries near-instant.
- **Cause:** R called `MAIN_RELOAD_TRACK` (disk re-read of selected file). CP/M directory seek + file size scale with slot — felt like “redraw latency.”
- **Fix:** `MAIN_REDRAW_REQ` mutes, `UI_FULL_REDRAW` from already-loaded state, mutes again, resumes. No disk. Removed R’s `STATUS_REDRAW`/`MAIN_RELOAD_FULL_UI` path from `MAIN_RELOAD_TRACK`.
- **Version:** v0.0.279 (**13,528 B**). **Deploy:** `A1:VTUNE.COM`.

## Session Delta (2026-09-05, R redraw noise)

- **Symptom:** R muted the note, paused during disk reload, then noise during full redraw.
- **Cause:** `STATUS_REDRAW` ran deferred *after* `MAIN_RELOAD_TRACK` set `PLAY_PLAYING` and `MAIN_LOOP` ticked — INIT/first-tick PSG state sustained through slow ANSI paint.
- **Fix:** Mute after `ENGINE_INIT`/`META_SNAPSHOT` on every reload; R consumes `STATUS_REDRAW` inside `MAIN_RELOAD_TRACK` and runs `UI_FULL_REDRAW` while `PLAY_STATE` is not playing, mute again after paint, then enable play.
- **Version:** v0.0.278 (**13,535 B**). **Deploy:** `A1:VTUNE.COM`.

## Session Delta (2026-09-05, R mute + reload)

- **Symptom:** R while playing left the note sustaining; it only queued deferred `UI_FULL_REDRAW` with playback still active.
- **Fix:** `MAIN_REDRAW_REQ` calls `START_EXIT_SILENCE` when playing, then `MAIN_RELOAD_TRACK`. UI mode still queues `STATUS_REDRAW` for a full playlist redraw after the reload settles.
- **Version:** v0.0.277 (**13,484 B**). **Deploy:** `A1:VTUNE.COM`.

## Session Delta (2026-09-05, Esc quit latency + reload mute)

- **Quit ~3s:** `UI_ESC_TRY` used `UI_ESC_GETCH` with BC=8000; bare Esc burned a full spin before pending/quit. Cut spin to **400**; late CSI still completes next frame via `UI_ESC_CONTINUE`.
- **Reload mute:** `MAIN_NAV_RELOAD_OR_DEFER` mutes immediately when playing (WASD/N/P/arrows) before `MAIN_RELOAD_TRACK`.
- **Version:** v0.0.276.

## Session Delta (2026-09-05, Esc mute during CSI)

- **Symptom:** v0.0.274 deferred mute until reload/quit → current note sustained through CSI wait (annoying).
- **Fix:** Mute immediately on Esc when playing; skip `PLAYBACK_TICK` while `ESC_CSI_STATE` pending so the engine cannot re-sound. Cross-frame CSI assembler unchanged.
- **Version:** v0.0.275 (**13,470 B**). **Deploy:** `A1:VTUNE.COM`.

## Session Delta (2026-09-05, list-mode key path Phases A–C)

- **Phase A:** `MAIN_ESC` no longer mutes before CSI wait; `FORCED_DLY_FRAME_END` then assemble; mute only in `MAIN_RELOAD_TRACK` / `MAIN_QUIT`.
- **Phase B:** `MAIN_RELOAD_TRACK` paints `UI_UPDATE_MARKER_DELTA` **before** disk I/O; after load only `UI_TRACK_STATUS_UPDATE` + state (no full playlist on nav).
- **Phase C:** Cross-frame CSI via `ESC_CSI_STATE` + `UI_ESC_TRY` (same-frame spin) / `UI_ESC_CONTINUE` (NB). Bare Esc quits on next frame with no follower; incomplete `[`/letter can complete across frames without mute.
- **Non-goals kept:** no playing-nav debounce, no FORCED_DLY/QDLY changes, no playlist redraw on nav.
- **Size:** **13,460 B**. **Version:** v0.0.274. **Verify:** build clean; `A1:VTUNE.COM` uploaded; `A1:VTUNE -HELP` OK. Manual: `-list` arrows / hold / Esc (reporter retest for first-key drop).

## Session Delta (2026-09-05, arrow CSI first-key drop)

- **Report:** Other RC2014+SIO2+Tera Term user: first cursor key in `-list` ignored; orphan `[` after quit; hold-arrow eventually crashes. Not reproducible on Miguel's identical setup.
- **Cause:** `UI_ESC_GETCH` waited only `B=$40` CONST polls per CSI byte. If ESC arrives before `[`/letter (UART split), sequence treated incomplete — ESC consumed, `[` left in buffer (no nav). `vtunecfg` already used `BC=8000` for the same race.
- **Fix:** `UI_ESC_GETCH` uses fixed `BC=8000` (same as `TCFG_GETCH_TO`). No nav debounce / track-reload delay changes.
- **Version:** v0.0.273. **Verify:** build + deploy; ask reporter to retest first arrow + hold.

## Session Delta (2026-08-29, ANSI UI regression fixes)

**Root cause (header wipe / full-screen redraw):** this branch's rewrite of
`UI_CLEAR_PLAYLIST` passed the start row in C, then `CALL UI_PL_ROWS` clobbered C
with the track count (61→C=1, 60→C=0). The erase loop started at row 0/1 instead
of `UI_ROW_PLLIST` (9), wiping banner/keys/metadata/footer on every playlist
redraw. Introduced by the optimisation branch (diff vs v0.0.246 confirmed).

**Fixes:**

1. `UI_CLEAR_PLAYLIST` (ansiui.inc) — set C **after** `UI_PL_ROWS`; clear range now
   rows 9 .. loop-row+1 (the +1 covers a prior list that shrank by a tile row after
   a delete); dead `LD D,A` removed.
2. Delete path (`MAIN_DEL_YES`, vibetune.asm) — `CALL UI_SHOW_LOOP_STATUS` after
   `UI_SHOW_PLAYLIST`; the erase covers the loop row but only State was repainted
   by `MAIN_RELOAD_TRACK` ("Looping Status" vanished after a delete).
3. Startup — banner/timing no longer print at the CP/M prompt before the ANSI
   frame: `UI_SETUP` moved up to right after `DETECT_DISPLAY_MODE`; plain
   `PRINT_BANNER`/`PRINT_TIMING_MODE` are gated on `UI_ACTIVE`=0. New
   `PRINT_BANNER` helper; error/usage/help/credits paths call it themselves
   (no user-visible text lost in any mode).

**Verification:** build clean (TASM, 0 errors); raw `-LIST` output stream checked —
starts with `ESC[2J` (no prompt-line banner), header drawn at rows 1-2, erase
sweep limited to rows 9..25, State at 23 + Looping Status at 24 both painted.
Real delete flow on hardware **awaiting user test** (agent must not drive the
delete keystrokes — too slow, races the reload key flush).

**Version:** v0.0.272, 13,258 B (+35 B vs v0.0.271; correctness before size).
**Deploy:** `A1:VTUNE.COM` + `A15:VTUNE.COM` (both copies updated; F3 setpath
resolves A15:). Size ledger: gap to 12 KB now 13,258 − 12,288 = **+970 B**.

## Session Delta (2026-08-29, size tranche 4 — summary & ledger)

**Goal:** Close the ~989 B gap to 12 KB (12,288 B) without cutting user-visible text.

### Size ledger (this tranche, v0.0.266 → v0.0.271)

| Build | Bytes | Δ vs prior | Notes |
|-------|------:|-----------:|-------|
| v0.0.266 | 13,277 | — | Tranche start (user: “focus on size”) |
| v0.0.267 | 13,143 | −134 | Table-driven switch scan — **untested** |
| v0.0.268 | 13,161 | +18 | Partial switch revert; `unknown switch [-HELP]` on ZPM3 |
| v0.0.269 | 13,193 | +32 | Full switch scan + `IS_KNOWN` back to sequential |
| v0.0.270 | 13,206 | +13 | Whole-tile yellow restored |
| **v0.0.271** | **13,223** | **+17** | Yellow SGR leak fixed (belt `TCFG_COL_RST`) |
| **Net tranche** | | **−54 B** | vs v0.0.266 |

**Gap to 12 KB:** 13,223 − 12,288 = **+935 B (+7.6%)**.

### Branch context (wider picture)

| Milestone | Bytes | vs 12 KB |
|-----------|------:|---------:|
| Peak before `optimisation` (v0.0.246) | 14,290 | +2,002 B |
| Last under-limit build (v0.0.258, MYM optional + external docs) | 12,239 | −49 B ✓ |
| Embedded docs restored (v0.0.262) | 13,315 | +873 B net vs v0.0.259 |
| **Current (v0.0.271)** | **13,223** | **+935 B** |

Whole branch: **−1,067 B** from 14,290 B peak (−7.5%). Most of that was pre–tranche-4 work; this tranche netted **−54 B** after regressions and fixes.

### What was kept from tranche 4 (code)

- `STRINDEX_FCB` → `JP STRINDEX_UP_LEN` (duplicate search loop removed).
- `TS_CTXN_RESOLVE` — shared `TS_SAVE_CTXN` / `TS_LOAD_CTXN` pointer setup.
- **ansiui:** merged `UI_DRAW_STATE_*`, `TCFG_ANSI_STR` (CLRHOME/EL2/EL_EOL); `UI_PRT_MARK` for marker-only updates.

### What was reverted or reworked

- **Table-driven `SCAN_CMDLINE_SWITCHES` / `IS_KNOWN_SWITCH_TOKEN`** — abandoned after v0.0.267–268:
  - v0.0.267: `-HELP` hung after banner (bad table walk / `SWITCH_TOKEN_EQ` wedge).
  - v0.0.268: ZPM3 uppercases tail to `-HELP`; table `IS_KNOWN` failed validation.
  - **Fix:** sequential switch scan + chained `IS_KNOWN` (v0.0.269+).
- **Whole-tile yellow** — v0.0.269 `UI_PRT_MARK` reset yellow after `>` only (name stayed white). v0.0.270 restored full-tile highlight.
- **Yellow SGR leak** — v0.0.270 left metadata + all tiles yellow (sticky ANSI SGR). v0.0.271: `TCFG_COL_RST` before unselected tiles, after every tile, end of playlist, start of metadata block.

### Verification (hardware, RC2014 / ZPM3)

| Build | Result |
|-------|--------|
| v0.0.267 | `-HELP` hung after banner — **not shippable** |
| v0.0.269 | `-HELP` OK (full text, prompt return) |
| v0.0.271 | `-LIST` playlist OK; yellow on selected tile only; metadata white |

### Lessons / next size work

1. **Do not rewrite switch scan/validate without a ZPM3 uppercase test** (`-HELP`, `-help`, `-list`).
2. **ANSI colour changes need hardware check** — SGR is sticky; always pair PRM/RST on tile boundaries.
3. **~935 B gap remains** — embedded help/credits/Z180 ≈ **1,232 B** (~873 B net vs external sidecars). Code-only dedup without text cuts is nearly tapped; further wins need **ansiui/main-path** surgery (higher risk) or a **policy call on embedded docs**.
4. **Tranche 4 lesson:** −134 B at v0.0.267 was illusory until tested; shipped net is **−54 B**.

**Deploy:** `A1:VTUNE.COM` (v0.0.271, 13,223 B). **Outstanding:** none for tranche 4; size target still open.

## Session Delta (2026-08-29, yellow SGR leak fix)

- **Symptom:** v0.0.270 left metadata + all playlist tiles yellow (SGR not reset).
- **Fix:** `UI_PRT_TILE` — `TCFG_COL_RST` before unselected tiles and after every tile; `UI_SHOW_PLAYLIST` + `UI_TRACK_STATUS_BLOCK` belt resets.
- **Version:** v0.0.271. **Deploy:** `A1:VTUNE.COM`.

## Session Delta (2026-08-29, whole-tile yellow regression)

- **Symptom:** Selected playlist tile showed white `>` + name; only key-help row stayed yellow (v0.0.269).
- **Cause:** Size tranche `UI_PRT_MARK` reset yellow immediately after the marker; whole-tile highlight (marker + 12-char name + gap) was lost.
- **Fix:** `UI_PRT_TILE` again applies `TCFG_COL_PRM` before the tile and `TCFG_COL_RST` after; `UI_PRT_MARK` kept for marker-only delta updates.
- **Size:** 13,193 → **13,206 B** (+13 B). **Version:** v0.0.270. **Deploy:** `A1:VTUNE.COM`.

## Session Delta (2026-08-29, v0.0.267 switch-table regression fix)

- **Symptom:** `A1:VTUNE -HELP` hung after banner (v0.0.267); v0.0.268 returned `unknown switch [-HELP]`.
- **Cause:** Table-driven `SCAN_CMDLINE_SWITCHES` / `IS_KNOWN_SWITCH_TOKEN` (v0.0.267–268) broke switch detection on ZPM3 (uppercased `-HELP` tail). v0.0.267 likely wedged in `SWITCH_TOKEN_EQ` on bad table pointers; v0.0.268 failed validation before help path.
- **Fix:** Revert switch scan + `IS_KNOWN_SWITCH_TOKEN` to proven sequential form. Keep other tranche-4 wins (`STRINDEX_FCB` merge, `TS_CTXN_RESOLVE`, ansiui dedup).
- **Size:** 13,277 → **13,193 B** (−84 B net vs v0.0.266). **Verify:** `A1:VTUNE -HELP` OK on RC2014 (v0.0.269, full help text, prompt return).

## Session Delta (2026-08-29, size tranche 4 — code dedup)

- **Goal:** Close the 989 B gap to 12 KB without trimming user-visible text.
- **Changes:**
  - `STRINDEX_FCB` → `JP STRINDEX_UP_LEN` (duplicate search loop removed).
  - `IS_KNOWN_SWITCH_TOKEN` + `SCAN_CMDLINE_SWITCHES` → table-driven (`SWITCH_SCAN_TBL`: string + action byte + value byte).
  - `TS_CTXN_RESOLVE` — shared context pointer setup for `TS_SAVE_CTXN` / `TS_LOAD_CTXN`.
  - **ansiui:** `UI_PRT_MARK` (shared marker colour), merged `UI_DRAW_STATE_*`, `TCFG_ANSI_STR` (CLRHOME/EL2/EL_EOL).
- **Size:** 13,277 → **13,143 B** (−134 B). Still **855 B over** 12 KB.
- **Version:** v0.0.267. **Verify:** build clean; hardware/SIMH not run this tranche.

## Session Delta (2026-08-29, MSG_BANNER runaway PRTSTR)

- **Symptom:** `-help` printed `VTUNE   CFGCopyright…` then full credits before usage/help body.
- **Cause:** `MSG_BANNER` ended with `13, 10` not `0`; `PRTSTR` ran through `MSG_CFG_NAME` (11-byte FCB, no null) into `MSG_CREDITS` until the credits null byte. `START` already calls `CRLF` after the banner.
- **Fix:** Restore `MSG_BANNER` `0` terminator. **Version:** v0.0.265 (**13,272 B**).

## Session Delta (2026-08-29, MYM string dedup)

- **Refactor:** Credits, usage, and `-list` help use shared prefix + optional `MYM` fragment + single `.DB 0` terminator (no duplicated `PTxPlayer`/usage lines in source).
- **Size:** Default build unchanged at **13,272 B** (`#IFDEF` only emits one branch anyway); cleaner source, same ROM.
- **Version:** v0.0.264.

## Session Delta (2026-08-29, help/credits text cleanup)

- **a/b/g:** Fixed double `CRLF` in `MSG_CREDITS` and `MSG_Z180_WARN`; blank line before detailed switch list in `MSG_HELP_TEXT`.
- **c/d/e:** `MSG_USAGE` and `-list` help line omit `.mym`/MYM when built without `-dMYM`; `MSG_CREDITS` omits MYMPlay line likewise.
- **Version:** v0.0.263. **Deploy:** `A1:VTUNE.COM`.

## Session Delta (2026-08-29, revert external doc files)

- **User request:** Drop `VTUNE.HLP` / `VTUNE.CRD` / `VTUNE.Z80` sidecars and the ZPM3 path/COM-DU doc search added in v0.0.259.
- **Fix:** Restored embedded `MSG_HELP_TEXT`, `MSG_CREDITS`, `MSG_Z180_WARN`; `-help`/`-credits`/Z180 abort use `PRTSTR` again. Removed `PRINT_DOC_FILE`, `DOC_TRY_*`, `Z3_GET_ENV`, and related scratch.
- **`Build.cmd`:** No longer copies `VTUNE.HLP`/`CRD`/`Z80` to RomWBW.
- **Version:** v0.0.262 (**13,315 B**, +873 B vs v0.0.259 embedded-doc removal baseline). **Deploy:** `A1:VTUNE.COM` only.

## Session Delta (2026-08-29, compact VTUNE.HLP / doc newline fix)

- **Symptom:** `-help` showed three blank lines after the usage banner, then a blank line between every switch description.
- **Cause:** (1) `VTUNE.HLP` had been saved double-spaced when externalized; (2) `PRINT_DOC_FILE` echoed `CR` and `LF` separately — on RomWBW/ZPM3 each advances a line, so `CRLF` rendered as a blank row.
- **Fix:** Compacted `VTUNE.HLP` / `VTUNE.CRD` (single `CRLF` line endings). `PRINT_DOC_BYTE` skips `0x0D`, maps `0x0A` → `CRLF`.
- **Version:** v0.0.260. **Deploy:** `A1:VTUNE.COM` + `A1:VTUNE.HLP`.

## Session Delta (2026-08-29, doc files follow COM load DU)

- **Symptom:** From F3:, `A1:vtune -help` ran the player but reported HLP/CRD missing (opened on current DU only).
- **Fix:** `PRINT_DOC_FILE` searches (1) current DU, (2) ZPM3/ZCPR external-FCB load DU (where the COM was found), (3) command search path. Uses SCB→Z3ENV; restores user on exit.
- **Verified on hardware:** `F3>` + `A1:vtune -help` prints `VTUNE.HLP` from A1:.
- **Version:** v0.0.259 (12,442 B). **Deploy:** `A1:VTUNE.COM`.

## Session Delta (2026-08-29, optional MYM via `-dMYM` / `mymeng.inc`)

- **Decision:** PT3 is the primary format; MYM kept as optional to reclaim ~2 KB.
- **`mymeng.inc` (8.3):** MYMPlay 0.4 engine (`ENGINE_INIT_MYM`, depack, tick) moved out of `vibetune.asm`.
- **Gate:** all MYM classify/resolve/scan/validate/load/tick/timing/state paths use `#IFDEF MYM` (TASM; not `#IF MYM`).
- **`Build.cmd`:** default = no MYM; `Build.cmd MYM` passes `-dMYM`.
- **Size:** 12,804 → **12,239 B** (−565 B). Target ≤12,288 met.
- **Docs:** `AGENTS.md`, `README.md`, `VTUNE.HLP` updated. Credits still mention MYMPlay in `VTUNE.CRD`.
- **Version:** v0.0.258. **Deploy:** `A1:VTUNE.COM` (12,239 B) + `VTUNE.HLP` (29-Aug-2026).

## Session Delta (2026-08-29, size tranche 3 — PRINT_HW merge)

- **PRINT_HW_*:** `PRINT_PLAYBACK_HW_LINE` falls through into `PRINT_PLAYBACK_HW_VALUE`; removed duplicated `PRINT_HW_TS*` / `PRINT_HW_DESC_ONLY` and `PRINT_HW_VAL_TS_SINGLE` desc copy.
- **Misc:** Dropped `PAUSE_SILENCE` stub (callers → `START_EXIT_SILENCE`); `PTX_DETECT_TURBOSOUND` near-target `JP NZ` → `JR NZ` where in range.
- **Size:** 12,924 → **12,804 B** (−120 B). Still **516 B over** 12 KB.
- **Version:** v0.0.257. **Deploy:** `A1:VTUNE.COM` (29-Aug-2026; also ships unshipped Enter-resume from v0.0.256).
- **Next (~516 B):** optional lazy MYM, further ansiui CSI/table work, scan remaining duplicated strings/paths.

## Session Delta (2026-08-29, Enter-from-paused resume without reload)

- **Symptom:** Enter while paused on the current track reloaded from disk and redrew metadata (redundant).
- **Fix:** `MAIN_ENTER_PLAY` — if `PLAY_PAUSED` and `NAV_DEBOUNCE=0` (selection already loaded), jump to `MAIN_RESUME_PLAY` (same as Space). Reload only when browse debounce is pending (marker moved, file not yet loaded).
- **Version:** v0.0.256 (12,924 B). **Deploy:** included in v0.0.257 board upload.

## Session Delta (2026-08-29, Esc during playback crash/sustain)

- **Symptom:** Esc in ANSI `-list` while a track is playing sustains the current note and can hard-crash the machine (reset required).
- **Cause:** `MAIN_LOOP` calls `FORCED_DLY_FRAME_BEGIN` (DI) before `PLAYBACK_TICK`. `UI_ESC_SEQ` then polls BDOS for arrow-suffix bytes without muting or `FORCED_DLY_FRAME_END` — PSG holds the last register values; BDOS with interrupts off can wedge ZPM3/HBIOS.
- **Fix:** `MAIN_ESC` — `PAUSE_SILENCE` when `PLAY_PLAYING`, then `FORCED_DLY_FRAME_END` before `UI_ESC_SEQ`. `MAIN_QUIT` — early `START_EXIT_SILENCE`. `UI_ESC_GETCH` — CONST (11) peek before GET (non-blocking).
- **Version:** v0.0.255 (12,907 B). **Deploy:** `A1:VTUNE.COM` (29-Aug-2026).

## Session Delta (2026-08-29, Esc+arrow while paused + size tranche 2)

- **Bug:** v0.0.253 quit on any Esc while paused — left/right arrows (`Esc [ D`) were consumed as quit.
- **Fix:** Remove paused fast-quit in `MAIN_ESC`; always probe `UI_ESC_SEQ` (master behaviour). Slim `UI_ESC_GETCH` (BDOS 06 poll, no CONST). Revert `TCFG_EMIT` to `CFG_FLAGS` gate (matches master).
- **Size tranche 2:** `PTX_MATCH_SIG` table-driven matcher replaces duplicated Vortex/ProTracker byte loops (−~100 B vs v0.0.253).
- **Fix-run size audit:** v0.0.249 12,982 → v0.0.253 13,002 (+20 B regressions) → v0.0.254 12,884 (−118 B net). Kept: whole-tile yellow, `UI_CURSOR_ON_SELECTED` on pause/resume.
- **SIMH:** `scripts/Patch-SIMH-Vtune.py`, `Drive-SIMH-Attach.py`, `Test-SIMH-EscPause.py`. ZPM3 slice patched; paused left-arrow does not quit (pass). Esc→prompt inconclusive on telnet (no visible CP/M banner); hardware retest advised.
- **Version:** v0.0.254. **Deploy:** `vtune.com` pending.

## Session Delta (2026-08-28, optimisation tranche 1)

- **Goal:** Size/speed/rendering optimisations without losing features, text, or ANSI usability.
- **Size:** 14,290 → **12,982 B** (−1,308 B, 9.2%). Still **691 B over** 12 KB CP/M limit.
- **Dead code removed:** `PSG_MIXER_OFF`, `PRINT_HARDWARE_CONFIG`, `PTX_VARIANT`, `PSG_HW_VALID`, `PTX_STATE_POS`, `TS_TOPO_PROMOTED`, `HBIOSMD`; Bulba HBIOS mute/play paths (`#IF 0` in `pt3bulba.inc`).
- **Runtime:** `UPDATE_AUDIO_MODE_FROM_MUSIC` reads `TSFLAG` (no second `PTX_DETECT` scan); key dispatch uses `TO_UPPER` once.
- **ANSI UI (`ansiui.inc`):** `UI_TILE_AT_INDEX`, marker-only `UI_UPDATE_MARKER_DELTA`, scoped `UI_CLEAR_PLAYLIST`, `TCFG_ANSI_ON`, merged `UI_ESC_GETCH`, removed duplicate `TCFG_ANSI_AT` in `UI_CLR_ROW`; cold-start footer via `UI_TRACK_STATUS_BLOCK` + `UI_SHOW_LOOP_STATUS` (no double State line from `UI_SHOW_PLAYLIST`).
- **Docs externalised (full text preserved on disk):** `VTUNE.HLP` (`-help`), `VTUNE.CRD` (`-credits`), `VTUNE.Z80` (Z180 port-collision message). `PRINT_DOC_FILE` + `Build.cmd` copies all four to `RomWBW/Binary/Apps/`.
- **Dedup:** `TSSTR_MSX`/`TSSTR_EB` → `HW_DESC_*`; merged `TS_SAVE_CTX`/`TS_LOAD_CTX`; unified `PSG_WRITE_REG`/`PSG_WRITE_REG_B`.
- **Version:** v0.0.249. **Deploy (2026-08-28):** `A1:VTUNE.COM` (12,982 B) + `VTUNE.HLP`/`CRD`/`Z80`. **SIMH:** not run. **Hardware:** deployed, manual test pending.
- **Next tranche (~691 B):** `PRINT_HW_*` merge, PTX header matcher dedup, optional lazy MYM linker, further ansiui table-driven CSI.

## Session Delta (2026-08-28, TS/module playback regression fix)

- **Symptom:** TurboSound and FE/FF module playback broken on v0.0.249 (user report, RC2014).
- **Cause 1:** `TS_SAVE_CTXN` LDIR copied **from** context **to** `VT_+16` (reversed); dual-chip state save corrupted every quark.
- **Cause 2:** Merged `PSG_WRITE_REG` used wrong port in `OUT (C),A` after `POP BC` (C held value, not RSEL) — broke routed writes including module latch.
- **Fix:** Correct `TS_SAVE_CTXN` copy direction (`HL=VT_+16`, `DE=ctx`); revert to separate `PSG_WRITE_REG` / `PSG_WRITE_REG_B`.
- **Version:** v0.0.250 (12,984 B). **Deploy:** `vtune.com` only.

## Session Delta (2026-08-28, ANSI marker/cursor wrong tile)

- **Symptom:** After v0.0.250 optimisation, ANSI `-list`: block cursor on wrong row; yellow `>`/colour stuck on first track after N/P (metadata correct).
- **Cause:** `UI_TILE_AT_INDEX` called `UI_CALC_COLS` before saving entry index in `A`; `LD E,A` then used **UI_PLCOLS** (e.g. 4) as the track index — marker delta and `UI_CURSOR_ON_SELECTED` wrote to the wrong tile.
- **Fix:** `PUSH AF` / `POP AF` around `UI_CALC_COLS` in `UI_TILE_AT_INDEX`.
- **Version:** v0.0.251 (12,986 B). **Deploy:** `vtune.com` only.

## Session Delta (2026-08-28, ANSI cursor + highlight on track switch)

- **Symptom:** v0.0.251: `>` moved but block cursor flashed after `Playing`; prior track name stayed yellow.
- **Cause 1:** `MAIN_RELOAD_TRACK` called `UI_UPDATE_MARKER_DELTA` (parks cursor on `>`) then `UI_DRAW_STATE_PLAYING` (leaves cursor on State row).
- **Cause 2:** `UI_PRT_TILE` left SGR yellow active while printing the 12-char name — whole selected tile went yellow; marker-only delta could not clear it.
- **Fix:** Draw State row before marker delta; park cursor last. Yellow SGR only on `>` char. Marker delta uses full `UI_DRAW_PL_ENTRY` on old/new tiles.
- **Version:** v0.0.252. **Deploy:** `vtune.com` only.

**Build on board: v0.0.241 (28-Aug-2026)** — RC2014 EB `$D8/$D0`, ZPM3, `A1:VTUNE.COM`.

## Session summary (2026-08-28) — verified on hardware

### Playback stability (RC2014 EB, `-list` on `A1:`)

- **TS → non-TS sound** — After any TurboSound-format PT3, regular tracks keep playing on `$D8/$D0` without restart (**v0.0.230** port snapshot/restore: `PSG_PLAY_*`, `RESTORE_PLAY_PSG_PORTS`, no phantom Coleco chip-2).
- **Keys stable** — Track switch, pause, nav, and quit work after the drag/UI fixes (**v0.0.236** baseline retained).

### ANSI `-list` UI (incremental redraw)

- **Track switch** — `UI_TRACK_STATUS_UPDATE` rewrites only the value column (from col 13) on rows 4–7; `UI_UPDATE_MARKER_DELTA` moves `>` on two playlist tiles. Full paint only on cold start and **R** redraw.
- **Order** — Load + init + UI complete before `PLAY_STATE` goes to playing.
- **Pause / resume** — Footer `State:` line updates immediately via `UI_DRAW_STATE_PAUSED` / `UI_DRAW_STATE_PLAYING` (**v0.0.241**).

### Plain `-list` UI

- **Track switch** — One `State: Playing` / `State: Paused` line per reload (no duplicate footer) (**v0.0.240**).

### Startup pitch (ANSI list, track 2+)

- **Resolved** — Brief “vinyl speed-up” on track switch was ANSI serial I/O overlapping first play quarks, not Bulba portamento or disk latency. Fixed by incremental redraw (**v0.0.239**). Confirmed by user.

### AY mute hygiene (retained)

- Host `PSG_MUTE_ROUT` and Bulba `MUTE` use mixer `$3F` (8910: 0 enables tones).

---

## Outstanding / optional follow-up

| Item | Notes |
|------|--------|
| **Cold-start pop** | Small pop on first track load may remain; not reported as blocking. |
| **Hardware line on TS files** | Plain EB at `$D8/$D0` should show **Single-Card mode** for TS *files*, not `FF/FE` unless a real TurboSound module is present. Re-check if `VTUNE.CFG` / auto-detect mis-tags. |
| **Commit** | Session changes uncommitted unless user requests. |
| **SIMH** | Not run this session (per project policy). |

---

## Session Delta (2026-08-28, ANSI resume State line stale)

- **Issue:** After Space-resume in ANSI `-list`, footer still showed `State: Paused`.
- **Cause:** v0.0.239+ dropped deferred `STATUS_MSG_PENDING` on ANSI reload; resume still relied on deferred status, which did not refresh the footer row.
- **Fix:** ANSI pause/resume call `UI_DRAW_STATE_PAUSED` / `UI_DRAW_STATE_PLAYING` immediately; playing reload path calls `UI_DRAW_STATE_PLAYING`. Plain mode keeps deferred status only.
- **Version:** v0.0.241. **Deploy:** `vtune.com` only.

## Session Delta (2026-08-28, plain mode duplicate State line)

- **Issue:** Plain `-list` printed `State: Playing` twice from track 2 onward.
- **Cause:** Plain reload set `STATUS_MSG_PENDING` and also printed the state line inline; `PRINT_DEFERRED_STATUS` printed it again on the first main-loop frame.
- **Fix:** Drop `STATUS_MSG_PENDING` on plain `MAIN_RELOAD_TRACK` path (ANSI reload already omitted it).
- **Version:** v0.0.240. **Deploy:** `vtune.com` only.

## Session Delta (2026-08-28, ANSI list-mode drag — incremental UI)

- **Symptom:** In `-list` + ANSI mode only, track 2+ had a brief vinyl-speed-up pitch glide; plain mode and single-file play were fine; `tune.com` clean. First track in a list session OK.
- **Cause:** `MAIN_RELOAD_TRACK` called `UI_TRACK_STATUS_BLOCK` (four `ESC[2K` row clears + footer redraw) and set `STATUS_MSG_PENDING` before `MAIN_LOOP`, so the first play quarks overlapped heavy ANSI serial I/O. First track used one-time full paint; subsequent switches repainted everything.
- **Fix:** `UI_TRACK_STATUS_UPDATE` — erase-to-EOL at column 13 only, rewrite value fields; `UI_UPDATE_MARKER_DELTA` unchanged (two tiles). Reload path: load+init → incremental UI → then `PLAY_STATE`. No `STATUS_MSG_PENDING` on ANSI reload. `UI_TRACK_STATUS_BLOCK` kept for cold start / R redraw.
- **Version:** v0.0.239. **Deploy:** `vtune.com` only.

## Session Delta (2026-08-28, revert post-load settle)

- **Retest:** v0.0.237 `POST_LOAD_SETTLE` (8× WAITQ after load) — no change to startup drag.
- **Fix:** Revert `POST_LOAD_READY` / `POST_LOAD_SETTLE` and `POST_LOAD_SETTLE_FRAMES`.
- **Symptom (user):** first note sounds briefly slow, like hand-cranking a vinyl record up to speed — likely pitch/portamento, not I/O latency.
- **Version:** v0.0.238. **Deploy:** `vtune.com` only.

## Session Delta (2026-08-28, post-load I/O settle)

- **Issue:** Startup "drag" on first rows may be CPU/BDOS still busy from file load when the first audible quarks run.
- **Fix:** `POST_LOAD_READY` (refresh QDLY + `POST_LOAD_SETTLE`: 8× `WAITQ` with `PLAY_STATE` still stopped) after `LOAD_MUSIC_FILE`+`ENGINE_INIT`, before `PLAY_STATE` goes to playing. Used on cold start, `MAIN_RELOAD_TRACK`, and `MAIN_RELOAD_DIRECT`.
- **Version:** v0.0.237. **Deploy:** `vtune.com` only.

## Session Delta (2026-08-28, revert prime/silence crash on keypress)

- **Issue:** v0.0.235 plays first track (small pop) then any key causes a scream/crash loop.
- **Cause:** v0.0.233+ `PTX_SILENCE_BULBA` in `START_EXIT_SILENCE` calls Bulba before `ENGINE_INIT` has run `INIT` (reload path: after `HEAP_CLEAR`). `PTX_PRIME_PLAYBACK` added an extra `PLAY` quark + host `PSG_ROUT_BLOCK` that desynchronised Bulba state from the live tick path.
- **Fix:** Remove `PTX_SILENCE_BULBA`, `PTX_PRIME_PLAYBACK`, and `PTX_FLUSH_SILENT`. Restore Bulba `INIT` ending with `JP ROUT` (no pre-flush). Keep v0.0.230 port snapshot/restore and mixer `$3F` in host `PSG_MUTE_ROUT` / Bulba `MUTE`.
- **Version:** v0.0.236. **Deploy:** `vtune.com` only.

## Session Delta (2026-08-28, revert v0.0.234 scream/crash)

- **Issue:** v0.0.234 screamed and crashed on RL2WOF at session start (-list).
- **Cause:** `PTX_PRIME_ROW` used `DJNZ` on `B` after `BULBA_START+5` (PLAY), which clobbers `B`. Loop ran uncontrolled; repeated audible ROUT+flush corrupted player state.
- **Fix:** Revert to v0.0.233 single silent quark (`PTX_PRIME_PLAYBACK`). Remove post-`ENGINE_INIT` `PTX_FLUSH_SILENT` from `MAIN_RELOAD_TRACK`.
- **Version:** v0.0.235. **Deploy:** `vtune.com` only.

## Session Delta (2026-08-28, startup drag take 4)

- **Issue:** Slow drag at every track start still present on v0.0.232; v0.0.233 (one silent quark) likely insufficient.
- **Cause:** Bulba row 0 often runs portamento/attack across the whole first `Delay` tick count — one quark only decodes the row; the slide continues for `Delay` more ticks before row 1.
- **Fix:** `PTX_PRIME_PLAYBACK` burns row 0 entirely (decode quark + `DelyCnt` follow-up quarks), each followed by `PTX_FLUSH_SILENT`. `MAIN_RELOAD_TRACK` calls `PTX_FLUSH_SILENT` after `ENGINE_INIT` so hardware is muted before the first audible frame after TS→non-TS reload I/O.
- **Version:** v0.0.234. **Deploy:** `vtune.com` only.

## Session Delta (2026-08-28, startup drag take 3)

- **Context:** User has a plain EB AY at $D8/$D0 (Single-Card mode on TS *files*, not a TurboSound module). FF/FE module tag should never appear.
- **Issue:** Slow drag at every track start persists through v0.0.232; TS→non-TS may add noise.
- **Hypothesis:** (1) Host-only mute on track switch does not always match Bulba's ROUT path, so the previous row can sustain through reload I/O. (2) Bulba frame 0 after INIT is often a portamento/attack row — audible as a "drag" if it is the first output.
- **Fix:** `START_EXIT_SILENCE` calls Bulba `MUTE` (START+8) when the outgoing engine is PTx. `PTX_PRIME_PLAYBACK` runs one quark then a silent flush so MAIN_LOOP begins at frame 1.
- **Version:** v0.0.233. **Deploy:** `vtune.com` only.

## Session Delta (2026-08-28, startup drag + TS→non-TS noise, take 2)

- **Issue:** v0.0.231 did not fix the slow drag at track start; TS→non-TS added noise on top.
- **Cause:** Skipping INIT `ROUT` left hardware undefined between init and first quark. `TS_END_DUAL_SESSION` reverted auto-promoted MODULE→AUTO on non-TS, breaking FF/FE latch discipline on the EB TurboSound module (chip 2 could stay selected). Dual `TS_INIT` only flushed one virtual chip per pass.
- **Fix:** INIT ends with `ROUT` after forcing AYREGS mixer `$3F`. `PTX_FLUSH_SILENT` after single-chip init. Keep MODULE topology for the session (no revert). `TSMOD_MUTE` after `TS_INIT` mutes both virtual chips before first quark.
- **Version:** v0.0.232. **Deploy:** `vtune.com` only.

## Session Delta (2026-08-28, startup frame drag)

- **Issue:** Brief audible "drag" at the start of playback (track load or session start).
- **Cause:** Mute and Bulba `INIT` flushed all-zero AY registers. On the 8910, mixer=0 **enables** all tones; period=0 is maximum pitch — a short squeal/smeared attack until the first real `PLAY` frame.
- **Fix:** `PSG_MUTE_ROUT` sets reg 7 to `$3F` (all channels off). Bulba `MUTE` does the same. `INIT` returns without `ROUT` — hardware stays at the host mute until the first quark.
- **Version:** v0.0.231. **Deploy:** `vtune.com` only.

## Session Delta (2026-08-28, TS mute port stomp + phantom chip2)

- **Issue (retest v0.0.229):** After RL2WOFTS.PT3, LAID.PT3 showed `Coleco ($50/$51) / MSX ($A0/$A1)` and was silent; returning to RL2WOF.PT3 showed correct D8/D0 in the UI but still no sound.
- **Cause 1:** `TS_MUTE_BOTH_HARDWARE` left `PSG_REG_PORT`/`PSG_DATA_PORT` on chip-2 ports ($50/$51). `BULBA_SYNC_PORTS` and the next `TS_PORTS_SETUP` copied those, so all later playback targeted the wrong I/O.
- **Cause 2:** Coleco/MSX chip-2 fallback in `TS_PORTS_TRY_PROBE` ran before `TS_PORTS_AUTO_MODULE`, falsely enabling dual-card mode on a single EB TurboSound module at D8/D0.
- **Fix:** `PSG_PLAY_REG_PORT`/`PSG_PLAY_DATA_PORT` snapshot at config time; `RESTORE_PLAY_PSG_PORTS` after dual mute, module mute, single mute, `BULBA_SYNC_PORTS`, and `TS_END_DUAL_SESSION`. `TS_PORTS_SETUP` seeds chip1 from the snapshot. Removed Coleco/MSX phantom chip-2 fallback.
- **Version:** v0.0.230. **Deploy:** `vtune.com` only. **Retest:** RL2WOF → RL2WOFTS (expect `TurboSound 0xFF/0xFE` or single-card module, not Coleco/MSX) → LAID → RL2WOF; sound must persist.

## Session Delta (2026-08-28, TS→non-TS silent playback)

- **Issue:** On RC2014 EB module ($D8/$D0), non-TS files played fine until any TurboSound PT3 ran; after that, further tracks appeared to play but produced no sound until vtune was restarted.
- **Cause:** TurboSound module chip select (0xFF/0xFE on RSEL) is sticky. Dual TS playback ends on chip 2 (0xFE latched). Track-switch mute took the single-chip path when `TS_DUALHW=0`, and non-TS init never re-selected chip 0. Auto Hi-Z detection also left `TS_TOPOLOGY=MODULE` latched for the session, so `TSMOD_SLOWIO` kept prepending 0xFF to every ROUT on plain AY paths after topology revert was needed.
- **Fix:** `TS_END_DUAL_SESSION` re-selects chip 0 and reverts auto-promoted MODULE topology; called from `ENGINE_INIT_PTX_SINGLE` and `ENGINE_INIT_MYM`. `START_EXIT_SILENCE` uses `TSMOD_MUTE` whenever module topology is active, not only when `TS_DUALHW=1`. `TS_TOPO_PROMOTED` tracks auto `AUTO→MODULE` promotion.
- **Version:** v0.0.229. **Deploy:** `vtune.com` only. **Retest:** `vtune -list -rc A1:` — play RL2WOF.PT3, switch to RL2WOFTS.PT3, then back to RL2WOF or LAID.PT3; sound must continue without restart.

## Session Delta (2026-08-26, README refresh)

- Rewrote `README.md` for v0.0.228: `-tsm`, CFG AY/TS cards, auto Hi-Z module, Enter-to-play, `ansiui.inc`, docs index. No binary rebuild.

## Session Delta (2026-08-26, rename ansiui.inc)

- Renamed `uian.inc` → `ansiui.inc`; updated `#include`, Makefile `DEPS`, AGENTS file list, comments.
- Version **v0.0.228**; rebuild player only (no behavioral change).

## Session Delta (2026-08-26, Enter clears pause)

- **Enter:** no longer gated on already-paused only; forces `PLAY_PLAYING` + `STATUS_PLAYING` before reload (clears stale paused pending from debounce reload). Keypad Enter `ESC O M` also plays.
- **Deploy:** `vtune.com` only.

## Session Delta (2026-08-26, pause mute + Enter play)

- **Pause:** `PSG_MIXER_OFF` left TS/module chip2 sustaining; now `PAUSE_SILENCE` → `START_EXIT_SILENCE` (both chips / FF/FE).
- **Enter** while paused: clear debounce, reload selected track, play. Help/UI key line updated.
- **Deploy:** `vtune.com` only.

## Session Delta (2026-08-26, vtunecfg Esc twice)

- **Bug:** size tuner needed Esc twice — follower wait used BDOS 6 GETKEY, which can block with no char ready (ZPM3), so the second Esc “completed” the wait.
- **Fix:** `TCFG_GETCH_TO` polls BDOS CONST (11) before read; Esc Esc / unknown CSI also quit. Upload `vtunecfg.com` only.

## Session Delta (2026-08-26, CFG AY card selection)

- **vtunecfg:** First questions = primary AY (A/M/R/E/C), then TurboSound mode, then second AY if dual-card. CFG bytes 6–7. Summary lists cards first.
- **vtune:** CFG is default; CLI `-msx/-rc/-eb/-coleco/-tsm` overrides. Dual-card topology uses CFG card2 ports (no Z180 port guessing; HBIOS dual still unused in practice). Auto still Hi-Z⇒module.
- **Deploy:** both `vtune.com` + `vtunecfg.com`. Re-run `vtunecfg` to set cards; old CFG files keep card bytes 0.

## Session Delta (2026-08-26, auto AVR module without -tsm)

- **Issue:** `vtune -eb -list` on AVR module showed Single-Card — dual needed explicit `-tsm`.
- **Fix:** After dual-card probe fails, auto topology probes play ports; Hi-Z ⇒ set `TS_TOPOLOGY=MODULE` + `TS_DUALHW=1` (FF/FE). Readable AY stays chip-1 only. `-tsm` still forces module path; CFG dual-card skips auto-module.
- **Deploy:** `vtune.com` only. **Retest:** `vtune -eb -list` on TS file → `… - TurboSound 0xFF/0xFE chip select in use`.

## Session Delta (2026-08-26, status layout + hardware wording)

- **Layout (ANSI):** Input `[Regular|TurboSound]` → Song → by → Hardware → playlist → State → Looping Status. State/Loop are footer rows under the list (not fixed row 8).
- **Hardware one-liner:** regular card desc; TS+AVR dual `… - TurboSound 0xFF/0xFE chip select in use`; TS one AY `Single-Card mode …`; TS two AYs `Dual-Card mode … / …`. Shared `PRINT_PLAYBACK_HW_LINE` / `PRINT_INPUT_FILE_LINE` for ANSI + plain.
- **Plain:** same four header lines + State (dropped class/variant/audio-mode dump).
- **Deploy:** `vtune.com` only.

## Session Delta (2026-08-26, ANSI TurboSound status)

- **Issue:** ANSI `-list` only called `PRINT_HARDWARE_CONFIG`, so TS dual / chip-1 notes / module tag never appeared (plain mode already used `PRINT_PLAYBACK_HW_CONFIG`).
- **Fix:** `UI_PRINT_PLAYBACK_HW` — row 5 = HW or "TurboSound (2x AY…)" (+ `[module 0xFF/0xFE]`); row 9 = chip1/chip2 or chip-1-only note. Initial UI load also calls `UPDATE_AUDIO_MODE_FROM_MUSIC`.
- **Deploy:** `vtune.com` only. **Retest:** `vtune -list -tsm` on a `*TS.PT3` — expect TS header + chip lines (or chip-1 note without dual).

## Session Delta (2026-08-25, ANSI cursor on selection marker)

- **Issue:** In `-list` ANSI mode the VT cursor blinked in the tile gap (start of next column), not on the `>` marker.
- **Fix:** `UI_CURSOR_ON_SELECTED` parks `TCFG_ANSI_AT` on the selected tile origin; called after marker delta, loop-status print, and Playing/Paused status.
- **Deploy:** build + upload A1:. **Retest:** `vtune -list` — blink should overlay `>`.

## Session Delta (2026-08-25, -eb help ports)

- Help line for `-eb` now includes `($68/$60)` like the other port switches.

## Session Delta (2026-08-25, unknown-switch message + help wording)

- Unknown switch error is now `Error: unknown switch [-tms].` (token from `ARG_SCRATCH`).
- Help: `(0xFF/0xFE chip select)`.

## Session Delta (2026-08-25, unknown switch -tms accepted)

- **Bug:** any `-…` token was skipped; `-list`/`-help`/`-credits` skipped the token walk entirely, so `-tms` was ignored.
- **Fix:** `VALIDATE_SWITCH_TOKENS` (exact match vs known list) before mode early-out; `APPLY_IF_SWITCH` returns unknown → `ERR_UNKNOWN_SWITCH`. ASCII-only `-tsm` hint (em dash had mojibaked on CP/M).
- **Deploy:** uploaded. **Retest:** `vtune -list -tms` → error + valid switches list.

## Session Delta (2026-08-25, Z180 collide abort + module chip1-only)

- **Z180/-rc:** no longer remaps to EB and plays. Prints Rev5 EB `$60/$68` / Rev6.1 MSX or Coleco guidance and **quits** (`SANITIZE_AY_ABORT` → `START_EXIT`, ports parked on MSX for safe mute).
- **Module:** user ran `vtune -list` (no `-tsm`) on TS file → `TS_DUALHW=0`, chip 1 only (expected). Added note suggesting `-tsm` when a TS file plays without dual HW under auto topology.
- **Retest:** `vtune -rc` on SC126 → abort text, no play. Module: `vtune -list -tsm` (and `-msx` if needed).

## Session Delta (2026-08-25, -rc crashes SC126 — Z180 I/O window)

- **User:** still crash on track change with `-tsm -rc`; notes `$0C`/`$0D` external SD/RTC/LED trap and asks for system identity to avoid foreign OUTs.
- **Root cause on SC126:** HBIOS `Z180_IO_BASE=$C0`. `-rc` ports `$D0`/`$D8` are **inside** the Z180 internal register window (`$C0+$10` TCR, `$C0+$18` …), not an external AY. Dual/module FF/FE traffic corrupts the CPU. Same class as `$0C`/`$0D` external strobes.
- **Fix (v0.0.215):** `SANITIZE_AY_PORTS` after CLI/detect — if RSEL/RDAT ∈ `[Z180_IO_BASE, +3Fh]`, print note and force EB `$68`/`$60`. ROUT/`PSG_ROUT_BLOCK` clear B before every `OUT (C),A`/`OUTI`.
- **Identity already available:** `HBIOS_PLATFORM_ID` (e.g. `$08` SCZ180) + `Z180_IO_BASE`.
- **Retest:** `vtune -list -tsm -rc` → expect collision note + EB ports, Down→TS should not hard-lock. Real MSX card: `-tsm -msx`.

## Session Delta (2026-08-25, revert CLI dual ban)

- **User:** correctly rejected “no module dual under -rc/-msx” — module is Hi-Z, HBIOS never sees it; `-tsm -msx`/`-rc`/`-eb` are the normal way to address it.
- **Change (v0.0.214):** restore module dual whenever configured ports are Hi-Z (auto or CLI). Keep `TS_LOAD_TMPL` in `ENGINE_INIT_PTX_SINGLE` (real crash fix when dual is refused because play ports have a readable AY).
- **Deploy:** uploaded. **Retest:** `vtune -list -tsm -rc` Down→TS; and real module with `-tsm -msx` (or matching force).

## Session Delta (2026-08-25, v0.0.212 still crashes — dirty Bulba single path)

- **User:** v0.0.212 `vtune -list -tsm -rc` Down→RL2WOFTS still hard-crashes.
- **Cause:** dual correctly refused → `ENGINE_INIT_PTX_SINGLE` without `TS_LOAD_TMPL`. Track 1 left Bulba self-mod dirty; next INIT jumped into garbage. (Dual path already reloaded the template; the refuse path did not.)
- **Fix (v0.0.213):** `ENGINE_INIT_PTX_SINGLE` calls `TS_LOAD_TMPL` before `BULBA_START`. Module dual never enables when `HW_DETECT_MODE≠0` (`-rc`/`-msx`/…); use plain `-tsm` for AVR module on HBIOS ports.
- **Deploy:** A1: + ERASE + upload. **Retest:** `vtune -list -tsm -rc`, Down to RL2WOFTS.

## Session Delta (2026-08-25, v0.0.211 still crashes on Down→TS)

- **User:** `vtune -list -tsm -rc` v0.0.211 — Down arrow to RL2WOFTS still hard-crashes (no new status printed).
- **Likely cause:** `TSMOD_ANY_READABLE_AY` shotgun-probed `$A0/$68/$D8/$51`; foreign OUTs can lock the board. Also prior HBIOS mismatch treated “no HBIOS” as OK to enable dual.
- **Fix (v0.0.212):** probe **configured ports only** (MSX alt RIN `$A0`); CLI force requires HBIOS primary **match** or refuse dual; never probe alien pairs during module setup.
- **Deploy:** `A1:` + `ERASE VTUNE.COM` / upload both COMs.
- **Retest:** `vtune -list -tsm -rc`, Down to RL2WOFTS — expect survive + fallback note; still silent on wrong ports.

## Session Delta (2026-08-25, ZPM3 ERASE syntax)

- **ZPM3:** `ERASE` does not take a drive/user prefix. Correct sequence: `A1:` then `ERASE VTUNE.COM`. `ERASE A1:VTUNE.COM` → delimiter/option error.
- **Docs:** `.cursor/rules/rc2014bridge-upload.mdc` + `AGENTS.md` updated.

## Session Delta (2026-08-25, -tsm -rc TS track still crashes)

- **User:** `vtune -list -tsm -rc` on single AY at MSX `$A0/$A1` — RL2WOF silent OK; switch to RL2WOFTS hard-crashes machine.
- **Cause:** prior guard only used readback. Many RC MSX-addressed cards lack `$A2` RIN, so all probes look Hi-Z → `TS_DUALHW=1` → FF/FE dual init on forced empty `$D8`.
- **Fix (v0.0.211):** MSX probe tries RIN `$A2` then `$A0`; refuse module dual when CLI-forced ports disagree with HBIOS primary AY (`TSMOD_CLI_HBIOS_MISMATCH`). Chip-1 only + existing fallback note.
- **Deploy:** built + uploaded `A1:VTUNE.COM` / `A1:VTUNECFG.COM`.
- **Retest:** `vtune -list -tsm -rc` → N to RL2WOFTS — expect no crash, silent (wrong ports), note about module ignored; `vtune -list -tsm` (or drop `-rc`) for sound on MSX card.

## Session Delta (2026-08-25, ZPM3 ERASE/SDZ permanent)

- **Board OS:** ZPM3 — `ERA` and `STAT` do not work. Permanent equivalents: **`ERASE`** (delete) and **`SDZ`** (file check / size). Do not `DIR A1:`.
- **Docs:** `.cursor/rules/rc2014bridge-upload.mdc` + `AGENTS.md` updated to require `ERASE`/`SDZ` only.

## Session Delta (2026-08-25, rc2014bridge deploy workflow)

- **Workflow:** `.cursor/rules/rc2014bridge-upload.mdc` + `AGENTS.md` — after build, deploy to `A1:` via rc2014bridge MCP. Check with `SDZ` (not `STAT`/`DIR A1:`); erase before XMODEM; upload `vtune.com` / `vtunecfg.com`.
- **Build:** v0.0.210 / 25-Aug-2026, TASM clean.
- **Deploy:** Bridge MCP HTTP endpoint (default port 8014; not yet registered as a Cursor MCP namespace — called over HTTP). `rc2014_upload_file` → `A1:VTUNE.COM` (13104 B, verified) and `A1:VTUNECFG.COM` (3646 B, verified). `overwrite=true` replaced existing; bare `ERA A1:…` returned `ERA ?` (ZPM3 — use `ERASE`).
- **Outstanding:** Add rc2014bridge to Cursor MCP config so tools appear as a native namespace.

## Session Delta (2026-08-24, -list -tsm -rc crash on TS track)

- **User:** card on MSX `$A0/$A1`, forced `-rc`; RL2WOF silent OK; switch to RL2WOFTS crashed.
- **Cause:** module probe only checked the *forced* ports. Empty `$D8` → “no readback” → `TS_DUALHW=1` → dual init on wrong ports. Also `PROBE_AY_QUIET` nested `PSG_IO_SLOW_ENTER/EXIT` on `$D8`/`$68`, corrupting Z180 DCNTL restore.
- **Fix:** `TSMOD_ANY_READABLE_AY` probes configured + MSX/EB/RC/Coleco; any hit → chip 1 only. Remove nested slow-I/O from `PROBE_AY_QUIET` (parent `PROBE_AY_PORTS` already holds it).
- **Retest:** `vtune -list -tsm -rc` → TS track should not crash (still silent if ports wrong); drop `-rc` for sound. Module present → all probes Hi-Z → dual still enables.

## Session Delta (2026-08-24, -tsm + real AY garbles TS tracks)

- **User:** `vtune -list -tsm` — RL2WOF OK; RL2WOFTS dual overlay on one real AY sounds wrong.
- **Cause:** `-tsm` forced `TS_DUALHW` with no check; FF/FE selects are ignored by a real AY so both streams hit the same chip.
- **Fix:** `TS_PORTS_SETUP_MODULE` runs `PROBE_AY_PORTS` on the detected pair. Readable AY → leave `TS_DUALHW=0` (chip 1 only); no readback (Hi-Z module) → enable dual. Note line when a TS file plays under module topology but single hardware.
- **Retest:** `vtune -list -tsm` on real AY → RL2WOFTS shows MSX hardware + fallback note, chip-1 melody. With dual-AVR module → still TurboSound 2x lines / dual play.

## Session Delta (2026-08-24, plain list marker on track switch)

- **User:** after switching tracks, plain mode only printed HW/meta; the `>` list was not refreshed.
- **Fix:** `MAIN_RELOAD_SHOW_PLAIN` calls `PRINT_TRACK_LIST` before the status block so the new selection is marked.
- **Retest:** `vtune -list`, Down/N between RL2WOF and RL2WOFTS — list should show `>` on the active file each time.

## Session Delta (2026-08-24, plain list Down should mean next track)

- **User:** plain list shows RL2WOFTS *below* RL2WOF; Down should select it.
- **Cause:** `UI_NAV_DOWN` always stepped by `UI_PLCOLS` (ANSI tile grid). With ~5 cols and 2 tracks on one logical row, Down wrapped to the same index.
- **Fix:** when `UI_ACTIVE=0`, Up/Left = linear prev, Down/Right = linear next (wrap). ANSI mode unchanged.
- **Retest:** `vtune -list`, Down-arrow → RL2WOFTS status lines (or crash if reload bug remains). Also try `N`.

## Session Delta (2026-08-24, arrow keys in plain -list)

- **User:** still “crash” on track change with v0.0.204; switching with **arrow keys**.
- **Cause:** `MAIN_ESC` only ran `UI_ESC_SEQ` when `UI_ACTIVE≠0`. Plain `-list` treated the leading Esc of `ESC [ A/B/C/D` as **quit**, so arrows never navigated (despite help/README).
- **Fix:** probe Esc sequences whenever `TRACK_COUNT≠0` (playlist); bare Esc still quits.
- **Note:** with 2 tracks and wide cols, both sit on one row — **Right** (not Down) selects track 2; Down wraps to same index and reloads.
- **Retest:** `vtune -list`, then **N** (or Right-arrow) to RL2WOFTS. Report whether Esc/arrow previously returned to `A1>` or hard-locked.

## Session Delta (2026-08-24, v0.0.203 still crash → dirty TS template)

- **v0.0.203** fixed stack wipe in `HEAP_CLEAR` but switch RL2WOF→RL2WOFTS still crashed (sustained note).
- **Cause:** with CFG/module topology (`-tsm` / byte 5), dual `TS_INIT` called `CTX_SAVE_TMPL` *after* play had dirtied Bulba self-mod, and *after* `HEAP_CLEAR` zeroed the heap-resident template — so chip INIT reloaded poisoned opcodes.
- **Fix (v0.0.204):**
  - Move `TS_CTXTMPL_*` **pre-VARS** (survives `HEAP_CLEAR`).
  - `TS_CAPTURE_PRISTINE` once at startup (zero VARS + save patches) before any INIT/PLAY.
  - `TS_INIT` only `TS_LOAD_TMPL` (never re-snapshot).
  - `MAIN_RELOAD_TRACK` clears `PLAY_STATE` before reload I/O.
- **Test:** `vtune -list`, RL2WOF → RL2WOFTS (N or auto-advance). If CFG topology is module, expect TurboSound HW lines on the TS track. Also `vtune rl2wofts -tsm` direct.

## Session Delta (2026-08-24, -list plain RL2WOF→RL2WOFTS crash)

- **Symptom:** `vtune -list` (plain), change track RL2WOF→RL2WOFTS → crash with sustained last note.
- **Cause:** `HEAP_CLEAR` LDIR’d `VARS..$C000`, which includes the CP/M stack. On track reload (deeper SP) return addresses were destroyed; mute often skipped via `PSG_TOUCHED` gate → hanging note.
- **Fix:** clear only `VARS .. MUSIC_BUF-1`; always mute in `START_EXIT_SILENCE`; `ENGINE_INIT` mutes TS-aware before clearing `TSFLAG`/`TS_DUALHW`.
- No more `VT###.COM` copies — ship `vtune.com` only.
- **Test:** `vtune -list`, play RL2WOF, next to RL2WOFTS (and reverse); also direct `vtune rl2wofts`.

## Session Delta (2026-08-24, strip module diags → v0.0.202)


- Removed `-tsmcopy`, `-tsm2only`, `TSM_COPY`/`TSM_ONLY2`, FE-only/copy init paths, and diag status strings.
- Kept production module path: `-tsm`, `TSMOD_CURSEL` + `TSMOD_SLOWIO` (select in ROUT slow window), `TSMOD_MUTE`.
- `PTX_PATCHSZ` corrected 53→52 (payload sum).
- **Real-chip test:** omit `-tsm` (topology auto/dual-card). Module: `vtune RL2WOFTS -tsm`.

## Session Delta (2026-08-24, U1 reflash → SUCCESS)

- After ISP1 flash of `AY_TS_chip1.hex` + `1.789725Mhz` conf, user reports **it works** (FE/chip2 + dual module path).
- Root cause of “wrong chip2” was **stale/wrong image on U1**, not VibeTune stream/OFF2/select logic (diags `-tsmcopy` / `-tsm2only` were decisive).
- Host path kept: `-tsm`, `TSMOD_SLOWIO` select-in-ROUT, Z180 slow-I/O fix from v0.0.197.

## Session Delta (2026-08-24, U1 ISP1 reflash)

- USBasp confirmed on **ISP1** (U1). Prior on-chip flash matched neither current chip0 nor chip1 hex (stale/other image).
- Flashed + verified: `AY_TS_chip1.hex` (660 bytes) + `Conf_parallel_24MHz_1_789725Mhz.hex` (5 bytes, ICR1L=`0x6A`). EXIT=0 both write and re-verify.
- **User must unplug USBasp** (holds AVR in reset), then: `A1:VT201 RL2WOFTS -tsm2only` → expect clean melody; then `-tsmcopy` / `-tsm`.

## Session Delta (2026-08-24, VT201 -tsm2only → broken)

- **Result:** FE-only play of the known-good chip1 module is **broken**. Combined with `-tsmcopy` (chip2 wrong with identical data) and clean single-chip/`TUNE` on chip0:
  - Host FF path + U0 firmware: **OK**
  - Host stream2/OFF2/context: **ruled out**
  - **Fault is on the FE → U1 path** (U1 `CHIP_ID=1` firmware, flash/clock, or FE latch not accepted by U1)
- **VibeTune dual-module work paused** until U1 plays a clean tone/melody under FE select.
- **Next (AVR / hardware, not vtune):**
  1. Reflash ISP1 (U1): `AY_TS_chip1.hex` + `Conf_parallel_24MHz_1_789725Mhz.hex` (see RCA `SESSION.md` cheat-sheet). Unplug USBasp after.
  2. Confirm U1 got **CHIP_ID=1** image (not a second copy of chip0).
  3. Retest: `VT201 RL2WOFTS -tsm2only` — expect clean melody alone; then `-tsmcopy` / `-tsm`.
  4. Optional: fault-follows-firmware — swap chip0/chip1 hex between ISP0/ISP1 once.

## Session Delta (2026-08-24, VT200 -tsmcopy → chip2 still wrong)

- **Result:** `-tsmcopy` still has wrong chip2 while chip1 is fine → **not OFF2/stream2**. Leading causes: **U1 (CHIP_ID=1) firmware/hardware**, or **FE select not sticking** so U1 plays junk while U0 sounds clean.
- RCA never verified TurboSound chip1 playback (only `TUNE` on chip0).
- **v0.0.201:** `-tsm2only` — mute chip1 (FF), play chip1-module on chip2 only (FE). Interpreting:
  - **Good melody alone** → FE+U1 OK; prior “wrong” was mix/interference (revisit host path).
  - **Garbled alone** → U1 firmware/hardware (reflash ISP1 / check clock share).
  - **Silence** → FE select never reaches the module (host select path).
- **Test:** `A1:VT201 RL2WOFTS -tsm2only`

## Session Delta (2026-08-24, VT199 still wrong chip2 → select-in-ROUT + tsmcopy)

- **VT199** (B=0 on TSMOD_SELECT) unchanged on hardware — expected on SC126 (I/O decode ignores A15–A8; prior B≠0 was a red herring here).
- **Evidence:** `RL2WOF` and `RL2WOFTS` without `-tsm` are clean (chip0 / stream1 only). Wrong audio is specific to the module second-chip path.
- **v0.0.200:**
  1. Chip select moved into `TSMOD_SLOWIO` (Bulba `SLOWIO` hook) so `0xFF`/`0xFE` latch shares the same DCNTL slow window as the register dump — `TS_SETPORTS*` only sets `TSMOD_CURSEL`.
  2. **`-tsmcopy`**: forces module topology and inits/plays chip2 from `MUSIC_BUF` (same as chip1), not `TS_OFF2`. Isolates select/hardware vs stream2/OFF2.
- **Test plan:**
  1. `A1:VT200 RL2WOFTS -tsmcopy` — if **both chips sound like the same good melody**, FE select + chip1 AVR are OK → next look at OFF2/stream2. If chip2 still wrong, select or U1 firmware/hardware.
  2. `A1:VT200 RL2WOFTS -tsm` — retest real dual after (1).

## Session Delta (2026-08-24, VT198 chip2 still wrong → OUT (C),A port high byte)

- **User:** `VT198 RL2WOFTS` (no `-tsm`) plays the one-chip portion cleanly; with `-tsm` chip2 still wrong. Rules out file/OFF2 as primary and points at module select.
- **Bug:** `TSMOD_SELECT` left the select code in B during `OUT (C),A`. On Z80/Z180 that uses **BC as the full port address**, so latches went to `$FFA0`/`$FEA0` instead of `$00A0`. Chip0 often still worked (reset default = FF selected); **FE never selected chip1**, so stream2 writes hit chip0 / chip1 stayed stale.
- **Fix:** zero B before OUT (same pattern as `PSG_WRITE_REG`). v0.0.199.
- **Verification:** Build 0 errors ×2. **Test:** `A1:VT199 RL2WOFTS -tsm`.

## Session Delta (2026-08-24, VT197 -tsm chip2 wrong → SETUP context)

- **VT197 single-chip OK; `RL2WOFTS -tsm` runs but chip 2 sounds wrong.**
- **Cause:** v0.0.151 removed `SETUP` from `PTX_PATCHTBL` ("host-owned"). On dual TS that lets chip1's SETUP bit7 contaminate chip2's player state, and `PTX_ENGINE_CHECK_END` treated either chip's bit7 as song-end (old_vibetune requires **both** `TSSET1` and `TSSET2` bit7). Mid-quark CHECK_END after chip1 could also skip chip2.
- **v0.0.198:** put `SETUP` back in the patch table (`PTX_PATCHSZ` 52→53); snapshot `TSSET1`/`TSSET2` after each chip quark/init; dual end-detect matches old PTXLP; removed mid-quark early stop in `TS_PLAYQUARK`. Also: CFG byte 5 no longer overwrites a non-auto `TS_TOPOLOGY` already set by `-tsm`.
- **Verification:** Build 0 errors ×2. Binary **12,847 bytes**, sha256 `8ce92183…cca5`. **Test:** `A1:VT198 RL2WOFTS -tsm` (and sanity `VT198 RL2WOF`).

## Session Delta (2026-08-24, VT190/196 fail on AVR → slow-I/O root cause)

- **VT190 and VT196 both crash+fuzzy on the dual-AVR module.** Stock `v0.1b146` on the SD and RomWBW `TUNE RL2WOF -MSX` play clean. The v0.0.192 cleanup bisect was a red herring — **v0.0.190 was never good on this AVR setup**.
- **Upstream comparison (GitHub):**
  - [`jduraes/vibetune` `master`](https://github.com/jduraes/vibetune/blob/master/vibetune.asm) (`c1816d4` / v0.0.190): same bug — `DETECT_HBIOS_PLATFORM` does `OR A / RET NZ` after `BC_SYSGET_SNDCNT` with comment "No sound devices reported".
  - HBIOS API ([`API.txt` SNDCNT](https://github.com/wwarthen/RomWBW/blob/master/Source/HBIOS/API.txt)): **E = sound unit count**; E≠0 means devices *are* present. Correct polarity is **RET Z** (fail only when E=0).
  - Working lineage ([`old_vibetune` / local `VibeTune-old/hwcfg.inc`](https://github.com/jduraes/vibetune/tree/old_vibetune)): `OR A / JR Z,HBGM_NONE`.
  - Canonical Z180+MSX pairing in [`wwarthen/RomWBW` `tune.asm`](https://github.com/wwarthen/RomWBW/blob/master/Source/Apps/Tune/tune.asm): CFGTBL entry `$0A, $A0,$A1,$A2, $C0` (SCZ180 + MSX ports + **Z180 base $C0** for DCNTL SLOWIO). SLOWIO no-ops when Z180=`$FF`.
- **Failure chain on SC126+AVR:** inverted SNDCNT → HBIOS path always fails when AY exists → fallback/probe `SET_CONFIG_MSX` which **forced `Z180_IO_BASE=$FF`** → Bulba ROUT runs without DCNTL wait states → AVR can't keep up at 18.432 MHz → fuzzy + crash. Real AY chips often tolerate this; the module does not.
- **v0.0.197 fixes:**
  1. `RET NZ` → `RET Z` after SNDCNT (match HBIOS API + old_vibetune).
  2. `SET_CONFIG_MSX` no longer forces Z180=`$FF`.
  3. `CAPTURE_PLATFORM_Z180` on CLI override path; `APPLY_Z180_FOR_PLATFORM` after probe success and MSX fallback (MSX ports on SCZ180/RCZ180 still get `$C0`).
- **Verification:** `Build.cmd` → 0 errors ×2. Binary **12,798 bytes**, sha256 `bcd68546…782b`. No SIMH. **Test:** `A1:VT197 RL2WOF` (expect clean single-chip); then `RL2WOFTS -tsm`.

## Session Delta (2026-08-24, VT195 fail → PRTLN/tail-call revert)

- **VT195 (signature revert) failed on SC126** — same fuzzy + crash on `RL2WOF`. Signature matcher ruled out (with VT194 ruling out the table-walker).
- **v0.0.196:** reverted the rest of the v0.0.192 micro-opts: all `PRTLN` call sites back to `CALL PRTSTR`/`CALL CRLF`, removed `PRTLN` helper, restored `CALL`/`RET` for the 192 tail-call JPs (`TS_SAVE_CTX2`, `PTX_ENGINE_CHECK_END`, `UI_STATUS_*`, `UI_SHOW_LOOP_STATUS`, `UI_FULL_REDRAW`). Tree vs `c1816d4` is now essentially **only TS-module wiring** (`-tsm`, `TS_TOPOLOGY`, `tsmodule.inc`, vtunecfg byte 5).
- **Verification:** `Build.cmd` → Number of errors = 0 ×2. Binary **12,770 bytes**, sha256 `8a9655d0…808b`. Also extracted stock `c1816d4` binary as `VT190.COM` (12,530 bytes) for a control test if 196 still fails.
- **Ready for hardware:** `A1:VT196 RL2WOF`. If still bad → run `A1:VT190 RL2WOF` to re-validate the known-good baseline on this AVR/module setup; if 190 is OK but 196 is not, the TS-wiring commit is implicated despite the earlier 192-only bisect.

## Session Delta (2026-08-24, VT194 fail → signature revert)

- **VT194 (parser revert) failed on SC126** — same fuzzy sound + crash on `A1:VT194 RL2WOF`. Table-walker is ruled out.
- **v0.0.195:** restored proven inline `PTX_MATCH_VORTEX_*` / `PTX_MATCH_PROTRACKER_*` and IX-displacement `PTX_TS_SCAN_LOOP` from `c1816d4` (v0.0.190). Removed `STRPREFIX_MATCH` and `PTX_SIG_*` strings.
- Kept: PRTLN helper, if-chain parser with `-tsm`, TS-module wiring (`TS_TOPOLOGY` / `tsmodule.inc` / vtunecfg).
- Note from prior HANDOVER: v0.0.191 (Vortex/ProTracker STRPREFIX only) was hardware-OK; v0.0.192 added TS-scan STRPREFIX — that rewrite is the primary remaining suspect among the 192 cleanup.
- **Verification:** `Build.cmd` → Number of errors = 0 ×2. Binary **12,683 bytes**, sha256 `7751ea46…0fa0`. No SIMH. **Ready for hardware:** upload as `A1:VT195.COM`, run `A1:VT195 RL2WOF`.
- If still broken → next bisect target is PRTLN / remaining 192 micro-opts (part 1).

## Session Delta (2026-07-31, tranche-5 micro-opts)
- **VT195 (signature revert) failed on SC126** — same fuzzy + crash on `RL2WOF`. Signature matcher ruled out (with VT194 ruling out the table-walker).
- **v0.0.196:** reverted the rest of the v0.0.192 micro-opts: all `PRTLN` call sites back to `CALL PRTSTR`/`CALL CRLF`, removed `PRTLN` helper, restored `CALL`/`RET` for the 192 tail-call JPs (`TS_SAVE_CTX2`, `PTX_ENGINE_CHECK_END`, `UI_STATUS_*`, `UI_SHOW_LOOP_STATUS`, `UI_FULL_REDRAW`). Tree vs `c1816d4` is now essentially **only TS-module wiring** (`-tsm`, `TS_TOPOLOGY`, `tsmodule.inc`, vtunecfg byte 5).
- **Verification:** `Build.cmd` → Number of errors = 0 ×2. Binary **12,770 bytes**, sha256 `8a9655d0…808b`. Also extracted stock `c1816d4` binary as `VT190.COM` (12,530 bytes) for a control test if 196 still fails.
- **Ready for hardware:** `A1:VT196 RL2WOF`. If still bad → run `A1:VT190 RL2WOF` to re-validate the known-good baseline on this AVR/module setup; if 190 is OK but 196 is not, the TS-wiring commit is implicated despite the earlier 192-only bisect.

## Session Delta (2026-08-24, VT194 fail → signature revert)

- **VT194 (parser revert) failed on SC126** — same fuzzy sound + crash on `A1:VT194 RL2WOF`. Table-walker is ruled out.
- **v0.0.195:** restored proven inline `PTX_MATCH_VORTEX_*` / `PTX_MATCH_PROTRACKER_*` and IX-displacement `PTX_TS_SCAN_LOOP` from `c1816d4` (v0.0.190). Removed `STRPREFIX_MATCH` and `PTX_SIG_*` strings.
- Kept: PRTLN helper, if-chain parser with `-tsm`, TS-module wiring (`TS_TOPOLOGY` / `tsmodule.inc` / vtunecfg).
- Note from prior HANDOVER: v0.0.191 (Vortex/ProTracker STRPREFIX only) was hardware-OK; v0.0.192 added TS-scan STRPREFIX — that rewrite is the primary remaining suspect among the 192 cleanup.
- **Verification:** `Build.cmd` → Number of errors = 0 ×2. Binary **12,683 bytes**, sha256 `7751ea46…0fa0`. No SIMH. **Ready for hardware:** upload as `A1:VT195.COM`, run `A1:VT195 RL2WOF`.
- If still broken → next bisect target is PRTLN / remaining 192 micro-opts (part 1).

## Session Delta (2026-07-31, tranche-5 micro-opts)

- Version bumped to **v0.0.192**. Binary: **12,423 → 12,244 bytes (−179)**. v0.0.191 hardware-verified by user first.
- **PRTLN helper (~75B):** 27 sites of `CALL PRTSTR / CALL CRLF` → `CALL PRTLN` (helper = `CALL PRTSTR / JP CRLF`, added just above PRTSTR). Exact-adjacency replacement only.
- **Tail-calls (12B):** 12 × `CALL X / RET` → `JP X` (6 composed via PRTLN, 6 direct: TS_SAVE_CTX2, PTX_ENGINE_CHECK_END, UI_STATUS_PAUSED/PLAYING, UI_SHOW_LOOP_STATUS, UI_FULL_REDRAW).
- **Table-driven SCAN_CMDLINE_SWITCHES (~34B):** the 9 nearly identical `LD DE,sig / CALL / JR NZ / LD A / LD (var),A` blocks are one loop over `SCAN_SW_TABLE` (entry = sig ptr, var ptr, value). Same switch order → same last-match-wins precedence for RUN_MODE and HW_DETECT_MODE.
- **TurboSound signature (~52B):** the 12 × `LD A,(IX+d) / CP imm / JP NZ` compares in `PTX_TS_SCAN_LOOP` ("PT3!"@+0, "PT3!"@+6, "02TS"@+12) now use `STRPREFIX_MATCH` 3× with HL advancement (+4 consumed, +2 skipped per quad). New strings `PTX_SIG_PT3X`/`PTX_SIG_02TS`. BC/IX preserved — outer scan-loop contract intact.
- **Skipped (documented for later):** BUILD_FCB name/ext loop merge (~35B but the filename-parsing area that produced 3 bugs), SET_CONFIG_* port-block table (~14B, hardware-setup risk), EXTR PT2/PT3/MYM ext-check (irregular control flow, ~0 net).
- **Verification:** TASM + uz80as zero errors, byte-identical outputs, Apps in sync. Desk-checked register flow on all four patterns (rule 6). No SIMH (rule 5) — hardware eyeball: switch parsing (-list/-help/-credits/-msx etc.), a TurboSound file (rl2wofts), and general playback UI.

## Session Delta (2026-07-31, signature matcher optimisation)

- Version bumped to **v0.0.191**. Binary: **12,530 → 12,423 bytes (−107)**.
- **User asked** whether the inline per-char magic-string matchers really couldn't be optimised — they could. `PTX_MATCH_VORTEX_HL` ("Vortex Tracker", 14 chars) and `PTX_MATCH_PROTRACKER_HL` ("ProTracker ", 11 chars) were ~98 and ~80 bytes of `LD A,(HL) / CP imm / JR NZ / INC HL` chains; now one shared `STRPREFIX_MATCH` loop (DE = NUL-terminated signature, exact case, early-exit) + 2 signature strings + thin HEADER/MUSIC wrappers. Same A=0/Z=match contract, same early-exit-on-mismatch, same byte counts compared. Slight per-iteration cost (DJNZ-style loop vs unrolled) is irrelevant — runs once per file load.
- Desk-checked register flow (rule 6): DE now clobbered (safe at all 4 call sites), B preserved, flags contract identical at `OR A` call sites.
- **Verification:** TASM + uz80as builds zero errors, byte-identical, signatures present in binary, Apps in sync. No SIMH (rule 5) — worth a hardware sanity play of one Vortex and one ProTracker PT3 (e.g. ATTACK.PT3 vs a ProTracker-family file) since format detection is the touched path.

## Session Delta (2026-07-30, README + history cleanup)

- **README.md created** — succinct feature/system/build doc covering formats, playlist mode, ANSI/VT100 UI + vtunecfg, timing, a systems/cards/ports table (MSX/RC/Coleco/EB incl. Z80 `$D8/$D0` vs Z180 `$68/$60` EB addressing), TurboSound, usage/keys, dual-assembler build, and GPL v3 attribution (Joao Miguel Duraes / Wayne Warthen / S.V.Bulba / Marq-Lieves!Tuore). No binary change.
- **Git history:** all `Co-authored-by: Cursor` trailers stripped from every commit (filter-branch, 89 commits), master + old_vibetune force-pushed (branch protection toggled via gh API and restored). All hashes changed.

## Session Delta (2026-07-30, -credits switch)

- **v0.0.190:** user correction — no blank line between banner and the copyright line on `-credits`; removed the leading `CALL CRLF` from `START_CREDITS`. Blank line between the copyright line and `Derivative work from/by:` stays.
- Version bumped to **v0.0.189**. Binary: **12,345 → 12,533 bytes (+188)**.
- **User redirected the attribution UX** (v0.0.188 printed credits on the usage screen): credits now print **only** via a new `-credits` switch; bare `vtune.com` shows usage only.
- **Implementation:** new `RUNMODE_CREDITS` (3) — `SCAN_CMDLINE_SWITCHES` matches `-credits` (case-insensitive, any position); both `PARSE_CMDLINE` short-circuits treat it like LIST/HELP (no filename needed); `START_AFTER_PARSE_OK` routes to new `START_CREDITS` before any hardware probing (mirrors `START_HELP`: CRLF + `MSG_CREDITS` + CRLF + exit, banner already printed at startup).
- **Output** (per user spec): `Copyright (C) 2026, Joao Miguel Duraes (fackie)`, blank line, `Derivative work from/by:` then RomWBW tune.com / Wayne Warthen GPL v3, PTxPlayer / S.V.Bulba, MYMPlay / Marq-Lieves!Tuore lines.
- `-credits` added to the `Valid switches:` line and the `-help` body (`  -credits  Show copyright and attribution`).
- Source headers updated to the full name: `Copyright (C) 2026, Joao Miguel Duraes (fackie), GNU GPL v3 (or later).` in `vibetune.asm` and `vtunecfg.asm`.
- **Verification:** TASM + uz80as builds zero errors, byte-identical outputs, credits string confirmed in binary, Apps in sync. Desk-checked register flow (START_CREDITS mirrors START_HELP; RUN_MODE=3 exits before hardware probe). No SIMH (rule 5) — hardware eyeball of `-credits`, no-arg, and `-help` screens pending.

## Session Delta (2026-07-30, attribution & licensing)

- Version bumped to **v0.0.188**. Binary: **12,215 → 12,345 bytes (+130)** — three credit lines + print code.
- **License obligations established** (from RomWBW ReadMe.md "License Terms" + upstream `tune.asm` MSGUSE + old in-tree VibeTune `-credits` switch):
  - RomWBW / tune.asm: **GPL v3+** (Wayne Warthen) → vibetune.asm is a derivative and must carry GPL v3+.
  - PTxPlayer: **(c) 2004-2007 S.V.Bulba**, freeware with attribution (PTxPlay.txt, no explicit license text).
  - MYMPlay 0.4: **Marq/Lieves!Tuore & Fit**, freeware with attribution (MYMPlay.txt).
- **Changes:**
  - `LICENSE`: canonical GPL v3 text added to repo root (was missing entirely).
  - `vibetune.asm`: stale "clean-room bootstrap" header replaced with proper copyright/derivation/GPL block crediting Wayne Warthen, S.V.Bulba, Marq/Lieves!Tuore.
  - `pt3bulba.inc`: Bulba copyright/URL header restored (was reduced to "extracted from tune.asm").
  - `vtunecfg.asm`: GPL + derivation header added.
  - MYM depacker comment now credits Marq/Lieves!Tuore & Fit.
  - **Runtime:** `PRINT_USAGE` now appends `MSG_CREDITS` (same 3 lines as the old VibeTune's `-credits` output and upstream's MSGUSE) — shown on bare `vtune.com` (no args) and `-help`, since both share PRINT_USAGE. Matches how upstream tune.com embeds copyright in its usage text.
- **Verification:** TASM + uz80as builds, both zero errors, byte-identical outputs; credits string confirmed present in the binary; Apps copies in sync. No SIMH run (rule 5) — eyeball the no-arg screen on hardware next run.

## Session Delta (2026-07-30, uz80as toolchain validated)

- Version bumped to **v0.0.187** (build date 30-Jul-2026). Binary unchanged at **12,215 bytes**.
- **uz80as installed** under RomWBW `Tools/<BINDIR>/uz80as.exe` (official 2.02 Windows binary from jorgicor.niobe.org — local compile attempted first, but the only gcc on this machine is FPC's headerless 2.95 cross-compiler). Location matches RomWBW's `BINDIR = Tools/$(UNAME)` convention, so `make` via `Tools/Makefile.inc` now works on Windows too. Note: RomWBW's *source* tree carries 2.02 + wdl1908's JR-range-error patch; the binary is unpatched 2.02 (a too-long JR would silently mis-assemble — TASM errors; no such JRs exist in our code today).
- **Source adaptations for dual-assembler compatibility** (all proven byte-no-ops: TASM rebuild after edits differed from pre-edit baseline in exactly the version-string byte):
  - `pt3bulba.inc`: `.IF/.ENDIF` → `#IF/#ENDIF` (uz80as only knows hash-style conditionals; TASM accepts both).
  - `pt3bulba.inc`: bare `(IX)` → `(IX+0)` in 3 spots (`LD (IX),8`, `DEC (IX)`, `LD (IX),A`) — uz80as requires explicit displacement; TASM treats them identically.
- **Comparison result:** uz80as 2.02 vs TASM 3.2, same source — `vtune.com` **byte-identical**, `vtunecfg.com` **byte-identical**. Either assembler can build the project going forward.
- Deployed to `../RomWBW/Binary/Apps/` as usual; ready for hardware test.
- Optional follow-up for the user: commit `uz80as.exe` into the RomWBW fork under its `BINDIR` (not done — outside this repo).

## Session Delta (2026-07-30, repo cleanup + git refresh)

- **Repo hygiene pass** (no version bump, no rebuild — source unchanged since v0.0.185):
  - Untracked editor dirs (`.cursor/`, `.vscode/`) — gitignore already covered them.
  - Added to git: `uian.inc` (was untracked despite being a key source), `AGENTS.md`, `vtunecfg.com` (binary now shared like `vtune.com`).
  - Moved `showtail.asm/.com/.lst` (command-tail debug probe) into `scripts/` — local-only diagnostic tooling, consistent with the other SIMH drivers.
  - PII scrub: removed hardcoded absolute user home fallback path from `archive/cleanroom/Build-Pt3NoteTable.py` (relative candidates cover it). Full-tree scan (incl. ignored files) otherwise clean.
  - Fixed `Makefile` DEPS: `uian.inc` was missing from the `vtune.com` dependency list.
  - Docs verified current: `docs/SIMH-Testing.md` telnet-console workflow, `Build.cmd` dual-binary build, `AGENTS.md` conventions all match reality.
- Committed locally as the v0.0.185 state.

**Build under test: v0.0.195 (24-Aug-2026)** — *TS-regression bisect: signature matcher reverted after VT194 fail.*

## Session Delta (2026-07-30, size-reduction tranche 1–4)

- Version bumped to **v0.0.185**. Binary: **12,879 → 12,215 bytes (−664)**. No SIMH run (rule 5); build clean (2× errors = 0), desk-checked register flow (rule 6).
- **Item 1 — dead debug code:** deleted `PRINT_TIMING_DEBUG` block (`.IF 0`), `PRINT_HEX_BYTE/NIBBLE/DIGIT`, `PRINT_DEC_BYTE/WORD`, `QDLY_DBG1`/`APPLY_COUNT` vars and their stores in `APPLY_ENGINE_QDLY_ADJ`, `STRINDEX_UP_CMDTAIL`, and the `MSG_DBG_*`/`MSG_SWITCH_DELAY_WORD` strings. `PRINT_DECIMAL_BYTE` kept (live track-count print).
- **Item 2 — MYM frame hint:** removed `MYM_FRAME_HINT` var, its writes, and the `MYM frame hint: 0x..` diagnostic print from `PRINT_CUR_MYM` (now prints class + CRLF only).
- **Item 3 — CLI parser consolidation (biggest win):** one scanner + one comparator.
  - `SCAN_CMDLINE_SWITCHES` now handles **all** switches including `-delay` (case-insensitive substring scan of $0081 + FCB — superset of the old case-sensitive `-DELAY` scan, matching the usage line).
  - `PARSE_AND_CLASSIFY` simplified to a `RUN_MODE` check (RUNMODE_PLAY → classify, else OK); `PARSE_CMDLINE` already short-circuits LIST/HELP.
  - `APPLY_IF_SWITCH` collapsed to a `'-'` prefix check (its only remaining job: skip switch tokens as filenames; all flag-setting happens in `SCAN_CMDLINE_SWITCHES`, order-independent).
  - Deleted: `CHECK_LIST_SWITCH`, `APPLY_DELAY_FROM_CMDLINE`, `APPLY_LIST_FROM_CMDLINE`, `STRCMP_TUNE`, `STRINDEX_TUNE(_LEN)`, `MSG_SWITCH_LIST_TUNE`, `MSG_SWITCH_DELAY_TUNE`, and the six `APPLY_IF_SWITCH_*` handlers.
- **Item 4 — string dedup round 2:** dead-label sweep (defined-vs-referenced across all 5 sources) found and removed: `TS_MUTE` (dead routine, ~25B — superseded by `TS_MUTE_BOTH_HARDWARE`), `MSG_ERR_NO_ARG` (dead string — `START_NO_ARG` prints usage only), `HW_DESC_RC` (dead string — `-rc` and RSEL `$D8` both use `HW_DESC_EB_RC`, "RC2014 EB module", correct since the RC2014 AY card *is* the Ed Brindley design). TSSTR_*/HW_DESC_* pairs and `-help` body left alone: no byte-identical overlaps, and dedup there would change user-visible text for ~0 net after print-call overhead.
- **Behavior matrix preserved (desk-check):** `-help` / `-list` / `-loop` / `-msx -delay` / plain `file.pt3` / switch-token skipping all follow the same paths as v0.0.184. Remaining unreferenced labels (`WAITQ_TIM`, `TS_FALLBACK_SET_COLECO`, `START_EXIT_MSG`, `START_LOAD_SHOW_MODE`, `PARSE_TOK_TAKE_FILENAME`) are zero-cost fall-through markers, kept for readability.
- **Outstanding:** hardware verification of the consolidated parser on real CP/M (esp. `-delay` now case-insensitive and `-list` anywhere on the line) is for the user to eyeball on next real run.

## Session Delta (2026-07-29, "EB module" identified)

- Version bumped to **v0.0.184** (help string only).
- **"EB" origin established** (user asked): RomWBW `tune.asm` lists per-platform "(EB)" and "(MF)" RC-bus sound module variants with different ports — they are *designer variants*, not bus types. EB = [Ed Brindley's YM2149/AY-3-8910 RC2014 sound card](https://github.com/electrified/rc2014-ym2149) (`$D8/$D0` on Z80 platforms, `$68/$60` on Z180: SC126/RCZ180); MF = Mark Frampton's design (`$D1/$D0`, `$61/$60`). RomWBW auto-detects from platform ID; `-eb` is just an override.
- `-help` line updated: `-eb Force Ed Brindley (EB) sound module ports`.

## Session Delta (2026-07-29, paused-browse debounce)

- Version bumped to **v0.0.183**.
- **User-reported issue:** while paused, every nav move did a full reload — disk read, header parse, metadata snapshot, full status-block redraw — so rapid browsing (2-3 keys/s) wasted cycles and flickered "State: Playing" briefly before "Paused" re-drew.
- **Fix (debounce):** all three manual nav paths now end in a shared `MAIN_NAV_RELOAD_OR_DEFER`: playing → reload immediately (unchanged); paused → update tiles via `UI_UPDATE_MARKER_DELTA` only and set `NAV_DEBOUNCE=50` frames (~1s, new var + `NAV_DEBOUNCE_LEN` define). Each further move resets the countdown. `MAIN_LOOP_NODELAY` decrements once per frame and reloads (still paused, via the v0.0.179 `NAV_SAVED_STATE` mechanism) when it hits 0.
  - Space with a pending debounce → loads the *selected* track and plays it (not the stale loaded one).
  - Debounce cleared on delete-prompt entry and defensively at every `MAIN_RELOAD_TRACK` entry.
  - `UI_TRACK_STATUS_BLOCK` now draws the status row from `PLAY_STATE` instead of unconditionally `UI_STATUS_PLAYING` — kills the Playing flash on the settled paused reload (plain mode prints "State: Paused" as before).
  - Plain mode: no output during browsing (marker is a UI concept); track block prints once on settle.
- Two `JR` → `JP` widenings near `MAIN_RESUME` (branch range).

## Session Delta (2026-07-29, delete preserves pause)

- Version bumped to **v0.0.182**.

## Session Delta (2026-07-29, hardware-desc register fix)

- Version bumped to **v0.0.181**.
- **User-reported bug:** v0.0.180 always printed "Hardware:   Unknown (using default)". Root cause: my `PRINT_HARDWARE_CONFIG` edit pushed HL (post-`EX DE,HL` = fallback pointer) instead of DE (the actual descriptor). Fixed to PUSH DE/POP DE. Lesson codified as AGENTS.md rule #6 (desk-check register flow before building).
- **User-reported bug:** paused + DEL + Y → the track sliding into the deleted slot started playing. Root cause: `MAIN_DEL_YES2` reused `DEL_STATE` (which held the pre-prompt play state) as index scratch, then force-set `PLAY_STATE=PLAY_PLAYING` before `MAIN_RELOAD_TRACK`.
- **Fix:** pre-prompt state is copied `DEL_STATE` → `NAV_SAVED_STATE` before the scratch reuse, so the v0.0.179 pause-preserve logic in `MAIN_RELOAD_TRACK` handles it (paused → new track paused + "State: Paused"; playing → plays, unchanged from v0.0.171). Redundant force-write removed — the reload tail always sets `PLAY_STATE`.

## Session Delta (2026-07-29, prefix dedup + alignment)

- Version bumped to **v0.0.180**.
- **Redundancy fix:** "Hardware: " was baked into 8 strings (7 `HW_DESC_*` + `MSG_TS_HW_HDR`). Descriptors are now bare; a single padded `MSG_PFX_HW` ("Hardware:   ") is emitted by `PRINT_HARDWARE_CONFIG` and the TurboSound header path.
- **Alignment fix:** field prefixes padded to 12 columns so values line up — `MSG_INPUT` ("Input file: ", already 12), `MSG_PFX_HW` ("Hardware:   "), `MSG_SONGNAME` ("Song name:  "), `MSG_ARTIST` ("by:         "). Applies to plain mode, single-file mode, and the ANSI UI status block (all share the same strings/print path).
- No other references to the descriptor strings expect the old prefix (only `PRINT_HARDWARE_CONFIG` prints them).

## Session Delta (2026-07-29, pause survives nav)

- Version bumped to **v0.0.179**.
- **User-reported bug:** pausing (Space) then moving to another track with WASD/arrows started the new track playing — pause was lost. Root cause: `MAIN_RELOAD_TRACK` unconditionally set `PLAY_STATE=PLAY_PLAYING`.
- **Fix:** `MAIN_NAV_GO`/`MAIN_NEXT`/`MAIN_PREV` save `PLAY_STATE` into new emitted var `NAV_SAVED_STATE` before switching; `MAIN_RELOAD_TRACK` restores `PLAY_PAUSED` (and queues `STATUS_PAUSED` so row 8 / plain status shows paused) when the saved state was paused, then resets `NAV_SAVED_STATE` to `PLAY_PLAYING` so auto-advance/loop/initial-start always play. Silence comes free: the v0.0.173 instant mute runs at switch, and ticks don't run while paused.
- Applies to N/P as well as WASD/arrows (same user intent — "navigate the playlist"); easy to restrict to WASD/arrows if unwanted.

## Session Delta (2026-07-29, playlist auto-advance fix)

- Version bumped to **v0.0.178**.
- **User-reported bug:** in `-list` mode with looping off, a track ending naturally exited the player ("Done...") instead of advancing. Root cause: the `MAIN_LOOP_NODELAY` end-of-track path only advanced when `LOOP_MODE=LOOP_PLAYLIST` — advance and loop were conflated.
- **Fix:** playlist end-of-track now always advances to `TRACK_SELECTED+1`; only the wrap at the last track is gated on `LOOP_PLAYLIST` (otherwise exits after the final track, correct). `LOOP_TRACK` and direct-file paths unchanged.

## Session Delta (2026-07-29, MAX_TRACKS 128)

- Version bumped to **v0.0.177**.
- **User-reported bug:** `-list` showed only the first 32 of 66 `.PT3` files. Root cause: `#DEFINE MAX_TRACKS 32` caps `SCAN_TRACKS` and sizes `TRACK_LIST` (13 bytes/entry).
- **Fix:** `MAX_TRACKS` → 128. Verified no hardcoded 32/64 track-count assumptions elsewhere (nav wrap, DEL clamp, UI all use `TRACK_COUNT`); track indices are byte-sized (255 max). `TRACK_LIST` grows 416 → 1664 bytes; `MUSIC_BUF` moves to `$4308`, leaving ~32KB tune heap (largest corpus PT3 ~20KB, MYM ~12.5KB incl. depack windows) — ample.

## Session Delta (2026-07-29, -help/-loop parser fix)

- Version bumped to **v0.0.176**.
- **User-reported bug:** `vtune -help` printed only the 2-line usage, no help body. Root cause: the primary switch path is `SCAN_CMDLINE_SWITCHES` (substring scan of the command tail, same as `-list`), which didn't know `-help`; the token-path `APPLY_IF_SWITCH` did set `RUN_MODE=RUNMODE_HELP`, but `PARSE_CMDLINE` only short-circuits `ERR_NO_ARG` for `RUNMODE_LIST`, so a switch-only `-help` invocation bailed to `START_NO_ARG` before the help branch could run.
- **Fix:** `-help` and `-loop` added to `SCAN_CMDLINE_SWITCHES`; `PARSE_CMDLINE` now short-circuits to `PARSE_CL_DONE` for `RUNMODE_HELP` in both places it already did for `RUNMODE_LIST`. Side benefit: `-loop` now also registers in `-list` mode (previously lost when the LIST early-done skipped token parsing).
- Static trace verified: `-help` → usage + help body, no AY probe; `-list -loop` / `-loop -list` → `LOOP_PLAYLIST`; `-loop file` → `LOOP_TRACK`. PRTSTR is NUL-terminated, so `$A0`-style port strings in the help body are safe.

## Session Delta (2026-07-29, -loop switch + usage line v2)

- Version bumped to **v0.0.175**.
- Usage line per user spec: `Valid switches: -help -list -loop -delay -msx -rc -coleco -eb`; the "(use -help...)" hint line dropped (`MSG_USAGE_HINT` removed).
- New `-loop` switch: `APPLY_IF_SWITCH` sets new emitted var `LOOP_REQ`; new `APPLY_LOOP_REQ` (called from `START_AFTER_PARSE_OK` after the help branch, before hardware detect) resolves `LOOP_MODE` = `LOOP_PLAYLIST` in `-list` mode, `LOOP_TRACK` for direct-file. Works in either token order (`-loop -list` / `-list -loop`).
- `-help` body reordered to match the usage line and now explains `-loop`.

## Session Delta (2026-07-29, usage reformat + -help switch)

- Version bumped to **v0.0.174**.
- `MSG_USAGE` split into `MSG_USAGE` + `MSG_USAGE_SWITCHES` ("Valid switches: -delay -msx -rc -coleco -eb -list") + `MSG_USAGE_HINT` ("(use -help for switch details)"), all printed by a new shared `PRINT_USAGE` routine (used by no-arg, too-many-args, and help paths).
- New `-help` switch: `APPLY_IF_SWITCH` match sets `RUN_MODE=RUNMODE_HELP` (new define 2); `PARSE_AND_CLASSIFY` accepts it as usage-only (same path as `-list`); `START_AFTER_PARSE_OK` branches to `START_HELP` **before** hardware detection, so help prints without probing the AY. Help body (`MSG_HELP_TEXT`, CR/LF-embedded) describes each switch and the playlist keys.
- Not SIMH-tested (new process rule); logic mirrors the proven `-list` usage-only path.

## Session Delta (2026-07-29, nav-key instant mute)

- Version bumped to **v0.0.173**.
- **User-reported bug:** on a nav-key track switch (WASD/arrows/N/P), the last notes sustained ~300ms before muting — the old AY register state sat on the chip for the whole `MAIN_RELOAD_TRACK` disk I/O until `ENGINE_INIT` muted.
- **Fix:** `MAIN_RELOAD_TRACK` now calls `START_EXIT_SILENCE` (existing TS-aware full mute, no-ops if PSG untouched) immediately at entry, before any disk I/O. One funnel covers all switch paths (nav keys, end-of-track advance, playlist loop); the extra mute on auto-advance is sonically a no-op since the engine already silenced at end-of-tune.
- **SIMH regression (v0.0.173, plain playlist):** N/P switches across PT3↔MYM, pause + nav, Esc quit — all clean.
- **Process rule added (AGENTS.md #5):** SIMH runs only on explicit user request.

## Session Delta (2026-07-29, MYM engine port)

- Version bumped to **v0.0.172**.
- **`vibetune.asm`: real MYM engine** — the milestone-5 stub (14 contiguous bytes/frame from `MUSIC_BUF`, garbage audio, ~6s "duration") is replaced by a faithful port of the MYMPlay 0.4 depacker from `VibeTune-old/vibetune.asm:5161-5439`:
  - New routines `MYM_INIT` / `MYM_EXTRACT` / `MYM_READBITS` (+ `MYM_REGBITS` table) decode one 128-frame fragment per call into rotating register windows; bit-reader state lives in the EXX bank between calls (verified: nothing else in this build touches EXX).
  - Depack layout overlaid at `MUSIC_BUF`: `MYM_UNCOMP` (3*128*14 = 5376 bytes of windows), then `MYM_ROWS` (row-count word) / `MYM_DATA` (packed stream). `LOAD_MUSIC_FILE` now loads MYM files at `MYM_ROWS` (and computes `MUSIC_SIZE` from that base); PTx still loads at `MUSIC_BUF`.
  - `ENGINE_INIT_MYM` = `MYM_INIT` + two priming `MYM_EXTRACT` calls (double-buffer scheme from the old `gomym`); idempotent for `MAIN_RELOAD_DIRECT` loop-track.
  - New `MYM_ENGINE_TICK`: gathers 14 register bytes (stride 3*FRAG) into `MYM_FRAME` scratch, flushes via existing `PSG_ROUT_BLOCK` (keeps its reg-13 `$FF` skip); at fragment boundary swaps to the pre-depacked window (saved IY) and depacks the next; `MYM_EXTRACT` CF=0 → silence + `PLAY_STOPPED` (existing loop/advance handling takes over).
  - MYM state (`MYM_PLAYED/DEST1/DEST2/PSOURCE/PROWS/NEXT_SRC/CURRENT/FRAME`) in pre-VARS heap; emitted `MYM_STATE_PTR` removed.
  - `VALIDATE_MYM_STRUCTURE` no longer requires row-count low byte `$92` (corpus accident); now rejects only zero row count or high byte ≥ 64.
  - Did **not** port: old `upsg` (NABU reg-7 hack, direct port I/O) — `PSG_ROUT_BLOCK` covers it; old `gomym` timing tweak — `timing.inc` already applies the −125 MYM QDLY bias.
- **SIMH/ZPM3 verification (v0.0.172, telnet driver):**
  - `vtune demo3` (DEMO3.MYM, 3218 rows ≈ 64s): plays to natural end-of-tune → "Done..." + clean prompt (stub lasted ~6s).
  - `vtune demo` (125s): still playing at 70s, clean Esc quit.
  - Playlist plain mode: `n` advance PT3 → DEMO.MYM → DEMO1.MYM → DEMO3.MYM, each loads/plays via `MAIN_RELOAD_TRACK`.
  - ANSI+colour 80x24: multicolumn UI intact, arrow nav `ESC[C`×2 → `ESC[B` lands on DEMO4.MYM tile and plays it, `ESC[B` → NAMIDA.PT3, bare Esc → "Done...".
  - PT3 regression: `vtune yeovil`, `vtune namida` (metadata intact) both clean.
- Note: VTUNE.CFG on the SIMH disk does not survive the `BuildDsk.ps1 hd1k_combo` rebuild (combo image is regenerated from `hd1k_zpm3.img`; SIMH-session writes are lost). Recreate with `vtunecfg` → A → Y → Esc after each image sync.

## Session Delta (2026-07-28, DEL file deletion)

- Version bumped to **v0.0.171**.
- Triple-DEL/BS arms deletion of the selected playlist track (any other key resets the count); `ESC[3~` maps to the same arm via `UI_ESC_SEQ` returning A=2. Force-pause + mixer mute, Y/N confirm prompt (row 8 in UI mode, scrolling line in plain), Y → delete via BDOS fn 19, `SCAN_TRACKS` re-enumeration, index clamp, full UI redraw, track at slot plays. Cancel resumes prior play state.
- SIMH-verified: cancel path resumes; real delete of a copied file removed it from disk ("No File" on subsequent access), list redrawn with 23 tracks, replacement track at the slot played.

## Session Delta (2026-07-28, WASD/arrow playlist nav)

- Version bumped to **v0.0.170**.
- `uian.inc`: `UI_NAV_UP/DOWN/LEFT/RIGHT` with old-`PLAYLIST_MOVE_WASD` wrap semantics (marker == current track; a move switches track), `UI_PL_ROWS`/`UI_PL_COL_OF` helpers (AF preserved across `UI_CALC_COLS`), `UI_ESC_SEQ` decoding `ESC[A/B/C/D` and `ESC[O` variants with $40-iteration spin windows. `vibetune.asm`: `MAIN_NAV_GO` / `MAIN_ESC` dispatch.
- SIMH-verified exact tile walk: ATTACK→BACKUP→BADMICE→BACKUP→ATTACK→YEOVIL (`w` wrap)→SYNCH (`[A`)→SANXION (`[D`)→YEOLDE (`[B`)→YEOVIL (`[C`), Esc → Done.

## Session Delta (2026-07-28, CLI hardware override flags)

- Version bumped to **v0.0.167** (spanning v0.0.161-167 parser iterations).
- Three stacked parser bugs fixed in `vibetune.asm`: `STRCMP_UP` discarded its own `CP C` result via `POP AF` (never matched) and left HL advanced on partial match (fixed: PUSH/POP HL around the walk); `PARSE_TOK_DISPATCH` destroyed the tail pointer with `LD HL,ARG_SCRATCH` (fixed: PUSH/POP HL around `APPLY_IF_SWITCH`). Defensive ZPM3 fallback added in `GET_CMD_TAIL_LEN` (scan-to-terminator when `$0080`=0; turned out unnecessary but harmless).
- SIMH-verified matrix: `-rc`/`-coleco`/`-eb`/`-msx` in both token positions, `-msx -delay` combo, `-list -rc`, defaults.
- Driver fix: `scripts/Drive-SIMH-Attach.py` `clean()` replaces `\ufffd`; `META_SNAPSHOT` (v0.0.169) blanks metadata for non-PTX engines and sanitizes to 32..126 (MYM garbage bytes ≥$80 crashed the driver).

## Session Delta (2026-07-28, vtune ANSI playlist UI)

- Version bumped to **v0.0.160**.
- **New file `uian.inc`** (included from `vibetune.asm` after `timing.inc`): full ANSI/VT100 playlist UI ported from VibeTune-old, adapted to the current 13-byte `TRACK_LIST` format:
  - Screen layout: row 1 banner (cyan), row 2 key help (yellow), row 4 input file, row 5 hardware, row 6 song name, row 7 artist, row 8 status (green Playing / yellow Paused), rows 10+ playlist tiles, loop status one row below the last tile row.
  - Multicolumn tiles: marker (`>`) + 12-char name + 3-space gap = 16 chars; columns = `CFG_COLS/16` (5 per row at 80 cols).
  - `UI_ACTIVE` = `-list` mode AND (`DISP_MODE` ≠ plain OR ANSI-colour flag); every UI routine no-ops otherwise, so plain and single-file paths are byte-for-byte the old scrolling behaviour.
  - Deferred updates only (via existing `STATUS_MSG_PENDING`/`PRINT_DEFERRED_STATUS` hook after `WAITQ`) — no console I/O inside the frame wait, avoiding audio jitter. New status codes `STATUS_LOOP_UI=6`, `STATUS_REDRAW=7`.
- **`vibetune.asm` integration:**
  - `DETECT_DISPLAY_MODE` now loads VTUNE.CFG bytes 2-4 into new emitted vars `CFG_FLAGS`, `CFG_ROWS` (0→24), `CFG_COLS` (0→80).
  - `PRTCHR` now preserves AF (same ZPM3 BDOS-fn2 bug as vtunecfg v0.0.158; load-bearing for the ANSI emit loops).
  - Keys: `l` = toggle loop-track, `L` = toggle loop-playlist (mutually exclusive; same key again = off); `R`/`r` = full UI redraw. Plain mode keeps the scrolling "Loop mode:" messages.
  - `n`/`p` and playlist end-of-track advance record `TRACK_OLD`; reload path redraws the two affected tiles only (marker delta).
  - `META_SNAPSHOT` copies PT3 title/author from `MUSIC_BUF+$1E/+$42` (32 chars, bytes <32 sanitised to spaces) into pre-VARS heap (`METATITLE`/`METAARTIST`, survives `HEAP_CLEAR`); shown in UI rows 6/7 and as `Song name:`/`by:` lines in plain/single-file mode.
  - Quit/end paths call `UI_EXIT_TO_PROMPT` (park cursor below the list, reset colour) before `START_EXIT`.
- **SIMH/ZPM3 verification (v0.0.160, telnet driver):**
  - ANSI+colour 80x24: `ESC[2J` frame, cyan/yellow/green sequences, 5 tiles/row, `>`+yellow marker on current track, metadata rows populated from PT3 headers, "Looping Status: Off→Track→Playlist→Off" on `l`/`L`/`L`, Space pause/resume recolours row 8, `R` full redraw, Esc → `ESC[18;1H` + colour reset + "Done...".
  - VT100 (colour off): identical layout with cursor addressing/`EL2`, zero colour sequences.
  - Plain: legacy scrolling output preserved; `n`/`l`/Esc unchanged + new metadata lines.
  - Single-file `vtune rl2wof`: unchanged scrolling output + metadata lines, clean Esc exit, in all display modes.
  - No NUL bytes observed in any stream.
- **New tool `scripts/Drive-SIMH-Attach.py`:** attach variant of `Drive-SIMH.py` — connects to an already-running ZPM3 session (boots 2.4 only if the boot prompt is seen) and leaves SIMH running, so multiple test batches can share one emulator instance. (The original driver's end-of-run `\x05`+`q` quit races with a running program and leaves stale SIMH instances holding port 2323; kill with `taskkill //IM altairz80.exe //F`.)
- **Deferred:** WASD/arrow matrix navigation in the playlist, DEL-file deletion, CLI hw overrides, MYM decode.
- SIMH image config left at ANSI + colour + 80x24.

## Session Delta (2026-07-28, vtunecfg ruler-erase bugs)

- Version bumped to **v0.0.159** (via v0.0.158).
- **User-reported bug:** shrinking rows/cols through a decade (e.g. 30 → 29) erased the tens digit of the ruler label but left the `0` behind. Two stacked latent bugs, **both inherited from the old `vibetune -config` code**:
  1. **`PRTCHR` clobbered A** (v0.0.158 fix): on ZPM3/CPM3, BDOS fn 2 returns A=0, so `LD A,' '` + 3× `PRTCHR` emitted space+NUL+NUL — terminals ignore NUL, so only the first char of each ruler-label erase worked. Fix: `PUSH AF`/`POP AF` in `PRTCHR`.
  2. **`TCFG_SIZE_IS_DECADE` returned Z in all cases** (v0.0.159 fix): the `LD A,1` in the decade-return path does not affect flags, so Z from the final `SUB` survived and every caller's `JR Z` was taken — the incremental decade print/erase paths in `TCFG_SIZE_UPDATE_ROWS`/`_COLS` were dead code. Fix: `OR A` after `LD A,1`. (Draw-scales redraw had masked this; with it active the paths now run as originally designed.)
- **SIMH byte-level verification (v0.0.159, telnet driver):** full stream has zero NULs; 29→30 prints the `30` label twice (update + scales redraw); 30→29 erases with real spaces twice and never redraws; column decade 81→80 restores top-ruler `80`; save+quit works.

## Session Delta (2026-07-28, vtunecfg interactive)

- Version bumped to **v0.0.157** in `vtversion.inc`.
- **`vtunecfg.asm` rewritten:** bare `vtunecfg` now launches the interactive configuration ported from VibeTune-old's `-config` (`termcfg.inc` + TCFG_* block in old `vibetune.asm`):
  - Term type prompt (P=plain / V=VTxxx / A=ANSI, Enter keeps).
  - ANSI colour yes/no prompt (Enter keeps).
  - Interactive size-tuning grid (rulers, `C`/`R`/`X` markers) with `a/d/w/s` **and arrow keys** (CSI and SS3 sequences), bounds 20-150 cols × 8-50 rows, Esc = save+quit.
  - Colourised headers/prompts when ANSI colour enabled; clear-screen/erase-line only emitted when term ≠ plain or colour on (same gating as old code).
- **VTUNE.CFG record extended to 5 bytes:** `$A5`, term (0-2), flags (bit0 = ANSI colour), rows (0→24), cols (0→80). Byte 1 unchanged, so **vtune.com's existing reader is unaffected** (comment in `vibetune.asm` updated to document bytes 2-4 for the future ANSI rendering work).
- One-shot modes kept: `plain|vt100|ansi|0|1|2` now set term type **preserving** flags/rows/cols; `show` prints full summary (term/colour/size); `verify` round-trips all 4 fields.
- **SIMH/ZPM3 verification (v0.0.157):**
  - Interactive session driven via telnet driver: missing-file defaults shown → `A` + `Y` → grid drawn correctly (rulers/markers at right positions) → `ddd ss` → arrow right/up → final **84 x 25** → Esc → "Saved VTUNE.CFG" + summary ANSI/yes/84x25.
  - `verify` → PASS; `show` reads back ANSI/yes/84x25.
  - One-shot `plain` / `1` / `ansi` write correctly and preserve colour+size; `bogus` → usage.
  - Player smoke: `vtune rl2wof` with extended ANSI record → plays, clean Esc exit. Image config left at PLAIN.
- `scripts/Drive-SIMH.py`: added `RAW:` prefix (raw keystrokes without trailing CR, backslash escapes decoded) for driving interactive programs; `::N` suffix sets per-command drain time.

## Session Delta (2026-07-28)

- Version bumped to **v0.0.156** in `vtversion.inc`; build date **28-Jul-2026**.
- `Build.cmd` now also assembles `vtunecfg.asm` → `vtunecfg.com` and copies it to `../RomWBW/Binary/Apps/` (previously it was never wired into the build; the Apps copy was a stale v0.0.32).
- **SIMH/ZPM3 verification of `vtunecfg.com` (v0.0.156)** — all paths pass:
  - `show` with no file → "not found; using default mode" + PLAIN.
  - `vt100` / `ansi` / `plain` / numeric alias `2` → "Wrote VTUNE.CFG mode: X"; read-back via `show` correct each time.
  - `verify` → PASS (roundtrip write + read + compare).
  - `bogus` → error + usage line.
  - `dir vtune.cfg` confirms file on A: user 0, 1 record (128 bytes).
  - HDSK writes work despite the SIMH "Forcing WRTLCK" warning on attach.
- **Player smoke test:** with `VTUNE.CFG` mode=ANSI present, `vtune rl2wof` loads, prints status, plays, clean Esc exit. Config load path OK in v0.0.156. Mode reset to PLAIN afterwards.
- **SIMH automation findings (documented in `docs/SIMH-Testing.md`):**
  - Piped stdin does not reach the guest console (confirmed); telnet console (`set console telnet=2323`) + `scripts/Drive-SIMH.py` works reliably. Config: `../RomWBW/Tools/simh/Sim.vtunecfg-test.cfg` (lives outside the repo).
  - `BuildImg.ps1 hd1k_zpm3` rebuilds from staging dirs and does **not** pick up fresh binaries — patch the image with `cpmrm`/`cpmcp` into user 0, then re-concat via `BuildDsk.ps1 hd1k_combo` (this is how the stale v0.0.32 got into the earlier test).
- Test residue: `hd1k_combo.img` ZPM3 slice now contains `VTUNE.CFG` (mode PLAIN) on A: user 0 — harmless, per-image state only.

## Session Delta (2026-06-17, handover)

- Reviewed open todo list with user; identified historical items still not covered in current code:
  - Full interactive `-list` UI with ANSI/VT100 rendering and PT3 metadata (`ProjectGoals.md` §8.3).
  - Full MYM decode/decompression (`PlaybackEngineSkeleton.md` §4.2.1).
  - `engine_query` runtime metadata interface (`PlaybackEngineSkeleton.md` §2.3.4).
  - CLI hardware override flags (`-msx`, `-rc`, `-eb`, `-coleco`) still stubbed (`ImplementationPlan.md` §3.12.4).
  - PT3 metadata header print (song name/author).
  - Loop toggle polish (`l` currently only acts at end-of-track).
  - TurboSound per-quark overhead reduction (long-term optimization).
  - VGM support remains out of scope.
- Proposed phased plan: (1) PT3 metadata, (2) ANSI/VT100 rendering, (3) MYM decode, (4) CLI overrides + loop polish, (5) optimization.
- **User decided to pivot focus to `vtunecfg.com` before starting Phase 1.**
- Inspected `vtunecfg.asm` (v0.0.155): small CP/M utility that writes `VTUNE.CFG` (magic `$A5` + mode byte), supports `plain|vt100|ansi|show|verify`, uses BDOS FCB/DMA calls, restores default DMA on exit.
- No code changes made in this turn; `HANDOVER.md` updated for next-agent handoff.

## Session Delta (2026-06-17)

- Version bumped to **v0.0.155** in `vtversion.inc`; build date updated to **17-Jun-2026**.
- Build verified: `cmd /c Build.cmd` → TASM passes, `vtune.com` copied to `../RomWBW/Binary/Apps/`.
- Created `AGENTS.md` with permanent rules:
  1. Increment `VT_VERSION` z-component and update `VT_BUILD_DATE` to system date on every `vibetune.com` compile.
  2. Update `HANDOVER.md` with new findings and steps taken.
  3. Do not reintroduce abandoned clean-room engine / unsafe buffer scans / `.DS` in COM image.
  4. Prefer minimal changes.
- Historical to-do audit (`archive/docs/`): real PT2/PT3 decode, TurboSound routing, and CLI hardware overrides are complete. Still open from historical docs:
  - Full interactive `-list` UI with ANSI/VT100 rendering and PT3 metadata (song name/author).
  - Full MYM decode/decompression (current tick assumes unpacked 14-byte frames).
  - `engine_query` runtime metadata interface (deferred).
  - TurboSound per-quark overhead reduction (long-term).
  - VGM support (out of scope).
- **ANSI/VT100 status:** `DISP_MODE` is loaded from `VTUNE.CFG` and validated, but no rendering path branches on it. Current output is plain text only.
- Open item from root handoff updated: Pop / `-list` whine marked resolved.

## Session Delta (2026-06-13, final)

- Version bumped to **v0.0.154** in `vtversion.inc`.
- **SC126 forced `-delay` — hardware verified (v0.0.152–153):** `vtune rl2wof -delay` on RCZ180 EB (platform 10): **94 BPM**, clean channels, no drift/blips. Timer mode without `-delay` unchanged. RC2014 `rl2wofts` auto-delay still **94 BPM**.
- **Exit message:** `Exiting.` → `Done...` (v0.0.154).

### SC126 forced-delay fix summary (v0.0.152–153)

| Symptom | Root cause | Fix |
|---------|------------|-----|
| 114 BPM (want 94) | `QDLY0` scales with CPU kHz but `-185` bias is absolute; Z180 base ~2× RC2014 | `FORCED_DLY_HWTIMER` flag + `SC126_DLY_SCALE` (×155/128) on single-chip PTx delay |
| White-noise / rhythmic fuzz | HBIOS timer IRQ during `WAITQ_DLY` busy-wait | v0.0.152: DI/EI around delay loop (superseded by v0.0.153) |
| Out-of-phase blips/blops | IRQ during Bulba quark computation and between ROUT `EI` and next frame | v0.0.153: `FORCED_DLY_FRAME_BEGIN`/`END` (DI through play+wait); ROUT defers `EI` when flag set |

**Discriminator:** `FORCED_DLY_HWTIMER=1` only when `-delay` forced **and** live HBIOS `$D0` tick ≠ 0. RC2014/RCZ80 never sets it — native delay path byte-identical to v0.0.148.

**Calibration (SC126, `rl2wof -delay`):** CPU kHz `0x4800`, QDLY0 `0x2400`, after bias `0x2347`, final QDLY `0x2AA9` (×155/128).

## Session Delta (2026-06-13, continued)

- Version bumped to **v0.0.153** in `vtversion.inc`.
- **SC126 forced `-delay` corruption (v0.0.153):** v0.0.152 DI/EI only around `WAITQ_DLY` eliminated white-noise but channels still drifted — root cause was HBIOS timer IRQ during engine quark computation and between ROUT's `EI` and the next frame. Fix: `FORCED_DLY_FRAME_BEGIN`/`END` bracket play+wait in `MAIN_LOOP`; suppress ROUT `EI` when `FORCED_DLY_HWTIMER` (defer to frame end).
- **SC126 forced `-delay` tempo (v0.0.152):** **94 BPM verified** on `rl2wof -delay`; `SC126_DLY_SCALE` (×155/128) correct as-is.
- **`PRINT_TIMING_DEBUG`:** disabled again after SC126 tempo confirmation.

Hardware verification (v0.0.152–153) — **complete:**

- **SC126 / RCZ180 EB:** `vtune rl2wof -delay` — **94 BPM**, clean channels ✓
- **RC2014 / RCZ80:** `vtune rl2wofts` — **94 BPM** unchanged ✓

## Session Delta (2026-06-13)

- Version bumped to **v0.0.152** in `vtversion.inc`.
- **SC126 forced `-delay` (single-chip PTx):** `PROBETIMER` sets `FORCED_DLY_HWTIMER` when `-delay` is forced on a board with a live HBIOS timer tick (SC126); RC2014/RCZ80 never sets this flag (no timer).
- **Tempo:** `APPLY_QDLY_SC126_SCALE` / `SC126_DLY_SCALE` scales QDLY by **155/128** (~114→94 BPM starting estimate) for single-chip PTx delay only; TurboSound dual RC2014 trim path untouched.
- **Corruption:** `WAITQ_DLY` runs under `DI`/`EI` when `FORCED_DLY_HWTIMER` is set so HBIOS timer interrupts cannot jitter the delay frame.
- **`PRINT_TIMING_DEBUG`:** re-enabled (`.IF 1`); prints platform id and `forced-dly-hwtimer` flag — remove after SC126 hardware confirms 94 BPM and clean channels.

Hardware verification needed (v0.0.152):

- **SC126 / RCZ180 EB:** `vtune rl2wof -delay` — expect ~94 BPM, clean channels; debug line should show `platform=8`, `forced-dly-hwtimer=1`, scaled QDLY ~10921 from base ~9031.
- **RC2014 / RCZ80:** `vtune rl2wofts` (auto delay) — must remain **94 BPM** (v0.0.148 calibration); `forced-dly-hwtimer=0`.

## Session Delta (2026-06-11 to 2026-06-12)

- Version bumped through **v0.0.148** in `vtversion.inc`.
- **TurboSound runtime (v0.0.131–132):** full dual-chip path (`TS_INIT` / `TS_PLAYQUARK` / `TS_MUTE`), Coleco chip-2 fallback `$50/$51`, `TS_VERIFY_DUAL_PORTS`, per-chip `VT_/NT_` context save, tune-style `TS_INIT` ordering.
- **TurboSound delay tempo (v0.0.136–148):** see postmortem below — **v0.0.148** lands **94 BPM** on RC2014 delay mode for `rl2wofts`.
- **TurboSound exit (v0.0.134–135):** hardware mute before BDOS; `BDOS` fn 0 return; disable Bulba `LoopChecker` (CHECKLP `POP` corrupted stack); `FLUSH_KEYS` on quit.
- **Repo hygiene:** planning docs moved to `archive/docs/`; active specs/scripts under `docs/` and `scripts/`.

Hardware/behavior validation from this session:

- `vtune rl2wof` on RCZ180 EB and MSX: playback good (single-chip baseline).
- `vtune rl2wofts` on MSX (TurboSound): **playback good (v0.0.132+)**; **clean Esc exit (v0.0.135)**.
- **RC2014 / RCZ80 (delay auto-fallback):** `vtune rl2wofts` — **94 BPM verified (v0.0.148)**; QDLY final `0x683` (1667), trim **986** loops after `TS_ADJTIM`.

Immediate next debugging target:

- PT3 metadata header print; loop toggle polish; optional `-list` UX refresh.

## Goal

RomWBW CP/M player (`vtune.com`) for PT2/PT3/MYM on real hardware (SC126 / RCZ180 EB, ZPM3, F3:), comparable to `tune.com`. Bulba engine; clean-room engine abandoned.

## State

- **TurboSound:** auto-detected dual PT3 (`rl2wofts`); prints both chip port sets; MSX + Coleco fallback when HBIOS has no second device query.
- **PT3 playback:** both ProTracker-family and Vortex-family PT3 files now use the Bulba engine. `ATTACK.PT3` was hardware-verified after removing the old Vortex proof stub.
- **`-list` mode:** bare `vtune -list` now scans the current drive, prints the discovered tracks, selects the first one, and enters playlist playback.
- **`-delay` CLI:** `vtune rl2wof -delay` enters delay mode on hardware. SC126 forced-delay tempo + corruption **hardware-verified (v0.0.152–153)**.
- **Hardware verification summary:**
  - **v0.0.113:** SC126 / RCZ180 EB and RC2014 / RCZ80 startup is clean (no pop).
  - **v0.0.114:** temporary startup debug markers used for isolation were removed.
  - **v0.0.108:**
  - **SC126 / RCZ180 EB:** `vtune rl2wof` → timer mode; `vtune rl2wof -delay` → delay mode. Confirms explicit `-delay` flag works correctly.
  - **RC2014 / RCZ80:** Auto-fallback to delay mode (no timer hardware). Delay mode playback tested and working.
- Build: `Build.cmd` → TASM `-t80 -g3 -fFF -dWBW` → `vtune.com` → `..\RomWBW\Binary\Apps\vtune.com`.
- Deploy: ZPM3 **ZMD** v1.50, `zmd r`, **Y-Modem** (1024-byte CRC blocks) — not ZMODEM.
- Version: `vtversion.inc` (`v{version}, {date}` banner).

## Engine

- **Bulba PT2/PT3** from RomWBW `tune.asm`: `pt3bulba.inc` + `pt3bulba_shim.inc`. Init `CALL BULBA_START`; tick `CALL BULBA_START+5`.
- **Do not** reintroduce clean-room engine (`archive/cleanroom/`).

## Three fixes that made playback work (do not regress)

1. **Flat `.COM` image** — no `.DS` in emitted region; file ends at `HEAP` (like `tune.com`). `.DS` between code shifts load addresses → silent crash.
2. **`HEAP_CLEAR` starts at `VARS`, not `HEAP`** — preserves parse buffers / `BULBA_PORTS` below `VARS`.
3. **`PROBETIMER` uses `RET Z`** (not `RET NZ`) — nonzero HBIOS tick ⇒ timer mode (`timing.inc`).

## CLI / `-delay` (v0.0.104)

**Model (match tune.com):**

- Filename from CP/M default **FCB (`$5C`)**; tail token walk for trailing switches when FCB holds the name (`PARSE_SWITCH_ONLY`).
- **`-DELAY` only via `APPLY_DELAY_FROM_CMDLINE`:** after banner, **before any BDOS/file I/O** — same timing as tune `CLI_HAVE_DELAY_SWITCH`.
- **`GET_CMD_TAIL_LEN`** → **`STRINDEX_TUNE_LEN`** on `-DELAY` (case-sensitive, tune `STRCMP`); **clear `DELAYMD` then set** if found.
- Other switches (`-list`, `-msx`, …): **`SCAN_CMDLINE_SWITCHES`** with **bounded** tail (`STRINDEX_UP_LEN`); FCB name field for leading switches only.
- Token walk **`APPLY_IF_SWITCH`** remains backup for `-delay` / `-list` in tail.

**Symbols:** `DELAYMD`, `WMOD`, `PROBETIMER`, `PRINT_TIMING_MODE` in `timing.inc` / `vibetune.asm`.

## Hardware / ports / timing

- Ports: HBIOS `BF_SNDQUERY` + probe + CLI (`-msx -rc -coleco -eb`). EB on target: **$68/$60**.
- `-delay` → `DELAYMD=1` → delay loop; else timer when HBIOS timer live.
- **Auto-selection matches `tune.com`:** `PROBETIMER` does a live HBIOS `BF_SYSGET` / `$D0` tick probe. If `DE:HL == 0`, stay in delay mode; if nonzero, use timer mode. This is not a hardcoded SC126/RC2014 split, so RC2014/RCZ80 systems without a live timer should fall back to delay automatically.

## Audio policy (keep)

- **Pause (v0.0.108):** Zeros amplitude registers (8-10) + mixer reg 7 = `$3F` for complete 100% note mute. Resume continues from engine's exact internal position.
- Exit mute via ROUT only when `PSG_TOUCHED`.

## SIMH (non-hardware)

- See `docs/SIMH-Testing.md`. Launch scripts were removed from repo root in this session; use RomWBW tooling or restore from git history if needed.
- Boot **`2.4`** (not `2`, not `3.x`); image **`hd1k_combo.img`**.
- Piped keystrokes into SIMH on Windows unreliable; use interactive boot.

## Known problems (user-reported, still open)

| Issue | Notes |
|-------|--------|
| **Startup pop(s)** | **Fixed (v0.0.113, cleanup v0.0.114):** root causes documented below; validated clean on SC126 and RC2014. |
| **Pause sustain** | **v0.0.108 verified:** Pause cuts all notes cleanly (zeros amplitude regs 8-10 + mixer). Resume continues from exact engine state—no skipped notes. ✓ |
| **Loop toggle (`l`)** | Deferred status OK v0.0.89; host `LOOP_MODE` only at end-of-track. |
| **PT3 metadata** | Need full header print (song name `$1E`, author `$42`, etc.); see `docs/PT3FormatSpec.md`. |
| **Delay mode too fast / fuzzy** | **Fixed (v0.0.152–153):** SC126 forced `-delay` — 94 BPM + clean channels on `rl2wof`. RC2014 TS dual delay fixed v0.0.148 (~94 BPM `rl2wofts`). |
| **`-list` playlist UX** | Core behavior works: scan, first-track autostart, `N`/`P` navigation. Keep an eye on metadata/status refresh when switching tracks. |

## `-delay` parser history (compressed)

| Build | Result | Cause / note |
|-------|--------|----------------|
| v0.0.91 | Multiple-args error | Token parser rejected trailing `-delay`. |
| v0.0.92–95 | Regressions | CR tail, stack clobber, `B` zeroed, fragile token loop. |
| v0.0.96–99 | Play OK; `-delay` wrong | FCB-first parse; tail scan / token issues. |
| v0.0.100–102 | Timer with `-delay` | Scan missed switch (incl. `$5C-$FF` abort on FCB NULs in v0.0.101). |
| v0.0.103 | **Always delay** | Unbounded scan past empty `$81` into stale buffer; `DELAYMD` never cleared; `DELAYMD_SAVED` sticky. |
| v0.0.104 | **Fix attempt** | Bounded tail only; clear-then-set; one `-DELAY` check after banner; no `DELAYMD_SAVED`. |
| v0.0.105–107 | **Fix verified** | Restored tune-like `CLIARGS` substring handling; hardware now shows timer mode without `-delay` and delay mode with `-delay`. |

## Startup pop postmortem (v0.0.109-v0.0.113)

Two separate startup-audio defects existed and were fixed in stages.

1. **Pop at/after hardware probe (first defect):**
  - Probe writes `R2=$AA` to test AY presence (`PROBE_AY_PORTS`).
  - Startup PSG state is unknown, so probe activity could leak audible transitions.
  - Initial mitigation in v0.0.109: call `PSG_MUTE_DIRECT` after detection/probe and again before engine init. This reduced startup pops from two to one.

2. **Pop + temporary high-pitched whine around probe success (second defect):**
  - Isolated using single-character startup markers with per-marker pauses on hardware.
  - Repro showed event between probe success (`E`) and post-detect stage (`2`).
  - Root cause: `PROBE_AY_QUIET` wrote mixer register 7 to `$3F` (mute mixer) but wrote amplitude registers 8/9/10 to `$0F` (max volume), not zero.
  - This left channels armed at max amplitude; later register activity could produce a pop/whine burst until full mute/path initialization completed.

Final fix (v0.0.113):
- Change `PROBE_AY_QUIET` amplitude writes for regs 8/9/10 from `$0F` to `$00`.
- Keep post-detection `PSG_MUTE_DIRECT` for full-register safety cleanup.

Validation:
- SC126 (RCZ180 EB): clean startup, no pops.
- RC2014 (RCZ80): clean startup, no pops.

Cleanup (v0.0.114):
- Removed temporary debug marker output and keypress pauses used during isolation.

## PT3 playback postmortem (v0.0.124)

`ATTACK.PT3` exposed that PTx classification and PTx playback were not using the same capability boundary.

- Detection/classification already recognized both ProTracker-family and Vortex-family PT3 headers.
- Only ProTracker-family PT3 files used the Bulba engine.
- Vortex-family PT3 files were still routed into an old proof/stub path that only poked one PSG register, so valid files classified as Vortex appeared silent.

Final fix (v0.0.124):
- Keep the Vortex/ProTracker variant distinction for display only.
- Route both PT3 header families through the same Bulba init/tick path.

Validation:
- `ATTACK.PT3` now plays on hardware.
- `RL2WOF.PT3` and `RL2WOFTS.PT3` continue to play.

## TurboSound postmortem (v0.0.131–v0.0.135)

`RL2WOFTS.PT3` (packed dual PT3) regressed after Bulba integration. Several independent defects stacked:

1. **Wrong chip-2 Coleco ports** — fallback used swapped RSEL/RDAT vs tune/RomWBW (`$50/$51` standard).
2. **Shared `VT_/NT_` workspace** — `TS_PLAYQUARK` switched channel state but not unpacked tables; caused garbled audio until per-chip `TS_CTX1/2_VTNT` save/restore was added.
3. **False dual-hardware** — `TS_DUALHW` could be set without distinct data ports; gated with `TS_VERIFY_DUAL_PORTS`.
4. **Exit stack corruption** — Bulba `LoopChecker` + `CHECKLP` `POP` (loop disabled) removed return addresses during playback; Esc exit then hit spurious parse errors and skipped mute. Fixed by `LoopChecker=0`, mute-before-BDOS, `BDOS` fn 0 exit, `FLUSH_KEYS`.
5. **Exit mute on chip 2** — `PSG_MUTE_DIRECT` only touched MSX `$A0/$A1`; Coleco chip kept sustaining. Fixed with `TS_MUTE_BOTH_HARDWARE` on configured port pairs.

Validation (MSX, delay mode):
- `vtune rl2wofts` — audible dual-chip playback; Esc → silent, single `Exiting.`, clean CCP return (v0.0.135).

## TurboSound delay tempo postmortem (v0.0.136–v0.0.148)

Target: **~94 BPM** for `RL2WOFTS.PT3` on **RC2014 @ 7.3728 MHz** (auto delay mode; HBIOS timer tick = 0). Reference: RomWBW **`tune.com` v3.2b100** reads ~93 BPM on same hardware.

### Root causes (stacked)

1. **WAITQ zero-guard bug (v0.0.141)** — `LD BC,1` ran *before* `JR NZ`, clobbering QDLY every frame → ~1 loop iteration → ~174 BPM. Fixed to match tune.com: test BC first, `LD BC,1` only when QDLY==0.
2. **QDLY apply stacking (v0.0.138)** — `APPLY_ENGINE_QDLY_ADJ` must always derive from HBIOS base in `QDLY0`, not mutate `(QDLY)` in place (was ~163 BPM when stacked).
3. **Failed scale heuristics (v0.0.136–137)** — `×65/94` / divide-first 16-bit routines had overflow and compare bugs (QDLY→0 re-triggered cartoon speed). Abandoned; tune.com path is **one −185**, then **`TS_ADJTIM` (×97/128)** only.
4. **VibeTune vs tune.com play overhead** — At identical post-`TS_ADJTIM` QDLY **2653 (`0A5D`)**, tune.com ≈93 BPM but VibeTune ≈74.5 BPM after WAITQ fix. Cause: per-quark **432-byte `VT_/NT_` LDIR** in `TS_PLAYQUARK` (required for garbled-audio fix); tune.com `TS_PLAYQUARK` calls `PLAY` without that cost.

### Tempo model (why empirical trim was needed)

Frame time ≈ **play_overhead + QDLY × 40 T-states**. BPM is **not** `∝ 1/QDLY`. Inverse-product retuning (`Q_new = Q × BPM_old / BPM_target`) consistently undershot when speeding up; linear extrapolation from early points overshot when pushed too far.

**RC2014 calibration table** (delay, TS dual, after `TS_ADJTIM` baseline 2653):

| Trim | QDLY (hex) | BPM |
|------|------------|-----|
| 0 | 0A5D | 74.5 |
| 528 | 084D | 84 |
| 755 | 076A | 89 |
| 856 | 0705 | 90 |
| **986** | **0683** | **94** ✓ |
| 1084 | 0621 | 97 |

Final trim **986** = bracket between 856→90 and 1084→97: `856 + (94−90) × (228/7)`.

### Pipeline (v0.0.148, `timing.inc`)

1. `INIT_QDLY_BASE`: HBIOS `$F0` → `CPUKHZ`; `QDLY0 = kHz/2` (7372 → 3686 `0E66`).
2. `APPLY_ENGINE_QDLY_ADJ`: from `QDLY0`, subtract **185** (PTX) → `0DAD`; if PTx + TS dual + delay mode: `TS_ADJTIM` → `0A5D`; subtract **986** → **`0x683` (1667)**.
3. `WAITQ`: timer path when `WMOD≠0`; else delay loop (40 T-states/iter, tune.com zero-guard).
4. **`PRINT_TIMING_DEBUG`** (temporary): prints CPU kHz, QDLY0, post-bias, final QDLY, apply count, flags — remove when broader validation done.

### Long-term fix (not done)

Shrink TS per-quark overhead (optimize or reduce `VT_/NT_` context copies) so tune.com QDLY path alone suffices and CPU-specific trim → 0.

Validation (RC2014, delay auto-fallback):
- `vtune rl2wofts` — **94 BPM on the dot (v0.0.148)**; debug line matches table above.

## SC126 forced-delay postmortem (v0.0.152)

Target: **~94 BPM** for single-chip PTx (e.g. `RL2WOF.PT3`) on **SC126 / SCZ180** when `-delay` is forced. Observed before fix: **114 BPM** and channel corruption (rhythmic white-noise / silence). Timer mode on SC126 was clean.

### Root causes

1. **Tempo:** `QDLY0 = CPUKHZ/2` scales with Z180 speed (~9216 vs RC2014 ~3686) but the engine bias subtract (`-185`) is absolute; frame too short → ~21% fast (114 vs 94 BPM).
2. **Corruption:** `WAITQ_DLY` busy-wait is interruptible; SC126 HBIOS timer IRQ fires during the loop and perturbs frame timing. RC2014 has no timer IRQ in delay mode so its loop is naturally undisturbed.

### Fix (gated on `FORCED_DLY_HWTIMER`)

Set in `PROBETIMER` only when `DELAYMD≠0` **and** live HBIOS `$D0` tick is nonzero — exact SC126 forced-delay condition; always false on RC2014.

1. **`SC126_DLY_SCALE`:** `QDLY := QDLY + (QDLY/128)×27` (×155/128). **Verified 94 BPM (v0.0.152).**
2. **Full-quark IRQ shield (v0.0.153):** `FORCED_DLY_FRAME_BEGIN`/`END` in `MAIN_LOOP` (`DI` before play, `EI` after wait); ROUT skips `EI` when flag set. v0.0.152 WAITQ-only DI/EI was insufficient — IRQ during engine computation and between ROUT `EI` and `WAITQ` caused channel drift.

RC2014 native delay and SC126 timer mode are unchanged (flag never set).

### Pipeline (v0.0.152, `timing.inc`)

1. `INIT_QDLY_BASE`: HBIOS `$F0` → `CPUKHZ`; `QDLY0 = kHz/2`.
2. `APPLY_ENGINE_QDLY_ADJ`: subtract **185** (PTX); if single-chip PTx + delay + `FORCED_DLY_HWTIMER`: `SC126_DLY_SCALE`; if TS dual + delay (RC2014): `TS_ADJTIM` + trim **986** (unchanged).
3. `WAITQ`: timer path when `WMOD≠0`; else delay loop. SC126 forced-delay: full-quark `DI`/`EI` via `FORCED_DLY_FRAME_*`.
4. **`PRINT_TIMING_DEBUG`** (temporary): includes platform id and `forced-dly-hwtimer`.

Validation (SC126, forced delay):
- **v0.0.152:** `vtune rl2wof -delay` — **94 BPM** ✓; white-noise eliminated; channel drift remained.
- **v0.0.153:** `vtune rl2wof -delay` — **94 BPM**, clean channels ✓ (full-quark IRQ shield).

## Rejected / do not reintroduce

- **Unbounded `$81` scan** when `$0080=0` — false `-DELAY` in page-zero garbage → always delay (v0.0.103).
- **Full page-zero scan `$5C–$FF`** for switches — FCB interior NUL aborts before `$81` (v0.0.101).
- **`DELAYMD_SAVED` sticky restore** across parse — preserves false positives.
- **Setting `DELAYMD` without clearing first** in final delay path.
- **v0.0.90** pop/whine patches — hung after banner on hardware.
- **v0.0.136–137 QDLY scale routines** (`×65/94`, broken 16-bit divide) — use tune.com −185 + `TS_ADJTIM` + measured trim only.
- **Clean-room engine**, `.DS` in emitted COM, `HEAP_CLEAR` from `HEAP`, inverted `PROBETIMER` test.
- **New brittle SIMH automation** (long waits, piped boot) — use existing scripts only.
- **Standalone `hd1k_zpm3.img` attach** — HALT; use combo + `2.4`.

## Decisions

- Reference player: `..\RomWBW\Source\Apps\Tune\tune.asm` (`cli.inc` / `strings.inc` for `-DELAY`).
- Config: `vtunecfg.com` → `VTUNE.CFG`; no `-config` in player.
- TurboSound: auto from file; no user toggle.
- Versioning: `x.y.z`; bump **z** every build, **y** after successful test + commit.
- **This file** is the single live handoff — update in place, no new dated root handoffs.

## Open / verify

- [x] **SIMH v0.0.156:** `vtunecfg.com` all modes verified on ZPM3 (show/write/read-back/verify/bad-arg); `vtune` smoke test with `VTUNE.CFG` present.
- [x] **SIMH v0.0.157:** `vtunecfg` interactive config (term type, ANSI colour, size grid with arrows) verified end-to-end; extended 5-byte record round-trips; one-shot modes preserve fields; player tolerates extended record.

- [x] **Hardware v0.0.108:** SC126/RCZ180 EB and RC2014/RCZ80 tested; pause/resume flawless; timer mode on SC126 without `-delay`; auto-fallback to delay mode on RC2014 (no timer hardware); explicit `-delay` flag works.
- [x] **Hardware v0.0.113:** Startup pop fix validated on SC126 and RC2014; no pops.
- [x] **v0.0.114 cleanup:** Removed startup debug markers/pause prompts used for pop isolation.
- [x] **Hardware v0.0.124:** Vortex-family PT3 playback fixed; `ATTACK.PT3` now plays.
- [x] **Hardware v0.0.124:** `vtune -list` scans and autostarts playlist playback; `N`/`P` navigation works.
- [x] **Hardware v0.0.131–135:** TurboSound `rl2wofts` on MSX — playback and clean Esc exit verified.
- [x] **Hardware v0.0.148:** RC2014 delay-mode TurboSound tempo — **94 BPM** on `rl2wofts` (trim 986, QDLY `0x683`).
- [x] **Hardware v0.0.153:** SC126 forced-delay — **94 BPM + clean channels** on `rl2wof -delay`.
- [x] Pop / `-list` whine (safer than v0.0.90).

## Key files

| File | Role |
|------|------|
| `vibetune.asm` | Startup, CLI parse, HW detect, load, playlist/loop logic, MYM depack engine (`MYM_INIT`/`MYM_EXTRACT`/`MYM_READBITS`) |
| `pt3bulba.inc` / `pt3bulba_shim.inc` | Bulba player + glue |
| `timing.inc` | `WAITQ`, `PROBETIMER`, `QDLY`/`QDLY0`, `TS_ADJTIM`, `SC126_DLY_SCALE`, `FORCED_DLY_HWTIMER`, TS trim, timing debug print |
| `ansiui.inc` | ANSI/VT100 playlist UI (tiles, metadata, loop status, WASD/arrow nav) |
| `vtunecfg.asm` | Display-mode config utility (term type, colour, screen size) |
| `vtversion.inc` | Version / date |
| `showtail.asm` | One-off debug probe (command-tail inspection); not part of the build |
| `Build.cmd` | Build + copy to RomWBW |
| `HANDOVER.md` | This file |
| `docs/PT3FormatSpec.md`, `docs/SIMH-Testing.md`, `docs/SC126-Forced-Delay.md` | Active specs |
| `archive/docs/` | Superseded planning docs (see `README.md`) |
| `scripts/Validate-StructureChecks.ps1` | Format validation harness |
| `scripts/Drive-SIMH.py` | Telnet-console SIMH driver (see `docs/SIMH-Testing.md`) |
| `scripts/Drive-SIMH-Attach.py` | Attach variant: reuses a live SIMH session, leaves it running |

Reference: `..\RomWBW\Source\Apps\Tune\tune.asm`.

## Session Delta (2026-08-24, branch turbosound-module prep)

- New branch `turbosound-module`: design + skeleton for single-card dual-AVR
  TurboSound module support (chip select via 0xFF/0xFE latch codes on one
  port pair), alongside the existing dual-card topology.
- Added `docs/TurboSound-Module.md` (design: TS_TOPOLOGY flag, vtunecfg CFG
  byte 5 proposal, timing constraints from the AVR RCA session, work items).
- Added `tsmodule.inc` (dormant skeleton: TSMOD_SELECT / TSMOD_SETPORTS1/2 /
  TSMOD_MUTE — not yet included by vibetune.asm, no behavior change).
- No build run (skeleton only, per SIMH/build policy); version unchanged.
- Working-tree edits to vibetune.asm/vtversion.inc (PRTLN cleanup) are the
  user's in-progress work and were deliberately left uncommitted.
- Outstanding: wire TS_TOPOLOGY into TS_PLAYQUARK/TS_INIT/TS_MUTE, CFG byte-5
  load, vtunecfg menu, CLI switch, hardware test on the SC126 module.

## Session Delta (2026-08-24, turbosound-module wiring, v0.0.193)

- Wired the single-card dual-AVR TurboSound module topology into vtune:
  - `TS_TOPOLOGY` (0=auto, 1=dual-card, 2=module); set from VTUNE.CFG byte 5
    (old 5-byte files read as auto) or new `-tsm` CLI switch (forces module).
  - `TS_PORTS_SETUP_MODULE`: skips dual-pair probing (module is Hi-Z on
    reads), enables TS_DUALHW on the single pair.
  - `TS_SETPORTS1/2`: in module mode both use the PORT1 pair and issue a
    `TSMOD_SELECT` ($FF/$FE latch) before each chip's engine tick.
  - `TS_MUTE_BOTH_HARDWARE` routes to `TSMOD_MUTE` (mutes both chips, leaves
    chip 0 selected so a following single-chip tune plays correctly).
  - `tsmodule.inc` is now included by vibetune.asm (TS_TOPO_* defines moved
    to the top of vibetune.asm — TASM #DEFINEs are order-sensitive).
- vtunecfg: interactive TurboSound hardware prompt (A/D/M), summary line,
  CFG byte 5 load/save, verify roundtrip extended to 5 bytes.
- Built clean with tasm (both binaries), version 0.0.193 / 24-Aug-2026.
  No SIMH run (policy); hardware test pending on the SC126 module:
  `vtune RL2WOFTS.PT3 -tsm` (or after vtunecfg sets module mode), plus a
  non-TS regression tune, and a dual-card regression if hardware available.

## Session Delta (2026-08-28, 8.3 filenames + git hygiene)

- Renamed `pt3bulba_shim.inc` → `pt3shim.inc` and `vtversion.inc` → `vtver.inc`
  (8.3 compliance); updated all `#include`s, Makefile, README, AGENTS.md.
- Git history rewritten: stripped `Co-authored-by: cursoragent` trailer from 16
  commits (trees unchanged), force-pushed master; removed `.git/cursor` index cache;
  deleted stray board dump `vtune_board.cfg` from repo; `.codex` gitignored.
- Built clean with tasm (both binaries), version 0.0.242 / 28-Aug-2026.
  No SIMH run (policy); no functional change — filename hygiene only.

## Session Delta (2026-08-28, Esc mangling during track load)

- **Bug:** pressing keys while a track reload (disk I/O + engine init) was in
  progress left partial Esc sequences in the console buffer, mangling later
  arrow-key parsing.
- **Fix:** `MAIN_RELOAD_TRACK` now calls `FLUSH_KEYS` at `MAIN_RELOAD_STATE_OK`,
  discarding any input typed during the load (option 1: ignore keyboard while
  track details load). Register check: `FLUSH_KEYS` clobbers A/C/E only; A is
  reloaded immediately after.
- Built clean with tasm, version 0.0.243 / 28-Aug-2026.
- **Test (hardware):** `vtune -list`, hold/repeat arrow keys while a track
  loads; Esc-to-quit and arrow navigation should stay clean.

## Session Delta (2026-08-28, nav debounce 1 s -> 1.75 s)

- `NAV_DEBOUNCE_LEN` 50 -> 88 frames (~1.75 s): slightly longer settle delay
  after the last nav keypress before a paused-browse track reload starts.
  Playing-state nav still reloads immediately (unchanged).
- Built clean with tasm, version 0.0.246 / 28-Aug-2026.

## Session Delta (2026-10-12, size-reduction pass, v0.1.17)

- Pure size/cleanup pass over vibetune.asm + ansiui.inc (+pt3shim.inc/mymeng.inc);
  no functional change intended. 14808 -> 14446 bytes (-362).
- Deleted dead code: `PSG_WRITE_REG`/`PSG_WRITE_REG_B`/`PSG_WRITE_ROUTED` +
  `PSG_TEMP_VAL` (zero callers); `MSG_PLAYING`; `PSG_MUTE_DIRECT` and
  `PSG_SILENCE` trampolines (callers repointed to `PSG_MUTE_ALL`); `ISHBIOS`
  in pt3shim.inc (only referenced from `#IF 0` blocks); dead second RUN_MODE
  check in `PARSE_CMDLINE`.
- New shared helpers: `EXIT_MSG`/`EXIT_ERR`/`PRTERR` (+ `MSG_ERR_PFX`; "Error: "
  prefix deduped out of the seven MSG_ERR_* strings), BDOS tail-calls
  `BDOS_DMA_DEFAULT`/`BDOS_FCB_OPEN`/`BDOS_FCB_CLOSE`, flag-test subroutines
  `UI_ACTIVE_TEST` (32 sites) and `TRACK_COUNT_TEST` (17 sites), `HBIOS_IDENT_OK`
  (3 sites).
- Inline track-index multiply loops in `TRACK_LIST_ADD` and
  `COPY_SELECTED_TRACK_TO_ARG` replaced with `CALL UI_TRACK_PTR`; redundant
  PUSH/POP wrappers around `CALL UI_CLR_ROW` removed (UI_CLR_ROW preserves all);
  single-use trampolines `START_OK`/`STRINDEX_FCB`/`CLASS_RESOLVE_MISSING_EXT`/
  `PARSE_CLASSIFY_FILE` bypassed.
- `MSG_LOOPSTAT_OFF/TRK/PL` are now `.EQU`s onto the "Off"/"Track"/"Playlist"
  suffixes of `MSG_LOOP_*`; the EQUs live in vibetune.asm after those strings
  because TASM rejects forward references in equates.
- Built clean with tasm, 0 errors (default and MYM builds); uz80as output
  byte-identical to TASM. Version 0.1.17 / 12-Oct-2026.
- No SIMH/hardware run (policy) — regression check on SC126 pending:
  direct play, `-list` ANSI UI nav/loop/delete, `-help`/`-credits`/error paths.

## Session Delta (2026-10-12, branch saa1099: CFG SAA card + exit-mute fixes, v0.1.23)

- Hardware context this session: **RC2014 Zed Mini** (Z80 @ 7.3728 MHz, RomWBW
  platform id 27), EPSAA1099 card at `$FF` (reg select) / `$FE` (data, 8 MHz
  osc), AY card in MSX mode (`$A0/$A1`). ZPM3, deploy target `A1:`.
- v0.1.18: `vtunecfg`/`vtune` accept primary card id **5 = SAA1099** in
  VTUNE.CFG byte 6 (byte 7 stays AY-only). New `HWSTR_SAA` description.
- v0.1.19: SAA exit mute — `START_EXIT_SILENCE` branches to `SAA_INIT`
  (full 32-reg reset = silence) when SAAMD set; `TSMOD_MUTE` would write AY
  register sequences into SAA registers. Hardware-verified.
- v0.1.20: CLI card switches override CFG byte 6 — CFG load no longer
  clobbers a CLI-selected card (plain `VTUNE file` vs `-MSX` were silently
  resolving to the wrong card when CFG primary = SAA).
- v0.1.21–22: **AY-mode exit no-mute fixed** (pre-existing since v0.1.1 —
  VT011/VT116 also affected; user bisected). Root cause: VTUNE.CFG byte 5
  (TS topology) = 2 (module) routed `START_EXIT_SILENCE` to `TSMOD_MUTE`,
  but `TS_PORTS_SETUP` only runs for TS-flagged tracks, so `TS_PORT1_RSEL/
  RDAT` were still 0 — the entire mute+select sequence went to port `$00`.
  Fix: `TSMOD_MUTE` falls back to the play port pair when `TS_PORT1_RSEL`=0
  (correct on real module hardware too: a non-TS track plays on chip 0 of
  the play pair). Verified on hardware: `-MSX` Esc-quit mutes; diag line
  showed `ts=00 dual=00 topo=02 rsel=A0 rdat=A1`; SAA path untouched.
- v0.1.23: TEMP exit diag removed (one-shot hex dump of TS state on exit).
- Behaviour note: quit key is **Esc only** — prompts saying "any key" are
  wrong; do not reintroduce that wording.
- **Version:** v0.1.23 (**14,489 B**). **Deploy:** `A1:VTUNE.COM` on Zed Mini.

## Session Delta (2026-10-15/16, SAA1099 envelope bass + TS, v0.1.32)

- Target: RC2014 Zed Mini (Z80 @ 7.3728 MHz), EPSAA1099 at $FF/$FE, ZPM3,
  deploy `A1:VTUNE.COM`. Test tracks: RL2WOF.PT3 (single), RL2WOFTS.PT3 (TS).
- v0.1.24: SAA software stereo — pan LUTs `SAAVFULL` (AY log -> SAA linear,
  outer side) / `SAAVCTR` (center = FULL x 0.618 golden ratio), applied in
  `SAA_XAMP_CHAN`: A hard left, C hard right, B center. SAA TS banner tag fix.
- v0.1.25: envelope channel remap — enveloped AY channel dynamically swapped
  onto SAA ch 2/5 (the only envelope-modulated channels; datasheet + Furnace
  docs), displaced channel takes the freed slot; enable bits permuted via
  SAAPERM0/1 LUTs.
- v0.1.26: envelope latch fix — shape latched per block (`SAAENVSH`), gen
  programmed when the mapped value differs; previously a new shape and
  envelope use had to coincide in one frame or the gen never started.
- v0.1.27: B pan experiment 100/100 both sides — REJECTED by ear.
- v0.1.28: single-chip fixed channel map A->0, B->2, C->3 (table-driven
  `SAACHMAPS`/`SAABMAPS`, records 0-3 = single chip, 4-7 = TS-dual), freeing
  ch 1 as envelope clock: gen 0 steps at 2 x f_tone(ch1) (MAME saa1099.cpp),
  so ch1 = envper*2 as a silent tone = exact AY env step rate. Noise rate
  mirrored into both gens in single-chip mode (C sits on ch 3 = gen 1).
  First sustain carrier attempt (carrier = note period) — REJECTED by ear.
- v0.1.29: carrier pitch = envelope cycle rate instead (period = envper<<K,
  K=5 for 32-step triangle shapes 10/14, else 4) — on the AY the envelope IS
  the waveform during a tone+noise-off sustain, so the tone period is
  irrelevant there. ACCEPTED by ear (single chip).
- v0.1.30: carrier extended to TS-dual (per-block state, both blocks);
  SAA TS-dual tempo trim 986->1149 (two XLATEs/frame run ~1.1 ms long;
  88 -> 93 BPM on rl2wofts). TS distortion reported in busy later sections.
- v0.1.31: TS forced-carrier sustains play FLAT (envelope generator off —
  no spare clock channel, so the growl rate would wander with the neighbor
  melody; attack frames keep the envelope). envper == 0 (AY frozen-envelope
  idiom) maps to generator off in both modes (was sawtooth warble at the
  neighbor rate).
- v0.1.32: B pan reverted to 62% golden ratio (`SAAVCTR` restored verbatim)
  after the 100/100 experiment. ACCEPTED by ear, single chip and TS.
- Hardware facts captured (MAME saa1099.cpp, master): SAA env gen 0/1 steps
  on tone ch 1/4 toggles (rate = 2 x f_tone); a channel with freq_enable=0
  AND noise_enable=0 outputs nothing (envelope path gated); writing $18/$19
  resets the envelope step; tone counter free-runs regardless of freq_enable.
- Known approximations: AY hold shapes (11/13) -> single decay/attack; TS
  envelope rate approximate (melody-clocked) except flat sustains; TS
  envelope reset-on-rewrite semantics not exactly AY reg-13.
- PT3 analysis tooling lives in the session folder
  (Q:\My Drive\AI\2026-10-14-saa1099-rc2014-test\tmp\): decode_pt3b.py
  (correct Bulba row grammar), scan_env.py (envelope usage scan, both
  modules of a TS file).
- **Version:** v0.1.32 (**15,073 B**), dual-assembler clean (TASM + uz80as
  byte-identical). **Deploy:** `A1:VTUNE.COM`.

## Session Delta — 2026-10-16 (README SAA1099 docs)

- **What:** README.md now documents the SAA1099 backend — intro, `-saa` row in
  the hardware table ($FF/$FE, write-only, never auto-detected; CFG primary
  card 5, not valid as second card), a dedicated "SAA1099" section (software
  stereo pan A→L / C→R / B 62% both; envelope remap to ch 2/5 with ch1-clocked
  envelope + sustain carrier pitched from the envelope period; TurboSound on
  one chip, ch 0–2 + 3–5, second-chip envelopes flat), `-saa` in the usage
  line, `saa1099.inc` in key sources. Repo AGENTS.md key-source list gained
  `saa1099.inc`. Docs-only change — no build, no version bump.
- **Why:** the saa1099 branch shipped with zero user-facing SAA1099 docs.

## Session Delta — 2026-10-17 (SAA card relocated to $75/$74)

- **What:** SAA1099 ports changed $FF/$FE -> $75/$74 everywhere: SAA_RSEL/
  SAA_RDAT in saa1099.inc, -saa help text, MSG_HW_SAA banner, vtunecfg card
  name string. README hardware table + SAA section updated with the Z180
  internal-I/O-window rationale.
- **Why:** $FF/$FE is fatal on Z180 (RomWBW Z180_BASE=$C0 puts ICR at $FF,
  OMCR at $FE): VTUNE -saa on the SC126 reprogrammed the CPU's I/O window and
  hung the machine instantly. Card re-jumpered (J2: fit A7, A3, A1) so one
  address works on RC2014 / Zed Mini / SC126 alike.
- **Version:** v0.1.33, TASM clean, uz80as byte-identical.
- **Verification:** pending on SC126 (no-crash + sound after re-jumper).
- RomWBW side: SCZ180_sc126_std.asm SAAENABLE=TRUE SAABASE=$75;
  RC2014_ZedMini_sc137.asm SAABASE=$75 (SAA already enabled).
