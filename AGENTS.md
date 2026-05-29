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
