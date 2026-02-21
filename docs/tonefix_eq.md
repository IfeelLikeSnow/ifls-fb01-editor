# FB-01 ToneFix EQ

This project can optionally auto-insert **JS: IFLS FB-01 ToneFix** on the **FB-01 Audio Return** track.

## Why
Many users describe the FB-01 output as *quiet* with *noise* and a *treble roll-off / muffled* character.

## Default curve (starting point)
- HPF: 40 Hz
- Low shelf @120 Hz: 0 dB (optional)
- Presence @2.5 kHz: 0 dB (optional)
- High shelf @6 kHz: +6 dB (default)
- Output trim: 0 dB

## Noise-aware treble
If AutoCal baseline is measured, the script can set the high-shelf amount automatically:
- higher measured noise -> smaller high-shelf boost
- lower noise -> stronger high-shelf boost

## FX Chain export
Use the button **Install ToneFix FX Chain (.RfxChain)** to export a real Reaper FX Chain into `<ResourcePath>/FXChains/IFLS/`.
