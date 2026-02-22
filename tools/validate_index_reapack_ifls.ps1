param([Parameter(Mandatory=$true)][string]$IndexPath)
$ErrorActionPreference="Stop"
if(!(Test-Path $IndexPath)){ throw "Index not found: $IndexPath" }
$txt = Get-Content $IndexPath -Raw
if($txt -notmatch "<index"){ throw "index.xml is not XML (missing <index>)" }
if([regex]::Matches($txt,'<source\b[^>]*/>').Count -ne 0){ throw "index.xml contains self-closing <source/> (empty URL)" }
if($txt -notmatch "<source"){ throw "index.xml has no <source> entries" }
if($txt -notmatch "https://"){ throw "index.xml has no URLs inside <source> tags" }
Write-Host "OK: index.xml looks valid for ReaPack"
