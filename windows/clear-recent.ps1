<#
.SYNOPSIS
  Clears the Recent Items list and Jump Lists (the recent files that appear when
  you right-click a taskbar app). Lives in %APPDATA%\Microsoft\Windows\Recent.
.NOTES
  part of privacy-sweep (Windows). Modes: -DryRun (show only), (default) ask
  first, -Yes (no prompt).
#>
param([switch]$DryRun, [switch]$Yes)
$ErrorActionPreference = 'SilentlyContinue'

function Confirm-Proceed { if ($Yes) { return $true } ; return ((Read-Host "Proceed? [y/N]") -match '^[Yy]$') }

$recent = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
Write-Host "== Recent files & Jump Lists =="
Write-Host "Target: $recent (including AutomaticDestinations and CustomDestinations)"

$items = Get-ChildItem -Path $recent -Recurse -File 2>$null
if (-not $items) { Write-Host "No recent items found. Nothing to do."; return }
Write-Host ("Items: {0}" -f $items.Count)

if ($DryRun) { Write-Host "(dry run) Would delete $($items.Count) recent-item and jump-list files."; return }
if (-not (Confirm-Proceed)) { Write-Host "Cancelled."; return }

$items | Remove-Item -Force 2>$null
Write-Host "Done. Recent files and Jump Lists cleared."
Write-Host "To stop new ones: Settings > Personalization > Start > turn off 'Show recently opened items'."
