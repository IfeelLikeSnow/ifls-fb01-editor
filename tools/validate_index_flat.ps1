param(
  [Parameter(Mandatory=$false)][string]$IndexPath = ".\index.xml"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (!(Test-Path $IndexPath)) { throw "Index not found: $IndexPath" }
$txt = Get-Content $IndexPath -Raw

# Must look like XML
if ($txt -notmatch '<index\b')  { throw "index.xml doesn't contain <index> tag (looks corrupted)." }
if ($txt -notmatch '<source\b') { throw "index.xml doesn't contain any <source> tags." }

# ReaPack requires URL text inside <source> ... </source>
$selfClosing = [regex]::Matches($txt, '<source\b[^>]*/>').Count
$emptyText   = [regex]::Matches($txt, '<source\b[^>]*>\s*</source>').Count
if ($selfClosing -gt 0 -or $emptyText -gt 0) {
  throw "Invalid ReaPack index: empty source url (selfClosing=$selfClosing, emptyText=$emptyText)"
}

# Must NOT install into the old nested structure
if ($txt -match 'file="Scripts/IFLS FB-01 Editor/Editors/Scripts') {
  throw "Index still contains the unwanted Editors/Scripts nesting."
}

Write-Host "OK: index passes basic checks. selfClosing=$selfClosing emptyText=$emptyText"
