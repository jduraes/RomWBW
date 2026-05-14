# VibeTune MMU VGM Playback Handover (Second Opinion)
## Scope
This handover is focused on the `mmu` branch work to support MMU-backed VGM playback on real RC2014 hardware.

## Goal
Enable reliable VGM playback where VGM data is loaded into app banks (MMU path) instead of relying on a single contiguous in-bank buffer, while preserving existing PT3/MYM behavior.

Primary success target:
- `goneshrt.vgm` plays audible sound on RC2014 and does not terminate immediately with `Done`.

Secondary:
- Understand/confirm size-limit behavior for larger VGM (`gone.vgm`).
- No regressions in PT3/MYM playback.

## Current Hardware Findings (latest)
Retest with `v0.1b093`:

- `vtune.com` banner is correct.
- `vtune.com goneshrt.vgm`:
  - shows normal startup and metadata line
  - prints `Playing... Done`
  - no sound
- `vtune.com gone.vgm`:
  - still `Sound file too large to load!`

Interpretation:
- MMU sanity gate no longer fails (the prior explicit MMU self-test error is gone).
- Playback still exits early/silently for `goneshrt.vgm`.

## Productive Work Completed (only)
1. VGM-specific MMU loader path
   - VGM now uses a dedicated banked load path (`VGM_LOAD_MMU`) instead of the old flat-memory path.
   - Key points: `vibetune.asm:453`, `vibetune.asm:475`.
2. MMU state and mapping core added
   - MMU init / app-bank discovery: `vibetune.asm:676` (`VGM_MMU_INIT`)
   - Logical-offset to bank/address translation: `vibetune.asm` (`VGM_OFF_TO_BNK`)
   - Banked 128-byte record writer: `vibetune.asm:711` (`VGM_MMU_WRITE_REC`)
   - Cached reader API: `vibetune.asm:813` (`VGM_MMU_READ_AT`)
3. VGM stream runtime made 24-bit aware
   - Runtime entry and flow: `vgm_runtime.inc:5` (`goVGM`)
   - Stream byte reader and position helpers: `vgm_player.inc:14` (`VGM_RD_NEXT`) and nearby helpers.
4. Header-based safety checks
   - VGM image/header validation against loaded size: `vibetune.asm:526` (`VGM_VALIDATE_IMAGE`)
   - Stream start offset from header: `vibetune.asm:560` (`VGM_GET_STREAM_START`)
5. Parser correctness fixes
   - Wait handlers now force NZ return (`OR A`) before `RET` to avoid stale Z-flag causing false end:
     - `vgm_player.inc:315`, `vgm_player.inc:329`, `vgm_player.inc:338`, `vgm_player.inc:347`
   - `VGM_RD_NEXT` now preserves `BC/DE` around MMU read calls:
     - `vgm_player.inc:14`
6. MMU sanity test path added and corrected
   - MMU self-test routine added: `vibetune.asm:606` (`VGM_MMU_SELFTEST`)
   - Error path/message added: `vibetune.asm:2268`, `vibetune.asm:2602`
   - A false-positive bug in self-test compare logic was fixed in `v0.1b093`.
7. Builds are clean
   - Latest build compiles with zero assembler errors and contains `v0.1b093` banner.

## Known Gotchas and Lessons Learned
1. HBIOS calls can clobber registers
   - Any logic relying on register persistence across MMU/HBIOS helper calls is risky unless explicitly preserved.
2. Z80 `LD` does not set flags
   - Prior parser logic relied on flag state after `LD A,1`; this caused false EOS behavior.
3. Potential command-value collision in MMU read failure signaling
   - `VGM_MMU_READ_AT` returns `66h` on error/out-of-range (`vibetune.asm:819`, `vibetune.asm:883`).
   - In VGM parser, opcode `66h` means end/loop (`vgm_player.inc:158` path).
   - This creates a dangerous ambiguity: MMU read failure can look like legitimate EOS and produce immediate `Done`.
4. MMU path currently assumes 32KB app banks
   - Guard in `VGM_MMU_INIT` enforces `E == 0x80`.
5. Large-file behavior remains unresolved
   - `gone.vgm` still hits loader capacity and exits with `Sound file too large to load!`.

## Most Likely Current Failure Mode
Current evidence suggests:
- Self-test now passes, so basic header/cache access is functional.
- `goneshrt.vgm` still exits immediately with `Done`.
- Most likely parser is seeing early `0x66` (EOS), and one strong candidate is MMU read failure aliasing to `66h`.

This is currently the highest-value hypothesis to validate first.

## What Needs Doing Next (prioritized)
1. Decouple MMU read errors from valid VGM opcode stream
   - Stop using `66h` as MMU read error sentinel, or add a separate explicit read-error flag (`VGMRDERR`) checked by parser.
   - If read error occurs, exit through `ERRVGMMMU` (or dedicated read error) instead of normal `Done`.
2. Add minimal runtime instrumentation for one diagnostic build
   - Track/print at exit:
     - first N opcodes read from stream start
     - MMU read error count/flag
     - count of OPL writes processed
     - whether EOS `66h` was encountered naturally
   - Goal: distinguish “real early EOS” vs “read path corruption/failure”.
3. Validate stream start and first bytes for `goneshrt.vgm`
   - Confirm computed `vgmpos` start is in range and points to plausible command stream bytes.
4. Strengthen MMU readback checks around more boundaries
   - Beyond existing cache-window checks, add readback checks around key boundaries (including bank transition area) relevant to command stream traversal.
5. If parser is healthy but still silent, inspect audio-output path
   - Verify OPL writes are actually occurring and not being muted/neutralized.
6. After VGM path is fixed, run PT3/MYM regression validation
   - This remains pending and should be completed before merge.

## Reviewer Hotspots (start here)
- `vgm_runtime.inc:5` (`goVGM`)
- `vgm_player.inc:14` (`VGM_RD_NEXT`)
- `vgm_player.inc:158` (`VGM_PLAY_FRAME`)
- `vgm_player.inc:315`, `vgm_player.inc:329`, `vgm_player.inc:338`, `vgm_player.inc:347` (wait-return fixes)
- `vibetune.asm:526` (`VGM_VALIDATE_IMAGE`)
- `vibetune.asm:560` (`VGM_GET_STREAM_START`)
- `vibetune.asm:606` (`VGM_MMU_SELFTEST`)
- `vibetune.asm:676` (`VGM_MMU_INIT`)
- `vibetune.asm:711` (`VGM_MMU_WRITE_REC`)
- `vibetune.asm:813` (`VGM_MMU_READ_AT`)
- `vibetune.asm:819`, `vibetune.asm:883` (`66h` error return)
- `vibetune.asm:2268`, `vibetune.asm:2602` (MMU error reporting)
- `vgm_hw.inc` (`VGM_SETFDELAY`, `VGM_PACK_TEMPO_DELAY`, `VGM_SCALE_FDLY_KHZ`)
- `vgm_player.inc` (`VGM_STRETCH_VGMDLY`, `VGM_APPLY_DELAY`)

## VGM playback tempo (OPL / `gone.vgm`, ~May 2026)

Calibrated against a stable **~88 BPM** reference on real hardware.

- **`SYS_GETCPUINFO`** (`$F8F0`): save **`DE`** (KHz) and **`L`** (integer MHz index) to **`VGMTMPKHZ` / `VGMTMPMHZ`** before **`VGM_SETFDELAY`** so delay is not tied to truncated MHz only (`vgm_runtime.inc`, `vgm_hw.inc`).
- **`VGM_SCALE_FDLY_KHZ`**: scales **`VGMCLKTBL`** inner count by reported KHz vs nominal **MHz×1000** (`vgm_hw.inc`).
- **`VGM_PACK_TEMPO_DELAY`**: empirical rational chain then packs into **`vgmfdly0`** (inner **`DJNZ`**) × **`vgmfdlo`** (outer rounds per sample); **`VGM_APPLY_DELAY`** nests those loops (`vgm_player.inc`). Integer packing can plateau across small ratio tweaks.
- **`VGM_STRETCH_VGMDLY`**: each wait’s **`(vgmdly)`** is **`orig + (orig>>4)`** (~**+6.25%**); this is the lever that reliably moves measured BPM because decode and OPL I/O dominate wall time vs the inner delay loop alone.
- **Key poll**: **`VGMSAMPACC`** in **`goVGM_nodelay`** keys off sample time (~4410-sample threshold), not VGM frame count (`vgm_runtime.inc`).
- **Jitter**: **`VGM_MMU_RD_SLFILL`** (`vibetune.asm`) performs **`SYSSETCPY` / `SYSBNKCPY`** on 128-byte stream window misses; that cost sits in **`VGM_PLAY_FRAME`**, not **`VGM_APPLY_DELAY`**, so BPM meters may show mild swing at bank boundaries.

## Definition of Done for this workstream
- `goneshrt.vgm` plays audible audio on RC2014 without immediate false `Done`.
- MMU read path has explicit non-ambiguous error signaling.
- Large-file behavior (`gone.vgm`) is either improved or clearly documented as expected capacity limit.
- PT3/MYM regression checks pass.
