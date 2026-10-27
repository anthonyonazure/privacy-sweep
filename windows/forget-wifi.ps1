<#
.SYNOPSIS
  Forgets saved Wi-Fi profiles via netsh. The network you are using is kept
  unless you pass -IncludeCurrent. Passwords are never printed.
.NOTES
  part of privacy-sweep (Windows). Modes: -DryRun (list only), (default) ask
  first, -Yes (no prompt).
#>
param([switch]$DryRun, [switch]$Yes, [switch]$IncludeCurrent)

$ErrorActionPreference = 'Continue'

function Confirm-Proceed {
  if ($Yes) { return $true }
  return ((Read-Host "Forget the saved Wi-Fi networks listed above? [y/N]") -match '^[Yy]$')
}

if (-not (Get-Command netsh -ErrorAction SilentlyContinue)) {
  Write-Host "netsh was not found."
  exit 1
}

function Get-ProfileNames {
  param([string[]]$Lines)
  $names = @()
  foreach ($line in $Lines) {
    if ($line -match 'All User Profile\s*:\s*(.+)$') {
      $name = $Matches[1].Trim()
      if ($name -and $name -ne '<None>') { $names += $name }
    }
  }
  return $names
}

$current = ""
$iface = & netsh wlan show interfaces
foreach ($line in $iface) {
  if ($line -match '^\s*SSID\s*:\s*(.+)$' -and $line -notmatch 'BSSID') {
    $current = $Matches[1].Trim()
    break
  }
}

Write-Host "== Saved Wi-Fi profiles =="
if ($current) { Write-Host "Joined now: $current" } else { Write-Host "Not joined to a Wi-Fi network." }

$profiles = Get-ProfileNames (& netsh wlan show profiles)
$drop = @()
foreach ($name in $profiles) {
  if ($current -and $name -eq $current -and -not $IncludeCurrent) {
    Write-Host "In use, will keep: $name"
    continue
  }
  $drop += $name
  if ($current -and $name -eq $current) {
    Write-Host "Would forget (this disconnects you): $name"
  } else {
    Write-Host "Would forget: $name"
  }
}

if ($profiles.Count -gt 0 -and $current -and -not $IncludeCurrent) {
  Write-Host "Pass -IncludeCurrent to forget the network this PC is using."
}
if ($drop.Count -eq 0) {
  Write-Host "Nothing to forget."
  exit 0
}
if ($DryRun) {
  Write-Host "(dry run) Would delete $($drop.Count) profile(s). No change made."
  exit 0
}
if (-not (Confirm-Proceed)) { Write-Host "Cancelled."; exit 0 }

foreach ($name in $drop) {
  if ($name -match '["\r\n&|<>^]') {
    Write-Host "Skipping a profile whose name has shell metacharacters: $name"
    continue
  }
  & netsh wlan delete profile name="$name"
  if ($LASTEXITCODE -eq 0) { Write-Host "Forgot: $name" } else { Write-Host "Could not forget: $name" }
}
Write-Host "Done."
