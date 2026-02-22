<#
IFLS_FB01_Repo_Apply_SyntaxFix_v4.ps1
Applies the same fixes as the local patch, but inside a git repo checkout.

It searches for these possible repo paths:
- reaper/Scripts/IFLS_FB01_Editor/Editor/IFLS_FB01_SoundEditor.lua
- reaper/Scripts/IFLS_Workbench/Workbench/FB01/Editor/IFLS_FB01_SoundEditor.lua

and:
- reaper/Scripts/.../Tools/IFLS_FB01_Batch_Analyze_SYX_Archive.lua

Usage (from repo root):
  powershell -ExecutionPolicy Bypass -File .\tools\IFLS_FB01_Repo_Apply_SyntaxFix_v4.ps1
Then:
  git add -A
  git commit -m "Fix Lua syntax (SoundEditor peak block + batch syx escape)"
  git push
#>

$ErrorActionPreference="Stop"

function Banner($m){ Write-Host ""; Write-Host ("="*80); Write-Host $m; Write-Host ("="*80) }

$repoRoot = (Resolve-Path ".").Path

$searchRoots = @(
  (Join-Path $repoRoot "reaper\Scripts\IFLS_FB01_Editor"),
  (Join-Path $repoRoot "reaper\Scripts\IFLS_Workbench\Workbench\FB01")
) | Where-Object { Test-Path $_ }

if($searchRoots.Count -eq 0){
  throw "No expected script root found under repo. Expected reaper\Scripts\IFLS_FB01_Editor or IFLS_Workbench\Workbench\FB01"
}

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

function FixBatch($text){
  $t = $text
  $t = $t -replace ':gsub\(\s*"\|"\s*,\s*"\s*\\\|\s*"\s*\)', ':gsub("|","\\\\|")'
  $t = $t -replace '"\\\|"', '"\\\\|"'
  return $t
}

Banner "Patching repo files"
foreach($root in $searchRoots){
  Write-Host "Root: $root"

  $soundFiles = Get-ChildItem $root -Recurse -File -Filter IFLS_FB01_SoundEditor.lua -ErrorAction SilentlyContinue
  foreach($f in $soundFiles){
    Banner ("SoundEditor: " + $f.FullName.Substring($repoRoot.Length+1))
    $txt = Get-Content $f.FullName -Raw
    $new = $peakPattern.Replace($txt, "`r`n")
    if($new -ne $txt){
      [System.IO.File]::WriteAllText($f.FullName, $new, (New-Object System.Text.UTF8Encoding($false)))
      Write-Host "Removed stray AutoCal peak block."
    } else {
      Write-Host "No change needed."
    }
  }

  $batchFiles = Get-ChildItem $root -Recurse -File -Filter IFLS_FB01_Batch_Analyze_SYX_Archive.lua -ErrorAction SilentlyContinue
  foreach($f in $batchFiles){
    Banner ("Batch SYX: " + $f.FullName.Substring($repoRoot.Length+1))
    $txt = Get-Content $f.FullName -Raw
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
Write-Host "Next: git add -A; git commit; git push"
