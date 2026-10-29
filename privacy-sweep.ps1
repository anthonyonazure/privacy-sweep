<#
.SYNOPSIS
  Top-level launcher for Windows. Runs the full Windows sweep.
.NOTES
  Flags pass straight through, matching the per-OS runner:
    .\privacy-sweep.ps1 -DryRun   # show what would be cleared, delete nothing
    .\privacy-sweep.ps1           # ask before each step
    .\privacy-sweep.ps1 -Yes      # clear everything, no prompts
    .\privacy-sweep.ps1 -DryRun -AllModules
      Dry-run every module, including opt-in ones. Deletes nothing.
      -AllModules without -DryRun still forces a dry run.
  Sets $LASTEXITCODE. When this file is the powershell -File target, it also
  exits with that code. An interactive session (for example OpenSSH) is left open.
  Run in an elevated (Administrator) terminal so the Prefetch and system-temp
  steps work.
#>
param(
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$AllModules,
  [switch]$WhatIf
)

function Complete-PrivacySweep {
  param([int]$Code)
  $global:LASTEXITCODE = $Code
  $cmdArgs = [Environment]::GetCommandLineArgs()
  $entry = Split-Path -Leaf $PSCommandPath
  for ($i = 0; $i -lt $cmdArgs.Count; $i++) {
    if (($cmdArgs[$i] -eq '-File' -or $cmdArgs[$i] -eq '-f') -and ($i + 1) -lt $cmdArgs.Count) {
      $leaf = Split-Path -Leaf $cmdArgs[$i + 1]
      if ($leaf -eq $entry) { exit $Code }
    }
  }
}

if ($WhatIf) { $DryRun = $true }
Write-Host "Detected: Windows"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($AllModules) {
  if (-not $DryRun) {
    Write-Host "-AllModules forces a dry run. Nothing will be deleted."
    $DryRun = $true
  }
  . (Join-Path $dir 'lib\all-modules.ps1')
  Invoke-AllModules -RepoRoot $dir
  Complete-PrivacySweep 0
  return
}

try {
  & (Join-Path $dir 'windows\clear-all.ps1') -DryRun:$DryRun -Yes:$Yes
} catch {
  Write-Host $_.Exception.Message
  if ($DryRun) {
    Complete-PrivacySweep 0
    return
  }
  Complete-PrivacySweep 1
  return
}

if ($DryRun) {
  Complete-PrivacySweep 0
  return
}
if ($null -eq $global:LASTEXITCODE) {
  Complete-PrivacySweep 0
} else {
  Complete-PrivacySweep ([int]$global:LASTEXITCODE)
}
