[CmdletBinding()]
param(
  [string]$IndexPath = ".\index.xml"
)

$IndexPath = (Resolve-Path $IndexPath).Path
$txt = Get-Content $IndexPath -Raw

if ($txt -notmatch '<index\b') { throw "index.xml: missing <index> root" }
if ($txt -notmatch '<source\b') { throw "index.xml: missing <source> entries" }

$sc = [regex]::Matches($txt, '<source\b[^>]*/>').Count
if ($sc -ne 0) { throw "index.xml: has self-closing <source/> ($sc) -> empty source url" }

if ($txt -match 'Editors/Scripts/IFLS FB-01 Editor') {
  throw "index.xml: still installs into Editors/Scripts/IFLS FB-01 Editor (double nesting)"
}

if ($txt -notmatch 'file="\.\./IFLS FB-01 Editor/') {
  Write-Warning "No file=\"../IFLS FB-01 Editor/\" found. Are you flattening to Scripts root as intended?"
}

if ($txt -match 'file="\.\./\.\./MenuSets/') {
  Write-Host "OK: MenuSets install targets present (../../MenuSets/...)" -ForegroundColor Green
} else {
  Write-Warning "No MenuSets targets found (../../MenuSets/...). If you expect toolbar install, ensure a .ReaperMenu exists in MenuSets/ or reaper/MenuSets/."
}

Write-Host "Validation OK." -ForegroundColor Green
