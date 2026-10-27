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
| Windows | Prefetch files, Jump Lists, USBSTOR key paths, recent-item files, Wi-Fi profile names (not passwords), plus execution stores: ShimCache/AppCompatCache, Amcache.hve, SRUM (`SRUDB.dat`), BAM/DAM, UserAssist, and ShellBags. Also shadow-copy counts, Recycle Bin `$I`/`$R` counts, pagefile/hiberfil/MEMORY.DMP size, search-index size, thumbcache database counts, wipe-tool remnant names, BitLocker protection status | [audit-windows.ps1](audit-windows.ps1) |
| macOS | QuarantineEvents rows, recent-item files, Quick Look cache, shell-history line counts, unified logs under `/private/var/db/diagnostics`, knowledgeC.db, Biome, and FSEvents. Also local snapshots, Document Revisions size, external `.Trashes` counts, sleepimage/swap size, FileVault on/off | [audit-macos.sh](audit-macos.sh) |
| Linux | Thumbnail cache, recent-document entries (including `recently-used.xbel`), shell-history line counts, screenshot folders, systemd journal size, `wtmp` / `lastlog` / `btmp` size, and whether a user crontab exists. Also swap, LUKS status (no keys), wipe-tool remnant names | [audit-linux.sh](audit-linux.sh) |

`recently-used.xbel` was already part of the Linux recent-files section. It is still one count of
bookmark entries, and the URIs inside it are still not printed.

ShimCache, Amcache, SRUM, BAM, and DAM record that a program ran, and they can keep doing so
after the program file has been deleted. UserAssist and ShellBags are the same kind of leftover
for launches and for folders you opened. privacy-sweep **reports** those stores. It does not
delete them, which matches [SECURITY.md](../SECURITY.md): registry execution history and login
records stay out of the clear scripts. The Windows report prints the key or file path, whether
it is present, and a count or a size. It does not print the program paths, folder names, or
usage rows stored inside. macOS unified logs, knowledgeC, Biome, and FSEvents are presence and
size only; log lines and changed paths are not printed. Linux login records are the file and
its size, not who logged in. A crontab is reported as present or absent, not as a list of
commands. Screenshot folders are a path, a file count, and a size, not each file name.

Several of the Windows and macOS paths need an elevated terminal or a system account. If this
account cannot read them, the script says so. It does not turn "access denied" into a count of
zero.

Recovery structures (shadow copies, local snapshots, Document Revisions, swap, pagefile,
encryption status, wipe-tool remnant names) are reported by the same scripts and are not
deleted. Purging them is not part of this repo. Free-space fill is a separate opt-in module
and is not run from here. See [docs/leave-no-trace.md](../docs/leave-no-trace.md).

Thumbnail filenames are hashes, so the Linux report gives the directory, the file count, and the
size rather than tens of thousands of paths. The output can still name programs and networks.
Don't paste it into a public ticket.

## What cleaning cannot do

A normal delete marks the space as free. Until some later write uses that space, the old bytes
can still be read back. These scripts do not overwrite free space, so they do not close that gap.

An SSD does not behave like a spinning disk. TRIM tells the drive it may erase discarded blocks
on the drive's own schedule. Data sometimes disappears sooner than it would on a hard disk, and
sometimes a copy remains in space the operating system cannot address. No delete command you run
as a user makes those two results the same.

Filling a file with zeros, or setting its timestamps back, is visible in its own right. The
overwrite and the clock change become part of what an examiner can describe.

An artifact that is simply missing can stand out as well. A machine with no Prefetch, an empty
shell history, and no journal does not look like a machine that was used and then left as it was.
This report is here so you can see what is still present. It is not a way to make the machine
look unused.
