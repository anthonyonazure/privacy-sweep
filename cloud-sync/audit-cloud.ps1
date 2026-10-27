<#
.SYNOPSIS
  Report-only presence and size of local OneDrive, Dropbox, Google Drive, and iCloud caches.
.NOTES
  Deletes nothing. Does not print file contents or tokens.
  PRIVACY_SWEEP_CLOUD_ROOT points at a fixture tree for tests.
#>
param([switch]$DryRun, [switch]$Yes)

$ErrorActionPreference = 'Continue'

function Report-Dir {
  param([string]$Label, [string]$Path)
  Write-Host "-- $Label --"
  Write-Host "Path: $Path"
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "Present: no"
    Write-Host ""
    return
  }
  $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)
  $bytes = [int64]0
  foreach ($file in $files) { $bytes += [int64]$file.Length }
  Write-Host "Present: yes"
  Write-Host ("Files: {0}" -f $files.Count)
  Write-Host "Bytes: $bytes"
  Write-Host "Names inside this store are not listed."
  Write-Host ""
}

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

Write-Host "== Cloud sync metadata (report only; nothing deleted) =="
Write-Host "Clearing a local cache does not clear the account, its versions, its device list, or its activity log."
Write-Host "See cloud-sync/README.md for the per-service checklist."
Write-Host ""

if ($env:PRIVACY_SWEEP_CLOUD_ROOT) {
  $base = $env:PRIVACY_SWEEP_CLOUD_ROOT
  Report-Dir 'OneDrive logs' (Join-Path $base 'OneDrive\logs')
  Report-File 'OneDrive SyncEngineDatabase.db' (Join-Path $base 'OneDrive\SyncEngineDatabase.db')
  Report-Dir 'Dropbox instance db' (Join-Path $base 'Dropbox\instance_db')
  Report-Dir 'Google DriveFS' (Join-Path $base 'DriveFS')
  Report-Dir 'iCloud' (Join-Path $base 'iCloudDrive')
} else {
  foreach ($pair in @(
      @('OneDrive consumer root', $env:OneDrive),
      @('OneDrive commercial root', $env:OneDriveCommercial),
      @('OneDrive logs', $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\logs' })),
      @('Dropbox', $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Dropbox' })),
      @('Google DriveFS', $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Google\DriveFS' })),
      @('iCloud Drive', $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'iCloudDrive' }))
    )) {
    if ($pair[1]) { Report-Dir $pair[0] $pair[1] }
  }
}

Write-Host "Audit only: counts, sizes, and paths. Contents, passwords, message bodies, and row values are not printed."
Write-Host "Nothing was deleted."
Write-Host "The cloud copy, version history, device list, and activity log are unchanged."
$global:LASTEXITCODE = 0
