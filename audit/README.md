# Report only

These scripts list what a careful look at the machine would already find. They print **counts
and paths**. They do not print command history, download URLs, or file contents, and they do
not delete anything. `--dry-run` and `--yes` are accepted so the flags match the rest of the
repo; they do not change what the script does.

This does not wipe Windows Event Logs, the USBSTOR key, macOS Spotlight, or Linux login
records. [SECURITY.md](../SECURITY.md) still applies. The clear scripts live in the per-OS
folders and ask before they delete. The Windows audit may need an elevated terminal to read
Prefetch and USBSTOR; if it cannot, it says so instead of pretending the count is zero.

```bash
cd audit
chmod +x *.sh
./audit.sh                 # macOS or Linux
```

```powershell
.\audit-windows.ps1
```

| OS | What is counted | Script |
| --- | --- | --- |
| Windows | Prefetch files, Jump Lists, USBSTOR key paths, recent-item files, Wi-Fi profile names (not passwords) | [audit-windows.ps1](audit-windows.ps1) |
| macOS | QuarantineEvents rows, recent-item files, Quick Look cache, shell-history line counts | [audit-macos.sh](audit-macos.sh) |
| Linux | Thumbnail cache, recent-document entries, shell-history line counts | [audit-linux.sh](audit-linux.sh) |

Thumbnail filenames are hashes, so the Linux report gives the directory, the file count, and the
size rather than tens of thousands of paths. The output names programs and networks. Don't paste
it into a public ticket.
