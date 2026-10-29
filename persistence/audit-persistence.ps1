<#
.SYNOPSIS
  Report-only Windows persistence: non-Microsoft scheduled tasks, Run keys,
  Startup-folder files, and a WMI permanent-subscription count.
.NOTES
  Never deletes. Run-key value data and WMI queries are not printed.
  PRIVACY_SWEEP_PERSIST_ROOT is a fixture root for the Startup folder test.
#>
param([switch]$DryRun, [switch]$Yes)

$ErrorActionPreference = 'Continue'

Write-Host "== Persistence audit (report only; nothing deleted) =="
Write-Host "Command lines and WMI queries are not printed."
Write-Host ""

Write-Host "-- Scheduled tasks (non-Microsoft names) --"
$sch = Get-Command schtasks -ErrorAction SilentlyContinue
if ($env:PRIVACY_SWEEP_SCHTASKS_FIXTURE) {
  $lines = Get-Content -LiteralPath $env:PRIVACY_SWEEP_SCHTASKS_FIXTURE
} elseif (-not $sch) {
  Write-Host "schtasks was not found."
  $lines = @()
} else {
  $lines = @(& schtasks /query /fo csv)
}
$shown = 0
foreach ($line in @($lines)) {
  if ($line -match '^"([^"]+)"') {
    $task = $Matches[1]
  } else {
    continue
  }
  if ($task -like '\Microsoft\*' -or $task -eq 'TaskName') { continue }
  Write-Host "  $task"
  $shown++
}
Write-Host "Non-Microsoft tasks listed: $shown"
Write-Host "The action command line is not printed."
Write-Host ""

function Report-RunKey {
  param([string]$Path)
  Write-Host "-- Run key --"
  Write-Host "Path: $Path"
  try {
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    $names = @($item.Property)
    Write-Host "Present: yes"
    Write-Host ("Values: {0}" -f $names.Count)
    foreach ($name in $names) {
      if ($name) { Write-Host "  $name" }
    }
    Write-Host "Value data (command lines) are not printed."
  } catch {
    Write-Host "Present: no, or not readable from this account."
  }
  Write-Host ""
}

if (-not $env:PRIVACY_SWEEP_SCHTASKS_FIXTURE) {
  Report-RunKey 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  Report-RunKey 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
  Report-RunKey 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
  Report-RunKey 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
}

Write-Host "-- Startup folder --"
$startupPaths = @()
if ($env:PRIVACY_SWEEP_PERSIST_ROOT) {
  $startupPaths += (Join-Path $env:PRIVACY_SWEEP_PERSIST_ROOT 'Startup')
} else {
  if ($env:APPDATA) { $startupPaths += (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup') }
  if ($env:ProgramData) { $startupPaths += (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup') }
}
foreach ($path in $startupPaths) {
  Write-Host "Path: $path"
  if (-not (Test-Path -LiteralPath $path)) {
    Write-Host "Present: no"
    continue
  }
  $files = @(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue)
  Write-Host ("Files: {0}" -f $files.Count)
  foreach ($file in $files) { Write-Host "  $($file.FullName)" }
  Write-Host "Shortcut targets are not resolved."
}
Write-Host ""

Write-Host "-- WMI permanent subscriptions (count only) --"
if ($env:PRIVACY_SWEEP_WMI_COUNT) {
  Write-Host "WMI permanent event filters: $($env:PRIVACY_SWEEP_WMI_COUNT) (fixture)"
  Write-Host "Filter queries are not printed."
} elseif ($env:OS -ne 'Windows_NT') {
  Write-Host "WMI permanent-subscription count: not queried (this is not Windows)."
  Write-Host "Filter queries are not printed. Unavailable is not a count of zero."
} else {
  try {
    $filters = @(Get-CimInstance -Namespace root\subscription -ClassName __EventFilter -ErrorAction Stop)
    Write-Host "WMI permanent event filters: $($filters.Count)"
    Write-Host "Filter queries are not printed."
  } catch {
    Write-Host "WMI permanent-subscription count: unavailable from this account."
    Write-Host "This is a count note only. Subscription bodies are not parsed. Unavailable is not a count of zero."
  }
}
Write-Host ""
Write-Host "Nothing was deleted, disabled, or unregistered."
Write-Host "Audit only: counts, sizes, and paths. Contents, passwords, message bodies, and row values are not printed."
Write-Host "Nothing was deleted."
$global:LASTEXITCODE = 0
