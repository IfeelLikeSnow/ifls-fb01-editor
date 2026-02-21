<#
tools\generate_index_reapack_ifls.ps1
Generates a valid ReaPack index.xml for this repo.

Design goals (your requirements):
- Keep Category = "Editors" (for browsing), BUT do not create an "Editors" folder on disk.
- Install scripts directly under:  REAPER_RESOURCE\Scripts\IFLS FB-01 Editor\...
  (i.e. escape out of category folder using file="../<relpath>")
- Install toolbar into:           REAPER_RESOURCE\MenuSets\...
- Install JSFX into:              REAPER_RESOURCE\Effects\IFLS\...
- Mark a small set of entry scripts with main="main" so they appear in Action List after restart.

Repo layout expected:
- Scripts live in: reaper/Scripts/IFLS_FB01_Editor/...
- Optional toolbar lives in: MenuSets/*.ReaperMenu   (repo root)  OR reaper/MenuSets/*.ReaperMenu
- Optional jsfx lives in: reaper/Effects/IFLS/*.jsfx

Usage (run from repo root):
  powershell -ExecutionPolicy Bypass -File .\tools\generate_index_reapack_ifls.ps1 -Owner IfeelLikeSnow -Repo ifls-fb01-editor -Version 0.1.11

#>

param(
  [Parameter(Mandatory=$true)][string]$Owner,
  [Parameter(Mandatory=$true)][string]$Repo,
  [Parameter(Mandatory=$true)][string]$Version,
  [string]$Branch = "main",
  [string]$Category = "Editors",
  [string]$PackageName = "IFLS FB-01 Editor"
)

$ErrorActionPreference = "Stop"

function UrlEscape([string]$s){
  # Escape only what GitHub raw needs for file paths
  return ($s -replace " ", "%20")
}

$repoRoot = (Resolve-Path ".").Path

# --- locate scripts root inside repo ---
$scriptsRoot = Join-Path $repoRoot "reaper\Scripts\IFLS_FB01_Editor"
if(!(Test-Path $scriptsRoot)){
  throw "Repo scripts root not found: $scriptsRoot"
}

# --- locate MenuSets roots ---
$menuRoots = @()
$mr1 = Join-Path $repoRoot "MenuSets"
$mr2 = Join-Path $repoRoot "reaper\MenuSets"
if(Test-Path $mr1){ $menuRoots += $mr1 }
if(Test-Path $mr2){ $menuRoots += $mr2 }

# --- locate FX roots ---
$fxRoots = @()
$fr1 = Join-Path $repoRoot "reaper\Effects\IFLS"
$fr2 = Join-Path $repoRoot "reaper\Effects"
if(Test-Path $fr1){ $fxRoots += $fr1 }
if(Test-Path $fr2){ $fxRoots += $fr2 }

# collect files
$scriptFiles = Get-ChildItem -Path $scriptsRoot -Recurse -File | Where-Object { $_.Name -ne ".DS_Store" }
$menuFiles = @()
foreach($mr in $menuRoots){ $menuFiles += Get-ChildItem -Path $mr -Recurse -File -Filter *.ReaperMenu }
$fxFiles = @()
foreach($fr in $fxRoots){ $fxFiles += Get-ChildItem -Path $fr -Recurse -File | Where-Object { $_.Extension -ieq ".jsfx" } }

# write XML
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sb.AppendLine(('<index version="1" name="{0}">' -f $PackageName))
[void]$sb.AppendLine(('  <category name="{0}">' -f $Category))
[void]$sb.AppendLine(('    <reapack name="{0}" type="script" desc="Yamaha FB-01 editor &amp; librarian for REAPER.">' -f $PackageName))
[void]$sb.AppendLine(('      <version name="{0}" time="{1}">' -f $Version, $now))

# helper to compute raw URL
function RawUrl([string]$repoRel){
  return "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/" + (UrlEscape($repoRel.Replace('\','/')))
}

# scripts: install to Scripts/<package>/... (escape out of category folder)
foreach($f in $scriptFiles){
  $relRepo = $f.FullName.Substring($repoRoot.Length+1)     # e.g. reaper\Scripts\IFLS_FB01_Editor\Editor\X.lua
  $relInScriptsRoot = $f.FullName.Substring($scriptsRoot.Length+1).Replace('\','/')  # e.g. Editor/X.lua

  $url = RawUrl $relRepo

  # IMPORTANT: file="../<rel>" -> goes from Scripts/<pkg>/<Category>/.. to Scripts/<pkg>/
  $install = "../" + $relInScriptsRoot

  # mark key entrypoints as actions
  $mainAttr = ""
  $isEntry = $false
  if($relInScriptsRoot -ieq "Editor/IFLS_FB01_SoundEditor.lua"){ $isEntry = $true }
  if($relInScriptsRoot -ieq "IFLS_FB01_Register_Actions.lua"){ $isEntry = $true }
  if($relInScriptsRoot.StartsWith("Actions/")){ $isEntry = $true }
  if($isEntry -and $f.Extension -ieq ".lua"){ $mainAttr = ' main="main"' }

  [void]$sb.AppendLine(('        <source file="{0}"{1}>{2}</source>' -f $install, $mainAttr, $url))
}

# MenuSets: install to REAPER_RESOURCE\MenuSets (escape all the way to resource root)
foreach($m in $menuFiles){
  $relRepo = $m.FullName.Substring($repoRoot.Length+1)
  $url = RawUrl $relRepo
  # from Scripts/<pkg>/<Category>/ to resource root: ../../.. then MenuSets
  $install = "../../../MenuSets/" + $m.Name
  [void]$sb.AppendLine(('        <source file="{0}" type="data">{1}</source>' -f $install, $url))
}

# FX: install to REAPER_RESOURCE\Effects\IFLS
foreach($fx in $fxFiles){
  $relRepo = $fx.FullName.Substring($repoRoot.Length+1)
  $url = RawUrl $relRepo
  $install = "../../../Effects/IFLS/" + $fx.Name
  [void]$sb.AppendLine(('        <source file="{0}" type="effect">{1}</source>' -f $install, $url))
}

[void]$sb.AppendLine('      </version>')
[void]$sb.AppendLine('    </reapack>')
[void]$sb.AppendLine('  </category>')
[void]$sb.AppendLine('</index>')

# write UTF-8 without BOM
$xmlPath = Join-Path $repoRoot "index.xml"
[System.IO.File]::WriteAllText($xmlPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Wrote index.xml -> $xmlPath"
Write-Host ("Scripts listed : {0}" -f $scriptFiles.Count)
Write-Host ("MenuSets listed: {0}" -f $menuFiles.Count)
Write-Host ("JSFX listed    : {0}" -f $fxFiles.Count)

# quick sanity checks
$txt = Get-Content $xmlPath -Raw
if([regex]::Matches($txt,'<source\b[^>]*/>').Count -ne 0){ throw "index.xml has self-closing <source/> (empty URL)!" }
if($txt -notmatch '<index'){ throw "index.xml missing <index> tag" }
