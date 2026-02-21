param([string]$IndexPath = ".\index.xml")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$txt = Get-Content $IndexPath -Raw
$selfClosing = [regex]::Matches($txt,'<source\b[^>]*/>').Count
$emptyText  = [regex]::Matches($txt,'<source\b[^>]*>\s*</source>').Count
if ($selfClosing -gt 0 -or $emptyText -gt 0) {
  throw "Invalid ReaPack index: empty source url (selfClosing=$selfClosing, emptyText=$emptyText)"
}

if ($txt -match 'file="Scripts/IFLS FB-01 Editor/Editors/Scripts') {
  throw "Index still contains the unwanted Editors/Scripts nesting."
}

Write-Host "OK: index passes basic checks."
