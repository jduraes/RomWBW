# Agent Instructions for RomWBW

These rules apply repository-wide unless the user explicitly overrides them.

## VibeTune Build Banner Rule

For work in Source/Apps/VibeTune:

1. Before running Source/Apps/VibeTune/Build.cmd, update Source/Apps/VibeTune/vibetune.asm.
2. Bump #DEFINE VTBANREL to the next bNNN value.
3. Stamp MSGBAN with the real current date in dd-MMM-yyyy format.
4. Keep this as agent workflow behavior. Do not implement date/version stamping in any Build.cmd.

## RomWBW Release Guardrail

Do not change RomWBW-wide release/version files (for example Source/ver.inc or root release notes) unless the user explicitly asks.

## COPY.COM (ZSD COPY) — external source of truth

RomWBW carries NO source for the ZSDOS COPY app, only binaries. The source of
truth is `../ZSD_COPY` (COPY 1.75, a DOS-like modernization of Hal Bower's
authentic v1.73; all work happens there). After any rebuild in ZSD_COPY, copy
`copy.com` over ALL THREE in-tree locations and commit:

- `Source/Images/Common/Z/u15/COPY.COM`
- `Source/RomDsk/ROM_256KB/COPY.COM`
- `Source/RomDsk/ROM_384KB/COPY.COM`
- `Source/RomDsk/ROM_896KB/COPY.COM`

Then rebuild the ROM disks (`Source/RomDsk/Build.cmd`) and any affected ROM
images (`Source/BuildROM.cmd <platform> <config>`). Never edit or patch these
binaries in place. See `../ZSD_COPY/README.md`
("Deployment into RomWBW") and AGENTS.md there for build rules.

## XMODEM Trigger Mod (CTRL-\) — local custom feature

A local (uncommitted, not for upstream) mod in Source/CPM3 adds a console hotkey
that starts an XMODEM receive on CP/M 3 / ZPM3:

- **Key:** CTRL-\ (0x1C), chosen because CTRL-V (0x16, the original) and ESC/CTRL-[
  (0x1B, tried and rejected) collide with line editing / terminal escape sequences.
- **Behavior:** pressing CTRL-\ at the console prints
  `[CTRL-\ - Starting XMODEM receive]` and `Receiving: FILEnn.TMP`, then types
  `XM R FILEnn.TMP` + CR for the shell. `nn` is a counter in memory that
  increments per press and wraps 99 -> 0. XM.COM must exist on the current
  drive/user; the file lands there (A0: at the ZPM3 prompt).
- **Implementation (Source/CPM3/chario.z80):** the BIOS console-input routine
  `?ci` senses 0x1C and jumps to `xmodem_trigger`, which fills a feed buffer
  with the command text; subsequent `?ci` calls return the buffered chars one
  at a time (`xm_feed`, state in `xm_feedbuf`/`xm_feedptr`/`xm_feedlen`), and
  `?cist` reports "char ready" while feeding. `boot.z80` prints the
  `** CTRL-\ = XMODEM TRIGGER MOD **` signon line.
- **Why keystroke injection:** an earlier version ran inside `?ci` and called
  BDOS directly (open/read XM.COM, `ld sp,0100h`, `call 0100h`). That
  re-enters BDOS while it is still servicing the console-input call and
  crashed the machine on first use. Never call BDOS (0005h) from BIOS chario
  routines; feed input instead.
- **Build/deploy:** Source/CPM3/Build.cmd then Source/ZPM3/Build.cmd produce
  Binary/ZPM3/cpm3.sys; deploy to the SC126's A: user 0 via rc2014bridge (see
  below) and reboot. The mod is inside BNKBIOS3.SPR, so it ships in cpm3.sys
  for both the CP/M 3 and ZPM3 slices.


## Default Sound Unit NVRAM switch (NVSW_SNDDEF) — local custom feature

A local (uncommitted, not for upstream) mod adds a boot-time-selectable
default sound device, stored in the NVSW NVRAM block:

- **Layout:** the NVSW block grows by one byte — new switch `NVSW_SNDDEF=4`
  (hbios.inc), checksum moves to index 5 (`NVSW_DEFAULT`, `SWITCH_TAB`, and
  the HCB shadow `CB_SW_SNDDEF` in hbios.asm all extended accordingly).
- **Consumers:** the boot beep (hbios.asm INITSYS) and the ANSI BEL
  (ansi.asm ANSI_BEL) read `CB_SW_SNDDEF`, clamp it to `SND_CNT`, and
  dispatch `BF_SNDBEEP` to that unit. Both guard `SND_CNT=0` (no sound
  hardware) by skipping the beep entirely.
- **Setter UX:** SYSCONF gains an `SD` command (ROM app `W` at the loader
  and the CP/M SYSCONF.COM). `SD {unit}` validates against
  `BC_SYSGET_SNDCNT` and saves via the normal switch path; status shows in
  the `P`rint list; `H SD` for help.
- **TASM size trap (important):** sysconf.asm sits 208 bytes below its
  fixed 4KB NVR app region (`NVR_SIZ=$0800` in Source/HBIOS/layout.inc).
  If an addition overflows, the `#IF (SLACK<0)` guard prints "SYSCONF APP
  IS TOO BIG" but TASM then **segfaults** evaluating the negative `.FILL`
  instead of erroring — Build.cmd dies mid-stream with no error message
  and produces no ROM (this silently killed the Zed Mini build for a whole
  session). The SD implementation was deliberately slimmed (no device-name
  table, short help) to fit; only ~14 bytes of slack remain. Any further
  sysconf feature must first free space. Also note two `JR mainloop` had
  to become `JP mainloop` (relative range exceeded after the insert).
- **Build/deploy:** Source/HBIOS/Build.cmd as usual; the CP/M variant is
  Source/Apps/Build.cmd → Binary/Apps/SYSCONF.COM.

## Deploying to the SC126 via rc2014bridge (COM10)

The SC126's SD card stays in the machine. Deploy files over the serial console
with the rc2014bridge app (repo: Z:\rc2014bridge), which owns COM10 and serves
MCP over HTTP at http://127.0.0.1:8014/mcp (stateless; send header
`Accept: application/json, text/event-stream`).

Key tools: rc2014_run_command, rc2014_upload (zip + XMODEM + UNZIP + DIR
verify), rc2014_download, rc2014_send_text, rc2014_send_keys, rc2014_reboot,
rc2014_get_screen, rc2014_wait_until_ready.

ZPM3 quirks on this machine (bridge was built against ZSDOS/CP/M 2.2):
- Use `ERASE`, not `ERA` (ERA errors with "ERA ?"). The bridge's overwrite
  erase and post-upload ZIP cleanup use ERA and silently fail on ZPM3 — erase
  leftovers (e.g. CPM3.ZIP) manually with ERASE.
- Bridge UNZIP invocation (`UNZIP A:F.ZIP A:`) only CRC-checks; extraction
  needs `UNZIP CPM3.ZIP /E /O`.
- The ROM disk (B:) holds stale dev.12 utilities: B:XM rejects drive-prefixed
  targets, B:REBOOT rejects /C. The bridge config now has `xm-command = XM`
  (use the current drive's newer XM); for reboot, send `REBOOT /C` via
  rc2014_send_text instead of rc2014_reboot.
- ZPM3 boots from Disk Unit 4, Slice 4 = drive A:, user 0. Its system file is
  A:CPM3.SYS (replacing it is safe while the OS runs — it is memory-resident;
  takes effect next boot). Rebuilt by Source/CPM3/Build.cmd +
  Source/ZPM3/Build.cmd into Binary/ZPM3/cpm3.sys.
- Build.cmd note: `zxcc LINK` aborts on phantom keypress unless stdin is
  redirected (`< NUL`); both CPM3 and ZPM3 Build.cmd files have this fix.

