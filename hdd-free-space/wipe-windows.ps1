<#
.SYNOPSIS
  Opt-in free-space fill for a Windows hard disk, using cipher /w.
.NOTES
  Not part of clear-all or privacy-sweep.ps1. Refuses SSDs and unknown media
  unless -IKnowThisIsSsd (or --i-know-this-is-ssd) is passed. That override
  prints a warning that free-space fill does not reliably erase NAND.
  Does not delete Volume Shadow Copies or other recovery structures.
  -DryRun and -WhatIf print the plan and write nothing.
  -Simulate and PRIVACY_SWEEP_WIPE_SIMULATE=1 are test hooks. They do not
  overwrite free space.
  PRIVACY_SWEEP_CIPHER, if set, is the cipher executable (tests).
  PRIVACY_SWEEP_MEDIA_TYPE=hdd|ssd|unknown overrides disk detection.
  PRIVACY_SWEEP_FREE_BYTES overrides the free-space figure.
#>
param(
  [switch]$DryRun,
  [switch]$WhatIf,
  [switch]$Yes,
  [switch]$IKnowThisIsSsd,
  [switch]$Simulate,
  [string]$Volume = '',
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

if ($WhatIf) { $DryRun = $true }
if ($env:PRIVACY_SWEEP_WIPE_SIMULATE -eq '1') { $Simulate = $true }
if ($Rest) {
  foreach ($item in $Rest) {
    switch ($item) {
      '--i-know-this-is-ssd' { $IKnowThisIsSsd = $true }
      '--simulate' { $Simulate = $true }
      '--dry-run' { $DryRun = $true }
      '--yes' { $Yes = $true }
      default { Write-Host "Unknown option: $item"; exit 1 }
    }
  }
}

if (-not $Volume) { $Volume = 'C:\' }

function Get-FreeBytes {
  param([string]$Path)
  if ($env:PRIVACY_SWEEP_FREE_BYTES) { return [int64]$env:PRIVACY_SWEEP_FREE_BYTES }
  $full = [System.IO.Path]::GetFullPath($Path)
  $root = [System.IO.Path]::GetPathRoot($full)
  $info = New-Object System.IO.DriveInfo $root
  return [int64]$info.AvailableFreeSpace
}

function Get-MediaKind {
  param([string]$VolumePath)
  if ($env:PRIVACY_SWEEP_MEDIA_TYPE) {
    $script:MediaReason = 'override'
    return $env:PRIVACY_SWEEP_MEDIA_TYPE.ToLowerInvariant()
  }
  $script:MediaReason = 'could not determine media type'
  if (-not (Get-Command Get-Partition -ErrorAction SilentlyContinue)) {
    return 'unknown'
  }
  $letter = $null
  if ($VolumePath -match '^([A-Za-z]):') { $letter = $Matches[1] }
  if (-not $letter) { return 'unknown' }
  try {
    $part = Get-Partition -DriveLetter $letter -ErrorAction Stop
    $disk = Get-Disk -Number $part.DiskNumber -ErrorAction Stop
    $phys = @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DeviceId -eq $disk.Number })
    $media = ''
    $bus = ''
    if ($phys.Count -gt 0) {
      $media = [string]$phys[0].MediaType
      $bus = [string]$phys[0].BusType
    } elseif ($disk.BusType) {
      $bus = [string]$disk.BusType
    }
    $script:MediaReason = "MediaType=$media BusType=$bus"
    if ($bus -eq 'NVMe' -or $media -eq 'SSD' -or $media -eq 'SCM') { return 'ssd' }
    if ($media -eq 'HDD') { return 'hdd' }
    return 'unknown'
  } catch {
    $script:MediaReason = 'disk query failed'
    return 'unknown'
  }
}

function Get-CipherCommand {
  if ($env:PRIVACY_SWEEP_CIPHER) { return $env:PRIVACY_SWEEP_CIPHER }
  if ($env:WINDIR) {
    $candidate = Join-Path $env:WINDIR 'System32\cipher.exe'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  }
  $cmd = Get-Command cipher -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

$free = Get-FreeBytes -Path $Volume
$kind = Get-MediaKind -VolumePath $Volume
$rate = 80MB
$minutes = [math]::Floor($free / $rate / 60)
if ($minutes -lt 1) { $rough = 'under 1 minute' } else { $rough = "about $minutes minutes" }

Write-Host "== HDD free-space fill (Windows) =="
Write-Host "Volume: $Volume"
Write-Host "Free bytes: $free"
Write-Host "Estimated impact: up to $free bytes overwritten by cipher /w. Other files are not removed."
Write-Host "Rough time guess: $rough at 80 MiB/s (not a measurement)."
Write-Host "Media: $kind ($MediaReason)"
Write-Host "Tool: cipher /w:$Volume"
Write-Host "Would run: cipher /w:$Volume"
Write-Host "This does not remove Volume Shadow Copies, APFS snapshots, local Time Machine snapshots, or Document Revisions."
Write-Host "WARNING: free-space wiping leaves fingerprints examiners are trained to spot."
Write-Host "cipher /w can leave a directory named EFSTMPWP, or !FSTMPWP if it is interrupted."
Write-Host "SDelete can leave a zero-byte file named SDELTEMP. Some cleaners rename deleted files to a long run of z characters."
Write-Host "Wiping free space is common among ordinary users. The name alone is not proof of wrongdoing."

if ($kind -ne 'hdd' -and -not $IKnowThisIsSsd) {
  Write-Host "Refusing to fill free space: media is $kind ($MediaReason)."
  Write-Host "Free-space fill on an SSD is theater. TRIM, wear leveling, and overprovisioned areas are outside what cipher can reach."
  Write-Host "Nothing was written."
  Write-Host "To override this refusal: -IKnowThisIsSsd"
  exit 2
}

if ($IKnowThisIsSsd -and $kind -ne 'hdd') {
  Write-Host "WARNING: -IKnowThisIsSsd was set."
  Write-Host "Free-space fill on an SSD is theater. It will not reliably erase NAND, and it still leaves a wipe-tool fingerprint. Continuing only because you asked."
}

if ($DryRun) {
  Write-Host "Dry run: nothing was written."
  exit 0
}

if (-not $Yes) {
  $answer = ''
  if ($env:PRIVACY_SWEEP_ASSUME_ANSWER) {
    $answer = $env:PRIVACY_SWEEP_ASSUME_ANSWER
  } elseif ([Console]::IsInputRedirected) {
    $answer = [Console]::In.ReadLine()
  } else {
    $answer = Read-Host "Fill free space on $Volume with cipher /w? [y/N]"
  }
  if ($answer -notmatch '^[Yy]$') {
    Write-Host "Cancelled. Nothing was written."
    exit 0
  }
}

if ($Simulate) {
  Write-Host "SIMULATION: no free-space overwrite was performed."
  Write-Host "SIMULATION: cipher was not run. This does not erase a disk."
} else {
  $cipher = Get-CipherCommand
  if (-not $cipher) {
    Write-Host "cipher was not found. Nothing was written."
    exit 1
  }
  Write-Host "Running: cipher /w:$Volume"
  & $cipher "/w:$Volume"
  if ($LASTEXITCODE -ne 0) {
    Write-Host "cipher exited $LASTEXITCODE"
    exit $LASTEXITCODE
  }
}

Write-Host "-- After the fill: remnant scan --"
$scanner = Join-Path (Split-Path -Parent $PSScriptRoot) 'audit\scan-remnants.ps1'
& $scanner -Root $Volume -MaxDepth 2
Write-Host "Done. cipher does not remove Volume Shadow Copies. Other files were not removed by this script."
