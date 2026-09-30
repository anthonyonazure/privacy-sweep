<#
.SYNOPSIS
  Runs every clear-*.ps1 script in this folder, passing your flags to each.
.NOTES
  part of privacy-sweep (Windows). Modes: -DryRun (show only, run this first),
  (default) ask per step, -Yes (no prompts). Run in an elevated terminal so the
  Prefetch and system-temp steps work.
#>
param([switch]$DryRun, [switch]$Yes)

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$order = @('clear-thumbnails.ps1','clear-prefetch.ps1','clear-recent.ps1','clear-temp.ps1','clear-recyclebin.ps1','clear-clipboard.ps1')

Write-Host "#############################################"
Write-Host "# privacy-sweep - Windows - full run"
Write-Host "#############################################`n"

foreach ($s in $order) {
  $p = Join-Path $dir $s
  if (Test-Path $p) {
    Write-Host "----- $s -----"
    & $p -DryRun:$DryRun -Yes:$Yes
    Write-Host ""
  }
}

Write-Host "All Windows steps finished."
Write-Host "Reminder: the durable fix is BitLocker (Settings > Privacy & security > Device encryption)."
