# privacy-sweep - Windows

PowerShell scripts that clear the history stores Windows keeps about you. Each script is standalone.

## Setup

Windows blocks unsigned scripts by default. Open **Terminal as Administrator** (right-click Start >
Terminal (Admin)) so Prefetch and system-temp work, then allow scripts for this session only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
cd windows
```

Always preview first:

```powershell
.\clear-all.ps1 -DryRun
```

Run for real (asks before each step):

```powershell
.\clear-all.ps1
```

Run everything with no prompts:

```powershell
.\clear-all.ps1 -Yes
```

## The stores and how each script clears them

| Store | What it remembers | Script | How it clears it | Admin? |
| --- | --- | --- | --- | --- |
| Thumbnail & icon cache | Previews of files, including deleted photos | [clear-thumbnails.ps1](clear-thumbnails.ps1) | Deletes `thumbcache_*.db` / `iconcache_*.db` (restarts Explorer) | No |
| Prefetch | Every program run, with times and counts | [clear-prefetch.ps1](clear-prefetch.ps1) | Deletes `C:\Windows\Prefetch\*.pf` | Yes |
| Recent & Jump Lists | Files you opened, per-app recent menus | [clear-recent.ps1](clear-recent.ps1) | Clears `%APPDATA%\Microsoft\Windows\Recent` | No |
| Temp files | Working files programs leave behind | [clear-temp.ps1](clear-temp.ps1) | Empties `%TEMP%` and (as admin) `C:\Windows\Temp` | Partial |
| Recycle Bin | Deleted files awaiting purge | [clear-recyclebin.ps1](clear-recyclebin.ps1) | `Clear-RecycleBin -Force` | No |
| Clipboard | What you copied, plus Win+V history | [clear-clipboard.ps1](clear-clipboard.ps1) | Empties clipboard; guides you to clear history | No |
| PowerShell history | Every command you typed, kept across restarts | [clear-powershell-history.ps1](clear-powershell-history.ps1) | Empties the PSReadLine history files | No |

## What these scripts deliberately do NOT touch

- **The Registry stores** (USB history, typed paths, most-recently-used keys), **SRUM**,
  **Amcache**, **ShimCache**, **BAM/DAM**, **UserAssist**, **ShellBags**, and the **Event Logs**.
  These are woven into how Windows works; editing them by hand risks breaking the system, and
  wiping Event Logs is a maintenance and security concern rather than privacy hygiene. ShimCache,
  Amcache, SRUM, and BAM/DAM can still show a program run after the program file is gone. The
  audit script reports that those stores are present and does not delete them. Reducing what gets
  written is a Group Policy job, not a delete script.
- **Search index (Windows.edb / Windows.db), pagefile, hiberfil, crash dumps, and Volume Shadow
  Copies.** The clear scripts do not delete these. The audit reports presence, size, or
  shadow-copy counts and does not read their contents. Removing shadow copies deletes
  Previous Versions and restore points; that step is not part of this tool. Turning
  hibernation off (`powercfg /h off`) is a separate Windows setting, not a sweep.

## Other scripts (not part of `clear-all`)

| Script | What it does |
| --- | --- |
| [forget-wifi.ps1](forget-wifi.ps1) | Lists saved Wi-Fi profiles and deletes them with `netsh`. Keeps the one you are joined to unless you pass `-IncludeCurrent`. Does not print the password. |
| [../audit/audit-windows.ps1](../audit/audit-windows.ps1) | Report only: Prefetch, Jump Lists, USBSTOR, recent items, Wi-Fi profile names, execution-store presence (ShimCache, Amcache, SRUM, BAM/DAM, UserAssist, ShellBags), shadow copies, Recycle Bin metadata counts, pagefile/hiberfil/MEMORY.DMP, search index, BitLocker status. |
| [../hdd-free-space/wipe-windows.ps1](../hdd-free-space/wipe-windows.ps1) | Opt-in `cipher /w` for a hard disk. Not part of `clear-all`. Refuses SSDs unless you override. |
| [../browsers/clear-browsers.ps1](../browsers/clear-browsers.ps1) | History, cookies, and cache for Chrome, Edge, Firefox, and Brave. Refuses a browser that is still open. |

## Wi-Fi profile names

`forget-wifi.ps1` and the audit script list profile names. They do not run `key=clear`, so the
password is not printed. To forget a network by hand: Settings > Network & internet > Wi-Fi >
Manage known networks.
