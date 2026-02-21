param(
  [Parameter(Mandatory=$true)][string]$Owner,
  [Parameter(Mandatory=$true)][string]$Repo,
  [Parameter(Mandatory=$false)][string]$Branch = "main",
  [Parameter(Mandatory=$true)][string]$Version,
  [Parameter(Mandatory=$false)][string]$IndexName = "IFLS FB-01 Editor"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function IsoNowUtc() {
  # seconds resolution (ReaPack-friendly)
  return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function UrlEncodePath([string]$p) {
  # GitHub raw URLs allow spaces if encoded; ensure each segment is encoded
  $segments = $p -split "/"
  $enc = $segments | ForEach-Object { [System.Uri]::EscapeDataString($_) }
  return ($enc -join "/")
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# Expected source roots (in your repo)
$scriptsRoot = Join-Path $repoRoot "reaper\Scripts\IFLS_FB01_Editor"
$effectsRoot = Join-Path $repoRoot "reaper\Effects\IFLS"
$menuSetsRoot = Join-Path $repoRoot "MenuSets"

if (!(Test-Path $scriptsRoot)) { throw "Missing scripts root: $scriptsRoot" }

$time = IsoNowUtc

# Collect files (exclude macOS junk)
function GetFiles([string]$root) {
  if (!(Test-Path $root)) { return @() }
  return Get-ChildItem -Path $root -Recurse -File |
    Where-Object {
      $_.FullName -notmatch "\\__MACOSX\\"
      -and $_.Name -ne ".DS_Store"
      -and $_.Name -notmatch "^\\._"
    }
}

$scriptFiles = GetFiles $scriptsRoot
$effectFiles = GetFiles $effectsRoot
$menuFiles   = GetFiles $menuSetsRoot

# Build XML
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sb.AppendLine("<index version=""1"" name=""$IndexName"" generated-by=""ifls generate_index_flat.ps1"">")
[void]$sb.AppendLine('  <category name="Editors">')
[void]$sb.AppendLine('    <reapack name="IFLS FB-01 Editor" type="script" desc="Yamaha FB-01 editor &amp; librarian for REAPER (ReaImGui).">')
[void]$sb.AppendLine("      <version name=""$Version"" time=""$time"">")

function AddSource([string]$destFile, [string]$type, [string]$repoRelPath) {
  # repoRelPath uses forward slashes relative to repo root
  $repoRelPath = $repoRelPath -replace "\\", "/"
  $repoRelPathEnc = UrlEncodePath $repoRelPath

  $url = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/$repoRelPathEnc"

  # ReaPack index uses the URL as the element text content (must not be empty)
  $destFileXml = $destFile.Replace("&","&amp;").Replace("<","&lt;").Replace(">","&gt;").Replace('"',"&quot;")
  $urlXml = $url.Replace("&","&amp;").Replace("<","&lt;").Replace(">","&gt;")

  [void]$sb.AppendLine("        <source file=""$destFileXml"" platform=""all"" type=""$type"">$urlXml</source>")
}

# Scripts: install flat under Scripts/IFLS FB-01 Editor/<relative>
foreach ($f in $scriptFiles) {
  $rel = $f.FullName.Substring($scriptsRoot.Length).TrimStart("\","/")
  $relSlash = $rel -replace "\\", "/"
  $dest = "Scripts/IFLS FB-01 Editor/$relSlash"

  $ext = $f.Extension.ToLowerInvariant()
  $type = if ($ext -in @(".lua",".eel",".py")) { "script" } elseif ($ext -in @(".jsfx",".jsfx-inc")) { "effect" } else { "data" }

  $repoRel = "reaper/Scripts/IFLS_FB01_Editor/$relSlash"
  AddSource -destFile $dest -type $type -repoRelPath $repoRel
}

# Effects: install to Effects/IFLS/<relative> (standard)
foreach ($f in $effectFiles) {
  $rel = $f.FullName.Substring($effectsRoot.Length).TrimStart("\","/")
  $relSlash = $rel -replace "\\", "/"
  $dest = "Effects/IFLS/$relSlash"

  $ext = $f.Extension.ToLowerInvariant()
  $type = if ($ext -in @(".jsfx",".jsfx-inc")) { "effect" } else { "data" }

  $repoRel = "reaper/Effects/IFLS/$relSlash"
  AddSource -destFile $dest -type $type -repoRelPath $repoRel

  # Optional extra copy inside Scripts tree (requested by some users):
  # Scripts/IFLS FB-01 Editor/Editors/Effects/IFLS/<name>
  $dest2 = "Scripts/IFLS FB-01 Editor/Editors/Effects/IFLS/$relSlash"
  AddSource -destFile $dest2 -type $type -repoRelPath $repoRel
}

# MenuSets: install to MenuSets/<file>
foreach ($f in $menuFiles) {
  $name = $f.Name
  $dest = "MenuSets/$name"
  $repoRel = "MenuSets/$name"
  AddSource -destFile $dest -type "data" -repoRelPath $repoRel
}

[void]$sb.AppendLine("      </version>")
[void]$sb.AppendLine("    </reapack>")
[void]$sb.AppendLine("  </category>")
[void]$sb.AppendLine("</index>")

# Write index.xml to repo root (UTF-8 no BOM)
$indexPath = Join-Path $repoRoot "index.xml"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($indexPath, $sb.ToString(), $utf8NoBom)

Write-Host "Wrote index.xml: $indexPath"
Write-Host "Scripts: $($scriptFiles.Count), Effects: $($effectFiles.Count), MenuSets: $($menuFiles.Count)"
