# VibeTune — TODO / roadmap

## VGM metadata (GD3) vs. `vgmplay`

- [ ] **MMU / banked load:** When `VGMMMUMD` ≠ 0, `VGM_GD3_INIT` in `meta_print.inc` currently returns failure on purpose, so GD3 is never read. Implement GD3 discovery and field walking via `VGM_MMU_READ_AT` (or a single stream reader) using the VGM header GD3 offset (`vgmdata + 0x14` relative to file start, absolute in-file position). Goal: banked VGMs show real track / game / author instead of FCB filename and blank `by:`.
- [ ] **Linear mode — richer display:** Even when GD3 works (TPA linear buffer), `PRTVGMMETA` only prints English track, optional “from:” game, and English author. Add optional lines or a dedicated info command for remaining GD3 fields (system, release date, notes, etc.) in a stable order (mirror `vgmplay` / `vgminfo.asm` where practical).
- [ ] **Technical block:** Optional parity with `vgmplay` for format version, loop time, gain, “VGM by”, and used chips — likely a small shared parser or calls into patterns from `Source/Apps/VGM/vgmplay.asm` / `vgminfo.asm`.
- [ ] **User-facing note:** Help text or `handover.md` bullet: GD3-rich metadata may be limited until MMU GD3 is implemented; use RomWBW `vgmplay` for a full tag dump on CP/M.

## Reference

- `meta_print.inc`: `VGM_GD3_INIT`, `PRTVGMMETA`, `META_SNAPSHOT` (PT3 title/artist at fixed offsets — not VGM GD3).
- RomWBW reference implementation: `Source/Apps/VGM/vgmplay.asm`, `vgminfo.asm`.
