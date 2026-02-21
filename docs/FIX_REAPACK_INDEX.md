# Fix: ReaPack install paths + MenuSets

This patch replaces the broken generator that wrote `index.xml` as plain URLs (no XML tags).
It adds:

- `tools/generate_index_flat.ps1` -> generates a valid ReaPack `index.xml`:
  - installs scripts under `Scripts/IFLS FB-01 Editor/...`
  - installs JSFX under `Effects/IFLS/...`
  - installs toolbar file under `MenuSets/...` (goes to REAPER resource path `MenuSets`)

- `tools/validate_index_flat.ps1` -> sanity checks (no self-closing <source/> etc.)

## Usage (PowerShell)

From repo root:

```powershell
mkdir tools -Force
# (copy tools/* here)
.	ools\generate_index_flat.ps1 -Owner IfeelLikeSnow -Repo ifls-fb01-editor -Branch main -Version 0.1.10
.	oolsalidate_index_flat.ps1 -IndexPath .\index.xml
git add -A
git commit -m "Fix index.xml generation"
git push
```

Then in REAPER:
- ReaPack uninstall the package, close REAPER, delete `Scripts/IFLS FB-01 Editor`, restart and reinstall.
