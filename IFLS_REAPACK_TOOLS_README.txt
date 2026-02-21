# IFLS FB-01 ReaPack tools (fix4)

## What this solves
- Keep ReaPack category "Editors" (package list)
- Install scripts flat to `REAPER_RESOURCE/Scripts/IFLS FB-01 Editor/...` (no `Editors/Scripts/...` nesting)
- Install JSFX to `REAPER_RESOURCE/Effects/IFLS/...`
- Install toolbars to `REAPER_RESOURCE/MenuSets/...` (from `MenuSets/*.ReaperMenu`)

Uses ReaPack index format rules: category defines subfolders for script/effect packages and `source/@file` can change target; the `<source>` content must be the download URL; `main="main"` registers scripts in action list. See spec. 

## Usage (PowerShell)
From repo root (where `.git` and `index.xml` live):

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\generate_index_ifls.ps1 `
  -Owner IfeelLikeSnow -Repo ifls-fb01-editor -Branch main -Version 0.1.10

powershell -ExecutionPolicy Bypass -File .\tools\validate_index_ifls.ps1
```

Commit + push:
```powershell
git add index.xml tools
git commit -m "ReaPack index: keep category Editors, flatten installs"
git push
```

Then in REAPER: uninstall package, delete old `Scripts\IFLS FB-01 Editor\` folder, reinstall via ReaPack.
