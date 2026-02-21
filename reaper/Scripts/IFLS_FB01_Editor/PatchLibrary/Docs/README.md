# FB-01 Patch Archive – Manifest + Sender

## What this is
- A cleaned copy of the uploaded "FB01 Patch Archive" (without __MACOSX cruft)
- `manifest.json` with hashes and basic metadata
- A REAPER ReaScript to send `.syx` files to the Yamaha FB-01 via SWS

## How to use
1) Ensure SWS is installed.
2) In REAPER: Actions → Run ReaScript → `IFLS_FB01_Send_SYX_File.lua`
3) Choose a `.syx` file from `Patches/`
4) Set inter-message delay (10 ms is a safe start)
5) Make sure the FB-01 has Memory Protect OFF if you're writing to memory.

## Next step
If you record a dump after loading a bank, we can build a true librarian:
- parse voice names
- categorize (bass/pad/bell/percussion)
- integrate into IFLS Workbench as "patch library"
