<#
.SYNOPSIS
  Clears the PowerShell command history. PSReadLine saves every command you
  type to a plain text file that survives restarts, sometimes with passwords
  typed inline.
.NOTES
  part of privacy-sweep (Windows). Modes: -DryRun (show only), (default) ask
  first, -Yes (no prompt).
#>
param([switch]$DryRun, [switch]$Yes)
$ErrorActionPreference = 'SilentlyContinue'

function Confirm-Proceed { if ($Yes) { return $true } ; return ((Read-Host "Proceed? [y/N]") -match '^[Yy]$') }

Write-Host "== PowerShell command history =="

$paths = @()
$opt = Get-PSReadLineOption
if ($opt -and $opt.HistorySavePath) { $paths += $opt.HistorySavePath }
# Windows PowerShell 5.1 and PowerShell 7 keep separate files in the same folder
if ($env:APPDATA) {
  $dir = Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine'
  if (Test-Path $dir) { $paths += (Get-ChildItem $dir -Filter '*_history.txt').FullName }
}
$paths = @($paths | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)

if ($paths.Count -eq 0) { Write-Host "No history file found. Nothing to do."; return }
foreach ($p in $paths) { Write-Host ("Target: {0} ({1} lines)" -f $p, (Get-Content $p | Measure-Object -Line).Lines) }

if ($DryRun) { Write-Host "(dry run) Would empty the files above."; return }
if (-not (Confirm-Proceed)) { Write-Host "Cancelled."; return }

foreach ($p in $paths) { Clear-Content -Path $p }
Clear-History
Write-Host "Done. History files emptied."
Write-Host "This window's in-memory history persists until you close it."
