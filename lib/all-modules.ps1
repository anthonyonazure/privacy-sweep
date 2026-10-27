# Dry-run every Windows module. Dot-sourced by privacy-sweep.ps1 -AllModules.
# Does not pass an apply switch. wipe-windows.ps1 is a child process so its exit 2
# (SSD refusal) does not close a Windows PowerShell 5.1 session.

function Invoke-PrivacySweepStep {
  param([string]$Label, [string]$Script, [hashtable]$Parameters)
  Write-Host ""
  Write-Host "===== $Label ====="
  try {
    # A string array of switch names is not bound when this file is dot-sourced
    # by a script that already has a DryRun switch. A hashtable splat is.
    if ($Parameters) {
      & $Script @Parameters
    } else {
      & $Script
    }
  } catch {
    Write-Host $_.Exception.Message
  }
}

function Invoke-AllModules {
  param([string]$RepoRoot)
  Write-Host "== Dry run of every module =="
  Write-Host "Nothing is deleted. Opt-in tools are planned only. An apply switch is not passed."
  Write-Host "An SSD free-space tool that refuses (exit 2) is reported and does not fail this pass."
  Write-Host "The recovery audit runs once, inside the Windows audit."

  $dry = @{ DryRun = $true }
  $vssArgs = @{ DryRun = $true; PurgeVss = $true }
  $browserArgs = @{ DryRun = $true; ClearBrowserDeep = $true }
  $memoryArgs = @{ DryRun = $true; DisableHibernation = $true; ClearPageFileAtShutdown = $true }
  $localArgs = @{ DryRun = $true; AllOptIn = $true }
  $eventArgs = @{ DryRun = $true; ClearEventLogs = $true }
  $searchArgs = @{ DryRun = $true; ResetSearchIndex = $true }
  Invoke-PrivacySweepStep "Windows clear-all" (Join-Path $RepoRoot 'windows\clear-all.ps1') $dry
  Invoke-PrivacySweepStep "Windows audit" (Join-Path $RepoRoot 'audit\audit-windows.ps1') $dry
  Invoke-PrivacySweepStep "Volume Shadow Copies" (Join-Path $RepoRoot 'recovery-purge\purge-vss.ps1') $vssArgs
  Invoke-PrivacySweepStep "browser deep stores" (Join-Path $RepoRoot 'browser-deep\clear-browser-deep.ps1') $browserArgs
  Invoke-PrivacySweepStep "cloud sync metadata" (Join-Path $RepoRoot 'cloud-sync\audit-cloud.ps1') $dry
  Invoke-PrivacySweepStep "persistence" (Join-Path $RepoRoot 'persistence\audit-persistence.ps1') $dry
  Invoke-PrivacySweepStep "memory residue" (Join-Path $RepoRoot 'memory-residue\memory-windows.ps1') $memoryArgs
  Invoke-PrivacySweepStep "local artifacts" (Join-Path $RepoRoot 'local-artifacts\audit-local.ps1') $dry
  Invoke-PrivacySweepStep "local artifact clears" (Join-Path $RepoRoot 'local-artifacts\clear-local.ps1') $localArgs
  Invoke-PrivacySweepStep "event logs (plan only)" (Join-Path $RepoRoot 'local-artifacts\clear-local.ps1') $eventArgs
  Invoke-PrivacySweepStep "search index (plan only)" (Join-Path $RepoRoot 'local-artifacts\clear-local.ps1') $searchArgs

  Write-Host ""
  Write-Host "===== free-space fill ====="
  $exe = (Get-Process -Id $PID).Path
  $wipe = Join-Path $RepoRoot 'hdd-free-space\wipe-windows.ps1'
  & $exe -NoProfile -NonInteractive -File $wipe -DryRun
  $wipeCode = $LASTEXITCODE
  if ($null -eq $wipeCode) { $wipeCode = 0 }
  Write-Host "wipe-windows exit: $wipeCode"
  if ($wipeCode -eq 2) {
    Write-Host "The free-space tool refused (SSD or unknown media). That refusal stands. This dry run continues."
  }
  Write-Host ""
  Write-Host "Dry run of every module finished. Nothing was deleted."
}
