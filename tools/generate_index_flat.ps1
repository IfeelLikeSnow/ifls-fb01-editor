param(
  [Parameter(Mandatory=$true)][string]$Owner,
  [Parameter(Mandatory=$true)][string]$Repo,
  [string]$Branch = "main",
  [Parameter(Mandatory=$true)][string]$Version,
  [string]$CategoryName = "Editors",
  [string]$RepoDisplayName = "IFLS FB-01 Editor",
  [string]$Desc = "Yamaha FB-01 editor & librarian for REAPER (ReaImGui).",
  [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  param([string]$Provided)
  if (-not [string]::IsNullOrWhiteSpace($Provided)) {
    return (Resolve-Path $Provided).Path
  }
  # Avoid $PSScriptRoot in param defaults (can be empty in Windows PowerShell)
  $scriptPath = $PSCommandPath
  if ([string]::IsNullOrWhiteSpace($scriptPath)) {
    # fallback
    return (Resolve-Path ".").Path
  }
  $scriptDir = Split-Path -Parent $scriptPath
  return (Resolve-Path (Join-Path $scriptDir "..")).Path
}

function Escape-Xml([string]$s) {
  if ($null -eq $s) { return "" }
  return $s.Replace("&","&amp;").Replace("<","&lt;").Replace(">","&gt;").Replace('"',"&quot;").Replace("'","&apos;")
}

function Encode-PathForUrl([string]$p) {
  # p uses / separators
  $parts = $p -split '/'
  $enc = $parts | ForEach-Object { [System.Uri]::EscapeDataString($_) }
  return ($enc -join '/')
}

$RepoRoot = Get-RepoRoot -Provided $RepoRoot

$reaperDir = Join-Path $RepoRoot "reaper"
if (!(Test-Path $reaperDir)) { throw "Expected folder not found: $reaperDir" }

# Find the "inner root" containing Editor/Actions etc by locating IFLS_FB01_SoundEditor.lua
$editorFile = Get-ChildItem -Path $reaperDir -Recurse -File -Filter "IFLS_FB01_SoundEditor.lua" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $editorFile) {
  # fallback: common path
  $fallback = Join-Path $reaperDir "Scripts\IFLS FB-01 Editor"
  if (Test-Path $fallback) {
    $scriptRoot = (Resolve-Path $fallback).Path
  } else {
    throw "Could not locate IFLS_FB01_SoundEditor.lua under '$reaperDir'. Cannot determine script root."
  }
} else {
  # Editor file is typically ...\<Root>\Editor\IFLS_FB01_SoundEditor.lua
  $scriptRoot = $editorFile.Directory.Parent.FullName
}

if (!(Test-Path $scriptRoot)) { throw "Script root not found: $scriptRoot" }

# Collect script/data files from scriptRoot
$scriptFiles = Get-ChildItem -Path $scriptRoot -Recurse -File | Where-Object { $_.Name -notmatch '^\.' }

# Collect MenuSets (any .ReaperMenu under reaper/)
$menuFiles = Get-ChildItem -Path $reaperDir -Recurse -File -Filter "*.ReaperMenu" -ErrorAction SilentlyContinue

# Collect JSFX under reaper/Effects (optional)
$fxFiles = Get-ChildItem -Path (Join-Path $reaperDir "Effects") -Recurse -File -Filter "*.jsfx" -ErrorAction SilentlyContinue

$time = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Build XML
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('<?xml version="1.0" encoding="UTF-8"?>')
$lines.Add('<index version="1" generated-by="generate_index_flat.ps1" name="' + (Escape-Xml $RepoDisplayName) + '">')
$lines.Add('  <category name="' + (Escape-Xml $CategoryName) + '">')
$lines.Add('    <reapack name="' + (Escape-Xml $RepoDisplayName) + '" type="script" desc="' + (Escape-Xml $Desc) + '">')
$lines.Add('      <version name="' + (Escape-Xml $Version) + '" time="' + $time + '">')

function Add-Source {
  param(
    [string]$TargetFile,
    [string]$RelPathFromRepoRoot,
    [string]$Type
  )
  $relUrlPath = ($RelPathFromRepoRoot -replace '\\','/')
  $relUrlPath = Encode-PathForUrl $relUrlPath
  $url = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/$relUrlPath"
  $lines.Add('        <source file="' + (Escape-Xml $TargetFile) + '" platform="all" type="' + (Escape-Xml $Type) + '">' + (Escape-Xml $url) + '</source>')
}

# Scripts/data under Scripts/IFLS FB-01 Editor/...
foreach ($f in $scriptFiles) {
  $rel = $f.FullName.Substring($scriptRoot.Length).TrimStart('\','/')
  $target = ("Scripts/IFLS FB-01 Editor/" + ($rel -replace '\\','/'))
  $repoRel = (Resolve-Path $f.FullName).Path.Substring($RepoRoot.Length).TrimStart('\','/')
  $ext = $f.Extension.ToLowerInvariant()
  $type = if ($ext -in @(".lua",".eel",".py")) { "script" } else { "data" }
  Add-Source -TargetFile $target -RelPathFromRepoRoot $repoRel -Type $type
}

# MenuSets -> MenuSets/<filename>
foreach ($f in $menuFiles) {
  $target = ("MenuSets/" + $f.Name)
  $repoRel = (Resolve-Path $f.FullName).Path.Substring($RepoRoot.Length).TrimStart('\','/')
  Add-Source -TargetFile $target -RelPathFromRepoRoot $repoRel -Type "data"
}

# Effects -> Effects/IFLS/<...>
foreach ($f in $fxFiles) {
  # preserve subpath below Effects\
  $effectsRoot = (Resolve-Path (Join-Path $reaperDir "Effects")).Path
  $rel = $f.FullName.Substring($effectsRoot.Length).TrimStart('\','/')
  $target = ("Effects/" + ($rel -replace '\\','/'))
  $repoRel = (Resolve-Path $f.FullName).Path.Substring($RepoRoot.Length).TrimStart('\','/')
  Add-Source -TargetFile $target -RelPathFromRepoRoot $repoRel -Type "effect"
}

$lines.Add('      </version>')
$lines.Add('    </reapack>')
$lines.Add('  </category>')
$lines.Add('</index>')

$indexPath = Join-Path $RepoRoot "index.xml"
[System.IO.File]::WriteAllLines($indexPath, $lines, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Wrote index.xml -> $indexPath"
Write-Host "Script root: $scriptRoot"
Write-Host ("Sources: {0} scripts/data, {1} menusets, {2} effects" -f $scriptFiles.Count, $menuFiles.Count, $fxFiles.Count)
