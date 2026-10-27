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

function Get-OneDriveFolderCounts {
  param([string]$ProfileRoot)
  $consumer = 0
  $business = 0
  if ($ProfileRoot -and (Test-Path -LiteralPath $ProfileRoot)) {
    foreach ($dir in @(Get-ChildItem -LiteralPath $ProfileRoot -Directory -Force -ErrorAction SilentlyContinue)) {
      if ($dir.Name -eq 'OneDrive') { $consumer++ }
      elseif ($dir.Name -like 'OneDrive - *') { $business++ }
    }
  }
  return ,@{ Consumer = $consumer; Business = $business }
}

function Get-SharePointRootCount {
  param([string]$ProfileRoot)
  if (-not $ProfileRoot) { return 0 }
  $settings = Join-ProfilePath $ProfileRoot 'AppData\Local\Microsoft\OneDrive\settings'
  if (-not (Test-Path -LiteralPath $settings)) { return 0 }
  $n = 0
  foreach ($dir in @(Get-ChildItem -LiteralPath $settings -Directory -Force -ErrorAction SilentlyContinue)) {
    if ($dir.Name -notlike 'Business*') { continue }
    foreach ($file in @(Get-ChildItem -LiteralPath $dir.FullName -File -Force -ErrorAction SilentlyContinue)) {
      if ($file.Length -gt 262144) { continue }
      foreach ($line in @(Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)) {
        if ($line -like 'libraryFolder=*' -or $line -like 'LibraryFolder=*' -or $line -like 'MountPoint=*') {
          $n++
        }
      }
    }
  }
  return $n
}

function Get-ProfileStoreCounts {
  param([string]$ProfileRoot)
  $chrome = Get-ChromiumProfileCount (Join-ProfilePath $ProfileRoot 'AppData\Local\Google\Chrome\User Data')
  $edge = Get-ChromiumProfileCount (Join-ProfilePath $ProfileRoot 'AppData\Local\Microsoft\Edge\User Data')
  $firefox = Get-FirefoxProfileCount (Join-ProfilePath $ProfileRoot 'AppData\Roaming\Mozilla\Firefox')
  $folders = Get-OneDriveFolderCounts $ProfileRoot
  $consumer = $folders.Consumer
  $business = $folders.Business
  $sharePoint = Get-SharePointRootCount $ProfileRoot
  return @{
    Chrome = $chrome
    Edge = $edge
    Firefox = $firefox
    Consumer = $consumer
    Business = $business
    SharePoint = $sharePoint
    OneDrive = ($consumer + $business)
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
  param([string]$Kind, [string]$ProfilePath = '')
  $session = Get-SessionProfile
  if (-not $session) { return }
  $own = Get-ProfileStoreCounts $session
  $ownBrowsers = $own.Chrome + $own.Edge + $own.Firefox
  if ($Kind -eq 'browser' -and $ownBrowsers -gt 0) { return }
  if ($Kind -eq 'cloud' -and $own.Consumer -gt 0 -and $own.Business -gt 0 -and $own.SharePoint -gt 0) { return }
  $usersRoot = Get-UsersRoot
  if (-not $usersRoot) { return }
  $sessionNorm = Get-NormalizedPath $session
  $targetNorm = ''
  if ($ProfilePath) { $targetNorm = Get-NormalizedPath $ProfilePath }
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
    $dirNorm = Get-NormalizedPath $dir.FullName
    if ($dirNorm -eq $sessionNorm) { continue }
    if ($targetNorm -and $dirNorm -eq $targetNorm) { continue }
    $counts = Get-ProfileStoreCounts $dir.FullName
    $browsers = $counts.Chrome + $counts.Edge + $counts.Firefox
    if ($Kind -eq 'browser' -and $browsers -eq 0) { continue }
    if ($Kind -eq 'cloud') {
      $missing = $false
      if ($own.Consumer -eq 0 -and $counts.Consumer -gt 0) { $missing = $true }
      if ($own.Business -eq 0 -and $counts.Business -gt 0) { $missing = $true }
      if ($own.SharePoint -eq 0 -and $counts.SharePoint -gt 0) { $missing = $true }
      if (-not $missing) { continue }
    }
    [void]$lines.Add((
      "  {0}: Chrome profiles {1}, Edge profiles {2}, Firefox profiles {3}, OneDrive roots {4}, OneDrive for Business roots {5}, SharePoint roots {6}" -f `
        $name, $counts.Chrome, $counts.Edge, $counts.Firefox, $counts.Consumer, $counts.Business, $counts.SharePoint))
    [void]$lines.Add(("  An elevated dry run can pass -ProfilePath {0} to audit it." -f $dir.FullName))
  }
  if ($lines.Count -eq 0) { return }
  Write-Host "-- Other profiles --"
  if ($Kind -eq 'browser') {
    Write-Host "This session's profile has no browser data: $session"
  } elseif ($own.Consumer -eq 0 -and $own.Business -eq 0 -and $own.SharePoint -eq 0) {
    Write-Host "This session's profile has no OneDrive data: $session"
  } else {
    $gaps = @()
    if ($own.Consumer -eq 0) { $gaps += 'OneDrive' }
    if ($own.Business -eq 0) { $gaps += 'OneDrive for Business' }
    if ($own.SharePoint -eq 0) { $gaps += 'SharePoint' }
    if ($gaps.Count -eq 0) { $gaps += 'OneDrive' }
    $gapText = $gaps -join ' or '
    Write-Host "This session's profile has no $gapText roots: $session"
  }
  Write-Host "Other profiles on this machine do:"
  foreach ($line in $lines) { Write-Host $line }
  Write-Host "Re-run as that user."
  Write-Host "Nothing is deleted unless -Apply and the usual typed confirmation are both given."
  Write-Host ""
}
