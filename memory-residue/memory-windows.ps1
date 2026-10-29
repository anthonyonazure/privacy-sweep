<#
.SYNOPSIS
  Audit pagefile, hiberfil, MEMORY.DMP, and minidumps. Opt-in: powercfg /h off
  and ClearPageFileAtShutdown.
.NOTES
  Dry-run unless -Apply. -Yes does not change the system.
  Phrases: DISABLE HIBERNATION
           CLEAR PAGEFILE AT SHUTDOWN
  Not part of clear-all. Does not read file contents.
  PRIVACY_SWEEP_POWERCFG and PRIVACY_SWEEP_REGISTRY_LOG are test aids.
#>
param(
  [switch]$DryRun,
  [switch]$WhatIf,
  [switch]$Yes,
  [switch]$Apply,
  [switch]$DisableHibernation,
  [switch]$ClearPageFileAtShutdown
)

$ErrorActionPreference = 'Continue'
if ($WhatIf) { $DryRun = $true }
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\confirm.ps1')

function Report-Bytes {
  param([string]$Label, [string]$Path)
  Write-Host "-- $Label --"
  Write-Host "Path: $Path"
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
    Write-Host "Present: no"
    Write-Host ""
    return
  }
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if (-not $item) {
    Write-Host "Present: yes (size unreadable)"
  } elseif ($item.PSIsContainer) {
    $sum = [int64]0
    $n = 0
    Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
      $sum += [int64]$_.Length
      $n++
    }
    Write-Host "Present: yes"
    Write-Host "Files: $n"
    Write-Host "Bytes: $sum"
    Write-Host "File names are not listed."
  } else {
    Write-Host "Present: yes"
    Write-Host "Bytes: $($item.Length)"
  }
  Write-Host "Contents are not read."
  Write-Host ""
}

Write-Host "== Memory residue (Windows) =="
Write-Host "WARNING: turning hibernation off deletes hiberfil.sys. ClearPageFileAtShutdown wipes the pagefile at the next shutdown."
Write-Host "This destroys a copy of memory. It can also remove a crash-analysis or ransomware-recovery aid."
Write-Host "Nothing changes unless you pass -Apply and type the phrase. -Yes does not change anything."
Write-Host "This is not part of clear-all."
Write-Host ""

$roots = @()
if ($env:PRIVACY_SWEEP_RECOVERY_ROOT) {
  $drives = Join-Path $env:PRIVACY_SWEEP_RECOVERY_ROOT 'drives'
  if (Test-Path -LiteralPath $drives) {
    Get-ChildItem -LiteralPath $drives -Directory -ErrorAction SilentlyContinue | ForEach-Object { $roots += $_.FullName }
  }
} elseif ($env:SystemDrive) {
  $roots += $env:SystemDrive + '\'
}

foreach ($root in $roots) {
  Report-Bytes 'pagefile.sys' (Join-Path $root 'pagefile.sys')
  Report-Bytes 'hiberfil.sys' (Join-Path $root 'hiberfil.sys')
}
if ($env:WINDIR -and -not $env:PRIVACY_SWEEP_RECOVERY_ROOT) {
  Report-Bytes 'MEMORY.DMP' (Join-Path $env:WINDIR 'MEMORY.DMP')
  Report-Bytes 'Minidump' (Join-Path $env:WINDIR 'Minidump')
} elseif ($env:PRIVACY_SWEEP_RECOVERY_ROOT) {
  foreach ($root in $roots) {
    Report-Bytes 'MEMORY.DMP' (Join-Path $root 'Windows\MEMORY.DMP')
    Report-Bytes 'Minidump' (Join-Path $root 'Windows\Minidump')
  }
}

if (-not $DisableHibernation -and -not $ClearPageFileAtShutdown) {
  Write-Host "No opt-in flag was set. Pass -DisableHibernation and/or -ClearPageFileAtShutdown."
  Write-Host "Dry run: nothing was changed."
  Write-Host "Audit only: counts, sizes, and paths. Contents, passwords, message bodies, and row values are not printed."
  Write-Host "Nothing was deleted."
  $global:LASTEXITCODE = 0
  return
}

if ($DisableHibernation) {
  $power = $env:PRIVACY_SWEEP_POWERCFG
  if (-not $power) {
    $cmd = Get-Command powercfg -ErrorAction SilentlyContinue
    if ($cmd) { $power = $cmd.Source }
  }
  Write-Host "-- Plan: disable hibernation --"
  if ($power) { Write-Host "Would run: powercfg /h off" } else { Write-Host "powercfg was not found." }
  Write-Host "This deletes hiberfil.sys. A reboot is not required for that delete; the pagefile is separate."
  if ($Apply -and -not $DryRun) {
    if (Confirm-Phrase "DISABLE HIBERNATION") {
      if (-not $power) {
        Write-Host "powercfg was not found. Nothing was changed."
      } else {
        & $power /h off
        Write-Host "powercfg finished (exit $LASTEXITCODE)."
      }
    }
  } else {
    Write-Host "Dry run: nothing was changed."
  }
  Write-Host ""
}

if ($ClearPageFileAtShutdown) {
  $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
  Write-Host "-- Plan: ClearPageFileAtShutdown --"
  Write-Host "Would set DWORD 1 on $key name ClearPageFileAtShutdown"
  Write-Host "This takes effect at the next shutdown. Reboot, then shut down once, for the pagefile to be cleared."
  Write-Host "Other values in that key are not printed and are not changed."
  if ($Apply -and -not $DryRun) {
    if (Confirm-Phrase "CLEAR PAGEFILE AT SHUTDOWN") {
      if ($env:PRIVACY_SWEEP_REGISTRY_LOG) {
        Add-Content -LiteralPath $env:PRIVACY_SWEEP_REGISTRY_LOG -Value "ClearPageFileAtShutdown=1"
        Write-Host "SIMULATION: registry was not modified."
      } else {
        try {
          New-ItemProperty -LiteralPath $key -Name ClearPageFileAtShutdown -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
          Write-Host "Set ClearPageFileAtShutdown=1. Reboot, then shut down, for it to take effect."
        } catch {
          Write-Host "Could not set the value. An administrator terminal is required. Nothing else was changed."
          Write-Host $_.Exception.Message
        }
      }
    }
  } else {
    Write-Host "Dry run: nothing was changed."
  }
  Write-Host ""
}

Write-Host "Audit only: counts, sizes, and paths. Contents, passwords, message bodies, and row values are not printed."
Write-Host "Nothing else was deleted."
$global:LASTEXITCODE = 0
