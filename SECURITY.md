# Responsible use

privacy-sweep clears the history stores your operating system keeps about **your own activity on
your own device**. It is a privacy-hygiene tool, the same category as the built-in Disk Cleanup or
[BleachBit](https://www.bleachbit.org/). Please use it that way.

## Use it for

- Reducing the data footprint on a device you own or administer.
- Preparing a machine to sell, donate, or return.
- Cleaning up after using a shared or public computer you were authorized to use.
- Routine privacy maintenance.

## Do not use it for

- **Destroying records you have a duty to keep.** If you are subject to a legal hold, a preservation
  order, an audit, an active investigation, or a workplace retention policy, deleting these stores
  may be a crime (obstruction / evidence tampering) regardless of what this tool makes easy. When in
  doubt, talk to a lawyer before running anything.
- **Any device you do not own or administer.** Do not run this on someone else's machine, a work
  machine you are not authorized to wipe, or shared infrastructure.
- **Hiding wrongdoing.** That is not privacy; it is a different thing with different consequences.

## What the scripts will and won't do

- Every script previews with `--dry-run` and asks before deleting. Nothing is silent.
- The scripts clear caches, histories, and recent-item lists that the OS rebuilds on its own. They
  deliberately leave system internals alone (Windows Registry and Event Logs, macOS Spotlight and
  system databases, Linux login records) because editing those risks breaking the machine and
  crosses out of privacy hygiene. The audit reports whether Windows execution stores, macOS
  unified logs, knowledgeC, Biome, FSEvents, Linux login-record files, and recovery structures
  (snapshots, shadow copies, swap, encryption status) are present. It does not edit them.
- **The default scripts do not securely overwrite data.** `clear-all` and `privacy-sweep.sh` clear
  named stores. They do not scrub free space, and they do not guarantee unrecoverability. The
  opt-in `hdd-free-space/` module can fill free space on a hard disk. It is not part of
  `clear-all`. It refuses SSDs unless you pass a flag that acknowledges the fill will not
  reliably erase an SSD. It does not remove shadow copies or snapshots.
- For the protection that covers every store at once, use full-disk encryption: FileVault,
  BitLocker, LUKS, or a phone's built-in encryption. When you retire a drive, destroying that
  key (or the drive vendor's erase) is the honest step. This repo will not destroy a key for you.

## Network, browsers, and the audit report

The `network/` scripts are for a Pi-hole, an AdGuard Home, or a LAN you administer. They are
not a scanner for networks that are not yours. Adding blocklists changes DNS for every device
that uses that resolver, so that script previews and changes nothing until you pass `--ask`
or `--yes`. `--adguard` is explicit; an `ADGUARD_URL` alone does not switch the target.
Passwords stay in `PIHOLE_PASSWORD` / `ADGUARD_PASSWORD` or a mode-0600 file, not on the
command line.

Brand lists (HaGeZi Samsung, LG, Roku, Amazon/Fire TV) block more than the combined smart-TV
lists and can stop an account, a channel, or a firmware check. A keep-list of names that
those lists are known to break is allowlisted on every apply and is never added as a block.
That list is not a promise that every app still works. If a TV breaks, disable that list in
the resolver UI and reload gravity or filters.

The audit scripts, `android/audit-permissions.sh`, and `android-tv/audit-tv.sh` only print
counts, paths, sizes, package names, and permission names. The audit also reports whether
Windows execution stores (ShimCache, Amcache, SRUM, BAM/DAM, UserAssist, ShellBags), macOS
unified logs, knowledgeC, Biome, and FSEvents, and Linux login-record files are present. It
does not print the program paths, log lines, or login rows inside them. The Android TV script
does not disable, hide, or uninstall packages, and it is not part of `clear-all`. None of
these reports wipe Windows Event Logs, the USBSTOR registry key, those execution stores,
macOS Spotlight, Linux login records, or anything else this file already puts out of scope.
An audit printout is itself sensitive (program names, network names, installed packages).
Keep it to yourself.

The same audits also **report** recovery structures: Volume Shadow Copy counts, APFS local
snapshot names, Document Revisions size, Recycle Bin `$I`/`$R` counts (not the original
paths inside those files), pagefile/hiberfil/MEMORY.DMP and sleepimage/swap presence and
size, Windows Search index size, thumbcache database counts, wipe-tool remnant **names**,
and FileVault/BitLocker/LUKS **status**. They do not delete any of those, and they do not
print Wi-Fi passwords, encryption keys, or file contents. **Purging shadow copies, local
snapshots, or Document Revisions is not in this repository.** That would destroy backups
and Previous Versions. It is left for a later opt-in tool, and it will not be added to
`clear-all`.

`hdd-free-space/` is opt-in and off by default. Nothing in `privacy-sweep.sh` or the
`clear-all` scripts calls it. A free-space fill does not clear shadow copies or snapshots.
See [docs/leave-no-trace.md](docs/leave-no-trace.md).

Forgetting a saved Wi-Fi network, and clearing browser cookies, are opt-in. They are not part
of `clear-all`. The Wi-Fi scripts leave the network you are joined to alone unless you pass
`--include-current`. The browser scripts leave bookmarks and saved passwords alone, and they
will not touch a browser that is still running, even with `--yes`.

## Reporting

Found a script that deletes more than its description says, needs privileges it shouldn't, or could
harm a system? Open an issue. No warranty is provided (see LICENSE); you are responsible for what you
run.
