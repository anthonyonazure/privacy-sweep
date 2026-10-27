<#
.SYNOPSIS
  Opt-in clear of Chromium LevelDB, IndexedDB, Cache_Data, service workers,
  session restore, and Crashpad dumps. Bookmarks are never deleted.
.NOTES
  Dry-run unless -Apply. -Yes does not delete. Refuses a running browser.
  Not part of clear-all.
  PRIVACY_SWEEP_BROWSER_ROOT, if set, is an extra Chrome-style user-data directory (tests).
  PRIVACY_SWEEP_ASSUME_OPEN=chrome,edge,firefox,brave refuses that browser.
#>
param(
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$Apply,
  [switch]$ClearBrowserDeep,
  [string]$Only = ''
)

$ErrorActionPreference = 'Continue'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\confirm.ps1')

function Want-Browser {
  param([string]$Id)
  if (-not $Only) { return $true }
  $items = $Only.ToLowerInvariant().Split(',') | ForEach-Object { $_.Trim() }
  return @($items) -contains $Id
}

function Test-BrowserRunning {
  param([string]$Id)
  $assume = ",$($env:PRIVACY_SWEEP_ASSUME_OPEN),"
  if ($assume.ToLowerInvariant().Contains(",$Id,")) { return $true }
  $names = @()
  switch ($Id) {
    'chrome' { $names = @('chrome') }
    'edge' { $names = @('msedge') }
    'brave' { $names = @('brave') }
    'firefox' { $names = @('firefox') }
  }
  foreach ($name in $names) {
    if (Get-Process -Name $name -ErrorAction SilentlyContinue) { return $true }
  }
  return $false
}

function Test-UnderHome {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  $homeDir = $env:USERPROFILE
  if (-not $homeDir) { $homeDir = $env:HOME }
  if (-not $homeDir) { return $false }
  $full = [System.IO.Path]::GetFullPath($Path)
  $root = [System.IO.Path]::GetFullPath($homeDir)
  return ($full -eq $root -or $full.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar) -or $full.StartsWith($root + '\'))
}

$script:Actions = New-Object System.Collections.Generic.List[string]
$script:Refused = $false

function Add-ClearPath {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return }
  if (-not (Test-UnderHome $Path)) {
    Write-Host "  Skipping $Path (outside your home directory)."
    return
  }
  $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)
  $count = $files.Count
  if (-not (Get-Item -LiteralPath $Path).PSIsContainer) { $count = 1 }
  Write-Host "  CLEAR $Path  (files: $count)"
  $script:Actions.Add($Path) | Out-Null
}

function Report-Keep {
  param([string]$Path, [string]$Label)
  Write-Host "  KEEP $Label"
  Write-Host "    Path: $Path"
  if (Test-Path -LiteralPath $Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item -and -not $item.PSIsContainer) {
      Write-Host "    Present: yes  Bytes: $($item.Length)"
    } else {
      Write-Host "    Present: yes"
    }
  } else {
    Write-Host "    Present: no"
  }
  Write-Host "    Contents are not printed. This file is not deleted."
}

function Invoke-ChromiumRoot {
  param([string]$Id, [string]$Label, [string]$Root)
  Write-Host "-- $Label --"
  if (-not (Test-Path -LiteralPath $Root)) {
    Write-Host "  Not installed ($Root)."
    return
  }
  if (Test-BrowserRunning $Id) {
    Write-Host "  REFUSED: $Label is running. Quit it and run this script again."
    $script:Refused = $true
    return
  }
  $profiles = @()
  $default = Join-Path $Root 'Default'
  if (Test-Path -LiteralPath $default) { $profiles += $default }
  Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -like 'Profile *' -or $_.Name -eq 'Guest Profile') { $profiles += $_.FullName }
  }
  foreach ($profile in $profiles) {
    Write-Host "  Profile: $profile"
    Report-Keep (Join-Path $profile 'Bookmarks') 'bookmarks'
    if (-not $ClearBrowserDeep) { continue }
    foreach ($rel in @(
        'Local Storage\leveldb', 'IndexedDB', 'Session Storage', 'Service Worker',
        'Cache\Cache_Data', 'Sessions', 'Current Session', 'Current Tabs',
        'Last Session', 'Last Tabs')) {
      Add-ClearPath (Join-Path $profile $rel)
    }
  }
  if ($ClearBrowserDeep) {
    Add-ClearPath (Join-Path $Root 'Crashpad')
    Add-ClearPath (Join-Path $Root 'Crash Reports')
  }
  Write-Host "  Bookmarks are not deleted."
}

Write-Host "== Browser deep stores (LevelDB, IndexedDB, session restore, Crashpad) =="
Write-Host "Bookmarks are reported and are never deleted."
Write-Host "Pass -ClearBrowserDeep to plan a clear. Pass -Apply as well to delete."
Write-Host "-Yes does not delete. This is not part of clear-all."
Write-Host ""

$roots = @()
if ($env:LOCALAPPDATA) {
  $roots += @{ Id = 'chrome'; Label = 'Chrome'; Path = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data') }
  $roots += @{ Id = 'edge'; Label = 'Edge'; Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data') }
  $roots += @{ Id = 'brave'; Label = 'Brave'; Path = (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data') }
  $roots += @{ Id = 'chromium'; Label = 'Chromium'; Path = (Join-Path $env:LOCALAPPDATA 'Chromium\User Data') }
}
if ($env:PRIVACY_SWEEP_BROWSER_ROOT) {
  $roots += @{ Id = 'chrome'; Label = 'Chrome fixture'; Path = $env:PRIVACY_SWEEP_BROWSER_ROOT }
}

foreach ($root in $roots) {
  if (Want-Browser $root.Id) {
    Invoke-ChromiumRoot -Id $root.Id -Label $root.Label -Path $root.Path
  }
}

if ($env:APPDATA -and (Want-Browser 'firefox')) {
  Write-Host "-- Firefox --"
  $ff = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
  if (Test-BrowserRunning 'firefox') {
    Write-Host "  REFUSED: Firefox is running. Quit it and run this script again."
    $script:Refused = $true
  } elseif (Test-Path -LiteralPath $ff) {
    Get-ChildItem -LiteralPath $ff -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      Write-Host "  Profile: $($_.FullName)"
      Report-Keep (Join-Path $_.FullName 'places.sqlite') 'Firefox places.sqlite (bookmarks live here; not deleted)'
      if ($ClearBrowserDeep) {
        Add-ClearPath (Join-Path $_.FullName 'storage\default')
        Add-ClearPath (Join-Path $_.FullName 'sessionstore.jsonlz4')
        Add-ClearPath (Join-Path $_.FullName 'sessionstore-backups')
        Add-ClearPath (Join-Path $_.FullName 'minidumps')
      }
    }
  } else {
    Write-Host "  Not installed ($ff)."
  }
}

Write-Host ""
Write-Host "Audit only: counts, sizes, and paths. Contents, passwords, message bodies, and row values are not printed."

if (-not $ClearBrowserDeep) {
  Write-Host "Nothing was deleted."
  $global:LASTEXITCODE = 0
  return
}

if ($script:Actions.Count -eq 0) {
  if ($script:Refused) {
    Write-Host "Nothing was cleared. At least one browser was open."
    $global:LASTEXITCODE = 2
    return
  }
  Write-Host "No deep browser stores found."
  Write-Host "Nothing was deleted."
  $global:LASTEXITCODE = 0
  return
}

if (-not $Apply -or $DryRun) {
  Write-Host "Dry run: would clear $($script:Actions.Count) path(s). Nothing was deleted."
  if ($script:Refused) { $global:LASTEXITCODE = 2; return }
  $global:LASTEXITCODE = 0
  return
}

if (-not (Confirm-YesNo "Clear the browser deep stores listed above? Bookmarks stay")) {
  Write-Host "Cancelled. Nothing was deleted."
  $global:LASTEXITCODE = 0
  return
}

foreach ($path in $script:Actions) {
  $name = Split-Path -Leaf $path
  if ($name -in @('Bookmarks', 'Bookmarks.bak', 'places.sqlite', 'Login Data', 'key4.db', 'logins.json')) {
    Write-Host "Refusing to delete $path"
    continue
  }
  if ((Get-Item -LiteralPath $path -Force).PSIsContainer) {
    Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  }
}
Write-Host "Done. Bookmarks were not deleted."
if ($script:Refused) { $global:LASTEXITCODE = 2; return }
$global:LASTEXITCODE = 0
