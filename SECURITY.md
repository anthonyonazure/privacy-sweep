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

## Reporting

Found a script that deletes more than its description says, needs privileges it shouldn't, or could
harm a system? Open an issue. No warranty is provided (see LICENSE); you are responsible for what you
run.
