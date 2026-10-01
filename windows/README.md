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
  **Amcache**, **ShimCache**, and the **Event Logs**. These are woven into how Windows works;
  editing them by hand risks breaking the system, and wiping Event Logs is a maintenance and
  security concern rather than privacy hygiene. Reducing what gets written is a Group Policy job,
  not a delete script.
- **Search index (Windows.edb), pagefile, hiberfil.** Managed by Windows. Turn hibernation off with
  `powercfg /h off` if you want the hiberfil gone; that is a deliberate setting, not a sweep.

## Wi-Fi passwords (view, not clear)

To see saved network passwords: `netsh wlan show profiles`, then
`netsh wlan show profile name="NETWORK" key=clear` and read the Key Content line. To forget a
network: Settings > Network & internet > Wi-Fi > Manage known networks.
