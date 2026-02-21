# IFLS FB-01 Integration Pack v3 (SysEx Config + Dump + Transpose + Bank Select)

Generated: 2026-02-04T20:05:45Z

## Goal (V3)
Add a **working SysEx engine** for Yamaha FB-01 inside REAPER:
- Config/Instrument parameter change by **System Channel + Instrument**
- Value nibble-splitting (low/high) for 0..255 data
- Signed transpose helper
- Dump request helpers (config + voice banks)
- Bank select helper (per known FB-01 SysEx bank change patterns)

> Voice/operator edit table mapping is V4 once we lock your preferred parameter list.
> V3 gives you the **reliable transport + helpers**.

## Requirements
- **SWS extension** recommended: uses `SNM_SendSysEx()` for reliable SysEx send.
- ReaImGui optional: UI nicer; if missing, script uses prompts.

## Sources used for message formats
- Nibble split explanation for FB-01 voice data values (dataHigh/dataLow). citeturn2view0
- Config change pattern `F0 43 75 0s zz pp 0y 0x F7`, with `zz = 0x18 + instrument` and low/high nibble order. citeturn2view1
- Dump request examples + ACK behavior + memory protect notes. citeturn2view2
- Bank select SysEx example for FB-01. citeturn2view3

## Contents
### Scripts
- `IFLS_FB01_SysEx_Toolkit.lua` (main)
- `IFLS_FB01_Create_8Part_Rack_1824c.lua` (from V2, included)

### Docs
- `FB01_SysEx_CheatSheet.md`
- `FB01_REAPER_1824c_Setup.md`

### Ctrlr
- `FB01_Ctrlr_SysEx_Snippets.md` (ready-to-paste Lua + Global Variables usage)

