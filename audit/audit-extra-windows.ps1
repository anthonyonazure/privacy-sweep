<#
.SYNOPSIS
  Report-only inventory of second-tier Windows stores the main audit does not
  cover: Windows Recall, PowerShell history and logging, USB and device
  history beyond USBSTOR, Explorer typed paths and search terms, Remote
  Desktop client history and bitmap cache, Bluetooth pairings, Windows
  Timeline, notifications, registry hive backups, installed-software keys,
  SSH known_hosts, and cloud CLI folders.
.NOTES
  part of privacy-sweep (Windows). Prints presence, counts, and sizes.
  Deletes nothing. Does not print typed paths, search terms, server names,
  device serials, command history, Recall content, or credentials.
  -DryRun and -Yes exist so the flag style matches the other scripts; both
  print the same report.
  Recall paths and the Recall policy name come from public Microsoft
  documentation, not from the Praxis library. Verify them on your build.
#>
param([switch]$DryRun, [switch]$Yes)

$ErrorActionPreference = 'Continue'

Write-Host "== Windows extra artifacts (counts and paths, nothing deleted) =="
Write-Host "Report only. This does not clear these stores."
if ($DryRun -or $Yes) { Write-Host "(flags noted; this script has nothing to apply)" }
Write-Host ""

function Report-File {
  param([string]$Label, [string]$Path)
  Write-Host "-- $Label --"
  Write-Host "Path: $Path"
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "Present: no"
    Write-Host ""
    return
  }
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  Write-Host "Present: yes"
  if ($item) { Write-Host ("Bytes: {0}" -f $item.Length) } else { Write-Host "Bytes: unreadable" }
  Write-Host "Contents are not read."
  Write-Host ""
}

function Report-DirSummary {
  param([string]$Label, [string]$Path)
  Write-Host "-- $Label --"
  Write-Host "Path: $Path"
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "Present: no"
    Write-Host ""
    return
  }
  $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)
  $bytes = ($files | Measure-Object -Property Length -Sum).Sum
  if ($null -eq $bytes) { $bytes = 0 }
  Write-Host "Present: yes"
  Write-Host ("Files: {0}" -f $files.Count)
  Write-Host ("SizeKiB: {0}" -f [math]::Round($bytes / 1KB))
  Write-Host "Names inside this store are not listed."
  Write-Host ""
}

function Report-TextLines {
  param([string]$Label, [string]$Path)
  Write-Host "-- $Label --"
  Write-Host "Path: $Path"
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "Present: no"
    Write-Host ""
    return
  }
  try {
    $n = (Get-Content -LiteralPath $Path -ErrorAction Stop | Measure-Object -Line).Lines
    Write-Host "Present: yes"
    Write-Host ("Lines: {0}" -f $n)
  } catch {
    Write-Host "Present: yes (unreadable from this account)"
  }
  Write-Host "Contents are not printed."
  Write-Host ""
}

function Report-SubkeyCount {
  param([string]$Label, [string]$Path, [string]$Note = '')
  Write-Host "-- $Label --"
  Write-Host "Key: $Path"
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "Present: no"
    Write-Host ""
    return
  }
  try {
    $n = @(Get-ChildItem -LiteralPath $Path -ErrorAction Stop).Count
    Write-Host "Present: yes"
    Write-Host ("Subkeys: {0}" -f $n)
  } catch {
    Write-Host "Present: yes (subkeys unreadable from this account)"
  }
  if ($Note) { Write-Host $Note }
  Write-Host "Key and value names are not printed."
  Write-Host ""
}

function Report-ValueCount {
  param([string]$Label, [string]$Path)
  Write-Host "-- $Label --"
  Write-Host "Key: $Path"
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "Present: no"
    Write-Host ""
    return
  }
  try {
    $key = Get-Item -LiteralPath $Path -ErrorAction Stop
    Write-Host "Present: yes"
    Write-Host ("Values: {0}" -f $key.ValueCount)
    Write-Host ("Subkeys: {0}" -f $key.SubKeyCount)
  } catch {
    Write-Host "Present: yes (unreadable from this account)"
  }
  Write-Host "Value data is not printed."
  Write-Host ""
}

function Report-EventLog {
  param([string]$Label, [string]$Channel)
  Write-Host "-- $Label --"
  Write-Host "Channel: $Channel"
  try {
    $log = Get-WinEvent -ListLog $Channel -ErrorAction Stop
    Write-Host ("Enabled: {0}" -f $log.IsEnabled)
    Write-Host ("Records: {0}" -f $log.RecordCount)
    Write-Host ("Bytes: {0}" -f $log.FileSize)
  } catch {
    Write-Host "Not present, or not readable from this account."
  }
  Write-Host "Event messages are not printed."
  Write-Host ""
}

function Report-Policy {
  param([string]$Label, [string]$Path, [string]$Name)
  Write-Host "-- $Label --"
  Write-Host "Policy: $Path  value $Name"
  try {
    $prop = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
    Write-Host ("Set: {0}" -f $prop.$Name)
  } catch {
    Write-Host "Set: no (not configured by policy)"
  }
  Write-Host ""
}

# ---------------------------------------------------------------------------
Write-Host "### Windows Recall"
Write-Host "Recall takes periodic screenshots and keeps a searchable text database."
Write-Host "Only presence and size are reported. Snapshot content is never read."
Write-Host ""
Write-Host "-- Recall feature state --"
try {
  $feature = Get-WindowsOptionalFeature -Online -FeatureName Recall -ErrorAction Stop
  Write-Host ("State: {0}" -f $feature.State)
} catch {
  Write-Host "State: unknown (needs an elevated terminal, or Recall is not offered on this build)."
}
Write-Host ""
Report-Policy "Recall policy: turn off saving snapshots" 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis'
Report-DirSummary "Recall data folder" (Join-Path $env:LOCALAPPDATA 'CoreAIPlatform.00')
Write-Host "If this folder is present, snapshots and a text index of what was on screen may exist."
Write-Host "Turn Recall off or pause it from Settings > Privacy & security > Recall & snapshots."
Write-Host ""

# ---------------------------------------------------------------------------
Write-Host "### PowerShell history and logging"
Write-Host "Command text is not printed."
Write-Host ""
$psReadLine = Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt'
Report-TextLines "PSReadLine command history" $psReadLine
$docs = [Environment]::GetFolderPath('MyDocuments')
$transcripts = @()
if ($docs -and (Test-Path -LiteralPath $docs)) {
  $transcripts = @(Get-ChildItem -LiteralPath $docs -Filter 'PowerShell_transcript.*' -File -Force -ErrorAction SilentlyContinue)
}
Write-Host "-- PowerShell transcript files in Documents --"
Write-Host ("Count: {0}" -f $transcripts.Count)
Write-Host ""
Report-Policy "Policy: transcription" 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription' 'EnableTranscripting'
Report-Policy "Policy: script block logging" 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' 'EnableScriptBlockLogging'
Report-EventLog "PowerShell operational log (script blocks land here)" 'Microsoft-Windows-PowerShell/Operational'
Report-EventLog "Windows PowerShell log" 'Windows PowerShell'

# ---------------------------------------------------------------------------
Write-Host "### USB and device history beyond USBSTOR"
Write-Host "Device serials and names are not printed. Subkey counts show how many distinct devices left a record."
Write-Host ""
Report-SubkeyCount "USB devices (Enum\USB)" 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB'
Report-SubkeyCount "HID devices (Enum\HID)" 'HKLM:\SYSTEM\CurrentControlSet\Enum\HID' 'Keyboards, mice, and other USB peripherals.'
Report-SubkeyCount "SCSI and UAS storage (Enum\SCSI)" 'HKLM:\SYSTEM\CurrentControlSet\Enum\SCSI'
Report-SubkeyCount "Device classes (Control\DeviceClasses)" 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses'
Report-SubkeyCount "Drives and volumes this user mounted (MountPoints2)" 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2' 'Includes network shares and drive letters this user opened.'
Report-File "Device install log (setupapi.dev.log)" (Join-Path $env:WINDIR 'INF\setupapi.dev.log')
Report-File "Setup log (setupapi.setup.log)" (Join-Path $env:WINDIR 'INF\setupapi.setup.log')
Report-EventLog "Partition diagnostic log" 'Microsoft-Windows-Partition/Diagnostic'
Report-EventLog "Driver framework log" 'Microsoft-Windows-DriverFrameworks-UserMode/Operational'
Report-EventLog "Kernel PnP configuration log" 'Microsoft-Windows-Kernel-PnP/Configuration'
Report-EventLog "Storage service diagnostic log" 'Microsoft-Windows-Storsvc/Diagnostic'
Write-Host "Digital Forensics Cookbook cites Event ID 507 for connected-device information."
Write-Host "The channel was not named in the passage read, so four candidate channels are sized above."
Write-Host ""
Report-SubkeyCount "Bluetooth paired devices" 'HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices' 'This key is often readable only by SYSTEM.'

# ---------------------------------------------------------------------------
Write-Host "### Explorer typed paths, searches, and dialogs"
Write-Host "Typed text is not printed. Counts show how many entries exist."
Write-Host ""
$explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
Report-ValueCount "Typed Explorer address-bar paths (TypedPaths)" "$explorer\TypedPaths"
Report-SubkeyCount "File Explorer search terms (WordWheelQuery)" "$explorer\WordWheelQuery"
Report-ValueCount "Win+R Run box history (RunMRU)" "$explorer\RunMRU"
Report-ValueCount "Recent documents by type (RecentDocs)" "$explorer\RecentDocs"
Report-SubkeyCount "Files opened or saved in dialogs (OpenSavePidlMRU)" "$explorer\ComDlg32\OpenSavePidlMRU"
Report-SubkeyCount "Last folders used in dialogs (LastVisitedPidlMRU)" "$explorer\ComDlg32\LastVisitedPidlMRU"
Report-File "Windows Timeline activity database" (Join-Path $env:LOCALAPPDATA 'ConnectedDevicesPlatform\ActivitiesCache.db')
Report-File "Notification history database" (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Notifications\wpndatabase.db')

# ---------------------------------------------------------------------------
Write-Host "### Remote Desktop client history"
Write-Host "Server names and cached screen images are not printed."
Write-Host ""
$tsc = 'HKCU:\Software\Microsoft\Terminal Server Client'
Report-ValueCount "Recently connected RDP servers (Default)" "$tsc\Default"
Report-SubkeyCount "RDP servers with saved settings (Servers)" "$tsc\Servers"
if ($docs) { Report-File "Saved RDP connection file (Default.rdp)" (Join-Path $docs 'Default.rdp') }
Report-DirSummary "RDP bitmap cache (screen fragments from past sessions)" (Join-Path $env:LOCALAPPDATA 'Microsoft\Terminal Server Client\Cache')
Report-EventLog "RDP client operational log" 'Microsoft-Windows-TerminalServices-RDPClient/Operational'

# ---------------------------------------------------------------------------
Write-Host "### Registry backups and installed-software records"
Write-Host ""
Report-DirSummary "Registry hive backups (RegBack)" (Join-Path $env:WINDIR 'System32\config\RegBack')
Write-Host "Windows 10 1803 and later stop filling RegBack by default; files may be zero bytes."
Write-Host ""
Report-SubkeyCount "Installed programs (Uninstall, 64-bit)" 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
Report-SubkeyCount "Installed programs (Uninstall, 32-bit)" 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
Report-SubkeyCount "WSL distributions" 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'

# ---------------------------------------------------------------------------
Write-Host "### Where you have connected, and cloud tool folders"
Write-Host ""
$userRoot = $env:USERPROFILE
Report-TextLines "SSH known_hosts (one line per host; names not printed)" (Join-Path $userRoot '.ssh\known_hosts')
Report-DirSummary "AWS CLI config folder (credentials not read)" (Join-Path $userRoot '.aws')
Report-DirSummary "Azure CLI config folder (tokens not read)" (Join-Path $userRoot '.azure')
Report-DirSummary "Docker config folder" (Join-Path $userRoot '.docker')

Write-Host "These stores are reported only. Nothing here is deleted by privacy-sweep."
Write-Host "Recall, typed paths, and RDP history can be cleared from Windows settings or the owning app."
