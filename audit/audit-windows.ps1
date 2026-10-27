<#
.SYNOPSIS
  Report-only inventory of Windows stores a forensic examiner would look at
  first: Prefetch, Jump Lists, USBSTOR, recent items, saved Wi-Fi profiles,
  execution stores (ShimCache, Amcache, SRUM, BAM/DAM, UserAssist, ShellBags),
  and recovery structures (shadow copies, Recycle Bin metadata counts,
  pagefile/hiberfil/MEMORY.DMP, the search index, thumbcache databases,
  wipe-tool remnant names, BitLocker protection status).
.NOTES
  part of privacy-sweep (Windows). Prints counts, paths, and presence.
  Deletes nothing. Does not print Wi-Fi passwords, program paths stored inside
  execution records, Event Log messages, $I file contents, or BitLocker keys.
  ShimCache, Amcache, SRUM, BAM, and DAM can still show that a program ran
  after the file itself is gone. This script reports those stores and the
  recovery structures above, and does not delete them.
  -DryRun and -Yes exist so the flag style matches the other scripts; both
  print the same report.
#>
param([switch]$DryRun, [switch]$Yes)

$ErrorActionPreference = 'Continue'

Write-Host "== Windows privacy audit (counts and paths, nothing deleted) =="
Write-Host "Report only. This does not clear these stores."
if ($DryRun -or $Yes) { Write-Host "(flags noted; this script has nothing to apply)" }
Write-Host ""

function Report-Directory {
  param([string]$Label, [string]$Path, [string]$Filter = '*')
  Write-Host "-- $Label --"
  Write-Host "Path: $Path"
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "Count: 0 (not present)"
    Write-Host ""
    return
  }
  $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Filter $Filter -ErrorAction SilentlyContinue)
  Write-Host ("Count: {0}" -f $files.Count)
  foreach ($file in $files) { Write-Host ("  {0}" -f $file.FullName) }
  Write-Host ""
}

$prefetch = Join-Path $env:WINDIR 'Prefetch'
Write-Host "-- Prefetch --"
Write-Host "Path: $prefetch"
try {
  $pf = @(Get-ChildItem -LiteralPath $prefetch -Filter '*.pf' -File -ErrorAction Stop)
  Write-Host ("Count: {0}" -f $pf.Count)
  foreach ($file in $pf) { Write-Host ("  {0}" -f $file.FullName) }
} catch {
  Write-Host "Count: unreadable. Prefetch often requires an elevated terminal."
  Write-Host ("  {0}" -f $_.Exception.Message)
}
Write-Host ""

$recent = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
Report-Directory -Label 'Recent items' -Path $recent
Report-Directory -Label 'Jump Lists (AutomaticDestinations)' -Path (Join-Path $recent 'AutomaticDestinations')
Report-Directory -Label 'Jump Lists (CustomDestinations)' -Path (Join-Path $recent 'CustomDestinations')

Write-Host "-- USB storage history (USBSTOR) --"
$usbstor = 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR'
Write-Host "Path: $usbstor"
try {
  $instances = @(Get-ChildItem -Path $usbstor -Recurse -ErrorAction Stop | Where-Object { $_.PSChildName -and $_.PSPath -match '\\USBSTOR\\.+' })
  $leaves = @($instances | Where-Object { -not (Get-ChildItem -LiteralPath $_.PSPath -ErrorAction SilentlyContinue) })
  if (-not $leaves) { $leaves = $instances }
  Write-Host ("Keys: {0}" -f $leaves.Count)
  foreach ($key in $leaves) { Write-Host ("  {0}" -f $key.Name) }
} catch {
  Write-Host "Keys: unreadable. Reading USBSTOR often requires an elevated terminal."
  Write-Host ("  {0}" -f $_.Exception.Message)
}
Write-Host "The key paths are listed. This script does not delete them and does not export the key."
Write-Host ""

Write-Host "-- Saved Wi-Fi profiles (names only) --"
$netsh = Get-Command netsh -ErrorAction SilentlyContinue
if (-not $netsh) {
  Write-Host "netsh was not found."
} else {
  $profiles = & netsh wlan show profiles
  $names = @()
  foreach ($line in $profiles) {
    if ($line -match ':\s*(.+)$' -and $line -match 'Profile') {
      $name = $Matches[1].Trim()
      if ($name -and $name -ne '<None>') { $names += $name }
    }
  }
  Write-Host ("Count: {0}" -f $names.Count)
  foreach ($name in $names) { Write-Host ("  {0}" -f $name) }
  Write-Host "Passwords are not requested. Do not add 'key=clear' to this command."
}
Write-Host ""
function Report-Bytes {
  param([string]$Path)
  try {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    Write-Host ("Present: {0} ({1} bytes)" -f $item.FullName, $item.Length)
  } catch {
    Write-Host ("Not present, or not readable: {0}" -f $Path)
  }
}

Write-Host "-- ShimCache (AppCompatCache) --"
$shim = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache'
Write-Host "Path: $shim"
try {
  $shimKey = Get-Item -LiteralPath $shim -ErrorAction Stop
  $raw = $shimKey.GetValue('AppCompatCache', $null)
  if ($null -eq $raw) {
    Write-Host "Present: key yes, AppCompatCache value no"
  } else {
    $size = 0
    if ($raw -is [byte[]]) { $size = $raw.Length } else { $size = @($raw).Count }
    Write-Host "Present: yes"
    Write-Host ("AppCompatCache value size: {0} bytes" -f $size)
  }
  Write-Host "Paths cached inside the value are not printed."
} catch {
  Write-Host "Present: no, or not readable from this account."
  Write-Host ("  {0}" -f $_.Exception.Message)
}
Write-Host ""

Write-Host "-- Amcache.hve --"
$amcacheDir = Join-Path $env:WINDIR 'appcompat\Programs'
Write-Host "Path: $amcacheDir"
foreach ($name in @('Amcache.hve', 'Amcache.hve.LOG', 'Amcache.hve.LOG1', 'Amcache.hve.LOG2')) {
  Report-Bytes (Join-Path $amcacheDir $name)
}
Write-Host "The hive is not opened, so program names inside it are not printed."
Write-Host ""

Write-Host "-- SRUM (SRUDB.dat) --"
$sruDir = Join-Path $env:WINDIR 'System32\sru'
Write-Host "Path: $sruDir"
foreach ($name in @('SRUDB.dat', 'SRUDB.dat.LOG1', 'SRUDB.dat.LOG2')) {
  Report-Bytes (Join-Path $sruDir $name)
}
Write-Host "The database is not opened, so resource-usage rows are not printed."
Write-Host ""

function Report-ExecutionKey {
  param([string]$Label, [string]$Path)
  Write-Host "-- $Label --"
  Write-Host "Path: $Path"
  try {
    $null = Get-Item -LiteralPath $Path -ErrorAction Stop
    $users = @(Get-ChildItem -LiteralPath $Path -ErrorAction SilentlyContinue)
    $entries = 0
    foreach ($userKey in $users) { $entries += @($userKey.Property).Count }
    Write-Host "Present: yes"
    Write-Host ("User keys: {0}" -f $users.Count)
    Write-Host ("Entries: {0}" -f $entries)
    Write-Host "Entry names are program paths and are not printed."
  } catch {
    Write-Host "Present: no, or not readable from this account."
    Write-Host ("  {0}" -f $_.Exception.Message)
  }
  Write-Host ""
}

Report-ExecutionKey -Label 'BAM (Background Activity Moderator)' -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings'
Report-ExecutionKey -Label 'BAM (older UserSettings path)' -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings'
Report-ExecutionKey -Label 'DAM (Desktop Activity Moderator)' -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\dam\State\UserSettings'
Report-ExecutionKey -Label 'DAM (older UserSettings path)' -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\dam\UserSettings'

Write-Host "-- UserAssist (presence) --"
$assist = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
Write-Host "Path: $assist"
try {
  $guidKeys = @(Get-ChildItem -LiteralPath $assist -ErrorAction Stop)
  $values = 0
  foreach ($guidKey in $guidKeys) {
    $countItem = Get-ChildItem -LiteralPath $guidKey.PSPath -ErrorAction SilentlyContinue |
      Where-Object { $_.PSChildName -eq 'Count' } |
      Select-Object -First 1
    if ($countItem) { $values += @($countItem.Property).Count }
  }
  Write-Host "Present: yes"
  Write-Host ("GUID keys: {0}" -f $guidKeys.Count)
  Write-Host ("Count values: {0}" -f $values)
  Write-Host "Program names in those values are not printed."
} catch {
  Write-Host "Present: no, or not readable from this account."
  Write-Host ("  {0}" -f $_.Exception.Message)
}
Write-Host ""

function Report-ShellBag {
  param([string]$Path)
  Write-Host "Path: $Path"
  try {
    $null = Get-Item -LiteralPath $Path -ErrorAction Stop
    $subs = @(Get-ChildItem -LiteralPath $Path -Recurse -ErrorAction SilentlyContinue)
    Write-Host "Present: yes"
    Write-Host ("Subkeys: {0}" -f $subs.Count)
  } catch {
    Write-Host "Present: no, or not readable from this account."
  }
}

Write-Host "-- ShellBags (presence) --"
Write-Host "Folder names stored in the values are not printed."
Report-ShellBag 'HKCU:\Software\Microsoft\Windows\Shell\BagMRU'
Report-ShellBag 'HKCU:\Software\Microsoft\Windows\Shell\Bags'
Report-ShellBag 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU'
Report-ShellBag 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags'
Write-Host ""
Write-Host "ShimCache, Amcache, SRUM, BAM, and DAM can still record a program run"
Write-Host "after that program has been deleted. UserAssist and ShellBags are the"
Write-Host "same kind of record for launches and folders. This script reports them"
Write-Host "and does not delete them."
Write-Host ""
& (Join-Path $PSScriptRoot 'audit-recovery-windows.ps1')
Write-Host ""
Write-Host "Shadow copies and the other recovery structures above are reported only."
Write-Host "This script does not delete them. Purging restore points is not part of this tool."
Write-Host "Not included, and not cleared by this tool: Event Logs and the rest of"
Write-Host "the Registry. See SECURITY.md."
