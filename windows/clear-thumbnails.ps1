<#
.SYNOPSIS
  Clears the Windows thumbnail and icon caches (thumbcache_*.db, iconcache_*.db).
  Windows keeps small previews of your files, including photos you later deleted.
.NOTES
  part of privacy-sweep (Windows). Modes: -DryRun (show only), (default) ask
  first, -Yes (no prompt). Explorer restarts when files are actually cleared.
#>
param([switch]$DryRun, [switch]$Yes)
$ErrorActionPreference = 'SilentlyContinue'

function Confirm-Proceed { if ($Yes) { return $true } ; return ((Read-Host "Proceed? [y/N]") -match '^[Yy]$') }

$dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
Write-Host "== Thumbnail & icon cache =="
Write-Host "Target: $dir\thumbcache_*.db and iconcache_*.db"

$files = Get-ChildItem -Path $dir -Filter 'thumbcache_*.db' -File 2>$null
$files += Get-ChildItem -Path $dir -Filter 'iconcache_*.db' -File 2>$null
if (-not $files) { Write-Host "No cache files found. Nothing to do."; return }
$size = [math]::Round((($files | Measure-Object Length -Sum).Sum / 1MB), 1)
Write-Host ("Files: {0}   Size: {1} MB" -f $files.Count, $size)

if ($DryRun) { Write-Host "(dry run) Would delete the files above (Explorer would restart)."; return }
if (-not (Confirm-Proceed)) { Write-Host "Cancelled."; return }

Write-Host "Stopping Explorer so the cache files unlock..."
Stop-Process -Name explorer -Force 2>$null
Start-Sleep -Seconds 1
$files | Remove-Item -Force 2>$null
Start-Process explorer.exe
Write-Host "Done. Caches cleared. They rebuild as you browse folders."
