param(
  [Parameter(Mandatory=$true)][string]$Owner,
  [Parameter(Mandatory=$true)][string]$Repo,
  [Parameter(Mandatory=$false)][string]$Branch = "main",
  [Parameter(Mandatory=$true)][string]$Version,
  [Parameter(Mandatory=$false)][string]$IndexName = "IFLS FB-01 Editor",
  [Parameter(Mandatory=$false)][string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,

  # Source roots inside repo (relative to RepoRoot)
  [Parameter(Mandatory=$false)][string]$ScriptsRootRel = "reaper/Scripts/IFLS_FB01_Editor",
  [Parameter(Mandatory=$false)][string]$EffectsRootRel = "reaper/Effects/IFLS",
  [Parameter(Mandatory=$false)][string]$MenuSetsRootRel = "MenuSets",

  # Destination roots inside REAPER resource path
  [Parameter(Mandatory=$false)][string]$DestScriptsRoot = "Scripts/IFLS FB-01 Editor",
  [Parameter(Mandatory=$false)][string]$DestEffectsRoot = "Effects/IFLS",

  # Optional: also copy JSFX into Scripts tree (so users find it alongside docs)
  [switch]$AlsoCopyEffectsIntoScripts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function IsoNowUtcSeconds() {
  return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function UrlEncodePath([string]$p) {
  $p = $p -replace "\\","/"
  $segments = $p -split "/"
  ($segments | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join "/"
}

function GetFiles([string]$absRoot) {
  if (!(Test-Path $absRoot)) { return @() }
  Get-ChildItem -Path $absRoot -Recurse -File | Where-Object {
    $_.FullName -notmatch "\\__MACOSX\\" -and
    $_.Name -ne ".DS_Store" -and
    $_.Name -notmatch "^\\._"
  }
}

function GuessType([string]$path) {
  $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
  if ($ext -in @(".lua",".eel",".py")) { return "script" }
  if ($ext -in @(".jsfx",".jsfx-inc")) { return "effect" }
  if ($ext -in @(".reapermenu")) { return "data" }
  if ($ext -in @(".rtracktemplate")) { return "data" }
  return "data"
}

$repoRootAbs = (Resolve-Path $RepoRoot).Path
$scriptsRootAbs = Join-Path $repoRootAbs ($ScriptsRootRel -replace "/","\" )
$effectsRootAbs = Join-Path $repoRootAbs ($EffectsRootRel -replace "/","\" )
$menuSetsRootAbs = Join-Path $repoRootAbs ($MenuSetsRootRel -replace "/","\" )

if (!(Test-Path $scriptsRootAbs)) { throw "Missing scripts root: $scriptsRootAbs (set -ScriptsRootRel accordingly)" }

$scriptFiles = GetFiles $scriptsRootAbs
$effectFiles = GetFiles $effectsRootAbs
$menuFiles   = GetFiles $menuSetsRootAbs

$time = IsoNowUtcSeconds
$indexPath = Join-Path $repoRootAbs "index.xml"

# XML writer (UTF-8 no BOM)
$settings = New-Object System.Xml.XmlWriterSettings
$settings.Indent = $true
$settings.Encoding = New-Object System.Text.UTF8Encoding($false)
$writer = [System.Xml.XmlWriter]::Create($indexPath, $settings)

$writer.WriteStartDocument()
$writer.WriteStartElement("index")
$writer.WriteAttributeString("version","1")
$writer.WriteAttributeString("name",$IndexName)
$writer.WriteAttributeString("generated-by","ifls index generator (flat paths)")

# Single category + single multi-file package
$writer.WriteStartElement("category")
$writer.WriteAttributeString("name","Editors")

$writer.WriteStartElement("reapack")
$writer.WriteAttributeString("name","IFLS FB-01 Editor")
$writer.WriteAttributeString("type","script")
$writer.WriteAttributeString("desc","Yamaha FB-01 editor & librarian for REAPER (ReaImGui).")

$writer.WriteStartElement("version")
$writer.WriteAttributeString("name",$Version)
$writer.WriteAttributeString("time",$time)

function WriteSource([string]$destFile, [string]$type, [string]$repoRelPath, [bool]$isMain=$false) {
  $repoRelPath = $repoRelPath -replace "\\","/"
  $url = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/" + (UrlEncodePath $repoRelPath)
  $writer.WriteStartElement("source")
  $writer.WriteAttributeString("file",$destFile)
  $writer.WriteAttributeString("platform","all")
  $writer.WriteAttributeString("type",$type)
  if ($isMain) { $writer.WriteAttributeString("main","main") }
  $writer.WriteString($url)
  $writer.WriteEndElement()
}

# Scripts -> Scripts/IFLS FB-01 Editor/<same tree>
foreach ($f in $scriptFiles) {
  $rel = $f.FullName.Substring($scriptsRootAbs.Length).TrimStart("\","/")
  $relSlash = $rel -replace "\\","/"
  $dest = "$DestScriptsRoot/$relSlash"
  $repoRel = "$ScriptsRootRel/$relSlash"
  $type = GuessType $f.Name

  # Mark a few scripts as "main" so they can appear as actions after restart (optional)
  $isMain = $false
  if ($type -eq "script") {
    if ($relSlash -match '^Actions/' -or $relSlash -match '^Editor/IFLS_FB01_SoundEditor\.lua$' -or $relSlash -match '^IFLS_FB01_Register_Actions\.lua$') {
      $isMain = $true
    }
  }
  WriteSource -destFile $dest -type $type -repoRelPath $repoRel -isMain:$isMain
}

# Effects -> Effects/IFLS/<...>
foreach ($f in $effectFiles) {
  $rel = $f.FullName.Substring($effectsRootAbs.Length).TrimStart("\","/")
  $relSlash = $rel -replace "\\","/"
  $dest = "$DestEffectsRoot/$relSlash"
  $repoRel = "$EffectsRootRel/$relSlash"
  $type = GuessType $f.Name
  WriteSource -destFile $dest -type $type -repoRelPath $repoRel -isMain:$false

  if ($AlsoCopyEffectsIntoScripts) {
    $dest2 = "$DestScriptsRoot/Editors/Effects/IFLS/$relSlash"
    WriteSource -destFile $dest2 -type $type -repoRelPath $repoRel -isMain:$false
  }
}

# MenuSets -> MenuSets/<...> (RESOURCE ROOT)
foreach ($f in $menuFiles) {
  $rel = $f.FullName.Substring($menuSetsRootAbs.Length).TrimStart("\","/")
  $relSlash = $rel -replace "\\","/"
  $dest = "MenuSets/$relSlash"
  $repoRel = "$MenuSetsRootRel/$relSlash"
  WriteSource -destFile $dest -type "data" -repoRelPath $repoRel -isMain:$false
}

$writer.WriteEndElement() # version
$writer.WriteEndElement() # reapack
$writer.WriteEndElement() # category
$writer.WriteEndElement() # index
$writer.WriteEndDocument()
$writer.Flush()
$writer.Close()

Write-Host "Wrote index.xml: $indexPath"
Write-Host "Scripts: $($scriptFiles.Count)  Effects: $($effectFiles.Count)  MenuSets: $($menuFiles.Count)"
