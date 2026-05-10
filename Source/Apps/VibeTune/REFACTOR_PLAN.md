# VibeTune Refactor Master Plan

Date: 2026-04-10
Branch: refactor
Scope: Source/Apps/VibeTune

## 1. Mission
VibeTune has evolved from a small Tune-compatible player into a multi-format, multi-chip, playlist/UI-heavy tool. The current architecture is feature-rich but monolithic, with the following pain points:

- Large source surface (`vibetune.asm` ~7.8K lines)
- Large resulting binary (~20KB class), reducing free TPA/RAM for larger files
- High code duplication in playback control logic
- Tight coupling between playback engines, key handling, playlist control, and UI
- Harder maintenance and higher regression risk for new changes

This plan decomposes VibeTune into clear modules, removes redundancy, and creates a path to smaller/faster binaries and safer evolution.

## 2. Current Composition Inventory
This section identifies the constituent parts and their responsibilities.

### 2.1 Core source files and size
- `vibetune.asm`: ~7816 lines
- `vgm_player.inc`: ~556 lines
- `cli.inc`: ~311 lines
- `termcfg.inc`: ~162 lines
- `printing.inc`: ~175 lines
- `timing.inc`: ~64 lines
- `strings.inc`: ~35 lines

### 2.2 Functional components
1. Startup and runtime orchestration
- Responsibilities: BIOS/platform checks, timer mode setup, CPU speed handling, heap clear, file loop orchestration, exit flow
- Primary locations: `vibetune.asm` entry through `PLAYNEXT`, `EXIT*` labels

2. Hardware and chip/port configuration
- Responsibilities: auto/manual port choice, HBIOS sound enumeration, AY probing, YM2151 mapping, dual-chip selection
- Primary locations: `AUTOSEL`, `HB_SND_*`, `PROBE_AY`, `YM2151_PORTCFG` in `vibetune.asm`

3. File handling and loading
- Responsibilities: file type detect (.PT2/.PT3/.MYM/.VGM/.D00), FCB open/read/close, size/load-ceiling checks, playlist scan
- Primary locations: load sequence in `vibetune.asm`, `PLAYLIST_*` family

4. Playback engines
- PT2/PT3 engine: Bulba player integration and quark loop (`PTXLP*`)
- MYM engine: fragment extraction and loop (`mym*`/`mymkey*`)
- VGM engine: command-stream decoder, delay/mute (`goVGM*` in `vibetune.asm` + parser in `vgm_player.inc`)

5. TurboSound support
- Responsibilities: detect packed dual-module PT3, dual-chip setup, context save/restore, timing adjust
- Primary locations: `TS_*`, `CTX_*` in `vibetune.asm`

6. CLI parsing
- Responsibilities: options (`-list`, `-loop`, `-config`, port options, `--hbios`, `-delay`, YM2151 options, octave adjust)
- Primary file: `cli.inc`

7. UI/printing and terminal profile
- Responsibilities: ANSI/non-ANSI rendering, status/meta lines, playlist matrix rendering, TERM.CFG persistence/config mode
- Primary locations: `printing.inc`, `termcfg.inc`, `TCFG_*`/`UI_*` labels in `vibetune.asm`

8. Timing and string utilities
- Responsibilities: timer/delay calibration (`timing.inc`), string compare/search (`strings.inc`)

## 3. Redundancy Audit (Name and Shame)
The biggest space and complexity waste is duplicated control flow.

### 3.1 Triple-duplicated playback key-control state machine
Subject: Key dispatch + pause loop duplicated in PT3/MYM/VGM

Evidence:
- PT3 path: `PTXLP*` labels
- MYM path: `mymkey*` labels
- VGM path: `goVGM*` labels

Duplicated behaviors:
- Space toggles pause/resume
- ESC abort
- N/P next/previous track
- WASD matrix navigation
- L/l loop mode toggles
- R redraw
- delete confirmation flow

Impact:
- Large code footprint
- Bug fixes must be repeated in 3 places
- Behavior drift risk (engines diverging unintentionally)

### 3.2 Duplicated playlist transition logic
Subject: Track-advance/rewind/wrap behavior repeated in play loops and exit handling

Evidence:
- `PTXLP_NEXT/PREV`, `mymkey_next/prev`, `goVGM_next/prev`
- Exit transition cluster: `EXITXALL*`, `EXITALL*`, `EXITS`

Impact:
- Hard to reason about exact behavior matrix
- Fragile loop-mode interactions

### 3.3 Mixed concerns in single file
Subject: Orchestration + hardware + playback + UI + metadata + utilities in one giant file

Evidence:
- `vibetune.asm` includes almost every high-level concern in one translation unit

Impact:
- Refactors create long-range branch-distance side effects
- Discoverability and ownership are poor

### 3.4 VGM integration shape mismatch
Subject: VGM parser is modularized (`vgm_player.inc`) but control loop and key handling remain in monolith

Impact:
- VGM remains partly disjoint from PTx/MYM control path
- Performance tuning and behavior consistency harder than needed

### 3.5 UI handling duplicated across modes
Subject: Similar message/render patterns split between general print routines and player-specific branches

Impact:
- Additional code size
- Inconsistent output semantics over time

## 4. Target Architecture (Modular Split)
Goal: separate policy (shared behavior) from engine-specific execution.

### 4.1 Proposed file layout
Keep existing utility includes, then split high-level logic into dedicated modules:

- `vibetune.asm`
  - minimal entry/orchestration
  - format dispatch
  - include order and globals coordination only

- `playback_core.inc` (new)
  - shared playback controller skeleton
  - common stop/skip/prev/nav/pause state management
  - loop mode policy

- `keyctl.inc` (new)
  - unified key decode and action mapping
  - pause-state handler
  - delete confirmation pipeline hooks

- `playlist_core.inc` (new)
  - playlist enumerate/load/move/delete/snapshot/restore logic
  - no engine-specific code

- `hwcfg.inc` (new)
  - hardware auto-detect/force path
  - AY probe and dual-chip selection helpers
  - YM2151 port selection helpers

- `ptx_runtime.inc` (new)
  - PT2/PT3 init/play/mute wrapper logic around Bulba core
  - TurboSound glue (`TS_*`, `CTX_*`) stays grouped here

- `mym_runtime.inc` (new)
  - MYM init/play/mute wrapper and fragment-cycle logic

- `vgm_runtime.inc` (new)
  - VGM runtime wrapper (`goVGM*` control side)
  - keeps parser in existing `vgm_player.inc`

- `meta_print.inc` (new)
  - metadata parse/print routines shared by modes
  - chip info summary rendering

Already modular and kept:
- `cli.inc`, `printing.inc`, `termcfg.inc`, `timing.inc`, `strings.inc`, `vgm_player.inc`

### 4.2 Shared flags and normalized action interface
Introduce a compact action enum and one shared dispatcher:
- Actions: none, abort, next, prev, nav, redraw, pause-toggle, loop-track-toggle, loop-playlist-toggle, delete-seq
- Engine-specific hooks only for:
  - frame/tick execution
  - mute routine
  - metadata routine

Result:
- one key-control state machine
- one playlist transition policy
- one pause policy

## 5. Binary Size and Speed Optimization Track
Refactor is not only structural; it is also for size/speed.

### 5.1 Size reductions expected
Primary wins:
- eliminate triple-duplicated key/pause/navigation logic
- collapse repeated message and status handling
- consolidate playlist transition logic

Estimated target:
- remove ~1.0K to ~1.5K lines equivalent from monolith logic paths
- reduce final COM size meaningfully (exact value validated after each phase)

### 5.2 Speed improvements expected
- Less branching complexity in hot key paths
- Cleaner VGM loop integration with unified control cadence
- Better profiling visibility after separation of responsibilities

### 5.3 VGM-specific performance questions to evaluate
- Poll cadence and key-check frequency in VGM loop
- Delay loop calibration and dither overhead behavior on target CPUs
- Stream parser skip paths for unknown commands (avoid unnecessary overhead)

## 6. CP/M On-Demand Module Feasibility
Question: can we avoid keeping all engines/features resident simultaneously?

Short answer: yes, with constraints.

### 6.1 What CP/M allows
CP/M does not provide modern dynamic linking, but it supports practical modular patterns:
1. Overlays loaded from disk into a fixed memory window
2. Multi-program architecture (launcher COM spawns or chains to engine COM)
3. Transient module load/read/jump with custom loader conventions

### 6.2 Repository precedent
Overlay-based applications exist in this tree (notably ZMP `.OVR` ecosystem), demonstrating practical on-demand module loading strategy in this codebase context.

### 6.3 VibeTune feasible options
Option A: Overlay engines
- Keep shell/UI/playlist resident
- Load PTx/MYM/VGM runtime overlays only when needed
- Return to shell after playback

Option B: Split binaries by role
- `VTUNE.COM` launcher + UI/file manager
- `VTPTX.COM`, `VTMYM.COM`, `VTVGM.COM` playback workers
- Pass selected file and mode via command tail/FCB conventions

Option C: Hybrid
- Keep most common engine resident (PT3) and overlay only heavy VGM path + config UI

### 6.4 Tradeoffs
- Pros: lower resident memory footprint, larger playable files
- Cons: disk I/O latency, complexity in state handoff, error handling across module boundaries

Recommendation:
- Execute structural refactor first
- Add overlay/multi-binary in phase 2 once behavior is stable

## 7. Phased Execution Plan

### Phase 0: Baseline and instrumentation
- Freeze behavior matrix (all options and key actions)
- Record binary size and free memory baseline
- Build and smoke-test WBW/ZX/MSX outputs

### Phase 1: Zero-behavior-change factoring
- Extract shared key dispatcher and pause handler
- Extract playlist core from monolith
- Keep label names stable via wrappers where possible

Deliverables:
- new include files introduced
- no feature changes
- all builds green

### Phase 2: Playback runtime normalization
- Introduce playback-core skeleton with engine hooks
- Move PTx/MYM/VGM control wrappers into dedicated runtime includes
- Keep existing parser/engine internals untouched

Deliverables:
- one common control policy across engines
- reduced duplication

### Phase 3: Hardware/config isolation
- Move hardware detect/select/probe logic into `hwcfg.inc`
- Keep CLI options behavior unchanged
- Ensure YM2151 and dual-chip behavior parity

### Phase 4: Metadata and info display unification
- Centralize chip/track metadata emitters
- Ensure chip-count flags drive both playback routing and display output

### Phase 5: Size/speed pass
- remove dead paths/macros and duplicate strings where safe
- evaluate branch sizes (`JR` vs `JP`) after split
- optional micro-optimizations in hot loops

### Phase 6 (optional): Demand-load architecture
- prototype either overlays or split worker COM model
- compare RAM gain vs complexity and launch latency

## 8. Validation Matrix
For every phase:
1. Build
- WBW, ZX, MSX targets compile with 0 errors

2. Playback
- PT2, PT3, MYM, VGM representative files
- TurboSound PT3 detect and dual-chip operation

3. Controls
- Esc, space pause/resume, N/P, WASD, redraw, loop toggles, delete confirm

4. Metadata and chip reporting
- Correct chip family and chip count shown
- VGM/TS info parity with actual playback path used

5. Resource checks
- COM size comparison against previous baseline
- free memory and max loadable file size trend

## 9. Risks and Constraints
1. Z80 branch distance
- Splits can move labels enough to break short jumps; expect `JR` to need `JP` conversions in some paths.

2. Self-modifying playback internals
- Bulba PTx and MYM internals are fragile; avoid deep surgery.

3. Cross-platform build parity
- Keep assembler behavior consistent across WBW/ZX/MSX variants.

4. Regression risk from control-flow consolidation
- Unified state machine must preserve current semantics exactly before optimization.

## 10. Immediate Work Backlog (Actionable)
1. Create `keyctl.inc` and migrate one engine (VGM) as pilot
2. Create `playlist_core.inc` and route existing `PLAYLIST_*` labels through it
3. Introduce `playback_core.inc` action enum and dispatcher stubs
4. Move PTx wrappers to `ptx_runtime.inc` (no engine-internal changes)
5. Move MYM wrappers to `mym_runtime.inc`
6. Move VGM runtime wrapper to `vgm_runtime.inc` and keep parser in `vgm_player.inc`
7. Add pre/post build-size report step in local workflow notes

## 11. Definition of Done (Refactor Program)
- Source split into coherent modules with documented ownership
- Redundant triple-control logic removed
- Behavior parity maintained across supported formats/options
- Binary size reduced and memory headroom improved
- Optional on-demand module strategy assessed with prototype recommendation

## 12. Execution Log
2026-04-10 - Phase 1 slice 1 completed
- Added new module: `keyctl.inc`
- Introduced shared key action constants (`KEYACT_*`) in `vibetune.asm`
- Refactored VGM normal-loop and VGM pause-loop key compare chains to use
  `KEYACT_VGM_DECODE` from `keyctl.inc`
- Included `keyctl.inc` in build via `vibetune.asm`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a behavior-preserving extraction focused on reducing duplication in
  one engine path first (VGM) before applying the same pattern to PTx and MYM.

2026-04-10 - Phase 1 slice 2 completed
- Generalized decoder to `KEYACT_DECODE` in `keyctl.inc` (kept
  `KEYACT_VGM_DECODE` as compatibility alias)
- Refactored PTX normal-loop and PTX pause-loop key decode branches to use
  shared key actions (`KEYACT_*`) instead of inline compare chains
- Refactored MYM normal-loop and MYM pause-loop key decode branches to use
  shared key actions (`KEYACT_*`) instead of inline compare chains
- Updated VGM call sites to use `KEYACT_DECODE` for consistency
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This removes one major family of duplicated key-classification logic across
  all three playback engines while preserving existing control-flow labels and
  playlist behavior.

2026-04-10 - Phase 1 slice 3 completed
- Added shared loop-toggle helper routines in `keyctl.inc`:
  - `KEY_TOGGLE_LOOP_TRACK_PLAY`
  - `KEY_TOGGLE_LOOP_PLAY_PLAY`
  - `KEY_TOGGLE_LOOP_TRACK_PAUSE`
  - `KEY_TOGGLE_LOOP_PLAY_PAUSE`
- Replaced duplicated loop-toggle blocks in PTX/MYM/VGM normal paths with
  shared helper calls
- Replaced duplicated loop-toggle blocks in PTX/MYM/VGM pause paths with
  shared helper calls
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a behavior-preserving consolidation step that removes another large
  repeated control-flow family without changing playlist, pause, or status UI
  semantics.

2026-04-10 - Phase 1 slice 4 completed
- Added shared playlist action helpers in `keyctl.inc`:
  - `KEY_NAV_PLAY`
  - `KEY_NAV_PAUSE`
  - `KEY_PAUSE_NEXT`
  - `KEY_PAUSE_PREV`
- Replaced duplicated PTX/MYM/VGM navigation blocks with shared helpers
  (`PLAYLIST_MOVE_WASD` + `NAVREQ` handling)
- Replaced duplicated PTX/MYM/VGM pause next/prev transition blocks with
  shared helpers (`PLAYLIST_ADVANCE/PREV/RESTORE` + selection refresh)
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a behavior-preserving extraction aimed at shrinking repeated
  playlist-control state transitions across all three playback engines.

2026-04-10 - Phase 1 slice 5 completed
- Added shared delete and redraw helpers in `keyctl.inc`:
  - `KEY_DELETE_ATTEMPT`
  - `KEY_REDRAW_PLAY_PTXMYM`
  - `KEY_REDRAW_PLAY_VGM`
  - `KEY_REDRAW_PAUSE_PTXMYM`
  - `KEY_REDRAW_PAUSE_VGM`
- Replaced duplicated delete-confirm/delete-result blocks in PTX/MYM/VGM
  normal and pause loops with `KEY_DELETE_ATTEMPT`
- Replaced duplicated redraw/show-info paths with the new shared redraw
  helpers while preserving metadata differences between PTX/MYM and VGM
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a behavior-preserving consolidation step reducing repeated UI and
  delete-flow control code across all three engine paths.

2026-04-10 - Phase 1 slice 6 completed
- Added shared request/abort helpers in `keyctl.inc`:
  - `KEY_REQ_NEXT`
  - `KEY_REQ_PREV`
  - `KEY_SET_STOPREQ`
- Replaced duplicated next/prev request setters in PTX/MYM/VGM normal loops
  with shared helpers
- Replaced duplicated stop-request setters in PTX/MYM/VGM abort paths with
  shared helper
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This preserves behavior while removing another repeated control-flow family
  and tightening key-loop parity across all three engine paths.

2026-04-10 - Phase 1 slice 7 completed
- Added shared pause transition helpers in `keyctl.inc`:
  - `KEY_PAUSE_ON`
  - `KEY_PAUSE_OFF`
- Replaced duplicated pause-on blocks in PTX/MYM/VGM with `KEY_PAUSE_ON`
- Replaced duplicated pause-off blocks in PTX/MYM/VGM with `KEY_PAUSE_OFF`
  while preserving each engine's original post-resume jump target
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a behavior-preserving extraction that centralizes pause state
  transitions and reduces repetition in all three playback loops.

2026-04-10 - Phase 1 slice 8 completed
- Added shared muted-abort helper in `keyctl.inc`:
  - `KEY_ABORT_MUTED`
- Replaced duplicated ESC abort blocks in PTX/MYM/VGM loops with the new
  helper while preserving each engine's original exit target
- Kept non-ESC abort paths routed through `KEY_SET_STOPREQ`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a behavior-preserving extraction reducing one more repeated
  key-control abort pattern across all engine paths.

2026-04-10 - Phase 1 slice 9 completed
- Added shared action-prep helpers in `keyctl.inc`:
  - `KEY_PREP_PLAYLIST_ACTION`
  - `KEY_PREP_PAUSE_ACTION`
- Replaced duplicated playlist map+decode scaffolding in PTX/MYM/VGM normal
  loops with `KEY_PREP_PLAYLIST_ACTION`
- Replaced duplicated pause key map/decode scaffolding in PTX/MYM/VGM pause
  loops with `KEY_PREP_PAUSE_ACTION`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This keeps behavior unchanged while centralizing another high-frequency
  key-processing scaffold used across all three engine paths.

2026-04-10 - Phase 1 slice 10 completed
- Removed unused compatibility decoder alias `KEYACT_VGM_DECODE`
- Added shared pause toggle helper in `keyctl.inc`:
  - `KEY_TOGGLE_PAUSE`
- Replaced duplicated pause-toggle scaffolding in PTX/MYM/VGM with the new
  helper while preserving each engine's original post-toggle branch target
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a behavior-preserving consolidation that removes repeated pause
  toggle code and keeps pause wait-loop entry semantics aligned.

2026-04-10 - Phase 1 slice 11 completed
- Added shared pause poll helper in `keyctl.inc`:
  - `KEY_PAUSE_POLL`
- Replaced duplicated pause wait prelude in PTX/MYM/VGM pause loops:
  - `GETKEY` poll + space handling
  - delete-sequence gate handling
  - shared pause action decode handoff
- Preserved per-engine action dispatch and exit targets
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a larger behavior-preserving extraction that centralizes the most
  repeated pause-loop pre-dispatch scaffold across all three engine paths.

2026-04-10 - Phase 1 slice 12 completed
- Added shared normal-loop poll helper in `keyctl.inc`:
  - `KEY_PLAY_POLL`
- Replaced duplicated normal-loop key prelude in PTX/MYM/VGM loops:
  - `GETKEY` poll + space/pause handling
  - delete-sequence gate handling
  - non-playlist abort gate handling
  - shared action decode handoff
- Preserved per-engine action dispatch and exit targets
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a larger behavior-preserving milestone that centralizes both pause
  and normal key-loop polling scaffolds across all engine paths.

2026-04-10 - Hotfix: VGM pause mute parity (SN76489 sustain)
- Updated `KEY_PAUSE_ON` to use `VGM_MUTE_ALL` when `VGMFLAG` is active,
  otherwise keep `MUTE_NOW` for PTX/MYM paths
- Fixes paused VGM playback where SN76489 last note could continue sustaining
  during pause
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

2026-04-10 - Phase 1 slice 13 completed
- Added shared normal action dispatcher in `keyctl.inc`:
  - `KEY_HANDLE_PLAY_ACTION`
- Replaced duplicated PTX/MYM/VGM normal action compare chains with one shared
  handler, preserving per-engine exit targets (PTX/MYM `EXIT`, VGM
  `goVGM_exit_mute`)
- Removed redundant per-engine normal action helper blocks that became
  unreachable after consolidation
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a larger module-reuse milestone that removes the biggest remaining
  duplicated normal-loop action dispatch chunk.

2026-04-10 - Phase 1 slice 14 completed
- Added shared pause action dispatcher in `keyctl.inc`:
  - `KEY_HANDLE_PAUSE_ACTION`
- Replaced duplicated PTX/MYM/VGM pause action compare chains with one shared
  handler, preserving per-engine exit targets (PTX/MYM `EXIT`, VGM
  `goVGM_exit_mute`)
- Removed redundant per-engine pause action helper blocks that became
  unreachable after consolidation
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a larger module-reuse milestone that removes the biggest remaining
  duplicated pause-loop action dispatch chunk.

2026-04-10 - Phase 1 slice 15 completed
- Inlined shared abort handling (`KEY_SET_STOPREQ`) in PTX/MYM/VGM normal
  loops where poll state indicated non-playlist abort
- Removed now-redundant per-engine abort labels that only wrapped
  `KEY_SET_STOPREQ` + engine exit jump
- Removed dead/unreachable post-exit jumps left behind by prior refactors
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This preserves behavior while trimming control-tail duplication and dead
  branch bytes in the hot key-loop paths.

2026-04-10 - Phase 1 slice 16 completed
- Inlined shared delete handling (`KEY_DELETE_ATTEMPT`) directly at PTX/MYM/VGM
  normal and pause poll sites
- Removed now-redundant per-engine delete labels that only wrapped
  `KEY_DELETE_ATTEMPT` + continue/exit branch targets
- Preserved per-engine continue/exit behavior for normal and pause loops
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a larger cleanup milestone that trims duplicated delete-flow
  wrappers and keeps all delete semantics module-driven.

2026-04-10 - Phase 1 slice 17 completed
- Merged `KEY_HANDLE_PLAY_ACTION` and `KEY_HANDLE_PAUSE_ACTION` internals into
  one context-driven dispatcher: `KEY_HANDLE_ACTION`
- Context now encoded in `D` bits:
  - bit7: play/pause mode
  - bit0: PTX/MYM vs VGM metadata variant
- Kept thin wrapper entry points (`KEY_HANDLE_PLAY_ACTION`,
  `KEY_HANDLE_PAUSE_ACTION`) so call sites remained stable
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a pure module-reuse milestone: one shared dispatch core now serves
  both play and pause action routing.

2026-04-10 - Phase 1 slice 18 completed
- Updated PTX/MYM/VGM action dispatch call sites to invoke `KEY_HANDLE_ACTION`
  directly with fully encoded context in `D`
- Removed transitional wrapper entry points:
  - `KEY_HANDLE_PLAY_ACTION`
  - `KEY_HANDLE_PAUSE_ACTION`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This finalizes the dispatcher merge by removing wrapper indirection and
  reducing extra branch/jump overhead.

2026-04-10 - Phase 1 slice 19 completed
- Added shared key poll core in `keyctl.inc`:
  - `KEY_POLL_CORE`
- Refactored `KEY_PLAY_POLL` and `KEY_PAUSE_POLL` into thin wrappers that set
  context and jump to the shared core
- Preserved existing poll result contract (`B`/`C`) used by PTX/MYM/VGM loops
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This removes another duplicated internal module pair while keeping external
  call-site behavior unchanged.

2026-04-10 - Phase 1 slice 20 completed
- Updated PTX/MYM/VGM play and pause loop call sites to call `KEY_POLL_CORE`
  directly with explicit context in `D`
- Removed transitional poll wrapper entry points:
  - `KEY_PLAY_POLL`
  - `KEY_PAUSE_POLL`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This finalizes the poll-core merge by removing wrapper indirection and
  reducing extra branch/jump overhead in hot loops.

2026-04-10 - Phase 1 slice 21 completed
- Optimized loop context handling by carrying `D` through poll->dispatch paths
  and removing repeated `LD D,...` reloads before action dispatch calls
- Applied consistently across PTX/MYM/VGM in both play and pause loops
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a hot-path byte trim that keeps behavior identical while reducing
  repeated context setup instructions.

2026-04-10 - Phase 1 slice 22 completed
- Inlined paused-key decode path directly into `KEY_POLL_CORE`
- Removed now-redundant `KEY_PREP_PAUSE_ACTION` helper indirection
- Kept playlist-mode key mapping and non-playlist raw decode behavior
  unchanged in pause context
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This trims another wrapper-level dispatch hop in hot pause input handling.

2026-04-10 - Phase 1 slice 23 completed
- Removed `KEY_PREP_PLAYLIST_ACTION` helper indirection
- Inlined shared playlist map/decode path directly inside `KEY_POLL_CORE`
  and reused that path for both play context and pause+playlist context
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This removes another helper layer in hot input decoding while preserving
  key mapping behavior across all engines.

2026-04-10 - Phase 1 slice 24 completed
- Unified raw and mapped decode tails in `KEY_POLL_CORE` via
  `KEY_POLL_CORE_DECODE`
- Converted pause+raw path to jump into shared decode tail instead of
  duplicating decode sequence
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- Small hot-path byte trim that keeps key decode behavior identical.

2026-04-10 - Phase 1 slice 25 completed
- Inlined single-use pause helpers into `KEY_HANDLE_ACTION`:
  - `KEY_NAV_PAUSE`
  - `KEY_PAUSE_NEXT`
  - `KEY_PAUSE_PREV`
- Removed those helper routines from `keyctl.inc`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This reduces call/ret wrapper overhead in pause action handling while
  preserving all prior pause navigation and playlist transition behavior.

2026-04-10 - Phase 1 slice 26 completed
- Added temporary audio mute around play-mode `(R)edraw` handling
  in `KEY_HANDLE_ACTION_REDRAW`
- Implemented engine-aware mute helper `KEY_REDRAW_PLAY_MUTE`:
  - PTX/MYM: `MUTE_NOW`
  - VGM: `VGM_MUTE_ALL`
- Kept pause redraw behavior unchanged
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- Redraw completion is defined by redraw helper return; playback loop then
  resumes and repopulates chip registers on subsequent update ticks.

2026-04-10 - Phase 1 slice 27 completed
- Consolidated repeated `B=0` continue returns in `KEY_HANDLE_ACTION`
  into one shared tail label: `KEY_HANDLE_ACTION_CONTINUE`
- Replaced duplicated local tails with jumps to the shared continue path
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a behavior-preserving control-flow dedup that trims repeated
  return boilerplate in the hot action dispatcher.

2026-04-10 - Phase 1 slice 28 completed
- Added new module file: `playlist_core.inc`
- Moved primary playlist core routines from `vibetune.asm` into
  `playlist_core.inc` and included it in-place to preserve assembly locality:
  - `PLAYLIST_INIT`
  - `PLAYLIST_SNAPSHOT` / `PLAYLIST_RESTORE`
  - `PLAYLIST_ENUM_*`
  - `PLAYLIST_LOAD_FCB`
  - `PLAYLIST_SET_FILTYP`
  - `PLAYLIST_ADVANCE` / `PLAYLIST_PREV`
  - `PLAYLIST_MOVE_WASD` and helper labels
  - `PLAYLIST_PTR_FROM_A`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is the first concrete playlist-core extraction step from the Phase 1
  backlog and keeps behavior unchanged by including the new module at the
  original source location.

2026-04-10 - Phase 1 slice 29 completed
- Moved remaining playlist key-sequence normalization routines into
  `playlist_core.inc`:
  - `PLAYLIST_MAP_KEY`
  - `PLAYLIST_GETKEY_WAIT`
- Removed those routines from `vibetune.asm`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This completes the main `PLAYLIST_*` routine migration into the dedicated
  playlist module while preserving behavior and call contracts.

2026-04-10 - Phase 1 slice 30 completed
- Added new module file: `playback_core.inc`
- Added stable dispatcher stubs:
  - `PLAYBACK_POLL_ACTION` -> `KEY_POLL_CORE`
  - `PLAYBACK_HANDLE_ACTION` -> `KEY_HANDLE_ACTION`
- Included `playback_core.inc` in `vibetune.asm`
- Rerouted PTX/MYM/VGM loop call sites to call `PLAYBACK_*` entry points
  instead of calling `KEY_*` directly
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This establishes a dedicated playback-core module boundary for the next
  normalization phase while preserving behavior and control contracts.

2026-04-10 - Phase 1 slice 31 completed
- Added new module file: `ptx_runtime.inc`
- Moved PTX runtime wrapper block from `vibetune.asm` into `ptx_runtime.inc`:
  - `GOPT2` / `GOPT3`
  - `GOPTX` init + metadata spacing and TurboSound init path
  - `PTXLP*` play/pause/key loop control block
- Replaced in-place PTX block with `#include "ptx_runtime.inc"` in `vibetune.asm`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- Extraction is include-in-place to preserve label behavior and branch locality
  while creating a dedicated PTX runtime module boundary for next-phase work.

2026-04-10 - Phase 1 slice 32 completed
- Added new module file: `mym_runtime.inc`
- Moved MYM runtime wrapper block from `vibetune.asm` into `mym_runtime.inc`:
  - `gomym` setup and metadata/formatting path
  - `mymlp` decode/play loop and key/pause handling labels
- Replaced in-place MYM block with `#include "mym_runtime.inc"` in `vibetune.asm`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- Extraction is include-in-place to preserve behavior and branch locality while
  establishing a dedicated MYM runtime module boundary for next-phase work.

2026-04-10 - Phase 1 slice 33 completed
- Added new module file: `vgm_runtime.inc`
- Moved VGM runtime wrapper block from `vibetune.asm` into `vgm_runtime.inc`:
  - `goVGM` load/play loop and pause/key handling flow
  - `goVGM_exit_mute` end-of-stream/abort mute exit path
- Replaced in-place VGM wrapper block with `#include "vgm_runtime.inc"` in `vibetune.asm`
- Kept `VGM_VALIDATE_IMAGE` and parser internals in `vibetune.asm` / `vgm_player.inc`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- Extraction is include-in-place to preserve behavior and branch locality while
  creating a dedicated VGM runtime module boundary for next-phase normalization.

2026-04-11 - Phase 3 slice 34 completed
- Added new module file: `hwcfg.inc`
- Moved hardware/config routines from `vibetune.asm` into `hwcfg.inc`:
  - `YM2151_PORTCFG`
  - `HB_SND_GETMASK`
  - `HB_SND_AUTOCFG`
  - `HB_SND_GET2`
  - internal `HBGM_*` state bytes
- Replaced in-place routine blocks with `#include "hwcfg.inc"` in `vibetune.asm`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This starts Phase 3 hardware/config isolation while preserving behavior by
  keeping extraction include-in-place near existing call sites and state.

2026-04-11 - Phase 5 slice 35 completed
- Metadata/UX consistency fix in `vibetune.asm`:
  - Updated banner build/date to `v0.1b039, 11-Apr-2026`
  - Updated usage text prefix from `TUNE` to `VTUNE`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- No behavior/path logic changes; this is a user-facing consistency cleanup.

2026-04-11 - Phase 3 slice 36 completed
- Moved remaining hardware auto-select/probe cluster into `hwcfg.inc`:
  - `AUTOSEL` flow (HBIOS-first auto-config with CFG table fallback)
  - internal config-scan/activate/probe loop labels
  - AY probe implementation body (`PROBE_AY`)
- Kept stable public entry labels in `vibetune.asm` as thin jump stubs:
  - `AUTOSEL` -> `AUTOSEL_IMPL`
  - `PROBE_AY` -> `PROBE_AY_IMPL`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This continues Phase 3 hardware/config isolation while preserving behavior
  and existing call-site labels/branch targets.

2026-04-11 - Metadata policy sync
- Bumped VibeTune banner build number in `vibetune.asm`:
  - `v0.1b039` -> `v0.1b040`
- Added explicit VibeTune workflow rule in top-level `WARP.md`:
  - Always increment `MSGBAN` build token (`v0.1bXXX`) when modifying
    `Source/Apps/VibeTune/vibetune.asm`
  - Always rebuild VibeTune after source edits
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This addresses runtime version ambiguity and aligns VibeTune with the same
  always-bump discipline already used for other app workflows.

2026-04-11 - Input UX tweak: Enter resumes from Pause
- Updated shared key poll path in `keyctl.inc` (`KEY_POLL_CORE`):
  - While paused (`D bit7=1`), Enter (`CR`, 13) now maps to the existing
    pause-toggle/resume action, same as Space
  - Play-mode behavior remains unchanged (Enter is not treated as pause toggle)
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a targeted behavior enhancement for pause usability with minimal
  control-path impact.

2026-04-11 - Versioning correction after Enter-resume build
- Bumped VibeTune banner build number in `vibetune.asm`:
  - `v0.1b040` -> `v0.1b041`
- Clarified workflow policy in top-level `WARP.md`:
  - every executable-producing VibeTune build must increment `MSGBAN`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This aligns the produced executable version marker with the latest behavior
  change and enforces explicit per-build bump discipline.

2026-04-11 - Phase 3 slice 37 completed
- Moved TurboSound hardware port/probe helpers into `hwcfg.inc`:
  - `TS_PORTS_SETUP`
  - `TS_DESC_FROM_HL`
  - `TS_PROBE_MSX`
  - `TS_PROBE_COLECO`
  - `TS_PROBE_RC`
- Kept stable public entry labels in `vibetune.asm` as thin jump stubs:
  - `TS_PORTS_SETUP` -> `TS_PORTS_SETUP_IMPL`
  - `TS_DESC_FROM_HL` -> `TS_DESC_FROM_HL_IMPL`
  - `TS_PROBE_MSX` -> `TS_PROBE_MSX_IMPL`
  - `TS_PROBE_COLECO` -> `TS_PROBE_COLECO_IMPL`
  - `TS_PROBE_RC` -> `TS_PROBE_RC_IMPL`
- Bumped VibeTune banner build number:
  - `v0.1b041` -> `v0.1b042`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This continues Phase 3 hardware/config isolation while preserving existing
  call-site labels and behavior.

2026-04-11 - Phase 3 slice 38 completed
- Moved TurboSound active-port helper routines into `hwcfg.inc`:
  - `TS_SETPORTS1`
  - `TS_SETPORTS2`
- Kept stable public entry labels in `vibetune.asm` as thin jump stubs:
  - `TS_SETPORTS1` -> `TS_SETPORTS1_IMPL`
  - `TS_SETPORTS2` -> `TS_SETPORTS2_IMPL`
- Bumped VibeTune banner build number:
  - `v0.1b042` -> `v0.1b043`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This further isolates hardware-facing port selection helpers without
  changing TurboSound runtime behavior.

2026-04-11 - Phase 5 slice 39 completed
- Removed dead TurboSound probe helpers no longer referenced by runtime paths:
  - Removed `TS_PROBE_MSX` / `TS_PROBE_COLECO` / `TS_PROBE_RC` stubs from
    `vibetune.asm`
  - Removed `TS_PROBE_MSX_IMPL` / `TS_PROBE_COLECO_IMPL` /
    `TS_PROBE_RC_IMPL` from `hwcfg.inc`
- Bumped VibeTune banner build number:
  - `v0.1b043` -> `v0.1b044`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a behavior-preserving dead-code trim after prior hardware-probe
  isolation slices.

2026-04-11 - Phase 3 slice 40 completed
- Moved TurboSound delay-mode timing adjustment helper into `hwcfg.inc`:
  - `TS_ADJTIM` -> `TS_ADJTIM_IMPL`
  - internal shift-loop label localized as `TS_ADJ2_IMPL`
- Kept stable public entry label in `vibetune.asm` as a thin jump stub:
  - `TS_ADJTIM` -> `TS_ADJTIM_IMPL`
- Bumped VibeTune banner build number:
  - `v0.1b044` -> `v0.1b045`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This continues Phase 3 hardware/runtime-adjacent helper isolation while
  preserving playback behavior and call sites.

2026-04-11 - Phase 5 slice 41 completed
- Removed redundant TurboSound trampoline stubs from `vibetune.asm`:
  - `TS_ADJTIM`
  - `TS_SETPORTS1`
  - `TS_SETPORTS2`
- Retargeted call sites to implementation labels directly:
  - `TS_ADJTIM_IMPL` (in `ptx_runtime.inc`)
  - `TS_SETPORTS1_IMPL` / `TS_SETPORTS2_IMPL` (in `vibetune.asm` TS runtime)
- Bumped VibeTune banner build number:
  - `v0.1b045` -> `v0.1b046`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a behavior-preserving jump-indirection trim in hot TS helper paths.

2026-04-11 - Hotfix: redraw preserves PTX/MYM metadata
- Fixed redraw regression where PTX/MYM song title/artist degraded after
  playback start (showing filename fallback and blank artist)
- Added per-track metadata cache in `vibetune.asm`:
  - `METACACHED`, `METATITLE`, `METAARTIST`
  - `METACACHE_PREP` snapshots title/artist from module header once per track
  - `PRTSONGMETA` now prints from cached fields for stable redraw output
- Reset metadata cache on `PLAYNEXT`
- Bumped VibeTune banner build number:
  - `v0.1b046` -> `v0.1b047`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a behavior-preserving display fix for redraw consistency during
  active PTX/MYM playback.

2026-04-11 - Hotfix correction: lean redraw metadata snapshot
- Replaced the previous stateful redraw cache approach with a lean
  snapshot-on-load approach:
  - Added `META_SNAPSHOT` called once after file close (`_LDX`)
  - `PRTSONGMETA` prints from snapshot buffers (`METATITLE`/`METAARTIST`)
  - Reused existing `PLSRCHBUF` storage via aliases for metadata fields
- Removed added per-track cache state bytes and lazy-prepare logic:
  - removed `METACACHED` and `METACACHE_PREP`
- Bumped VibeTune banner build number:
  - `v0.1b047` -> `v0.1b048`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This targets redraw correctness with lower code/data overhead.

2026-04-11 - UX policy update: ANSI redraw is playlist-only
- Updated redraw handlers in `keyctl.inc` so ANSI/VT100 mode no longer redraws
  current-track detail blocks on `(R)edraw`
  - In ANSI mode (`UI_ACTIVE!=0`), redraw now performs `SHOWPLSTATUS` only
  - Plain-text mode retains full redraw of play info + metadata + state line
- Applied consistently to play and pause redraw paths (PTX/MYM and VGM)
- Bumped VibeTune banner build number:
  - `v0.1b048` -> `v0.1b049`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This removes redundant ANSI track-detail redraw work per requested behavior.

2026-04-11 - Phase 5 slice 42 completed
- Removed remaining single-jump hardware trampoline labels from
  `vibetune.asm` by retargeting callsites directly to implementation labels:
  - removed trampoline usage for `AUTOSEL`, `TS_PORTS_SETUP`,
    `TS_DESC_FROM_HL`, and `PROBE_AY`
  - updated callsites to `AUTOSEL_IMPL`, `TS_PORTS_SETUP_IMPL`, and
    `PROBE_AY_IMPL` as appropriate
- Updated PTX/VGM runtime includes to call `TS_PORTS_SETUP_IMPL` directly
- Bumped VibeTune banner build number:
  - `v0.1b049` -> `v0.1b050`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a behavior-preserving indirection trim and helper callpath cleanup.

2026-04-11 - Phase 5 slice 43 completed
- Inlined single-use TS port-description helper logic into
  `TS_PORTS_SETUP_IMPL` in `hwcfg.inc`
- Removed now-redundant helper routine:
  - `TS_DESC_FROM_HL_IMPL`
- Bumped VibeTune banner build number:
  - `v0.1b050` -> `v0.1b051`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a behavior-preserving dead-helper elimination and call/return trim.

2026-04-11 - Phase 5 slice 44 completed
- Extracted the full TurboSound runtime/context code block from `vibetune.asm`
  into a new include:
  - `ts_runtime.inc`
- Moved in one behavior-preserving chunk:
  - `TS_INIT`, `TS_PLAYQUARK`, `TS_MUTE`
  - `TS_LOAD_TMPL`/`TS_SAVE_CTX*`/`TS_LOAD_CTX*`
  - `PTX_PATCHTBL` and `CTX_SAVE`/`CTX_LOAD` helpers
- Replaced the monolithic in-place block with:
  - `#include "ts_runtime.inc"`
- Bumped VibeTune banner build number:
  - `v0.1b051` -> `v0.1b052`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is a larger extraction slice that reduces monolith size while preserving
  labels/call semantics.

2026-04-11 - Phase 5 slice 45 completed
- Extended the TurboSound extraction by moving packed-PT3 detection support
  from `vibetune.asm` into `ts_runtime.inc`:
  - signature constants: `PT3SIG*`, `TSSIG*`
  - detection scanner: `TS_DETECT` and scan loop labels
- Kept include-in-place call/label behavior by using existing:
  - `#include "ts_runtime.inc"`
- Bumped VibeTune banner build number:
  - `v0.1b052` -> `v0.1b053`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This is another larger behavior-preserving monolith reduction focused on
  TurboSound-specific runtime support cohesion.

2026-04-11 - Phase 5 slice 46 completed
- Extracted the VGM hardware detect/summary block from `vibetune.asm` into a
  new include:
  - `vgm_hw.inc`
- Moved in one behavior-preserving chunk:
  - `VGM_DETECT_HW` command-stream scanner
  - `PRT_VGMHW_LINE` / `PRT_VGM_TOKEN`
  - `VGM_SETFDELAY` dither-table delay setup
- Replaced the in-place monolith region with:
  - `#include "vgm_hw.inc"`
- Bumped VibeTune banner build number:
  - `v0.1b053` -> `v0.1b054`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- This further isolates VGM-specific hardware/timing helpers and reduces
  `vibetune.asm` surface while preserving labels/call semantics.

2026-04-11 - Phase 5 slice 47 completed
- Hardened config table sizing semantics in `vibetune.asm`:
  - replaced implicit first-record-derived sizing
    - `CFGSIZ .EQU $ - CFGTBL`
  - with explicit fixed record size
    - `CFGSIZ .EQU 9`
- Rationale:
  - table records are structurally fixed at 7 `.DB` fields + 1 `.DW`
  - avoids accidental first-row coupling if table formatting changes
- Bumped VibeTune banner build number:
  - `v0.1b054` -> `v0.1b055`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

Notes:
- Behavior is unchanged; this is maintainability hardening for table iteration
  and config copy paths that already use `CFGSIZ`.

2026-04-11 - Hotfix: honor CP/M command tail length byte
- Fixed command-line parsing in `cli.inc`:
  - `CLI_PREP` now uses the CP/M tail length byte at `$80`
  - copy length is clamped instead of scanning blindly until a later CR/NUL
- Rationale:
  - prevents stale bytes from prior commands from leaking into `CLIBUF`
  - fixes spurious option detection such as accidental `-list` / `--hbios`
- Expected user-visible fix:
  - `VTUNE rl2wof -coleco` stays in single-file mode
  - forced Coleco direct-I/O selection is preserved
  - the requested file is opened instead of enumerating the playlist
- Bumped VibeTune banner build number:
  - `v0.1b056` -> `v0.1b057`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

2026-04-11 - Hotfix: reconcile raw command tail with CP/M FCB tokens
- Hardened CLI parsing in `cli.inc` against stale/mismatched command tails:
  - upper-cases copied raw tail for stable option matching
  - validates `CLIBUF` against current default FCB tokens
  - rebuilds `CLIBUF` from FCB1/FCB2 when the raw tail does not match
  - promotes a second-token filename into primary `FCB` when token 1 is an option
- Expected user-visible fix:
  - `VTUNE rl2wof -coleco` no longer inherits stale `-list` / `--hbios`
  - `VTUNE -coleco rl2wof` now resolves the filename from the second token
- Bumped VibeTune banner build number:
  - `v0.1b057` -> `v0.1b058`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

2026-04-11 - Hotfix: build filename FCB from current tail only
- Reworked startup filename resolution in `cli.inc`:
  - `CLI_PREP` now rebuilds the primary CP/M FCB from the current command tail
  - option tokens are skipped while scanning for the first filename token
  - inherited/stale default FCB contents are no longer used to reconstruct args
- Rationale:
  - avoids reintroducing stale filenames/options from prior CCP state
  - supports both `VTUNE RL2WOF -COLECO` and `VTUNE -COLECO RL2WOF`
- Bumped VibeTune banner build number:
  - `v0.1b058` -> `v0.1b059`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

2026-04-11 - Diagnostics build: startup CLI/FCB trace
- Added explicit startup debug dump in `cli.inc` (`CLI_DEBUG_DUMP`) and callsite
  in `vibetune.asm` after CLI option parsing.
- Debug output now prints:
  - raw CP/M tail length (`$80`) and normalized `CLIBUF`
  - `FCB1` and `FCB2` decoded as 8.3 tokens
  - key parser flags (`CREDMD/ALLMD/HBIOSMD/DELAYMD/USEPORTS`)
- Removed dead/unreachable legacy tail-reconciliation helpers from `cli.inc`
  to offset debug-build growth.
- Bumped VibeTune banner build number:
  - `v0.1b059` -> `v0.1b060`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

2026-04-11 - Hotfix: forced-port mode memory overwrite (root cause fix)
- Fixed config record copy size in `vibetune.asm`:
  - `CFGSIZ` changed to fixed record size (`9` bytes: 7 `.DB` + 1 `.DW`)
- Rationale:
  - force-port path (`-coleco` / `-msx` / `-rc`) uses `LDIR` from selected
    config into `CFG`; oversized `CFGSIZ` was corrupting runtime flags
    (including `ALLMD`) and triggering unintended playlist mode.
- Bumped VibeTune banner build number:
  - `v0.1b061` -> `v0.1b062`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

2026-04-11 - Cleanup: remove diagnostic/debug and temporary workaround hooks
- Removed CLI debug output plumbing:
  - deleted `CLI_DEBUG_DUMP` / `CLI_DBG_PRTFCB` from `cli.inc`
  - removed `[DBG]` strings and startup debug call in `vibetune.asm`
- Removed temporary extra `CLI_HAVE_ALL_SWITCH` refresh hook in startup flow.
- Bumped VibeTune banner build number:
  - `v0.1b062` -> `v0.1b063`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)

2026-04-11 - Size pass: remove redundant mixed-case CLI scans
- Since `CLI_PREP` uppercases command tail, removed duplicate lowercase option
  probes and token tables in `cli.inc` (`-list/-loop/-config/-credits/-ym*`).
- Normalized octave option token constants to uppercase (`+T1/+T2/-T1/-T2`).
- Bumped VibeTune banner build number:
  - `v0.1b063` -> `v0.1b064`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)
- Size note: `vtune.com` reduced to `19998` then `19919` in follow-on pass.

2026-04-11 - Size pass: unify OPL write handlers in VGM parser
- Consolidated duplicated OPL handlers in `vgm_player.inc`:
  - merged `0x5A`/`0x5E`/`0x5F` paths into one bank-aware write path
  - preserved carrier TL boost behavior and timing delay.
- Bumped VibeTune banner build number:
  - `v0.1b064` -> `v0.1b065`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)
- Size note: `vtune.com` reduced to `19919`.

2026-04-11 - Refactor: shared pause-step helper across PTX/MYM/VGM
- Added `PLAYBACK_PAUSE_STEP` in `playback_core.inc` and routed pause loops in:
  - `ptx_runtime.inc`, `mym_runtime.inc`, `vgm_runtime.inc`
- Bumped VibeTune banner build number:
  - `v0.1b065` -> `v0.1b066`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)
- Size note: `vtune.com` reduced to `19900`.

2026-04-11 - Refactor: shared normal-step helper across PTX/MYM/VGM
- Added `PLAYBACK_PLAY_STEP` in `playback_core.inc` and routed normal loops in:
  - `ptx_runtime.inc`, `mym_runtime.inc`, `vgm_runtime.inc`
- Bumped VibeTune banner build number:
  - `v0.1b066` -> `v0.1b067`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)
- Size note: `vtune.com` reduced to `19860`.

2026-04-11 - Hotfix: pause double-toggle regression from shared-step refactor
- Fixed play-loop handling of shared pause-entry signal:
  - route directly to `*_pause_wait` instead of calling `*_pause_toggle`
  - applied in `ptx_runtime.inc`, `mym_runtime.inc`, `vgm_runtime.inc`
- Bumped VibeTune banner build number:
  - `v0.1b067` -> `v0.1b068`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)
- User validation: pause behavior restored (no stutter/no continued playback).

2026-04-11 - Size pass: consolidate redraw handlers and loop-toggle handlers
- `keyctl.inc`:
  - merged 4 redraw routines into shared `KEY_REDRAW_COMMON`
  - merged 4 loop toggle routines into shared `KEY_TOGGLE_LOOP_MODE`
  - simplified action dispatch to use shared redraw/toggle entry points
- Bumped VibeTune banner build numbers:
  - `v0.1b068` -> `v0.1b069` (redraw consolidation)
  - `v0.1b069` -> `v0.1b070` (loop-toggle consolidation)
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)
- Size note: `vtune.com` reduced to `19717`.

2026-04-11 - Current size checkpoint
- `vtune.com` moved from `20251` (debug-era baseline in this session)
  to `19717`.
- Net reduction in this run: `534` bytes.

2026-04-25 - IO port centralization: ports.cfg created (b071)
- Added new configuration file: `ports.cfg`
  - Single source of truth for all hardware IO port addresses
  - Covers: PSG (MSX, Coleco, RC/EB, RC/MF, SCG, N8, RC/EB Z180, RC/MF Z180,
    LINC, MBC, Duodyne, NABU), YM2151 (primary/alt/secondary), OPL3
    (bank1/bank2), SN76489 (primary/secondary)
  - Z180 wait-state base port constants (`Z180_NONE/N8/RCZ180`)
  - ACR port and enable value constants (`ACR_*/ACRVAL_*`)
- Included via `#include "ports.cfg"` in `vibetune.asm` only (TASM does not
  support `INCLUDE` inside .inc files)
- Refactored `hwcfg.inc`: replaced inline hex port values in HBSA_DO_* and
  HBS2_TRY_* branches with named PSG_* constants
- Bumped VibeTune banner build number:
  - `v0.1b070` -> `v0.1b071`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)
- Size note: `vtune.com` 19,728 bytes (+11 from named constant overhead)

2026-04-25 - IO port centralization: CFGTBL and CLI tables refactored (b072)
- Extended `ports.cfg` with additional platform constants:
  - PSG_SCG_*, PSG_N8_*, PSG_RCEB_Z180_*, PSG_RCMF_Z180_*, PSG_LINC_*,
    PSG_MBC_*, PSG_DUO_*, PSG_NABU_* port sets
  - Z180_NONE/N8/RCZ180, ACR_NONE/SCG/MBC/DUO, ACRVAL_NONE/ENABLE
- Refactored `vibetune.asm`:
  - Replaced all 36 CFGTBL rows with named PSG_*/Z180_*/ACR_*/ACRVAL_* constants
  - Replaced MSXPORTS/RCPORTS/COLECOPORTS CLI override tables
  - Replaced OPL3/SN76489/YM2151 EQU definitions to alias ports.cfg constants
- Bumped VibeTune banner build number:
  - `v0.1b071` -> `v0.1b072`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)
- Size note: `vtune.com` 19,728 bytes (identical; named constants resolve same values)

2026-04-25 - IO port centralization: packed word constants + bug fix (b073)
- Added `PSG_*_PORTW` packed-word constants to `ports.cfg`:
  - `PSG_MSX_PORTW` ($A1A0), `PSG_COLECO_PORTW` ($5150),
    `PSG_RCEB_PORTW` ($D0D8), `PSG_RCMF_PORTW` ($D0D1)
  - Layout: H=RDAT, L=RSEL (matches PORTS memory layout)
- Fixed bug introduced in b071: all 10 `LD L,RDAT / LD H,RSEL` pairs in
  HBS2 sub-blocks had RDAT/RSEL swapped; replaced with correct
  `LD HL,PSG_X_PORTW` single instructions
- Replaced remaining hardcoded packed hex port literals in `hwcfg.inc`:
  - Coleco probe: `$5150/$52` -> `PSG_COLECO_PORTW / PSG_COLECO_RIN`
  - HBS2_TRY_RCTWO: `$D0D8/$D0D1` -> `PSG_RCEB_PORTW / PSG_RCMF_PORTW`
  - TS fallback compare/assign literals -> named PORTW constants
- IO port centralization now complete; all remaining hex values in .inc files
  confirmed as non-port data (VGM opcodes, BIOS codes, sentinels, arithmetic)
- Bumped VibeTune banner build number:
  - `v0.1b072` -> `v0.1b073`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors), user tested
- Size note: `vtune.com` 19,718 bytes (-10; 10x `LD L/H` pairs -> `LD HL`)

2026-04-30 - Maintenance sync: ports include rename + visible build bump (b074)
- Renamed VibeTune ports constants include:
  - `ports.cfg` -> `ports.inc`
- Updated `vibetune.asm` include accordingly:
  - `#include "ports.cfg"` -> `#include "ports.inc"`
- Bumped VibeTune banner build number:
  - `v0.1b073` -> `v0.1b074`
- Validation: VibeTune build artifact refreshed (`vtune.com` updated in commit)

2026-05-10 - Phase 4 slice 48 completed (metadata/display extraction + prefetch cleanup)
- Added new module file: `meta_print.inc`
- Moved metadata/display routines from `vibetune.asm` into `meta_print.inc`:
  - `PRTPLAYINFO`
  - `PRT_TSPORTS_LINE`
  - `META_SNAPSHOT`
  - `PRTSONGMETA`
- Included `meta_print.inc` in `vibetune.asm` and removed in-place duplicates
- Removed no-op playlist prefetch hook:
  - removed call-site comment/hook near `_LDX0` load flow
  - removed dead `PREFETCH_TRACKS` stub
- Bumped VibeTune banner build number:
  - `v0.1b074` -> `v0.1b075`
- Validation: `Build.cmd` passes on WBW/ZX/MSX targets (0 errors)
- Size note: `vtune.com` 19,708 bytes (-10 from b073 checkpoint 19,718)
---
This document is the governing blueprint for the VibeTune refactor effort. Keep it updated as each phase completes.










