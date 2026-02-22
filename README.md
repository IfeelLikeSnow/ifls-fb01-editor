# IFLS ReaPack Index Fix Toolkit

This toolkit fixes the current problem where `index.xml` in your GitHub repo is **not XML**, so ReaPack can't install packages.

## What happened (symptom)
`https://raw.githubusercontent.com/IfeelLikeSnow/ifls-fb01-editor/main/index.xml` currently **does not contain `<index>`** (it's a single-line text file), so ReaPack cannot parse it.

## Files
- `tools/generate_index_reapack_ifls.ps1` — generates a valid ReaPack `index.xml` from your repo contents.
- `tools/validate_index_reapack_ifls.ps1` — validates the generated `index.xml` (no self-closing `<source/>`, has `<index>`, has URLs).
- `.gitignore.snippet` — ignore `*.bak_*` backups.

## How to use (PowerShell)
Run these from your local repo folder:
`C:\Users\ifeel\Downloads\ifls-fb01-editor_push\ifls-fb01-editor`

```powershell
cd "$env:USERPROFILE\Downloads\ifls-fb01-editor_push\ifls-fb01-editor"

# copy toolkit into repo (tools/*)
# then generate + validate:
powershell -ExecutionPolicy Bypass -File .\tools\generate_index_reapack_ifls.ps1 -Owner IfeelLikeSnow -Repo ifls-fb01-editor -Branch main -Version 0.1.12
powershell -ExecutionPolicy Bypass -File .\tools\validate_index_reapack_ifls.ps1 -IndexPath .\index.xml

# ignore backups (recommended)
type .gitignore.snippet >> .gitignore

git add -A
git commit -m "Fix ReaPack index.xml (valid XML) + tools"
git push
```

## After pushing
Verify online:

```powershell
$u="https://raw.githubusercontent.com/IfeelLikeSnow/ifls-fb01-editor/main/index.xml"
$t=(Invoke-WebRequest -UseBasicParsing $u).Content
$t.Contains("<index")
([regex]::Matches($t,'<source\b[^>]*/>').Count) # must be 0
```

Then in REAPER:
ReaPack → Manage repositories → remove old entry → restart REAPER → Import:
`https://raw.githubusercontent.com/IfeelLikeSnow/ifls-fb01-editor/main/index.xml` → Synchronize.

