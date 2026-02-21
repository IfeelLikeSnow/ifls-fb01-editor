# V52 Additions (Repo-wide + FB-01 workflow)

Generated: 2026-02-05T13:07:47.992256Z

## FB-01
### AutoDump Adaptive upgraded
`Workbench/FB01/Pack_v8/Scripts/IFLS_FB01_AutoDump_Record_Adaptive.lua`
- Auto-selects the latest recorded MIDI item.
- Optional auto-export of the recorded SysEx into a framed `.syx` file in the project directory.

### Safe Replay remains
`Workbench/FB01/Pack_v8/Scripts/IFLS_FB01_Replay_SYX_File_Safe.lua`

## Repo-wide
### New: Workbench Doctor
`Scripts/IFLS_Workbench/Tools/IFLS_Workbench_Doctor.lua`
- Dependency + file presence sanity checker for any machine.

### New: DeepScan report
`Docs/V52_DeepScan_Report.md`
- Inventory + risks + recommended roadmap (beyond FB-01 patches).

## Small fixes
- Removed accidental leading backslash from V51 scripts.
- Added ReaImGui guards to older FB-01 tools that used ImGui without checking.
