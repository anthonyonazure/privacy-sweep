<#
.SYNOPSIS
  Report-only presence and size of local OneDrive, Dropbox, Google Drive, and iCloud caches.
.NOTES
  Deletes nothing. Does not print file contents or tokens.
  OneDrive, OneDrive for Business, and SharePoint roots are a top-level count
  only. A recursive walk can download files that were only online.
  PRIVACY_SWEEP_CLOUD_ROOT points at a fixture tree for tests.
  PRIVACY_SWEEP_HOME_ROOT is a fake profile (tests). Registry is skipped then.
#>
param([switch]$DryRun, [switch]$Yes)

$ErrorActionPreference = 'Continue'
$script:SeenPaths = @{}

function Report-File {
  param([string]$Label, [string]$Path)
  Write-Host "-- $Label --"
  Write-Host "Path: $Path"
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "Present: no"
    Write-Host ""
    return
  }
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  Write-Host "Present: yes"
  if ($item -and -not $item.PSIsContainer) { Write-Host "Bytes: $($item.Length)" }
  Write-Host "Contents are not read."
  Write-Host ""
}

function Report-TopLevel {
  param([string]$Label, [string]$Path)
  Write-Host "-- $Label --"
  Write-Host "Path: $Path"
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
    Write-Host "Present: no"
    Write-Host ""
    return
  }
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if (-not $item -or -not $item.PSIsContainer) {
    Write-Host "Present: yes (not a directory)"
    Write-Host ""
    return
  }
  $kids = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
  Write-Host "Present: yes"
  Write-Host ("TopLevelEntries: {0}" -f $kids.Count)
  Write-Host "This path is not walked. A recursive listing can hydrate cloud files."
  Write-Host ""
}

function Report-UniqueTop {
  param([string]$Label, [string]$Path)
  if (-not $Path) { return }
  $key = $Path.TrimEnd('\', '/').ToLowerInvariant()
  if ($script:SeenPaths.ContainsKey($key)) { return }
  $script:SeenPaths[$key] = $true
  Report-TopLevel -Label $Label -Path $Path
}

function Get-ProfileHome {
  if ($env:PRIVACY_SWEEP_HOME_ROOT) { return $env:PRIVACY_SWEEP_HOME_ROOT }
  if ($env:USERPROFILE) { return $env:USERPROFILE }
  if ($env:HOME) { return $env:HOME }
  return ''
}

function Get-LocalRoot {
  if ($env:PRIVACY_SWEEP_HOME_ROOT) {
    return [System.IO.Path]::Combine($env:PRIVACY_SWEEP_HOME_ROOT, 'AppData', 'Local')
  }
  if ($env:LOCALAPPDATA) { return $env:LOCALAPPDATA }
  $home = Get-ProfileHome
  if ($home) { return [System.IO.Path]::Combine($home, 'AppData', 'Local') }
  return ''
}

Write-Host "== Cloud sync metadata (report only; nothing deleted) =="
Write-Host "Clearing a local cache does not clear the account, its versions, its device list, or its activity log."
Write-Host "See cloud-sync/README.md for the per-service checklist."
Write-Host ""

if ($env:PRIVACY_SWEEP_CLOUD_ROOT) {
  $base = $env:PRIVACY_SWEEP_CLOUD_ROOT
  Report-TopLevel 'OneDrive logs' (Join-Path $base 'OneDrive\logs')
  Report-File 'OneDrive SyncEngineDatabase.db' (Join-Path $base 'OneDrive\SyncEngineDatabase.db')
  Report-TopLevel 'Dropbox instance db' (Join-Path $base 'Dropbox\instance_db')
  Report-TopLevel 'Google DriveFS' (Join-Path $base 'DriveFS')
  Report-TopLevel 'iCloud' (Join-Path $base 'iCloudDrive')
} else {
  $home = Get-ProfileHome
  $useRegistry = -not $env:PRIVACY_SWEEP_HOME_ROOT

  if ($useRegistry) {
    foreach ($pair in @(
        @('OneDrive consumer root', $env:OneDrive),
        @('OneDrive commercial root', $env:OneDriveCommercial),
        @('OneDrive consumer folder', $env:OneDriveConsumer)
      )) {
      if ($pair[1]) { Report-UniqueTop $pair[0] $pair[1] }
    }
    try {
      $accounts = 'HKCU:\Software\Microsoft\OneDrive\Accounts'
      if (Test-Path -LiteralPath $accounts) {
        Get-ChildItem -LiteralPath $accounts -ErrorAction SilentlyContinue | ForEach-Object {
          $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
          if ($props -and $props.UserFolder) {
            Report-UniqueTop ("OneDrive account " + $_.PSChildName) $props.UserFolder
          }
        }
      }
    } catch {
      Write-Host "OneDrive account registry could not be read from this session."
    }
    try {
      $sync = 'HKCU:\Software\SyncEngines\Providers\OneDrive'
      if (Test-Path -LiteralPath $sync) {
        Get-ChildItem -LiteralPath $sync -ErrorAction SilentlyContinue | ForEach-Object {
          $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
          if ($props -and $props.MountPoint) {
            Report-UniqueTop 'SharePoint sync' $props.MountPoint
          }
        }
      }
    } catch {
      Write-Host "SharePoint sync roots could not be read from this session."
    }
  }

  if ($home) {
    Get-ChildItem -LiteralPath $home -Force -ErrorAction SilentlyContinue | ForEach-Object {
      if (-not $_.PSIsContainer) { return }
      if ($_.Name -eq 'OneDrive' -or $_.Name -like 'OneDrive - *') {
        Report-UniqueTop 'OneDrive root' $_.FullName
      }
    }
  }

  $local = Get-LocalRoot
  if ($local) {
    $logs = [System.IO.Path]::Combine($local, 'Microsoft', 'OneDrive', 'logs')
    Report-UniqueTop 'OneDrive logs' $logs
    foreach ($child in @('Business1', 'Personal')) {
      $childPath = [System.IO.Path]::Combine($logs, $child)
      Report-UniqueTop ("OneDrive logs " + $child) $childPath
    }
    Report-UniqueTop 'Dropbox' ([System.IO.Path]::Combine($local, 'Dropbox'))
    Report-UniqueTop 'Google DriveFS' ([System.IO.Path]::Combine($local, 'Google', 'DriveFS'))
  }
  if ($home) {
    Report-UniqueTop 'iCloud Drive' (Join-Path $home 'iCloudDrive')
  }
}

Write-Host "Audit only: counts, sizes, and paths. Contents, passwords, message bodies, and row values are not printed."
Write-Host "Nothing was deleted."
Write-Host "The cloud copy, version history, device list, and activity log are unchanged."
$global:LASTEXITCODE = 0
