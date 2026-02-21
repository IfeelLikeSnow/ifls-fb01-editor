# IFLS FB-01 Integration Pack v8 (Bulk Dump Capture + Export + Replay + Analyzer)

Generated: 2026-02-05T05:13:41Z

## What V8 adds
V8 focuses on **real-world bulk dump workflows**:

1) **One-click request + timed record** of FB-01 dumps into a MIDI item
2) **Export** selected MIDI item SysEx to a standard `.syx` file (binary)
3) **Replay** a stored dump (raw SysEx) back to the FB-01 for full recall
4) **Analyze** recorded SysEx: count messages, types, lengths, detect FB-01 headers

Why this matters:
- Full voice bank dumps can be more complex than the simple param-change format.
- Rather than guessing mappings, V8 makes your dumps **portable and recallable** immediately.

## Requirements
- **SWS** required for sending SysEx (`SNM_SendSysEx`).
- Recording/parsing/exporting works without SWS, but request/replay needs SWS.

## Web-verified details used
- Dump request headers for FB-01 voice bank & config are documented in SysexDB. citeturn1view0
- Service manual summary notes voice data structure (48 voices, 64 bytes each) — indicates why bank dumps are large. citeturn0search2

## Files
- `IFLS_FB01_AutoDump_Record.lua`
- `IFLS_FB01_Export_SelectedItem_SysEx_To_SYX.lua`
- `IFLS_FB01_StoreDump_To_ExtState.lua`
- `IFLS_FB01_ReplayDump_From_ExtState.lua`
- `IFLS_FB01_SysEx_Analyzer_SelectedItem.lua`

## Workflow (recommended)
1. Cable FB-01 MIDI OUT -> 1824c MIDI IN
2. Arm a MIDI track with that input.
3. Run **AutoDump_Record** (choose dump type + duration).
4. Select the recorded MIDI item:
   - run **Analyzer** (sanity check)
   - run **Export** to save `.syx`
   - run **StoreDump** to keep it in ExtState slot
5. Later: run **ReplayDump** to restore the bank/config on hardware.

> Next (V9): parse bulk voice bank into a human-readable list of 48 patch names, and optionally map key macro params.
