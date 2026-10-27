<#
.SYNOPSIS
  Opt-in delete of Windows Volume Shadow Copies.
.NOTES
  Dry-run unless -Apply. -Yes does not delete and does not skip the typed phrase.
  Phrase: DELETE SHADOW COPIES
  Not part of clear-all. This destroys Previous Versions, restore points, and a
  common ransomware-recovery path.
#>
param(
  [switch]$DryRun,
  [switch]$WhatIf,
  [switch]$Yes,
  [switch]$Apply,
  [switch]$PurgeVss
)

$ErrorActionPreference = 'Continue'
if ($WhatIf) { $DryRun = $true }
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\confirm.ps1')

Write-Host "WARNING: this destroys your backups / Previous Versions / ransomware recovery."
Write-Host "Volume Shadow Copies hold prior copies of the disk. Deleting them removes restore points."
Write-Host "Nothing is deleted unless you pass -PurgeVss and -Apply and type DELETE SHADOW COPIES."
Write-Host "-Yes does not delete. This is not part of clear-all."
Write-Host ""

function Get-ShadowReport {
  if ($env:PRIVACY_SWEEP_RECOVERY_ROOT) {
    $path = Join-Path $env:PRIVACY_SWEEP_RECOVERY_ROOT 'vssadmin-shadows.txt'
    Write-Host "-- What the audit found (fixture) --"
    if (Test-Path -LiteralPath $path) {
      Get-Content -LiteralPath $path | ForEach-Object {
        $trim = $_.Trim()
        if ($trim -like 'Shadow Copy ID:*' -or $trim -like 'Original Volume:*' -or $trim -like 'Shadow Copy Volume:*' -or $trim -like 'No items found*') {
          Write-Host "  $trim"
        }
      }
    } else {
      Write-Host "No vssadmin-shadows.txt in the fixture."
    }
    return
  }
  Write-Host "-- What the audit found --"
  $vss = Get-Command vssadmin -ErrorAction SilentlyContinue
  if (-not $vss) {
    Write-Host "vssadmin was not found. Shadow list is unavailable."
    return
  }
  & vssadmin list shadows
}

Get-ShadowReport
Write-Host ""

if (-not $PurgeVss) {
  Write-Host "No purge flag was set. Pass -PurgeVss."
  Write-Host "Dry run: nothing was deleted."
  $global:LASTEXITCODE = 0
  return
}

$vssCmd = $env:PRIVACY_SWEEP_VSSADMIN
if (-not $vssCmd) {
  $found = Get-Command vssadmin -ErrorAction SilentlyContinue
  if ($found) { $vssCmd = $found.Source }
}
$wmicCmd = $env:PRIVACY_SWEEP_WMIC
if (-not $wmicCmd) {
  $foundW = Get-Command wmic -ErrorAction SilentlyContinue
  if ($foundW) { $wmicCmd = $foundW.Source }
}

Write-Host "-- Plan: Volume Shadow Copies --"
if ($vssCmd) {
  Write-Host "Would run: vssadmin delete shadows /all /quiet"
} elseif ($wmicCmd) {
  Write-Host "vssadmin was not found."
  Write-Host "Would run: wmic shadowcopy delete"
} else {
  Write-Host "Neither vssadmin nor wmic was found. Nothing would be deleted."
}
Write-Host ""

if (-not $Apply -or $DryRun) {
  Write-Host "Dry run: nothing was deleted."
  $global:LASTEXITCODE = 0
  return
}

if (-not (Confirm-Phrase "DELETE SHADOW COPIES")) {
  $global:LASTEXITCODE = 0
  return
}

if ($vssCmd) {
  Write-Host "Running: vssadmin delete shadows /all /quiet"
  & $vssCmd delete shadows /all /quiet
  if ($LASTEXITCODE -ne 0) {
    Write-Host "vssadmin exited $LASTEXITCODE. Shadows may remain."
    return
  }
} elseif ($wmicCmd) {
  Write-Host "Running: wmic shadowcopy delete"
  & $wmicCmd shadowcopy delete
  if ($LASTEXITCODE -ne 0) {
    Write-Host "wmic exited $LASTEXITCODE. Shadows may remain."
    return
  }
} else {
  Write-Host "Neither vssadmin nor wmic was found. Nothing was deleted."
  $global:LASTEXITCODE = 1
  return
}

Write-Host "Done. Free space was not filled. Other stores were not touched."
$global:LASTEXITCODE = 0
