<#
.SYNOPSIS
  Empties the Recycle Bin for all drives. Note: this marks the space reusable;
  it does not overwrite the bytes.
.NOTES
  part of privacy-sweep (Windows). Modes: -DryRun (show only), (default) ask
  first, -Yes (no prompt).
#>
param([switch]$DryRun, [switch]$Yes)
$ErrorActionPreference = 'SilentlyContinue'

function Confirm-Proceed { if ($Yes) { return $true } ; return ((Read-Host "Proceed? [y/N]") -match '^[Yy]$') }

Write-Host "== Recycle Bin =="
Write-Host "Target: the Recycle Bin on all drives."

if ($DryRun) { Write-Host "(dry run) Would empty the Recycle Bin (Clear-RecycleBin -Force)."; return }
if (-not (Confirm-Proceed)) { Write-Host "Cancelled."; return }

Clear-RecycleBin -Force -ErrorAction SilentlyContinue
Write-Host "Done. Recycle Bin emptied."
