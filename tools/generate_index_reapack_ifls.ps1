param(
  [Parameter(Mandatory=$true)][string]$Owner,
  [Parameter(Mandatory=$true)][string]$Repo,
  [Parameter(Mandatory=$true)][string]$Version,
  [string]$Branch = "main",
  [string]$Category = "Editors",
  [string]$PackageName = "IFLS FB-01 Editor"
)

$ErrorActionPreference = "Stop"

function UrlEscape([string]$s){ return ($s -replace " ", "%20") }

$repoRoot = (Resolve-Path ".").Path
$scriptsRoot = Join-Path $repoRoot "reaper\Scripts\IFLS_FB01_Editor"
if(!(Test-Path $scriptsRoot)){ throw "Repo scripts root not found: $scriptsRoot" }

$menuRoots = @()
$mr1 = Join-Path $repoRoot "MenuSets"
$mr2 = Join-Path $repoRoot "reaper\MenuSets"
if(Test-Path $mr1){ $menuRoots += $mr1 }
if(Test-Path $mr2){ $menuRoots += $mr2 }

$fxRoots = @()
$fr1 = Join-Path $repoRoot "reaper\Effects\IFLS"
$fr2 = Join-Path $repoRoot "reaper\Effects"
if(Test-Path $fr1){ $fxRoots += $fr1 }
if(Test-Path $fr2){ $fxRoots += $fr2 }

$scriptFiles = Get-ChildItem -Path $scriptsRoot -Recurse -File | Where-Object { $_.Name -ne ".DS_Store" }
$menuFiles = @()
foreach($mr in $menuRoots){ $menuFiles += Get-ChildItem -Path $mr -Recurse -File -Filter *.ReaperMenu }
$fxFiles = @()
foreach($fr in $fxRoots){ $fxFiles += Get-ChildItem -Path $fr -Recurse -File | Where-Object { $_.Extension -ieq ".jsfx" } }

function RawUrl([string]$repoRel){
  $p = $repoRel.Replace('\','/')
  return "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/" + (UrlEscape($p))
}

$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sb.AppendLine(('<index version="1" name="{0}">' -f $PackageName))
[void]$sb.AppendLine(('  <category name="{0}">' -f $Category))
[void]$sb.AppendLine(('    <reapack name="{0}" type="script" desc="Yamaha FB-01 editor &amp; librarian for REAPER.">' -f $PackageName))
[void]$sb.AppendLine(('      <version name="{0}" time="{1}">' -f $Version, $now))

# Scripts: Category erzeugt Unterordner -> ../ escaped raus -> Installation wird flach
foreach($f in $scriptFiles){
  $relRepo  = $f.FullName.Substring($repoRoot.Length+1)
  $relInPkg = $f.FullName.Substring($scriptsRoot.Length+1).Replace('\','/')
  $url = RawUrl $relRepo
  $install = "../" + $relInPkg

  $mainAttr = ""
  if($relInPkg -ieq "Editor/IFLS_FB01_SoundEditor.lua" -or
     $relInPkg -ieq "IFLS_FB01_Register_Actions.lua" -or
     $relInPkg.StartsWith("Actions/")){
    if($f.Extension -ieq ".lua"){ $mainAttr = ' main="main"' }
  }

  [void]$sb.AppendLine(('        <source file="{0}"{1}>{2}</source>' -f $install, $mainAttr, $url))
}

# MenuSets: direkt nach REAPER\MenuSets
foreach($m in $menuFiles){
  $relRepo = $m.FullName.Substring($repoRoot.Length+1)
  $url = RawUrl $relRepo
  $install = "../../../MenuSets/" + $m.Name
  [void]$sb.AppendLine(('        <source file="{0}" type="data">{1}</source>' -f $install, $url))
}

# Effects: nach REAPER\Effects\IFLS
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

$xmlPath = Join-Path $repoRoot "index.xml"
[System.IO.File]::WriteAllText($xmlPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote: $xmlPath"
