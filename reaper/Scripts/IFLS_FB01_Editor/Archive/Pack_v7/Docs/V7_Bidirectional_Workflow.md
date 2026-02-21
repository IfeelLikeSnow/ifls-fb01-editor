# V7 Bidirectional Workflow (Dump → Item → Import → Recall)

## 0) Cabling
- FB-01 MIDI OUT -> PreSonus 1824c MIDI IN
- PreSonus 1824c MIDI OUT -> FB-01 MIDI IN (for sending)

## 1) Enable MIDI input in REAPER
Preferences -> MIDI Devices:
- Enable the 1824c MIDI input
- Enable it for input + control (so SysEx is accepted)

## 2) Record the dump
1. Create a track and set its input to the 1824c MIDI input.
2. Arm the track.
3. Start recording.
4. Run `IFLS_FB01_Request_Dump.lua` (choose Config or Voice Bank).
5. Wait until the dump finishes, then stop recording.

You should now have a MIDI item containing SysEx text/sysex events.

## 3) Import into Slot
1. Select the recorded MIDI item.
2. Run `IFLS_FB01_Import_Dump_From_Selected_Item.lua`
3. Choose Slot (1-8).
4. Open `IFLS_FB01_VoiceMacro_GUI.lua` and Load Slot.

## 4) Apply back to hardware
Run `IFLS_FB01_Apply_Slot_To_FB01.lua` (Slot 1-8).

## Notes
- The importer currently recognizes param-change SysEx messages of the form:
  `F0 43 75 0s zz pp 0y 0x F7`
- If your recorded dump uses a different message format, we can extend the parser once we inspect a real dump item.
