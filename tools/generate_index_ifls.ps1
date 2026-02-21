<#
.SYNOPSIS
  Generate a valid ReaPack index.xml for IFLS FB-01 Editor.

.DESCRIPTION
  Keeps the ReaPack package category (default: "Editors") for browsing,
  but installs scripts flat to:  REAPER_RESOURCE/Scripts/IFLS FB-01 Editor/...
  by using file="../IFLS FB-01 Editor/<rel>"

  Script sources are read from:
    <RepoRoot>\reaper\Scripts\IFLS_FB01_Editor

  Optional assets:
    <RepoRoot>\reaper\Effects\IFLS\*.jsfx        -> REAPER_RESOURCE/Effects/IFLS/
    <RepoRoot>\MenuSets\*.ReaperMenu OR
    <RepoRoot>\reaper\MenuSets\*.ReaperMenu     -> REAPER_RESOURCE/MenuSets/

  NOTE: Do NOT paste this into the console line-by-line.
        Save as tools\generate_index_ifls.ps1 and run with -File.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Owner,
  [Parameter(Mandatory=$true)][string]$Repo,
  [string]$Branch = "main",
  [Parameter(Mandatory=$true)][string]$Version,
  [string]$Category = "Editors",
  [string]$InstallRoot = "IFLS FB-01 Editor",
  [string]$RepoRoot = ""
)

# Resolve repo root robustly (Windows PowerShell-safe)
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path ".").Path
} else {
  $RepoRoot = (Resolve-Path $RepoRoot).Path
}

function EscapePath([string]$path) {
  # Encode each segment, keep slashes
  $segs = $path -split '/'
  return ($segs | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join '/'
}

$scriptRoot = Join-Path $RepoRoot "reaper\Scripts\IFLS_FB01_Editor"
if (!(Test-Path $scriptRoot)) {
  throw "Script root not found: $scriptRoot`nRun from repo root or pass -RepoRoot <path>."
}

# Optional roots
$fxRoot = Join-Path $RepoRoot "reaper\Effects\IFLS"
$menuRootA = Join-Path $RepoRoot "MenuSets"
$menuRootB = Join-Path $RepoRoot "reaper\MenuSets"

$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sb.AppendLine("<index version=`"1`" name=`"IFLS FB-01 Editor`">")
[void]$sb.AppendLine("  <category name=`"$Category`">")
[void]$sb.AppendLine("    <reapack name=`"IFLS FB-01 Editor`" type=`"script`" desc=`"Yamaha FB-01 editor &amp; librarian for REAPER.`">")
[void]$sb.AppendLine("      <version name=`"$Version`" time=`"$now`">")

# ---- Scripts ----
$files = Get-ChildItem -Path $scriptRoot -Recurse -File |
  Where-Object { $_.Name -notin @(".DS_Store") -and $_.FullName -notmatch "__MACOSX" }

$scriptRootRel = "reaper/Scripts/IFLS_FB01_Editor"

foreach ($f in $files) {
  $rel = $f.FullName.Substring($scriptRoot.Length + 1).Replace('\','/')
  $url = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/" + (EscapePath("$scriptRootRel/$rel"))

  # Install out of Category folder (Scripts/<Category>/..) into Scripts/<InstallRoot>
  $install = "../$InstallRoot/$rel"

  $mainAttr = ""
  if ($f.Extension -ieq ".lua") {
    # Register only "entry" scripts as actions
    if ($rel -like "Actions/*" -or $rel -ieq "IFLS_FB01_Register_Actions.lua" -or $rel -like "Editor/*") {
      $mainAttr = ' main="main"'
    }
  }

  [void]$sb.AppendLine("        <source file=`"$install`"$mainAttr>$url</source>")
}

# ---- JSFX (optional) ----
if (Test-Path $fxRoot) {
  $fxFiles = Get-ChildItem -Path $fxRoot -Recurse -File | Where-Object { $_.Extension -ieq ".jsfx" -or $_.Extension -ieq ".jsfx-inc" -or $_.Extension -ieq ".rpl" }
  foreach ($fx in $fxFiles) {
    $rel = $fx.FullName.Substring($fxRoot.Length + 1).Replace('\','/')
    $url = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/" + (EscapePath("reaper/Effects/IFLS/$rel"))
    # For effect sources, category is applied under Effects/. Escape out into Effects/IFLS
    $install = "../IFLS/$rel"
    [void]$sb.AppendLine("        <source file=`"$install`" type=`"effect`">$url</source>")
  }
}

# ---- MenuSets (optional) ----
$menuRoot = $null
if (Test-Path $menuRootA) { $menuRoot = $menuRootA }
elseif (Test-Path $menuRootB) { $menuRoot = $menuRootB }

if ($menuRoot) {
  $menuFiles = Get-ChildItem -Path $menuRoot -Recurse -File | Where-Object { $_.Extension -ieq ".ReaperMenu" }
  foreach ($m in $menuFiles) {
    $rel = $m.FullName.Substring($menuRoot.Length + 1).Replace('\','/')
    $menuRel = if ($menuRoot -eq $menuRootA) { "MenuSets/$rel" } else { "reaper/MenuSets/$rel" }
    $url = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/" + (EscapePath($menuRel))

    # MenuSets is at REAPER resource root. From Scripts/<Category>/.. need to go up two:
    # Scripts/<Category>/../../MenuSets -> MenuSets
    $install = "../../MenuSets/$rel"
    [void]$sb.AppendLine("        <source file=`"$install`" type=`"data`">$url</source>")
  }
}

[void]$sb.AppendLine("      </version>")
[void]$sb.AppendLine("    </reapack>")
[void]$sb.AppendLine("  </category>")
[void]$sb.AppendLine("</index>")

$indexPath = Join-Path $RepoRoot "index.xml"
[System.IO.File]::WriteAllText($indexPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote: $indexPath"
