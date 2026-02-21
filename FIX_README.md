# IFLS ReaPack index generator (flat install)

This drops all installed scripts into:
- Scripts/IFLS FB-01 Editor/...

and installs:
- MenuSets/*.ReaperMenu into REAPER's MenuSets folder
- Effects/*.jsfx into REAPER's Effects folder

## Run

From repo root:

```powershell
$owner="IfeelLikeSnow"
$repoName="ifls-fb01-editor"
$branch="main"
$version="0.1.10"

powershell -ExecutionPolicy Bypass -File .\tools\generate_index_flat.ps1 -Owner $owner -Repo $repoName -Branch $branch -Version $version -RepoRoot (Resolve-Path .).Path
powershell -ExecutionPolicy Bypass -File .\tools\validate_index_flat.ps1 -IndexPath .\index.xml
```
