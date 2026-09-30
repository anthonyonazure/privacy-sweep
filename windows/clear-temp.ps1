<#
.SYNOPSIS
  Clears your user temp folder (%TEMP%) and, if run as Administrator, the system
  temp folder (C:\Windows\Temp). Programs leave working files here that outlive them.
.NOTES
  part of privacy-sweep (Windows). Modes: -DryRun (show only), (default) ask
  first, -Yes (no prompt). Files in use are skipped automatically.
#>
param([switch]$DryRun, [switch]$Yes)
$ErrorActionPreference = 'SilentlyContinue'

function Confirm-Proceed { if ($Yes) { return $true } ; return ((Read-Host "Proceed? [y/N]") -match '^[Yy]$') }

$targets = @($env:TEMP)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) { $targets += (Join-Path $env:WINDIR 'Temp') }

Write-Host "== Temporary files =="
foreach ($t in $targets) { Write-Host "Target: $t" }
if (-not $isAdmin) { Write-Host "(run as Administrator to also clear C:\Windows\Temp)" }

if ($DryRun) { Write-Host "(dry run) Would delete the contents of the folders above (locked files skipped)."; return }
if (-not (Confirm-Proceed)) { Write-Host "Cancelled."; return }

foreach ($t in $targets) {
  Get-ChildItem -Path $t -Force 2>$null | Remove-Item -Recurse -Force 2>$null
}
Write-Host "Done. Temp folders cleared (files in use were skipped)."
