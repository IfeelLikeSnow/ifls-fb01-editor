# IFLS FB-01 Integration Pack v2 (Mix/Assign first)

Generated: 2026-02-04T19:48:13Z

## What this pack does
- Creates a **practical REAPER hardware-instrument setup** for Yamaha FB-01 with **PreSonus Studio 1824c**.
- Focus: **Mix/Assign** workflow (multitimbral 1–8 parts) using **standard MIDI** (CC/PC/PB) for immediate usability.
- Optional: SysEx send helper (requires SWS if you want live SysEx from scripts).

## Why standard MIDI first?
FB-01 SysEx editing is totally possible but panel/SysEx maps vary. Standard MIDI gives you:
- Volume (CC7), Pan (CC10), Expression (CC11)
- Mod (CC1), Sustain (CC64), Pitch Bend
- Program Change per part
…which is enough to start producing + resampling right away.

## Contents
### Scripts
- `IFLS_FB01_Create_8Part_Rack_1824c.lua`
  Creates a folder track "FB-01 Rack" with 8 MIDI part tracks + one audio return track.
- `IFLS_FB01_CC_MixPanel.lua`
  Small control panel (ReaImGui if available; otherwise text prompts) to send CC7/10/11 + Program Change to a chosen part/channel.
- `IFLS_FB01_Send_SysEx_SWS.lua` (optional)
  Sends a raw SysEx string if SWS is installed (uses SNM_SendSysEx when available).

### Track templates
- `FB01_Rack_8Parts_1824c.RTrackTemplate`
- `FB01_SinglePart_1824c.RTrackTemplate`

## Setup steps (quick)
1. Connect:
   - 1824c MIDI OUT -> FB-01 MIDI IN
   - FB-01 audio OUT L/R -> 1824c line inputs (choose which pair)
2. REAPER: Preferences -> MIDI Devices -> enable **Studio 1824c MIDI Out** (and In if desired).
3. Run script `IFLS_FB01_Create_8Part_Rack_1824c.lua`.
4. Set the created Audio Return track input to the line inputs you used (default is "Input 1/2" placeholder).
5. Use `IFLS_FB01_CC_MixPanel.lua` to adjust volume/pan and send program changes.

## Notes
- If you want **true SysEx voice editing** from REAPER, we can build V3 with a dedicated SysEx engine + mapping once you confirm your FB-01 System Channel + whether you use Parts 1–8.
