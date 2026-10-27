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
  crosses out of privacy hygiene.
- **These scripts do not securely overwrite data.** They clear the stores; they do not scrub free
  space or guarantee unrecoverability. For that, and for the only protection that covers every store
  at once, use full-disk encryption: FileVault, BitLocker, LUKS, or a phone's built-in encryption.

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
counts, paths, package names, and permission names. The Android TV script does not disable,
hide, or uninstall packages, and it is not part of `clear-all`. They do not wipe Windows
Event Logs, the USBSTOR registry key, macOS Spotlight, Linux login records, or anything else
this file already puts out of scope. An audit printout is itself sensitive (program names,
network names, installed packages). Keep it to yourself.

Forgetting a saved Wi-Fi network, and clearing browser cookies, are opt-in. They are not part
of `clear-all`. The Wi-Fi scripts leave the network you are joined to alone unless you pass
`--include-current`. The browser scripts leave bookmarks and saved passwords alone, and they
will not touch a browser that is still running, even with `--yes`.

## Reporting

Found a script that deletes more than its description says, needs privileges it shouldn't, or could
harm a system? Open an issue. No warranty is provided (see LICENSE); you are responsible for what you
run.
