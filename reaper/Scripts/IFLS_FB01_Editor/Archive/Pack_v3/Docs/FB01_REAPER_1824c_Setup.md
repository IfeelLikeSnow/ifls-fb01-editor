# FB-01 + REAPER + PreSonus Studio 1824c (Setup)

## Cabling
- 1824c MIDI OUT -> FB-01 MIDI IN
- FB-01 audio OUT L/R -> 1824c line inputs (choose a stereo pair)

## REAPER
Preferences -> MIDI Devices:
- Enable "Studio 1824c MIDI Out"
- (Optional) enable MIDI In (for future dump capture)

## FB-01
- For multi mode: set Instruments 1..8 to receive on MIDI ch 1..8.
- Set **System Channel** (FB-01 front panel) to match what you use in the SysEx Toolkit.

## SysEx Toolkit requirements
- Install **SWS** (SNM_SendSysEx) so scripts can send SysEx reliably.

## Workflow
- Create rack (V2 script) -> route audio return inputs -> record/monitor.
- Use SysEx Toolkit for config changes (transpose, bank select, etc.).
- Resample returns for IDM workflows.
