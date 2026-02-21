# IFLS FB-01 Integration Pack v5 (Voice Macro GUI + Preset Slots)

Generated: 2026-02-04T20:21:08Z

## What is V5?
A **ReaImGui GUI** inside REAPER to control Yamaha FB-01 via **SysEx** (SWS required):
- System Channel + Instrument (Part) targeting
- Voice Macro controls: Algorithm, Feedback, Operator Enable bitmap, OP1..OP4 Total Level, Transpose
- **Preset slots** stored in REAPER ExtState (project-independent, but persistent)
- **Write Track Notes** for recall
- Quick macro buttons (IDM-friendly starting points)

## Requirements
- **SWS** installed (uses `SNM_SendSysEx`)
- **ReaImGui** installed (for GUI). If missing, script will show a message.

## Files
- `Scripts/IFLS_FB01_VoiceMacro_GUI.lua`  ← run this
- `Scripts/IFLS_FB01_SysEx_Toolkit.lua`  ← from V3 (utility: dump/bank select/etc.)

## Notes on parameter coverage
V5 uses a **safe, minimal** set of widely referenced FB-01 parameters:
- OP enable bitmap (pp=0x4B)
- Algorithm/Feedback packed byte (pp=0x4C)
- Transpose (pp=0x4F, two's complement)
- OP Total Level (pp=0x50,0x60,0x68,0x70)
If you want full operator EG/ratio/detune/etc., we’ll build V6 with a validated param table.

