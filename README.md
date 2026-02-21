# IFLS FB-01 Editor (REAPER / ReaImGui)

A Yamaha FB-01 editor & librarian built for REAPER (ReaScript + ReaImGui), including capture/verify workflows, patch library browser, A/B audition tools, scanning/queue audition, session bundles, and an algorithm calibration helper.

## Install (Manual)
1. Download the latest release ZIP from GitHub (or clone this repo).
2. Copy everything inside `reaper/` into your **REAPER resource path**:
   - REAPER: **Options → Show REAPER resource path in explorer/finder**
3. In REAPER, open **Actions → Show action list…**
4. Use **ReaScript: Load…** and load:
   - `reaper/Scripts/IFLS_Workbench/Workbench/FB01/Editor/IFLS_FB01_SoundEditor.lua`

## Install (ReaPack)
1. Install ReaPack (Extension) and restart REAPER. citeturn0search19turn0search9
2. Add this repository:
   - **Extensions → ReaPack → Import repositories…**
   - URL: `https://github.com/IfeelLikeSnow/ifls-fb01-editor/raw/main/index.xml`
3. **Extensions → ReaPack → Synchronize packages**
4. Find **IFLS FB-01 Editor** in the package browser and install. citeturn0search11turn0search6

## Requirements
- REAPER
- ReaImGui (recommended, for UI)
- MIDI interface connected to Yamaha FB-01 (SysEx enabled)
- For Auto-Calibration: FB-01 audio return routed into REAPER

## Docs
See `docs/` for wiring notes and installation details.

## License
See `LICENSE`.



## Optional Patch Libraries (Third‑Party)
To keep the ReaPack package lightweight and license-safe, third‑party SysEx libraries are shipped separately.

1. Download the optional libraries ZIP from the GitHub release assets (or use `ifls-fb01-editor_optional_libraries.zip`).
2. Extract it into your REAPER resource path next to `Scripts/` (or into the folder indicated in the Editor's Library import UI).
3. In the Editor, use the Library/Import function to index the folder.

See `docs/patches_attribution.md`.


## Releasing (Automation v2)

- Run **Actions → “Bump version (manual)”** to update `@version` + `index.xml` and optionally tag.
- Or push a tag like `v0.2.0` directly.
- Tag push triggers **Release (tag)** which builds `dist/ifls-fb01-editor_X.Y.Z.zip` from `reaper/` and publishes a GitHub Release with the ZIP attached.



## Optional Libraries (Not Included)

This public build does **not** ship with third-party patch archives / SYX libraries.

You can keep optional libraries locally (outside the repo) and import them from within the editor, depending on your setup.
See `THIRD_PARTY_NOTICES.md`.


## ReaPack (this repo)
This repository uses `index.xml` to install files under `Scripts/` and `Effects/` into your REAPER resource path.
If you update the repository, run **Extensions → ReaPack → Synchronize packages**.
