<#
.SYNOPSIS
  Report-only Windows recovery structures: shadow copies, Recycle Bin
  metadata counts, pagefile/hiberfil/MEMORY.DMP, the search index, thumbcache
  databases, wipe-tool remnant names, and BitLocker protection status.
.NOTES
  Deletes nothing. Does not print shadow-copy file contents, $I/$R file
  contents, pagefile bytes, search-index text, or BitLocker keys.
  Set PRIVACY_SWEEP_RECOVERY_ROOT to a fixture tree for tests.
  -DryRun and -Yes are accepted so the flag style matches the other audits.
#>
param([switch]$DryRun, [switch]$Yes, [switch]$Force)

$ErrorActionPreference = 'Continue'

# audit-windows.ps1 already runs this report. A full pass that also executes
# this file (every script in the folder, one PowerShell process) must not
# print the section twice. -Force prints it again. A new process starts over.
if (-not $Force -and -not $env:PRIVACY_SWEEP_RECOVERY_ROOT -and $global:PrivacySweepRecoveryAuditRan) {
  Write-Host "Windows recovery structures were already reported in this run. Skipping the duplicate."
  $global:LASTEXITCODE = 0
  return
}
if ($env:PRIVACY_SWEEP_RECOVERY_ROOT -and $global:PrivacySweepRecoveryAuditRan -and -not $Force) {
  Write-Host "Windows recovery structures were already reported in this run. Skipping the duplicate."
  $global:LASTEXITCODE = 0
  return
}
$global:PrivacySweepRecoveryAuditRan = $true

function Join-Parts {
  param([string]$Base, [string[]]$Parts)
  $path = $Base
  foreach ($part in $Parts) {
    $path = Join-Path $path $part
  }
  return $path
}

if ($DryRun -or $Yes) {
  Write-Host "(flags noted; this script has nothing to apply)"
}

function Get-Presence {
  param([string]$Label, [string]$Path)
  Write-Host "-- $Label --"
  Write-Host "Path: $Path"
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "Present: no"
    Write-Host ""
    return
  }
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if (-not $item) {
    Write-Host "Present: yes (size unreadable)"
    Write-Host "Contents are not read."
    Write-Host ""
    return
  }
  if ($item.PSIsContainer) {
    $sum = 0
    Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
      $sum += $_.Length
    }
    Write-Host "Present: yes (directory)"
    Write-Host "Bytes: $sum"
  } else {
    Write-Host "Present: yes"
    Write-Host "Bytes: $($item.Length)"
  }
  Write-Host "Contents are not read."
  Write-Host ""
}

function Report-ShadowText {
  param([string]$Shadows, [string]$Storage)
  if ($Shadows -match 'Access is denied|requires administrator|elevated') {
    Write-Host "Shadow copies: unreadable (try an elevated terminal)."
    Write-Host ""
    return
  }
  $count = 0
  if ($Shadows) {
    $count = [regex]::Matches($Shadows, 'Shadow Copy ID:').Count
    if ($Shadows -match 'No items found that satisfy the query') { $count = 0 }
  }
  Write-Host "Shadow copies: $count"
  if ($Shadows) {
    foreach ($line in ($Shadows -split "`n")) {
      $trim = $line.Trim()
      if ($trim -like 'Original Volume:*' -or $trim -like 'Shadow Copy Volume:*') {
        Write-Host "  $trim"
      }
    }
  }
  if ($Storage) {
    foreach ($line in ($Storage -split "`n")) {
      $trim = $line.Trim()
      if ($trim -like 'Shadow Copy Storage*' -or $trim -like 'For volume:*' -or
          $trim -like 'Used Shadow*' -or $trim -like 'Allocated Shadow*' -or
          $trim -like 'Maximum Shadow*') {
        Write-Host "  $trim"
      }
    }
  }
  Write-Host ""
}

function Report-BitLockerText {
  param([string]$Text)
  if (-not $Text) {
    Write-Host "BitLocker status: unavailable"
    Write-Host ""
    return
  }
  if ($Text -match 'Access is denied|requires administrator|elevated') {
    Write-Host "BitLocker status: unreadable (try an elevated terminal)."
    Write-Host ""
    return
  }
  $volume = '?'
  $printed = 0
  foreach ($line in ($Text -split "`n")) {
    $trim = $line.Trim()
    if ($trim -match '^Volume\s+(\S+)') {
      $volume = $Matches[1].TrimEnd(':')
    }
    if ($trim -match '^Protection Status:\s*(.+)$') {
      $status = $Matches[1].Trim()
      Write-Host "Volume ${volume}: $status"
      $printed++
    }
  }
  if ($printed -eq 0) {
    Write-Host "BitLocker status: no Protection Status line in the output."
  }
  Write-Host "Recovery passwords and key protectors are not printed."
  Write-Host ""
}

function Report-RecycleBin {
  param([string]$DriveRoot)
  $bin = Join-Path $DriveRoot '$Recycle.Bin'
  Write-Host "Path: $bin"
  if (-not (Test-Path -LiteralPath $bin)) {
    Write-Host "Present: no"
    Write-Host ""
    return
  }
  $sids = @(Get-ChildItem -LiteralPath $bin -Force -Directory -ErrorAction SilentlyContinue)
  if (-not $sids -or $sids.Count -eq 0) {
    $probe = Get-ChildItem -LiteralPath $bin -Force -ErrorAction SilentlyContinue
    if (-not $probe -and -not $?) {
      Write-Host "Unreadable: $bin"
      Write-Host ""
      return
    }
  }
  Write-Host ("SID folders: {0}" -f @($sids).Count)
  foreach ($sid in @($sids)) {
    $iCount = 0
    $rCount = 0
    $rBytes = [int64]0
    $files = @(Get-ChildItem -LiteralPath $sid.FullName -Force -File -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
      if ($file.Name.StartsWith('$I')) { $iCount++ }
      if ($file.Name.StartsWith('$R')) {
        $rCount++
        $rBytes += [int64]$file.Length
      }
    }
    Write-Host "SID folder: $($sid.Name)"
    Write-Host "  `$I count: $iCount"
    Write-Host "  `$R count: $rCount"
    Write-Host "  `$R bytes: $rBytes"
  }
  Write-Host "Metadata file contents (original paths inside `$I files) are not read."
  Write-Host ""
}

function Report-Thumbcache {
  param([string]$ExplorerDir)
  Write-Host "-- Thumbnail cache databases --"
  Write-Host "Path: $ExplorerDir"
  if (-not (Test-Path -LiteralPath $ExplorerDir)) {
    Write-Host "Count: 0 (not present)"
    Write-Host ""
    return
  }
  $dbs = @()
  $bytes = [int64]0
  Get-ChildItem -LiteralPath $ExplorerDir -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -like 'thumbcache_*.db') {
      $dbs += $_
      $bytes += [int64]$_.Length
    }
  }
  Write-Host ("Count: {0}" -f @($dbs).Count)
  Write-Host "Bytes: $bytes"
  Write-Host "Database contents are not read."
  Write-Host ""
}

Write-Host "== Windows recovery structures (report only; nothing deleted) =="
Write-Host ""

$fixture = $env:PRIVACY_SWEEP_RECOVERY_ROOT
if ($fixture) {
  Write-Host "-- Volume Shadow Copies --"
  $shadowPath = Join-Path $fixture 'vssadmin-shadows.txt'
  $storagePath = Join-Path $fixture 'vssadmin-shadowstorage.txt'
  $shadows = ''
  $storage = ''
  if (Test-Path -LiteralPath $shadowPath) { $shadows = Get-Content -LiteralPath $shadowPath -Raw -ErrorAction SilentlyContinue }
  if (Test-Path -LiteralPath $storagePath) { $storage = Get-Content -LiteralPath $storagePath -Raw -ErrorAction SilentlyContinue }
  if (-not $shadows -and -not $storage) {
    Write-Host "vssadmin output was not in the fixture."
    Write-Host ""
  } else {
    Report-ShadowText -Shadows $shadows -Storage $storage
  }

  Write-Host "-- Recycle Bin metadata (`$I / `$R counts) --"
  $drivesDir = Join-Path $fixture 'drives'
  $driveRoots = @()
  if (Test-Path -LiteralPath $drivesDir) {
    $driveRoots = @(Get-ChildItem -LiteralPath $drivesDir -Force -Directory -ErrorAction SilentlyContinue)
  }
  if ($driveRoots.Count -eq 0) {
    Write-Host "No fixture drives."
    Write-Host ""
  }
  foreach ($drive in $driveRoots) {
    Report-RecycleBin -DriveRoot $drive.FullName
  }

  Write-Host "-- Memory residue files (presence and size only) --"
  foreach ($drive in $driveRoots) {
    Get-Presence -Label 'pagefile.sys' -Path (Join-Path $drive.FullName 'pagefile.sys')
    Get-Presence -Label 'hiberfil.sys' -Path (Join-Path $drive.FullName 'hiberfil.sys')
    Get-Presence -Label 'MEMORY.DMP' -Path (Join-Parts $drive.FullName @('Windows', 'MEMORY.DMP'))
  }

  Write-Host "-- Windows Search index --"
  foreach ($drive in $driveRoots) {
    $searchDir = Join-Parts $drive.FullName @('ProgramData', 'Microsoft', 'Search', 'Data', 'Applications', 'Windows')
    Get-Presence -Label 'Windows.edb' -Path (Join-Path $searchDir 'Windows.edb')
    Get-Presence -Label 'Windows.db' -Path (Join-Path $searchDir 'Windows.db')
  }

  $explorer = $null
  foreach ($drive in $driveRoots) {
    $candidate = Join-Parts $drive.FullName @('Users', 'me', 'AppData', 'Local', 'Microsoft', 'Windows', 'Explorer')
    if (Test-Path -LiteralPath $candidate) { $explorer = $candidate }
  }
  if (-not $explorer) { $explorer = Join-Path $fixture 'Explorer' }
  Report-Thumbcache -ExplorerDir $explorer

  $scanner = Join-Path $PSScriptRoot 'scan-remnants.ps1'
  $scanRoots = @()
  foreach ($drive in $driveRoots) { $scanRoots += $drive.FullName }
  if ($scanRoots.Count -eq 0) { $scanRoots = @($fixture) }
  & $scanner -Root $scanRoots -MaxDepth 2

  Write-Host "-- BitLocker (protection status only) --"
  $bdePath = Join-Path $fixture 'manage-bde.txt'
  if (Test-Path -LiteralPath $bdePath) {
    $bde = Get-Content -LiteralPath $bdePath -Raw -ErrorAction SilentlyContinue
    Report-BitLockerText -Text $bde
  } else {
    Write-Host "BitLocker status: fixture file not present"
    Write-Host ""
  }
  Write-Host "Shadow copies, the Recycle Bin, pagefile, hiberfil, and the search index were not deleted."
  return
}

$onWindows = ($env:OS -eq 'Windows_NT')
if (-not $onWindows) {
  Write-Host "This report is for Windows. Detected OS=$($env:OS)."
  $global:LASTEXITCODE = 1
  # exit inside a script invoked with & closes a Windows PowerShell 5.1 session.
  # Exit the process only when this file is the -File target.
  $cmdArgs = [Environment]::GetCommandLineArgs()
  $entry = $false
  for ($i = 0; $i -lt $cmdArgs.Count; $i++) {
    if (($cmdArgs[$i] -eq '-File' -or $cmdArgs[$i] -eq '-f') -and ($i + 1) -lt $cmdArgs.Count) {
      if ((Split-Path -Leaf $cmdArgs[$i + 1]) -eq (Split-Path -Leaf $PSCommandPath)) { $entry = $true }
    }
  }
  if ($entry) { exit 1 }
  return
}

Write-Host "-- Volume Shadow Copies --"
$vss = Get-Command vssadmin -ErrorAction SilentlyContinue
if (-not $vss) {
  Write-Host "vssadmin was not found."
  Write-Host ""
} else {
  $shadows = & vssadmin list shadows 2>&1 | Out-String
  $storage = & vssadmin list shadowstorage 2>&1 | Out-String
  Report-ShadowText -Shadows $shadows -Storage $storage
}

Write-Host "-- Recycle Bin metadata (`$I / `$R counts) --"
$driveRoots = @()
Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object {
  if ($_.Root -match '^[A-Za-z]:\\$') { $driveRoots += $_.Root }
}
if ($driveRoots.Count -eq 0) {
  Write-Host "No drive letters found."
  Write-Host ""
}
foreach ($root in $driveRoots) {
  Report-RecycleBin -DriveRoot $root
}

Write-Host "-- Memory residue files (presence and size only) --"
foreach ($root in $driveRoots) {
  Get-Presence -Label 'pagefile.sys' -Path (Join-Path $root 'pagefile.sys')
  Get-Presence -Label 'hiberfil.sys' -Path (Join-Path $root 'hiberfil.sys')
}
if ($env:WINDIR) {
  Get-Presence -Label 'MEMORY.DMP' -Path (Join-Path $env:WINDIR 'MEMORY.DMP')
}

Write-Host "-- Windows Search index --"
if ($env:ProgramData) {
  $searchDir = Join-Path $env:ProgramData 'Microsoft\Search\Data\Applications\Windows'
  Get-Presence -Label 'Windows.edb' -Path (Join-Path $searchDir 'Windows.edb')
  Get-Presence -Label 'Windows.db' -Path (Join-Path $searchDir 'Windows.db')
} else {
  Write-Host "ProgramData is not set. Search index was not queried."
  Write-Host ""
}

$explorerDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
Report-Thumbcache -ExplorerDir $explorerDir

$scanner = Join-Path $PSScriptRoot 'scan-remnants.ps1'
& $scanner -MaxDepth 2

Write-Host "-- BitLocker (protection status only) --"
if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
  $volumes = @(Get-BitLockerVolume -ErrorAction SilentlyContinue)
  if ($volumes.Count -eq 0) {
    Write-Host "BitLocker status: no volumes returned."
  }
  foreach ($vol in $volumes) {
    # ProtectionStatus only. KeyProtector and RecoveryPassword are not printed.
    Write-Host ("Volume {0}: {1}" -f $vol.MountPoint, $vol.ProtectionStatus)
  }
  Write-Host "Recovery passwords and key protectors are not printed."
  Write-Host ""
} else {
  $bde = Get-Command manage-bde -ErrorAction SilentlyContinue
  if (-not $bde) {
    Write-Host "manage-bde and Get-BitLockerVolume were not found."
    Write-Host ""
  } else {
    $text = & manage-bde -status 2>&1 | Out-String
    Report-BitLockerText -Text $text
  }
}

Write-Host "Shadow copies, the Recycle Bin, pagefile, hiberfil, and the search index were not deleted."
