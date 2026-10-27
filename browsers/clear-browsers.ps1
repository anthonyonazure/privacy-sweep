<#
.SYNOPSIS
  Clears history, cookies, and cache for Chrome, Edge, Firefox, and Brave.
  Bookmarks and saved passwords are left in place. Refuses a browser that
  is still running; -Yes does not override that.
.NOTES
  part of privacy-sweep (Windows). Modes: -DryRun, (default) ask, -Yes.
  -Only takes a comma-separated list such as chrome,firefox.
  Safari does not run on Windows. Firefox history is edited with sqlite3 or
  python so bookmarks in places.sqlite survive. If neither tool exists, Firefox
  history is skipped rather than deleting the whole file.
#>
param(
  [switch]$DryRun,
  [switch]$Yes,
  [string]$Only = ""
)

$ErrorActionPreference = 'Continue'

function Confirm-Proceed {
  if ($Yes) { return $true }
  return ((Read-Host "Clear history, cookies, and cache for the browsers listed above? [y/N]") -match '^[Yy]$')
}

function Test-Wanted {
  param([string]$Id)
  if (-not $Only) { return $true }
  $parts = $Only.ToLower().Split(",") | ForEach-Object { $_.Trim() }
  return $parts -contains $Id
}

function Test-BrowserOpen {
  param([string]$Id)
  $assumed = $env:PRIVACY_SWEEP_ASSUME_OPEN
  if ($assumed) {
    $parts = $assumed.ToLower().Split(",") | ForEach-Object { $_.Trim() }
    if ($parts -contains $Id) { return $true }
  }
  $names = switch ($Id) {
    "chrome" { @("chrome") }
    "edge" { @("msedge") }
    "brave" { @("brave") }
    "firefox" { @("firefox") }
    default { @() }
  }
  foreach ($name in $names) {
    if (Get-Process -Name $name -ErrorAction SilentlyContinue) { return $true }
  }
  return $false
}

function Test-UnderUser {
  param([string]$Path)
  $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $item) { return $false }
  $full = $item.FullName
  # A junction or symlink named Cache must not empty a folder outside the profile.
  if ($item.LinkType -and $item.Target) {
    $target = @($item.Target)[0]
    if (-not [System.IO.Path]::IsPathRooted($target)) {
      $target = Join-Path (Split-Path -Parent $item.FullName) $target
    }
    $full = [System.IO.Path]::GetFullPath($target)
  }
  $roots = @($env:LOCALAPPDATA, $env:APPDATA, $env:USERPROFILE) | Where-Object { $_ }
  $sep = [System.IO.Path]::DirectorySeparatorChar
  foreach ($root in $roots) {
    $prefix = [System.IO.Path]::GetFullPath($root).TrimEnd($sep)
    if ($full.Equals($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($full.StartsWith($prefix + $sep, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
  }
  return $false
}

$script:Actions = @()
$script:Refused = $false

function Add-File {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  if (-not (Test-UnderUser $Path)) { Write-Host "Skipping $Path (outside your profile)."; return }
  $script:Actions += "file|$Path"
  Write-Host "  $Path"
}

function Add-Dir {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
  if (-not (Test-UnderUser $Path)) { Write-Host "Skipping $Path (outside your profile)."; return }
  $script:Actions += "dir|$Path"
  Write-Host "  $Path"
}

function Add-Chromium {
  param([string]$Id, [string]$Label, [string]$Root)
  Write-Host "-- $Label --"
  if (-not (Test-Path -LiteralPath $Root)) { Write-Host "  Not installed ($Root)."; return }
  if (Test-BrowserOpen $Id) {
    Write-Host "  REFUSED: $Label is running. Quit it and run this script again."
    $script:Refused = $true
    return
  }
  $profiles = @()
  $profiles += Join-Path $Root "Default"
  $profiles += @(Get-ChildItem -LiteralPath $Root -Directory -Filter "Profile *" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
  $guest = Join-Path $Root "Guest Profile"
  if (Test-Path -LiteralPath $guest) { $profiles += $guest }
  $found = $false
  foreach ($profile in $profiles) {
    if (-not (Test-Path -LiteralPath $profile -PathType Container)) { continue }
    $found = $true
    Write-Host "  Profile: $profile"
    Add-File (Join-Path $profile "History")
    Add-File (Join-Path $profile "History-journal")
    Add-File (Join-Path $profile "Cookies")
    Add-File (Join-Path $profile "Cookies-journal")
    Add-File (Join-Path $profile "Network\Cookies")
    Add-File (Join-Path $profile "Network\Cookies-journal")
    Add-Dir (Join-Path $profile "Cache")
    Add-Dir (Join-Path $profile "Code Cache")
    Add-Dir (Join-Path $profile "GPUCache")
    Add-Dir (Join-Path $profile "Service Worker\CacheStorage")
  }
  if (-not $found) { Write-Host "  No profiles under $Root." }
}

function Get-FirefoxProfiles {
  $ini = Join-Path $env:APPDATA "Mozilla\Firefox\profiles.ini"
  if (-not (Test-Path -LiteralPath $ini)) { return @() }
  $root = Split-Path -Parent $ini
  $profiles = @()
  $path = ""
  $relative = $true
  foreach ($line in Get-Content -LiteralPath $ini) {
    if ($line -like "Path=*") { $path = $line.Substring(5) }
    elseif ($line -eq "IsRelative=0") { $relative = $false }
    elseif ($line -eq "IsRelative=1") { $relative = $true }
    elseif ($line.StartsWith("[")) {
      if ($path) {
        if ($relative) { $profiles += (Join-Path $root ($path -replace '/', '\')) }
        else { $profiles += $path }
      }
      $path = ""
      $relative = $true
    }
  }
  if ($path) {
    if ($relative) { $profiles += (Join-Path $root ($path -replace '/', '\')) }
    else { $profiles += $path }
  }
  return $profiles
}

function Clear-FirefoxHistory {
  param([string]$Db)
  $sqlVisits = "DELETE FROM moz_historyvisits;"
  $sqlInput = "DELETE FROM moz_inputhistory;"
  $sqlPlaces = "DELETE FROM moz_places WHERE id NOT IN (SELECT fk FROM moz_bookmarks WHERE fk IS NOT NULL) AND (foreign_count = 0 OR foreign_count IS NULL);"
  $sqlite = Get-Command sqlite3 -ErrorAction SilentlyContinue
  if ($sqlite) {
    & sqlite3 $Db $sqlVisits
    & sqlite3 $Db $sqlInput
    & sqlite3 $Db $sqlPlaces
    & sqlite3 $Db "VACUUM;"
    return
  }
  $py = Get-Command python -ErrorAction SilentlyContinue
  if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
  if (-not $py) {
    Write-Host "sqlite3 and python were not found, so Firefox history was left untouched: $Db"
    Write-Host "The file was not deleted, because it also holds bookmarks."
    return
  }
  $code = @"
import sqlite3, sys
db = sys.argv[1]
con = sqlite3.connect(db)
tables = {row[0] for row in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
if "moz_bookmarks" not in tables or "moz_places" not in tables:
    raise SystemExit("not a places database")
con.execute("DELETE FROM moz_historyvisits")
if "moz_inputhistory" in tables:
    con.execute("DELETE FROM moz_inputhistory")
cols = {row[1] for row in con.execute("PRAGMA table_info(moz_places)")}
if "foreign_count" in cols:
    con.execute("DELETE FROM moz_places WHERE id NOT IN (SELECT fk FROM moz_bookmarks WHERE fk IS NOT NULL) AND (foreign_count = 0 OR foreign_count IS NULL)")
else:
    con.execute("DELETE FROM moz_places WHERE id NOT IN (SELECT fk FROM moz_bookmarks WHERE fk IS NOT NULL)")
con.commit()
con.execute("VACUUM")
con.close()
"@
  & $py.Source -c $code $Db
}

Write-Host "== Browser history, cookies, and cache =="
Write-Host "Bookmarks and saved passwords are not deleted."
Write-Host ""

if (Test-Wanted "chrome") {
  Add-Chromium "chrome" "Chrome" (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data")
}
if (Test-Wanted "edge") {
  Add-Chromium "edge" "Edge" (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data")
}
if (Test-Wanted "brave") {
  Add-Chromium "brave" "Brave" (Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data")
}
if (Test-Wanted "firefox") {
  Write-Host "-- Firefox --"
  if (Test-BrowserOpen "firefox") {
    Write-Host "  REFUSED: Firefox is running. Quit it and run this script again."
    $script:Refused = $true
  } else {
    $found = $false
    foreach ($profile in (Get-FirefoxProfiles)) {
      if (-not (Test-Path -LiteralPath $profile -PathType Container)) { continue }
      if (-not (Test-UnderUser $profile)) { Write-Host "Skipping $profile (outside your profile)."; continue }
      $found = $true
      Write-Host "  Profile: $profile"
      $places = Join-Path $profile "places.sqlite"
      if (Test-Path -LiteralPath $places) {
        $script:Actions += "ff|$places"
        Write-Host "  $places"
        Write-Host "    history rows only; bookmarks in this file are kept"
      }
      Add-File (Join-Path $profile "cookies.sqlite")
      Add-File (Join-Path $profile "cookies.sqlite-wal")
      Add-File (Join-Path $profile "cookies.sqlite-shm")
      Add-Dir (Join-Path $profile "cache2")
      Add-Dir (Join-Path $profile "startupCache")
    }
    if (-not $found) { Write-Host "  Not installed (no profiles.ini)." }
  }
}

if ($script:Actions.Count -eq 0) {
  if ($script:Refused) { Write-Host "Nothing was cleared. At least one browser was open."; exit 2 }
  Write-Host "No browser history, cookies, or cache found for the selected browsers."
  exit 0
}
if ($script:Refused) {
  Write-Host "Open browsers were skipped. The paths above are only the browsers that are closed."
}
if ($DryRun) {
  Write-Host "(dry run) Would clear $($script:Actions.Count) path(s). No change made."
  if ($script:Refused) { exit 2 }
  exit 0
}
if (-not (Confirm-Proceed)) { Write-Host "Cancelled."; if ($script:Refused) { exit 2 }; exit 0 }

foreach ($action in $script:Actions) {
  $kind, $path = $action.Split("|", 2)
  if ($kind -eq "file") {
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  } elseif ($kind -eq "dir") {
    Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  } elseif ($kind -eq "ff") {
    Clear-FirefoxHistory $path
  }
}

Write-Host "Done. Closed browsers had history, cookies, and cache cleared."
Write-Host "Local Storage and saved passwords were left alone."
if ($script:Refused) { exit 2 }
