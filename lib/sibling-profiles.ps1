# Dot-source only. Names and counts of browser and OneDrive data in other
# profiles under the Users directory. Does not read file contents, and does
# not delete anything.

function Join-ProfilePath {
  param([string]$Base, [string]$Rel)
  $parts = New-Object System.Collections.Generic.List[string]
  if ($Base) { [void]$parts.Add($Base) }
  foreach ($piece in ($Rel -split '[\\/]')) {
    if ($piece) { [void]$parts.Add($piece) }
  }
  if ($parts.Count -eq 0) { return '' }
  return [System.IO.Path]::Combine([string[]]$parts.ToArray())
}

function Get-SessionProfile {
  if ($env:USERPROFILE) { return $env:USERPROFILE }
  if ($env:HOME) { return $env:HOME }
  return ''
}

function Get-TargetProfile {
  param([string]$ProfilePath = '')
  if ($ProfilePath) { return $ProfilePath }
  if ($env:PRIVACY_SWEEP_HOME_ROOT) { return $env:PRIVACY_SWEEP_HOME_ROOT }
  return (Get-SessionProfile)
}

function Get-NormalizedPath {
  param([string]$Path)
  if (-not $Path) { return '' }
  $full = $Path
  try { $full = [System.IO.Path]::GetFullPath($Path) } catch { }
  return $full.TrimEnd('\', '/').ToLowerInvariant()
}

function Get-UsersRoot {
  $session = Get-SessionProfile
  if ($session) {
    $parent = Split-Path -Parent $session
    if ($parent) {
      $leaf = Split-Path -Leaf $parent
      if ($leaf -match '^(?i)Users$') { return $parent }
    }
  }
  if (Test-Path -LiteralPath 'C:\Users') { return 'C:\Users' }
  return ''
}

function Get-ChromiumProfileCount {
  param([string]$UserData)
  if (-not $UserData) { return 0 }
  if (-not (Test-Path -LiteralPath $UserData)) { return 0 }
  $n = 0
  foreach ($dir in @(Get-ChildItem -LiteralPath $UserData -Directory -Force -ErrorAction SilentlyContinue)) {
    if ($dir.Name -eq 'Default' -or $dir.Name -like 'Profile *') { $n++ }
  }
  if ($n -eq 0) { return 1 }
  return $n
}

function Get-FirefoxProfileCount {
  param([string]$Root)
  if (-not $Root) { return 0 }
  if (-not (Test-Path -LiteralPath $Root)) { return 0 }
  $ini = Join-ProfilePath $Root 'profiles.ini'
  if (Test-Path -LiteralPath $ini) {
    $n = 0
    foreach ($line in @(Get-Content -LiteralPath $ini -ErrorAction SilentlyContinue)) {
      if ($line -like 'Path=*') { $n++ }
    }
    if ($n -eq 0) { return 1 }
    return $n
  }
  $profilesDir = Join-ProfilePath $Root 'Profiles'
  if (Test-Path -LiteralPath $profilesDir) {
    $dirs = @(Get-ChildItem -LiteralPath $profilesDir -Directory -Force -ErrorAction SilentlyContinue)
    if ($dirs.Count -eq 0) { return 1 }
    return $dirs.Count
  }
  return 0
}

function Get-OneDriveRootCount {
  param([string]$ProfileRoot)
  if (-not $ProfileRoot) { return 0 }
  if (-not (Test-Path -LiteralPath $ProfileRoot)) { return 0 }
  $n = 0
  foreach ($dir in @(Get-ChildItem -LiteralPath $ProfileRoot -Directory -Force -ErrorAction SilentlyContinue)) {
    if ($dir.Name -eq 'OneDrive' -or $dir.Name -like 'OneDrive - *') { $n++ }
  }
  return $n
}

function Get-ProfileStoreCounts {
  param([string]$ProfileRoot)
  $chrome = Get-ChromiumProfileCount (Join-ProfilePath $ProfileRoot 'AppData\Local\Google\Chrome\User Data')
  $edge = Get-ChromiumProfileCount (Join-ProfilePath $ProfileRoot 'AppData\Local\Microsoft\Edge\User Data')
  $firefox = Get-FirefoxProfileCount (Join-ProfilePath $ProfileRoot 'AppData\Roaming\Mozilla\Firefox')
  $oneDrive = Get-OneDriveRootCount $ProfileRoot
  return @{
    Chrome = $chrome
    Edge = $edge
    Firefox = $firefox
    OneDrive = $oneDrive
  }
}

function Write-ForeignProfileWarning {
  param([string]$ProfilePath)
  if (-not $ProfilePath) { return }
  $session = Get-SessionProfile
  if ($session -and ((Get-NormalizedPath $session) -eq (Get-NormalizedPath $ProfilePath))) { return }
  Write-Host "ProfilePath targets another user's profile: $ProfilePath"
  Write-Host "This run audits that profile. Nothing is deleted unless -Apply and the usual typed confirmation are both given."
  Write-Host ""
}

function Write-SiblingProfileNote {
  param([string]$Kind)
  $session = Get-SessionProfile
  if (-not $session) { return }
  $own = Get-ProfileStoreCounts $session
  $ownBrowsers = $own.Chrome + $own.Edge + $own.Firefox
  if ($Kind -eq 'browser' -and $ownBrowsers -gt 0) { return }
  if ($Kind -eq 'cloud' -and $own.OneDrive -gt 0) { return }
  $usersRoot = Get-UsersRoot
  if (-not $usersRoot) { return }
  $sessionNorm = Get-NormalizedPath $session
  $skip = @{
    'public' = $true
    'default' = $true
    'default user' = $true
    'all users' = $true
    'defaultuser0' = $true
    'wdagutilityaccount' = $true
  }
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($dir in @(Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue)) {
    $name = $dir.Name
    if (-not $name) { continue }
    if ($name.StartsWith('.')) { continue }
    if ($skip.ContainsKey($name.ToLowerInvariant())) { continue }
    if ((Get-NormalizedPath $dir.FullName) -eq $sessionNorm) { continue }
    $counts = Get-ProfileStoreCounts $dir.FullName
    $browsers = $counts.Chrome + $counts.Edge + $counts.Firefox
    if ($Kind -eq 'browser' -and $browsers -eq 0) { continue }
    if ($Kind -eq 'cloud' -and $counts.OneDrive -eq 0) { continue }
    [void]$lines.Add((
      "  {0}: Chrome profiles {1}, Edge profiles {2}, Firefox profiles {3}, OneDrive roots {4}" -f `
        $name, $counts.Chrome, $counts.Edge, $counts.Firefox, $counts.OneDrive))
    [void]$lines.Add(("  An elevated dry run can pass -ProfilePath {0} to audit it." -f $dir.FullName))
  }
  if ($lines.Count -eq 0) { return }
  Write-Host "-- Other profiles --"
  if ($Kind -eq 'browser') {
    Write-Host "This session's profile has no browser data: $session"
  } else {
    Write-Host "This session's profile has no OneDrive data: $session"
  }
  Write-Host "Other profiles on this machine do:"
  foreach ($line in $lines) { Write-Host $line }
  Write-Host "Re-run as that user."
  Write-Host "Nothing is deleted unless -Apply and the usual typed confirmation are both given."
  Write-Host ""
}
