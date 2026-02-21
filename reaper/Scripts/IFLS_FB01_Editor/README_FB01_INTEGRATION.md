# Yamaha FB-01 Integration (IFLS Workbench)

This folder integrates:
- REAPER/1824c setup helpers (rack templates + CC mix panel)
- SysEx toolkit (SWS-based)
- Voice Macro GUI (ReaImGui)
- Bidirectional workflow via dump recording + import/apply
- Bulk dump tools: auto-record, export .syx, replay, analyzer
- Internet patch library (.syx banks) + manifest + sender script

## Quick start
1) Install SWS + ReaImGui.
2) Use `Pack_v2/Scripts/IFLS_FB01_Create_8Part_Rack_1824c.lua` to create the rack.
3) Use `Pack_v5/Scripts/IFLS_FB01_VoiceMacro_GUI.lua` for fast macro shaping.
4) Use `Pack_v8` to record/export/replay full banks.
5) Load internet banks from `PatchLibrary/Patches/` using `PatchLibrary/Scripts/IFLS_FB01_Send_SYX_File.lua`.

## Provenance
- Original archive preserved under `Sources/FB01_Patch_Archive_Original/`.
