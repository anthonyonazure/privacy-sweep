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
    Write-Host "  REFUSED: $Label is running. Quit $Label and run this script again."
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

function Get-ProfileHome {
  if ($env:PRIVACY_SWEEP_HOME_ROOT) { return $env:PRIVACY_SWEEP_HOME_ROOT }
  if ($env:USERPROFILE) { return $env:USERPROFILE }
  if ($env:HOME) { return $env:HOME }
  return ''
}

function Join-Parts {
  param([string]$Base, [string]$Rel)
  $parts = New-Object System.Collections.Generic.List[string]
  if ($Base) { $parts.Add($Base) | Out-Null }
  foreach ($piece in ($Rel -split '[\\/]')) {
    if ($piece) { $parts.Add($piece) | Out-Null }
  }
  if ($parts.Count -eq 0) { return '' }
  return [System.IO.Path]::Combine([string[]]$parts.ToArray())
}

function Get-DataBases {
  param([string]$Kind)
  $profileHome = Get-ProfileHome
  if ($env:PRIVACY_SWEEP_HOME_ROOT) {
    Write-Output (Join-Parts $env:PRIVACY_SWEEP_HOME_ROOT ("AppData\" + $Kind))
    return
  }
  $emitted = ''
  if ($Kind -eq 'Local' -and $env:LOCALAPPDATA) {
    Write-Output $env:LOCALAPPDATA
    $emitted = $env:LOCALAPPDATA
  }
  if ($Kind -eq 'Roaming' -and $env:APPDATA) {
    Write-Output $env:APPDATA
    $emitted = $env:APPDATA
  }
  if ($profileHome) {
    $fallback = Join-Parts $profileHome ("AppData\" + $Kind)
    if ($fallback -ne $emitted) { Write-Output $fallback }
  }
}

function Resolve-FirstPath {
  param([string[]]$Candidates)
  foreach ($candidate in $Candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
  }
  foreach ($candidate in $Candidates) {
    if ($candidate) { return $candidate }
  }
  return ''
}

function Write-FirefoxProfiles {
  param([string]$Root)
  $ini = Join-Path $Root 'profiles.ini'
  if (-not (Test-Path -LiteralPath $ini)) { return }
  $path = ''
  $relative = $true
  foreach ($line in @(Get-Content -LiteralPath $ini -ErrorAction SilentlyContinue)) {
    if ($line.StartsWith('Path=')) {
      $path = $line.Substring(5).Trim()
    } elseif ($line -eq 'IsRelative=0') {
      $relative = $false
    } elseif ($line -eq 'IsRelative=1') {
      $relative = $true
    } elseif ($line.StartsWith('[')) {
      if ($path) {
        if ($relative) { Write-Output (Join-Parts $Root $path) }
        else { Write-Output $path }
      }
      $path = ''
      $relative = $true
    }
  }
  if ($path) {
    if ($relative) { Write-Output (Join-Parts $Root $path) }
    else { Write-Output $path }
  }
}

$localBases = @(Get-DataBases 'Local')
$browserDefs = @(
  @{ Id = 'chrome'; Label = 'Chrome'; Rel = 'Google\Chrome\User Data' },
  @{ Id = 'edge'; Label = 'Edge'; Rel = 'Microsoft\Edge\User Data' },
  @{ Id = 'brave'; Label = 'Brave'; Rel = 'BraveSoftware\Brave-Browser\User Data' },
  @{ Id = 'chromium'; Label = 'Chromium'; Rel = 'Chromium\User Data' }
)
foreach ($def in $browserDefs) {
  if (-not (Want-Browser $def.Id)) { continue }
  $candidates = @()
  foreach ($base in $localBases) {
    if ($base) { $candidates += (Join-Parts $base $def.Rel) }
  }
  $chosen = Resolve-FirstPath $candidates
  Invoke-ChromiumRoot -Id $def.Id -Label $def.Label -Root $chosen
}
if ($env:PRIVACY_SWEEP_BROWSER_ROOT -and (Want-Browser 'chrome')) {
  Invoke-ChromiumRoot -Id 'chrome' -Label 'Chrome fixture' -Root $env:PRIVACY_SWEEP_BROWSER_ROOT
}

if (Want-Browser 'firefox') {
  Write-Host "-- Firefox --"
  $roamingBases = @(Get-DataBases 'Roaming')
  $ffCandidates = @()
  foreach ($base in $roamingBases) {
    if ($base) { $ffCandidates += (Join-Parts $base 'Mozilla\Firefox') }
  }
  $ffRoot = Resolve-FirstPath $ffCandidates
  $profiles = @()
  if ($ffRoot -and (Test-Path -LiteralPath (Join-Path $ffRoot 'profiles.ini'))) {
    $profiles = @(Write-FirefoxProfiles $ffRoot)
  } elseif ($ffRoot) {
    $legacy = Join-Path $ffRoot 'Profiles'
    if (Test-Path -LiteralPath $legacy) {
      Get-ChildItem -LiteralPath $legacy -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $profiles += $_.FullName
      }
    }
  }
  if ($profiles.Count -eq 0 -and -not ($ffRoot -and (Test-Path -LiteralPath $ffRoot))) {
    if (-not $ffRoot) { $ffRoot = 'Mozilla\Firefox' }
    Write-Host "  Not installed ($ffRoot)."
  } elseif (Test-BrowserRunning 'firefox') {
    Write-Host "  REFUSED: Firefox is running. Quit Firefox and run this script again."
    $script:Refused = $true
  } elseif ($profiles.Count -eq 0) {
    Write-Host "  Not installed ($ffRoot)."
  } else {
    foreach ($profile in $profiles) {
      if (-not $profile) { continue }
      Write-Host "  Profile: $profile"
      Report-Keep (Join-Path $profile 'places.sqlite') 'Firefox places.sqlite (bookmarks live here; not deleted)'
      if ($ClearBrowserDeep) {
        Add-ClearPath (Join-Path $profile 'storage\default')
        Add-ClearPath (Join-Path $profile 'sessionstore.jsonlz4')
        Add-ClearPath (Join-Path $profile 'sessionstore-backups')
        Add-ClearPath (Join-Path $profile 'minidumps')
      }
    }
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
