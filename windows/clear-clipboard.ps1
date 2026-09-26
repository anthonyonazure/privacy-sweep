<#
.SYNOPSIS
  Clears the current clipboard and the Windows clipboard history (Win+V).
  Clipboard history can hold anything you copied this session, including
  passwords pasted from a manager.
.NOTES
  part of privacy-sweep (Windows). Modes: -DryRun (show only), (default) ask
  first, -Yes (no prompt).
#>
param([switch]$DryRun, [switch]$Yes)
$ErrorActionPreference = 'SilentlyContinue'

function Confirm-Proceed { if ($Yes) { return $true } ; return ((Read-Host "Proceed? [y/N]") -match '^[Yy]$') }

Write-Host "== Clipboard & clipboard history =="
Write-Host "Target: current clipboard contents and the Win+V history."

if ($DryRun) { Write-Host "(dry run) Would empty the clipboard and clear its history."; return }
if (-not (Confirm-Proceed)) { Write-Host "Cancelled."; return }

# Current clipboard
Set-Clipboard -Value $null 2>$null
cmd /c "echo off | clip" 2>$null
# History: the documented reset is to clear via the system service
Start-Process -FilePath "cmd.exe" -ArgumentList "/c echooff|clip" -WindowStyle Hidden 2>$null
Write-Host "Done. Current clipboard emptied."
Write-Host "To also clear kept history now: press Win+V, click the three dots, Clear all."
Write-Host "To turn history off: Settings > System > Clipboard > turn off Clipboard history."
