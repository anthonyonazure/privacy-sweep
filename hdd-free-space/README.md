# Free space on a hard disk

Opt-in only. These scripts are **not** run by `privacy-sweep.sh` or any `clear-all`
script. A normal sweep does not fill free space, and filling free space does not remove
Volume Shadow Copies, APFS snapshots, or Document Revisions.

Read [docs/leave-no-trace.md](../docs/leave-no-trace.md) first. On an SSD, this is the
wrong tool: TRIM, wear leveling, and overprovisioned NAND are outside a file you write.
The scripts refuse SSDs and unknown media unless you pass an override that prints that
warning again.

| How you run it | What happens |
| --- | --- |
| `--dry-run` or `-DryRun` / `-WhatIf` | Prints the volume, free bytes, a rough time guess, and the tool. Writes nothing. |
| no extra flag | Prints the same plan, warns about fingerprints, then asks. The default answer is no. |
| `--yes` or `-Yes` | Skips the question. Still refuses an SSD unless you also override. |

The fingerprint warning is on purpose. `cipher /w` can leave `EFSTMPWP` or `!FSTMPWP`.
SDelete can leave `SDELTEMP`. Some cleaners leave long `z` names. The Linux script uses
a directory named `privacy-sweep-free-space-fill` and removes it when it finishes. The
audit looks for those names afterwards. Wiping free space is common; the name is not
automatic proof of anything.

## Linux

```bash
./wipe-linux.sh --dry-run --volume /mnt/data
./wipe-linux.sh --volume /mnt/data          # asks
./wipe-linux.sh --yes --volume /mnt/data
```

Media type comes from the kernel rotational flag (`1` spinning, `0` SSD). Some virtual
disks report `1` even when the file behind them is not a hard disk. If the flag is
missing, the script refuses. Override, only if you accept the warning:

```bash
./wipe-linux.sh --i-know-this-is-ssd --volume /mnt/data
```

On the root filesystem the fill stops about 128 MiB short so the directory can still be
deleted. If free space does not shrink (a compressed or sparse filesystem), the script
stops and removes the fill file instead of looping. Other files are not deleted.

`--simulate` (or `PRIVACY_SWEEP_WIPE_SIMULATE=1`) is a test hook. It prints
`SIMULATION` and does not overwrite free space. Do not treat that output as a finished
wipe.

## Windows

Run in PowerShell. `-WhatIf` is the same as `-DryRun`.

```powershell
.\wipe-windows.ps1 -DryRun -Volume D:\
.\wipe-windows.ps1 -Volume D:\
.\wipe-windows.ps1 -Yes -Volume D:\
.\wipe-windows.ps1 -IKnowThisIsSsd -Volume C:\
```

`--i-know-this-is-ssd` is accepted as the same override. The tool is `cipher /w` on the
folder you name. This script does not run `vssadmin` delete, and cipher does not clear
shadow copies.

`-Simulate` is the same test hook as on Linux. It does not run cipher.

## macOS

`wipe-macos.sh` only prints this pointer and writes nothing. APFS volumes on Macs are
usually SSDs. Use FileVault, and the retirement steps in the leave-no-trace doc, instead
of a fill file.

```bash
./wipe-macos.sh --dry-run
```
