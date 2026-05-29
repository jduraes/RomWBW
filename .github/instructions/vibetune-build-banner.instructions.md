---
applyTo: "Source/Apps/VibeTune/**"
description: "For VibeTune app work, bump VTBANREL and stamp MSGBAN date before running Build.cmd; keep this as agent workflow behavior only."
---

# VibeTune Build Banner Rule

When working in Source/Apps/VibeTune:

1. Before running Source/Apps/VibeTune/Build.cmd, update Source/Apps/VibeTune/vibetune.asm.
2. Bump #DEFINE VTBANREL to the next bNNN value.
3. Stamp MSGBAN with the real current date in dd-MMM-yyyy format.
4. Keep this as agent workflow behavior. Do not implement date/version stamping in any Build.cmd.

# Guardrail

Do not change RomWBW-wide release/version files (for example Source/ver.inc or root release notes) unless the user explicitly asks.
