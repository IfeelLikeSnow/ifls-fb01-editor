param(
  [Parameter(Mandatory=$true)][string]$IndexPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (!(Test-Path $IndexPath)) { throw "Index not found: $IndexPath" }
$txt = Get-Content $IndexPath -Raw

if ($txt -notmatch '<index\b') { throw "index.xml missing <index> root element." }
if ($txt -notmatch '<source\b') { throw "index.xml has no <source> entries." }

$bad1 = [regex]::Matches($txt, '<source\b[^>]*/>').Count
$bad2 = [regex]::Matches($txt, '<source\b[^>]*>\s*</source>').Count
if ($bad1 -gt 0 -or $bad2 -gt 0) {
  throw "Invalid: empty <source> URL detected. self-closing=$bad1 empty-text=$bad2"
}

if ($txt -match 'file="Scripts/IFLS FB-01 Editor/Editors/') {
  throw "Invalid: still installing under Scripts/IFLS FB-01 Editor/Editors/..."
}

Write-Host "OK: index.xml looks valid (no empty <source>, no Editors nesting)."
