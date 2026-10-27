<#
.SYNOPSIS
  Report-only Windows stores: Office MRU, RecentDocs, screenshots, clipboard
  managers, chat cache vs message DBs, mail, Timeline, event-log sizes, ADS.
.NOTES
  Deletes nothing. Does not print registry values, mail bodies, or stream bytes.
  PRIVACY_SWEEP_HOME_ROOT overrides the profile root for tests.
#>
param([switch]$DryRun, [switch]$Yes)

$ErrorActionPreference = 'Continue'

function Report-Dir {
  param([string]$Label, [string]$Path)
  Write-Host "-- $Label --"
  Write-Host "Path: $Path"
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
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

function Report-KeyCount {
  param([string]$Label, [string]$Path)
  Write-Host "-- $Label --"
  Write-Host "Path: $Path"
  try {
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    $values = @($item.Property).Count
    $subs = @(Get-ChildItem -LiteralPath $Path -ErrorAction SilentlyContinue).Count
    Write-Host "Present: yes"
    Write-Host "Values: $values"
    Write-Host "Subkeys: $subs"
    Write-Host "Value data (document paths) are not printed."
  } catch {
    Write-Host "Present: no, or not readable from this account."
    Write-Host "A non-interactive logon (SSH or a service) often does not load the interactive user's Explorer hive. An interactive desktop session for the same account can show Office MRU and RecentDocs that this run did not."
  }
  Write-Host ""
}

$homeRoot = $env:PRIVACY_SWEEP_HOME_ROOT
if (-not $homeRoot) { $homeRoot = $env:USERPROFILE }
if (-not $homeRoot) { $homeRoot = $env:HOME }

Write-Host "== Local artifacts (Windows, report only; nothing deleted) =="
Write-Host "Mail stores are listed and are never deleted by privacy-sweep."
Write-Host ""

foreach ($rel in @(
    'Software\Microsoft\Office\16.0\Word\File MRU',
    'Software\Microsoft\Office\16.0\Excel\File MRU',
    'Software\Microsoft\Office\16.0\PowerPoint\File MRU',
    'Software\Microsoft\Office\15.0\Word\File MRU',
    'Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs'
  )) {
  Report-KeyCount $rel "HKCU:\$rel"
}

$recent = $null
if ($env:APPDATA) { $recent = Join-Path $env:APPDATA 'Microsoft\Windows\Recent' }
if ($env:PRIVACY_SWEEP_HOME_ROOT) { $recent = Join-Path $homeRoot 'Recent' }
Write-Host "-- Standalone .lnk in Recent (count only) --"
Write-Host "Path: $recent"
if ($recent -and (Test-Path -LiteralPath $recent)) {
  $lnks = @(Get-ChildItem -LiteralPath $recent -Filter '*.lnk' -File -ErrorAction SilentlyContinue)
  Write-Host ("Count: {0}" -f $lnks.Count)
  Write-Host "Shortcut names are not listed."
} else {
  Write-Host "Present: no"
}
Write-Host ""

$temp = $env:TEMP
if ($env:PRIVACY_SWEEP_HOME_ROOT) { $temp = Join-Path $homeRoot 'Temp' }
Write-Host "-- Office autosave and ~WRL temps (count only) --"
Write-Host "Path: $temp"
if ($temp -and (Test-Path -LiteralPath $temp)) {
  $temps = @(Get-ChildItem -LiteralPath $temp -File -Force -ErrorAction SilentlyContinue | Where-Object {
      $_.Name -like '~WRL*' -or $_.Name -like '~$*' -or $_.Name -like '*.asd'
    })
  Write-Host ("Count: {0}" -f $temps.Count)
  Write-Host "File names are not listed."
} else {
  Write-Host "Present: no"
}
if ($env:LOCALAPPDATA) {
  Report-Dir 'Office UnsavedFiles' (Join-Path $env:LOCALAPPDATA 'Microsoft\Office\UnsavedFiles')
}
Write-Host ""

$spool = Join-Path $env:WINDIR 'System32\spool\PRINTERS'
if ($env:PRIVACY_SWEEP_HOME_ROOT) { $spool = Join-Path $homeRoot 'PRINTERS' }
Report-Dir 'Printer spool' $spool

Report-Dir 'Screenshots' (Join-Path $homeRoot 'Pictures\Screenshots')

foreach ($pair in @(
    @('Ditto', $(if ($env:APPDATA) { Join-Path $env:APPDATA 'Ditto' })),
    @('Clipboard history', $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Clipboard' }))
  )) {
  if ($env:PRIVACY_SWEEP_HOME_ROOT) { continue }
  if ($pair[1]) { Report-Dir $pair[0] $pair[1] }
}
if ($env:PRIVACY_SWEEP_HOME_ROOT) {
  Report-Dir 'Ditto' (Join-Path $homeRoot 'Ditto')
  Report-Dir 'Clipboard history' (Join-Path $homeRoot 'Clipboard')
}

if ($env:LOCALAPPDATA -and -not $env:PRIVACY_SWEEP_HOME_ROOT) {
  Report-Dir 'Notifications' (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Notifications')
  Report-Dir 'ActivitiesCache parent' (Join-Path $env:LOCALAPPDATA 'ConnectedDevicesPlatform')
} elseif ($env:PRIVACY_SWEEP_HOME_ROOT) {
  Report-Dir 'Notifications' (Join-Path $homeRoot 'Notifications')
  Report-Dir 'ActivitiesCache.db folder' (Join-Path $homeRoot 'ConnectedDevicesPlatform')
}
Write-Host "Windows Timeline: if ActivitiesCache.db is in that folder, the size above includes it. The database is not opened. Coverage of the schema in public DFIR notes is thin; this is presence and size only."
Write-Host ""

function Report-Chat {
  param([string]$Label, [string]$Root)
  Write-Host "-- $Label --"
  Write-Host "Path: $Root"
  if (-not $Root -or -not (Test-Path -LiteralPath $Root)) {
    Write-Host "Present: no"
    Write-Host ""
    return
  }
  $cacheBytes = [int64]0
  $msgPresent = $false
  $dirs = @(Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force -ErrorAction SilentlyContinue)
  foreach ($dir in $dirs) {
    $n = $dir.Name
    if (@('Cache', 'GPUCache', 'Code Cache', 'Cache_Data', 'CacheStorage') -contains $n) {
      $files = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
      foreach ($file in $files) { $cacheBytes += [int64]$file.Length }
    }
    if (@('IndexedDB', 'Local Storage', 'tdata') -contains $n) { $msgPresent = $true }
  }
  if ($msgPresent) { Write-Host "Message database directory: present (not opened, not cleared by default)" }
  Write-Host "Cache bytes (cache directories only): $cacheBytes"
  Write-Host "Message bodies are not read."
  Write-Host ""
}

$chatRoot = $homeRoot
if ($env:APPDATA -and -not $env:PRIVACY_SWEEP_HOME_ROOT) { $chatRoot = $env:APPDATA }
Report-Chat 'Teams' (Join-Path $chatRoot 'Microsoft\Teams')
Report-Chat 'Slack' (Join-Path $chatRoot 'Slack')
Report-Chat 'Discord' (Join-Path $chatRoot 'discord')
Report-Chat 'Telegram' (Join-Path $chatRoot 'Telegram Desktop')

Write-Host "-- Email stores (never deleted) --"
$mailFiles = @()
if ($homeRoot -and (Test-Path -LiteralPath $homeRoot)) {
  $mailFiles = @(Get-ChildItem -LiteralPath $homeRoot -Recurse -File -Include '*.pst','*.ost','*.mbox' -Depth 4 -ErrorAction SilentlyContinue)
}
Write-Host ("PST/OST/MBOX files: {0}" -f @($mailFiles).Count)
foreach ($file in @($mailFiles)) { Write-Host "Path: $($file.DirectoryName)" }
Write-Host "Message bodies are not read. These files are not deleted."
Write-Host ""

Write-Host "-- Event log channel sizes (messages are not read) --"
if (Get-Command Get-WinEvent -ErrorAction SilentlyContinue) {
  foreach ($name in @('Security', 'System', 'Application')) {
    try {
      $log = Get-WinEvent -ListLog $name -ErrorAction Stop
      Write-Host ("{0}: records={1} bytes={2}" -f $log.LogName, $log.RecordCount, $log.FileSize)
    } catch {
      Write-Host "$name : unreadable"
    }
  }
  Write-Host "Event messages are not printed. Mass wipe is not the default."
} else {
  Write-Host "Get-WinEvent was not found. Channel sizes were not queried."
}
Write-Host ""

Write-Host "-- Alternate Data Streams (shallow, user profile) --"
Write-Host "Stream bytes are not read. This is not an MFT or USN journal edit."
$ads = 0
foreach ($rel in @('Desktop', 'Documents', 'Downloads')) {
  $dir = Join-Path $homeRoot $rel
  if (-not (Test-Path -LiteralPath $dir)) { continue }
  Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue | Select-Object -First 200 | ForEach-Object {
    try {
      $streams = @(Get-Item -LiteralPath $_.FullName -Stream * -ErrorAction Stop)
      foreach ($stream in $streams) {
        if ($stream.Stream -and $stream.Stream -ne ':$DATA') { $ads++ }
      }
    } catch { }
  }
}
Write-Host "Non-default streams noticed (capped scan): $ads"
Write-Host "MFT and `$UsnJrnl are not modified. That mutilation is out of scope."
Write-Host ""

if ($env:LOCALAPPDATA -and -not $env:PRIVACY_SWEEP_HOME_ROOT) {
  Report-Dir 'RDP bitmap cache' (Join-Path $env:LOCALAPPDATA 'Microsoft\Terminal Server Client\Cache')
}
if ($env:ProgramData) {
  Report-Dir 'Samsung Magician' (Join-Path $env:ProgramData 'Samsung\Samsung Magician')
}
Write-Host "RDP cache coverage in this corpus is thin. Presence and size only."
Write-Host "USBSTOR is not deleted. See the Windows audit for the key, and SECURITY.md."
Write-Host ""
Write-Host "Audit only: counts, sizes, and paths. Contents, passwords, message bodies, and row values are not printed."
Write-Host "Nothing was deleted."
$global:LASTEXITCODE = 0
