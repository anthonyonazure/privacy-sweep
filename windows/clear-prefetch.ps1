<#
.SYNOPSIS
  Clears the Prefetch folder (C:\Windows\Prefetch\*.pf). Windows keeps one file
  per program holding its last launch times and total run count.
.NOTES
  part of privacy-sweep (Windows). REQUIRES an elevated (Administrator) terminal.
  Modes: -DryRun (show only), (default) ask first, -Yes (no prompt).
  Prefetch makes apps start faster; Windows rebuilds it over the next few launches.
#>
param([switch]$DryRun, [switch]$Yes)
$ErrorActionPreference = 'SilentlyContinue'

function Confirm-Proceed { if ($Yes) { return $true } ; return ((Read-Host "Proceed? [y/N]") -match '^[Yy]$') }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Warning "Prefetch needs Administrator. Right-click Terminal > Run as administrator, then re-run."; return }

$dir = Join-Path $env:WINDIR 'Prefetch'
Write-Host "== Prefetch (program run history) =="
$files = Get-ChildItem -Path $dir -Filter '*.pf' -File 2>$null
if (-not $files) { Write-Host "No .pf files found. Nothing to do."; return }
Write-Host ("Target: {0}   Files: {1}" -f $dir, $files.Count)

if ($DryRun) { Write-Host "(dry run) Would delete $($files.Count) .pf files."; return }
if (-not (Confirm-Proceed)) { Write-Host "Cancelled."; return }

$files | Remove-Item -Force 2>$null
Write-Host "Done. Prefetch cleared."
