<#
IFLS_FB01_Apply_SyntaxFix_v4.ps1
Fixes the remaining two Lua syntax errors you reported:

1) IFLS_FB01_SoundEditor.lua: <eof> expected near 'end'  (extra stray AutoCal "peak" block)
   -> Removes an unwrapped block that starts with:
        local db = _peak_hold_db(tr, false)
      and ends with:
        return
      end
      (This block is missing its surrounding 'if' and leaves an extra 'end'.)

2) IFLS_FB01_Batch_Analyze_SYX_Archive.lua: invalid escape sequence near '"\|'
   -> Fixes:
        r0[1]:gsub("|","\|")
      to:
        r0[1]:gsub("|","\\|")

This script patches BOTH:
- %APPDATA%\REAPER\Scripts\IFLS FB-01 Editor\...
- and if present, the nested bad install:
  %APPDATA%\REAPER\Scripts\IFLS FB-01 Editor\IFLS FB-01 Editor\...

Backups (.bak_TIMESTAMP) are created next to each patched file.

Usage:
  powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\IFLS_FB01_Apply_SyntaxFix_v4.ps1"
#>

param(
  [string]$ScriptsRoot = "$env:APPDATA\REAPER\Scripts"
)

$ErrorActionPreference="Stop"

function Banner($m){ Write-Host ""; Write-Host ("="*80); Write-Host $m; Write-Host ("="*80) }

if(!(Test-Path $ScriptsRoot)){ throw "ScriptsRoot not found: $ScriptsRoot" }

# Targets
$searchRoots = @(
  (Join-Path $ScriptsRoot "IFLS FB-01 Editor"),
  (Join-Path $ScriptsRoot "IFLS FB-01 Editor\IFLS FB-01 Editor")
) | Where-Object { Test-Path $_ }

if($searchRoots.Count -eq 0){ throw "No IFLS FB-01 Editor folder found under: $ScriptsRoot" }

# Regex: remove stray peak block
$peakPattern = New-Object System.Text.RegularExpressions.Regex(
  '\r?\n\s*local db\s*=\s*_peak_hold_db\s*\(\s*tr\s*,\s*false\s*\)\s*' +
  '\r?\n\s*AUTOCAL\.last_db\s*=\s*db\s*' +
  '\r?\n\s*local audible\s*=\s*\(db\s*>=\s*\(AUTOCAL\.thresh_db\s+or\s+-45\.0\)\)\s*' +
  '\r?\n\s*AUTOCAL\.audible\s*\[\s*AUTOCAL\.algo\s*\]\s*\[\s*AUTOCAL\.op\s*\]\s*=\s*audible\s*' +
  '\r?\n\s*_log_add\s*\(\s*"algo"\s*,\s*string\.format\s*\(\s*"AutoCal algo %d op %d peak=%\.1f dB -> %s"\s*,\s*AUTOCAL\.algo\s*,\s*AUTOCAL\.op\s*,\s*db\s*,\s*audible\s+and\s+"AUDIBLE"\s+or\s+"no"\s*\)\s*\)\s*' +
  '\r?\n\s*AUTOCAL\.status\s*=\s*string\.format\s*\(\s*"Algo %d / OP %d: peak %\.1f dB \(%s\)"\s*,\s*AUTOCAL\.algo\s*,\s*AUTOCAL\.op\s*,\s*db\s*,\s*audible\s+and\s+"AUDIBLE"\s+or\s+"no"\s*\)\s*' +
  '\r?\n\s*AUTOCAL\.t0\s*=\s*now\s*' +
  '\r?\n\s*AUTOCAL\.phase\s*=\s*"pause"\s*' +
  '\r?\n\s*return\s*' +
  '\r?\n\s*end\s*(\r?\n)',
  [System.Text.RegularExpressions.RegexOptions]::Singleline
)

# Fix batch gsub pattern
function FixBatch($text){
  $t = $text
  # exact buggy pattern
  $t = $t -replace ':gsub\(\s*"\|"\s*,\s*"\s*\\\|\s*"\s*\)', ':gsub("|","\\\\|")'
  # also if it appears as plain "\|"
  $t = $t -replace '"\\\|"', '"\\\\|"'
  return $t
}

Banner "Patching IFLS FB-01 Lua files"

foreach($root in $searchRoots){
  Write-Host "Root: $root"
  $soundFiles = Get-ChildItem $root -Recurse -File -Filter IFLS_FB01_SoundEditor.lua -ErrorAction SilentlyContinue
  foreach($f in $soundFiles){
    Banner ("SoundEditor: " + $f.FullName)
    $txt = Get-Content $f.FullName -Raw
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item $f.FullName ($f.FullName + ".bak_" + $stamp) -Force

    $new = $peakPattern.Replace($txt, "`r`n")
    if($new -ne $txt){
      [System.IO.File]::WriteAllText($f.FullName, $new, (New-Object System.Text.UTF8Encoding($false)))
      Write-Host "Removed stray AutoCal peak block."
    } else {
      Write-Host "No stray AutoCal peak block found (already fixed)."
    }
  }

  $batchFiles = Get-ChildItem $root -Recurse -File -Filter IFLS_FB01_Batch_Analyze_SYX_Archive.lua -ErrorAction SilentlyContinue
  foreach($f in $batchFiles){
    Banner ("Batch SYX: " + $f.FullName)
    $txt = Get-Content $f.FullName -Raw
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item $f.FullName ($f.FullName + ".bak_" + $stamp) -Force
    $new = FixBatch $txt
    if($new -ne $txt){
      [System.IO.File]::WriteAllText($f.FullName, $new, (New-Object System.Text.UTF8Encoding($false)))
      Write-Host "Fixed invalid escape sequence (\\|)."
    } else {
      Write-Host "No change needed."
    }
  }
}

Banner "DONE"
Write-Host "Restart REAPER and run the IFLS FB-01 Lua syntax scan again."
Write-Host "If there are new errors, paste them here and we'll patch the next layer."
