# V50 Fixes (FB-01 toolchain)

Generated: 2026-02-05T12:57:23.479853Z

## Fix 1: Lua syntax blocker
- Removed an erroneous leading backslash (`\`) at the start of 16 Lua scripts which caused immediate syntax errors.

## Fix 2: REAPER SysEx framing correctness
REAPER's `MIDI_GetTextSysexEvt` returns SysEx **payload without F0/F7** in many contexts.
V50 updates the following scripts to accept both framed/unframed and to export/store **properly framed** `.syx`:

- Pack_v7:
  - `IFLS_FB01_Import_Dump_From_Selected_Item.lua` (robust parser + correct API call)
- Pack_v8:
  - `IFLS_FB01_SysEx_Analyzer_SelectedItem.lua` (robust detection + correct API call)
  - `IFLS_FB01_Export_SelectedItem_SysEx_To_SYX.lua` (adds F0/F7 framing on export)
  - `IFLS_FB01_StoreDump_To_ExtState.lua` (stores framed hex)
- PatchLibrary:
  - `IFLS_FB01_Send_SYX_File.lua` (frames any unframed messages before send)

## Fix 3: Safer API usage
- Normalized `MIDI_GetTextSysexEvt(take, i)` call signatures (no extra dummy args).

## Recommended next step
- Record ONE real FB-01 voice bank dump in REAPER with Pack_v8, export `.syx`, then we can implement V9:
  - parse 48 patch names
  - tag/categorize
  - integrate as Workbench patch librarian
