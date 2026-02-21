# FB-01 SysEx Cheat Sheet (V3)

## Config/Instrument Parameter Change (Sys Channel + Instrument)
Pattern:
`F0 43 75 0s zz pp 0y 0x F7`

Where:
- `s` = system channel number-1 (System Ch 1 -> 00)
- `zz` = 0x18 + instrumentNumber (Instrument 1 -> 0x18; Instrument 8 -> 0x1F)
- `pp` = parameter number (1 byte)
- `xy` = data byte split to nibbles; sent as `0y 0x` (low nibble first)

Ref: MIDI.org thread with worked transpose examples and nibble order. citeturn2view1

## Nibble split formula
DataHigh = int(value/16)
DataLow  = value - 16*DataHigh
Send as `0Low 0High`.

Ref: MIDI.org explanation. citeturn2view0

## Dump requests (examples)
- Dump all config: `F0 43 75 00 20 03 00 F7`
- Dump voice bank 0: `F0 43 75 00 20 00 00 F7`
- Dump voice bank 1: `F0 43 75 00 20 00 01 F7`

Ref: NerdlyPleasures dump notes + ACK/error notes. citeturn2view2

## Bank select (user-reported)
`F0 43 75 01 18 04 xx F7` where xx = 00..06

Ref: LogicProHelp post. citeturn2view3
