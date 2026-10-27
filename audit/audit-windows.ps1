<#
.SYNOPSIS
  Report-only inventory of Windows stores a forensic examiner would look at
  first: Prefetch, Jump Lists, USBSTOR, recent items, saved Wi-Fi profiles,
  and recovery structures (shadow copies, Recycle Bin metadata counts,
  pagefile/hiberfil/MEMORY.DMP, the search index, thumbcache databases,
  wipe-tool remnant names, BitLocker protection status).
.NOTES
  part of privacy-sweep (Windows). Prints counts and paths. Deletes nothing.
  Does not read Event Logs, SRUM, Amcache, or ShimCache, and does not print
  Wi-Fi passwords, $I file contents, or BitLocker keys. -DryRun and -Yes
  exist so the flag style matches the other scripts; both print the same report.
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
& (Join-Path $PSScriptRoot 'audit-recovery-windows.ps1')
Write-Host ""
Write-Host "Shadow copies and the other recovery structures above are reported only."
Write-Host "This script does not delete them. Purging restore points is not part of this tool."
Write-Host "Not included, and not cleared by this tool: Event Logs, SRUM, Amcache,"
Write-Host "ShimCache, and the rest of the Registry. See SECURITY.md."
