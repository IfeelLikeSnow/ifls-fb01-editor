# FB-01 + PreSonus Studio 1824c + REAPER (Quick)

## Cabling
- 1824c MIDI OUT -> FB-01 MIDI IN
- FB-01 audio OUT L/R -> 1824c line inputs (choose a stereo pair)

## REAPER
Preferences -> MIDI Devices:
- Enable "Studio 1824c MIDI Out"
- (Optional) Enable "Studio 1824c MIDI In"

## FB-01
- Set Instrument 1..8 to receive on MIDI channels 1..8 if using the rack script.
- If you keep it monotimbral, just use Part 1 and MIDI CH 1.

## Using the rack
Run: Scripts/IFLS_FB01_Create_8Part_Rack_1824c.lua
Then set Audio Return track input to your used line inputs.

## Mix control
Select a Part track and run: Scripts/IFLS_FB01_CC_MixPanel.lua
