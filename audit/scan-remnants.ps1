<#
.SYNOPSIS
  Report-only names left behind by free-space wipe tools.
.NOTES
  Prints matching paths. Does not delete anything and does not read contents.
  Patterns: EFSTMPWP, !FSTMPWP, SDELTEMP, privacy-sweep-free-space-fill,
  and names of eight or more z's. Depth is shallow (default 2).
#>
param(
  [string[]]$Root,
  [int]$MaxDepth = 2
)

$ErrorActionPreference = 'Continue'

function Test-RemnantName {
  param([string]$Name)
  if ($Name.StartsWith('EFSTMPWP')) { return $true }
  if ($Name.StartsWith('!FSTMPWP')) { return $true }
  if ($Name.StartsWith('SDELTEMP')) { return $true }
  if ($Name.StartsWith('privacy-sweep-free-space-fill')) { return $true }
  if ($Name -match '^(?i)z{8,}') { return $true }
  return $false
}

function Get-RemnantPaths {
  param([string]$Dir, [int]$CurrentDepth, [int]$Limit)
  if ($CurrentDepth -ge $Limit) { return }
  if (-not (Test-Path -LiteralPath $Dir)) { return }
  $children = @(Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue)
  foreach ($item in $children) {
    if (Test-RemnantName $item.Name) {
      $item.FullName
    }
    if (-not $item.PSIsContainer) { continue }
    $reparse = [IO.FileAttributes]::ReparsePoint
    if (($item.Attributes -band $reparse) -ne 0) { continue }
    Get-RemnantPaths -Dir $item.FullName -CurrentDepth ($CurrentDepth + 1) -Limit $Limit
  }
}

$roots = @()
if ($Root -and $Root.Count -gt 0) {
  $roots = @($Root)
} elseif ($env:PRIVACY_SWEEP_RECOVERY_ROOT) {
  $roots = @($env:PRIVACY_SWEEP_RECOVERY_ROOT)
} else {
  Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Root -match '^[A-Za-z]:\\$') { $roots += $_.Root }
  }
  foreach ($extra in @($env:TEMP, $env:TMP, $env:LOCALAPPDATA)) {
    if ($extra) { $roots += $extra }
  }
}

$found = @()
foreach ($one in $roots) {
  if (-not $one) { continue }
  $found += @(Get-RemnantPaths -Dir $one -CurrentDepth 0 -Limit $MaxDepth)
}
$unique = @($found | Sort-Object -Unique)

Write-Host "-- Wipe-tool remnants --"
Write-Host "Patterns: EFSTMPWP, !FSTMPWP, SDELTEMP, privacy-sweep-free-space-fill, names of eight or more z's."
Write-Host "Scope: depth $MaxDepth from each root. Not a full-disk search. Contents are not read."
Write-Host ("Count: {0}" -f $unique.Count)
foreach ($path in $unique) {
  Write-Host ("  {0}" -f $path)
}
Write-Host ""
