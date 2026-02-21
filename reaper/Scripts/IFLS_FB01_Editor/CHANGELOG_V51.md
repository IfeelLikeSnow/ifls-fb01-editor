# V51 Additions (FB-01 dump workflow reliability)

Generated: 2026-02-05T13:01:25.442606Z

## New: AutoDump Adaptive
`Pack_v8/Scripts/IFLS_FB01_AutoDump_Record_Adaptive.lua`

- Starts recording
- Sends dump request after a user-defined delay
- Monitors the recorded MIDI take's SysEx event count
- Stops automatically when the SysEx stream goes quiet for QUIET_MS (after MIN_SEC)

This avoids guessy timers for different dump sizes and MIDI throughput.

## New: Safe .SYX Replay
`Pack_v8/Scripts/IFLS_FB01_Replay_SYX_File_Safe.lua`

- Splits concatenated .syx into individual messages (F0..F7)
- Sends with base delay + optional extra delay per message length
- Optional console progress logging

## Notes
- For AutoDump Adaptive, select or arm the MIDI track that receives FB-01 MIDI IN.
- Ensure REAPER MIDI input device is enabled, and SysEx recording is allowed.
