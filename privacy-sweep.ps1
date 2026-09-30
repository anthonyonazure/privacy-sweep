<#
.SYNOPSIS
  Top-level launcher for Windows. Runs the full Windows sweep.
.NOTES
  Flags pass straight through, matching the per-OS runner:
    .\privacy-sweep.ps1 -DryRun   # show what would be cleared, delete nothing
    .\privacy-sweep.ps1           # ask before each step
    .\privacy-sweep.ps1 -Yes      # clear everything, no prompts
  Run in an elevated (Administrator) terminal so the Prefetch and system-temp
  steps work. This script exists so Windows users get the same one-command entry
  point that macOS and Linux get from privacy-sweep.sh.
#>
param([switch]$DryRun, [switch]$Yes)

Write-Host "Detected: Windows"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $dir 'windows\clear-all.ps1') -DryRun:$DryRun -Yes:$Yes
