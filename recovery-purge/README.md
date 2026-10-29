# Opt-in purge of recovery structures

Examiners treat these stores as time capsules. A normal delete, and even a free-space
fill, does not remove them. Digital Forensics Cookbook and ransomware-recovery material
describe Volume Shadow Copies as the place a previous copy of a file still lives.
macOS forensics material describes APFS local snapshots (including local Time Machine
snapshots) the same way, and Document Revisions (`.DocumentRevisions-V100`) as hourly
prior versions of documents.

## What this tool does

It **lists** what the recovery audit already lists, then, only if you pass the matching
flag **and** `--apply` (or `-Apply`) **and** type the confirmation phrase, it deletes
that one store:

| Flag | Phrase you must type | What it runs |
| --- | --- | --- |
| `--purge-apfs-localsnapshots` | `DELETE LOCAL SNAPSHOTS` | `tmutil deletelocalsnapshots` for each local snapshot date |
| `--purge-document-revisions` | `DELETE DOCUMENT REVISIONS` | contents of `.DocumentRevisions-V100` only |
| `-PurgeVss` | `DELETE SHADOW COPIES` | `vssadmin delete shadows /all /quiet`, or `wmic shadowcopy delete` if `vssadmin` is missing |

Without `--apply` / `-Apply` the script is a dry run, including when you pass `--yes` /
`-Yes`. `--yes` does not skip the typed phrase.

```bash
./purge-macos.sh --dry-run --purge-apfs-localsnapshots
./purge-macos.sh --purge-apfs-localsnapshots --apply
```

```powershell
.\purge-vss.ps1 -DryRun -PurgeVss
.\purge-vss.ps1 -PurgeVss -Apply
```

## What it cannot do

- It is **not** part of `clear-all` or `privacy-sweep.sh` unless you are in the
  report-only `--all-modules` dry run, which still does not pass `--apply`.
- It does not fill free space and does not destroy a full-disk encryption key.
- It will not `sudo` for you. The system Document Revisions store and shadow copies
  need an administrator. If the command is refused, the files stay.
- Snapshot dates come from `tmutil`. If `tmutil` is missing, nothing is deleted.

## Residual risk

Purging these destroys backups, Previous Versions, and a common ransomware-recovery
path. After they are gone, copies can still exist in cloud accounts, mail, other
devices, and on an SSD in pages the operating system cannot address. People who do
this work are also trained to notice that the snapshots are simply missing.
