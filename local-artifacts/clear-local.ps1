<#
.SYNOPSIS
  Opt-in clears for Office MRU, screenshots, clipboard managers, chat caches,
  printer spool, Office temps, DNS, and (separately) event logs and the search index.
.NOTES
  Dry-run unless -Apply. -Yes does not delete. -AllOptIn does not include
  -ClearEventLogs or -ResetSearchIndex.
  Mail files are never deleted. Message DBs (IndexedDB, Local Storage, tdata) are never deleted.
  Phrases: CLEAR EVENT LOGS
           RESET SEARCH INDEX
  Not part of clear-all.
#>
param(
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$Apply,
  [switch]$AllOptIn,
  [switch]$ClearOfficeMru,
  [switch]$ClearRecentDocs,
  [switch]$ClearScreenshots,
  [switch]$ClearClipboardManagers,
  [switch]$ClearNotifications,
  [switch]$ClearPrinterSpool,
  [switch]$ClearOfficeTemps,
  [switch]$FlushDns,
  [switch]$ClearChatCaches,
  [switch]$ClearEventLogs,
  [switch]$ResetSearchIndex
)

$ErrorActionPreference = 'Continue'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\confirm.ps1')

if ($AllOptIn) {
  $ClearOfficeMru = $true
  $ClearRecentDocs = $true
  $ClearScreenshots = $true
  $ClearClipboardManagers = $true
  $ClearNotifications = $true
  $ClearPrinterSpool = $true
  $ClearOfficeTemps = $true
  $FlushDns = $true
  $ClearChatCaches = $true
}

$homeRoot = $env:PRIVACY_SWEEP_HOME_ROOT
if (-not $homeRoot) { $homeRoot = $env:USERPROFILE }
if (-not $homeRoot) { $homeRoot = $env:HOME }

function Test-WillApply { return ($Apply -and -not $DryRun) }

function Clear-CacheDir {
  param([string]$Path)
  $leaf = Split-Path -Leaf $Path
  if (@('Cache', 'GPUCache', 'Code Cache', 'Cache_Data', 'CacheStorage', 'Screenshots', 'Clipboard', 'Notifications', 'PRINTERS', 'Ditto', 'UnsavedFiles') -notcontains $leaf) {
    Write-Host "Refusing unexpected path: $Path"
    return
  }
  if ($leaf -eq 'tdata' -or $leaf -eq 'IndexedDB' -or $leaf -eq 'Local Storage') {
    Write-Host "Refusing message store: $Path"
    return
  }
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "Not present: $Path"
    return
  }
  $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)
  Write-Host "Path: $Path  Files: $($files.Count)"
  if (Test-WillApply) {
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Cleared contents of $Path"
  } else {
    Write-Host "Dry run: would clear contents. Nothing was deleted."
  }
}

Write-Host "== Local artifact clears (Windows, opt-in) =="
Write-Host "Mail stores and chat message databases are not cleared."
Write-Host "Nothing is deleted unless you pass -Apply. -Yes does not delete."
Write-Host "This is not part of clear-all."
Write-Host ""

$any = $ClearOfficeMru -or $ClearRecentDocs -or $ClearScreenshots -or $ClearClipboardManagers -or $ClearNotifications -or $ClearPrinterSpool -or $ClearOfficeTemps -or $FlushDns -or $ClearChatCaches -or $ClearEventLogs -or $ResetSearchIndex
if (-not $any) {
  Write-Host "No clear flag was set."
  Write-Host "Dry run: nothing was deleted."
  $global:LASTEXITCODE = 0
  return
}

if ($ClearScreenshots) {
  Write-Host "-- Screenshots --"
  Clear-CacheDir (Join-Path $homeRoot 'Pictures\Screenshots')
  Write-Host ""
}
if ($ClearClipboardManagers) {
  Write-Host "-- Clipboard managers --"
  $ditto = Join-Path $homeRoot 'Ditto'
  if ($env:APPDATA -and -not $env:PRIVACY_SWEEP_HOME_ROOT) { $ditto = Join-Path $env:APPDATA 'Ditto' }
  Clear-CacheDir $ditto
  $clip = Join-Path $homeRoot 'Clipboard'
  if ($env:LOCALAPPDATA -and -not $env:PRIVACY_SWEEP_HOME_ROOT) { $clip = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Clipboard' }
  # Clipboard's leaf is not in the allowlist. Clear only when the path ends with Clipboard.
  if ((Split-Path -Leaf $clip) -eq 'Clipboard' -and (Test-Path -LiteralPath $clip)) {
    Clear-CacheDir $clip
  } else {
    Write-Host "Not present: $clip"
  }
  Write-Host ""
}
if ($ClearNotifications) {
  Write-Host "-- Notifications --"
  $note = Join-Path $homeRoot 'Notifications'
  if ($env:LOCALAPPDATA -and -not $env:PRIVACY_SWEEP_HOME_ROOT) {
    $note = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Notifications'
  }
  if ((Split-Path -Leaf $note) -eq 'Notifications') { Clear-CacheDir $note }
  Write-Host ""
}
if ($ClearPrinterSpool) {
  Write-Host "-- Printer spool --"
  $spool = Join-Path $homeRoot 'PRINTERS'
  if ($env:WINDIR -and -not $env:PRIVACY_SWEEP_HOME_ROOT) { $spool = Join-Path $env:WINDIR 'System32\spool\PRINTERS' }
  Clear-CacheDir $spool
  Write-Host ""
}
if ($ClearOfficeTemps) {
  Write-Host "-- Office autosave temps --"
  $temp = $env:TEMP
  if ($env:PRIVACY_SWEEP_HOME_ROOT) { $temp = Join-Path $homeRoot 'Temp' }
  if ($temp -and (Test-Path -LiteralPath $temp)) {
    $temps = @(Get-ChildItem -LiteralPath $temp -File -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like '~WRL*' -or $_.Name -like '~$*' -or $_.Name -like '*.asd'
      })
    Write-Host ("Matching files: {0} (names not listed)" -f $temps.Count)
    if (Test-WillApply) {
      foreach ($file in $temps) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue }
      Write-Host "Removed matching temp files."
    } else {
      Write-Host "Dry run: nothing was deleted."
    }
  } else {
    Write-Host "Temp folder not present."
  }
  Write-Host ""
}
if ($ClearChatCaches) {
  Write-Host "-- Chat caches (not message databases) --"
  $chatRoot = $homeRoot
  if ($env:APPDATA -and -not $env:PRIVACY_SWEEP_HOME_ROOT) { $chatRoot = $env:APPDATA }
  foreach ($rel in @('Slack', 'discord', 'Microsoft\Teams', 'Telegram Desktop')) {
    $root = Join-Path $chatRoot $rel
    if (-not (Test-Path -LiteralPath $root)) { Write-Host "Not present: $root"; continue }
    $dirs = @(Get-ChildItem -LiteralPath $root -Recurse -Directory -Force -ErrorAction SilentlyContinue)
    foreach ($dir in $dirs) {
      if (@('Cache', 'GPUCache', 'Code Cache', 'Cache_Data', 'CacheStorage') -contains $dir.Name) {
        Clear-CacheDir $dir.FullName
      }
    }
  }
  Write-Host "IndexedDB, Local Storage, and tdata were not deleted."
  Write-Host ""
}
if ($ClearOfficeMru -or $ClearRecentDocs) {
  Write-Host "-- Office MRU and RecentDocs --"
  $keys = @()
  if ($ClearOfficeMru) {
    $keys += 'HKCU:\Software\Microsoft\Office\16.0\Word\File MRU'
    $keys += 'HKCU:\Software\Microsoft\Office\16.0\Excel\File MRU'
    $keys += 'HKCU:\Software\Microsoft\Office\16.0\PowerPoint\File MRU'
  }
  if ($ClearRecentDocs) {
    $keys += 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs'
  }
  foreach ($key in $keys) {
    Write-Host "Would clear values under $key"
    if (Test-WillApply) {
      if ($env:PRIVACY_SWEEP_REGISTRY_LOG) {
        Add-Content -LiteralPath $env:PRIVACY_SWEEP_REGISTRY_LOG -Value "clear $key"
        Write-Host "SIMULATION: registry was not modified."
      } else {
        try {
          Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop
          Write-Host "Removed $key"
        } catch {
          Write-Host "Could not remove $key. It may be absent. Nothing else was forced."
        }
      }
    } else {
      Write-Host "Dry run: nothing was deleted."
    }
  }
  Write-Host ""
}
if ($FlushDns) {
  Write-Host "-- DNS cache flush --"
  Write-Host "Would run: ipconfig /flushdns"
  Write-Host "The router and any upstream resolver keep their own logs."
  if (Test-WillApply) {
    if ($env:PRIVACY_SWEEP_DNS_LOG) {
      Add-Content -LiteralPath $env:PRIVACY_SWEEP_DNS_LOG -Value 'ipconfig /flushdns'
      Write-Host "SIMULATION: DNS cache was not flushed."
    } else {
      $ip = Get-Command ipconfig -ErrorAction SilentlyContinue
      if ($ip) { & ipconfig /flushdns } else { Write-Host "ipconfig was not found." }
    }
  } else {
    Write-Host "Dry run: nothing was flushed."
  }
  Write-Host ""
}
if ($ClearEventLogs) {
  Write-Host "-- Event logs --"
  Write-Host "WARNING: clearing Event Logs breaks incident response and can break a compliance duty."
  Write-Host "This is not the default. It is not part of clear-all. -AllOptIn does not include it."
  Write-Host "Messages are not printed."
  $channels = @('Application', 'System', 'Security')
  foreach ($channel in $channels) {
    $records = 'unavailable'
    $bytes = 'unavailable'
    try {
      $log = Get-WinEvent -ListLog $channel -ErrorAction Stop
      if ($log) {
        if ($null -ne $log.RecordCount) { $records = $log.RecordCount }
        if ($null -ne $log.FileSize) { $bytes = $log.FileSize }
      }
    } catch {
      $records = 'unavailable'
      $bytes = 'unavailable'
    }
    Write-Host "Channel: $channel  Records: $records  FileSize: $bytes"
    Write-Host "Would run: wevtutil cl $channel"
  }
  if (Test-WillApply) {
    if (Confirm-Phrase "CLEAR EVENT LOGS") {
      if ($env:PRIVACY_SWEEP_WEVTUTIL) {
        foreach ($channel in $channels) {
          Add-Content -LiteralPath $env:PRIVACY_SWEEP_WEVTUTIL -Value "wevtutil cl $channel"
        }
        Write-Host "SIMULATION: event logs were not cleared."
      } else {
        $bin = Get-Command wevtutil -ErrorAction SilentlyContinue
        if (-not $bin) {
          Write-Host "wevtutil was not found. Nothing was cleared."
        } else {
          foreach ($channel in $channels) {
            & $bin.Source cl $channel
            if ($LASTEXITCODE -ne 0) {
              Write-Host "wevtutil cl $channel exited $LASTEXITCODE. Security often needs an elevated terminal. Other channels were still attempted."
            }
          }
        }
      }
    }
  } else {
    Write-Host "Dry run: nothing was cleared."
  }
  Write-Host ""
}
if ($ResetSearchIndex) {
  Write-Host "-- Windows Search index rebuild plan --"
  Write-Host "WARNING: deleting Windows.edb / Windows.db drops the full-text index. Windows rebuilds it by reading files again."
  Write-Host "Plan: removing Windows.edb or Windows.db is what causes Windows to rebuild the index."
  $search = $null
  if ($env:ProgramData) { $search = Join-Path $env:ProgramData 'Microsoft\Search\Data\Applications\Windows' }
  if ($env:PRIVACY_SWEEP_HOME_ROOT) { $search = Join-Path $homeRoot 'Search' }
  $allowed = -not (Test-WillApply)
  if (Test-WillApply) {
    $allowed = Confirm-Phrase "RESET SEARCH INDEX"
    if (-not $allowed) { Write-Host "Nothing was deleted." }
  }
  foreach ($name in @('Windows.edb', 'Windows.db')) {
    if (-not $search) { continue }
    $path = Join-Path $search $name
    Write-Host "Would remove: $path"
    if (Test-WillApply) {
      if (-not $allowed) { continue }
      if ($env:PRIVACY_SWEEP_SEARCH_LOG) {
        Add-Content -LiteralPath $env:PRIVACY_SWEEP_SEARCH_LOG -Value $path
        Write-Host "SIMULATION: index file was not deleted."
      } elseif ((Split-Path -Leaf $path) -eq $name -and (Test-Path -LiteralPath $path)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        Write-Host "Removed $path"
      }
    } else {
      Write-Host "Dry run: nothing was deleted."
    }
  }
  Write-Host ""
}

if (-not (Test-WillApply)) { Write-Host "Dry run: nothing was deleted." }
Write-Host "Mail was not deleted."
$global:LASTEXITCODE = 0
