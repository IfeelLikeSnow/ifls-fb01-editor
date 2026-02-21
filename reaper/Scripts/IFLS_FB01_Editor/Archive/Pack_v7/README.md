# IFLS FB-01 Integration Pack v7 (Bidirectional via Dump → Parse → Recall)

Generated: 2026-02-04T20:32:53Z

## What V7 adds
A robust, practical "bidirectional" workflow without relying on fragile live polling:

1) **Request a dump** from the FB-01 (SysEx request)
2) **Record the incoming SysEx** into a REAPER MIDI item (your MIDI input must be enabled)
3) **Parse the recorded dump item** and store the parameters into:
   - ExtState preset slots used by the V5 GUI (so you can Load Slot and see values)
   - optional Track Notes recall

This is the most reliable way to do full recall inside REAPER.

## Requirements
- **SWS** (for SysEx send helper; parsing works without SWS)
- **ReaImGui** only if you use the V5 GUI (this pack includes import/export scripts, not a GUI)

## Files
- `IFLS_FB01_Request_Dump.lua`
  Sends dump requests (Config / Voice Bank 0/1). (SWS required)
- `IFLS_FB01_Import_Dump_From_Selected_Item.lua`
  Parses SysEx events from the selected MIDI item and writes a slot into ExtState.
- `IFLS_FB01_Apply_Slot_To_FB01.lua`
  Loads a stored slot and sends mapped parameters back to the FB-01 (SWS required).
- `IFLS_FB01_VoiceMacro_GUI.lua`
  (Copied from V5 for convenience; uses the same ExtState section.)

## Workflow (10 minutes)
1. Connect FB-01 MIDI OUT → 1824c MIDI IN.
2. REAPER Preferences → MIDI Devices → enable 1824c MIDI input for **input** and **control**.
3. Create a track, set input to the FB-01 MIDI input, arm, record.
4. Run `IFLS_FB01_Request_Dump.lua` and choose dump type.
5. Record for a few seconds until dump ends; stop.
6. Select the recorded MIDI item and run `IFLS_FB01_Import_Dump_From_Selected_Item.lua`.
7. Open `IFLS_FB01_VoiceMacro_GUI.lua` and Load the same Slot to view/use it; or run Apply script.

## Notes
- This V7 parser focuses on the **Param-Change format** used by our toolkit:
  `F0 43 75 0s zz pp 0y 0x F7`
- It ignores unknown SysEx types safely.
- Full voice bank dumps may include formats beyond simple param-change; if your dump uses a different layout,
  we can extend the parser in V8 once we confirm a real recorded dump item.

