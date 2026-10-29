# What examiners look for after a wipe

This page describes artifacts that trained examiners already know how to see. It is not
a guide to hiding activity. privacy-sweep does not timestomp, does not plant decoy
history, and does not mutilate the filesystem journal. Those actions are themselves
evidence, and they are out of scope.

## A missing store is a store

Ordinary use leaves Prefetch, shell history, a journal, recent items, and a search
index. A machine whose history is empty, whose timestamps jump, or whose one log was
cleared while the others were left, is easy to describe. The [audit](../audit/) exists
so you can see the set. It is not a kit for inventing a different past.

## Wipe-tool names

Free-space tools leave names when they are interrupted, and sometimes when they finish.
People who do this work are taught to look for `EFSTMPWP` and `!FSTMPWP` (`cipher /w`),
`SDELTEMP` (SDelete), a long run of `z` characters, and this repo's
`privacy-sweep-free-space-fill` directory if a Linux fill did not finish. The audit's
remnant scan reports those names at a shallow depth. It does not delete them and does
not read them. Finding one of these names is common among people who sold a computer.
Stacked with other changes, it is one more thing a careful person will notice.

## Timestamps and decoys

Changing a file's timestamps so it looks older does not change the other copies of that
time: the journal, the USN change journal on NTFS, Spotlight, a snapshot, or a backup.
Examiners compare those copies. A planted Prefetch entry or a fake UserAssist count that
does not line up with the rest of the system is a signal of its own. This repository
does not write decoys, and you should not either.

## Journals and the USN change journal

`$MFT` and `$UsnJrnl` record that files were created, renamed, and deleted. Userspace
mutilation of those structures is out of scope. It is easy to detect (a torn journal, a
sequence that restarts) and it can make the volume unmountable. The Linux systemd
journal can be sealed so a rewrite is visible. `auditd` is the same kind of trail.
`--vacuum-auditd` is opt-in, needs a typed phrase, and is not part of `clear-all`.

## Event logs, USB history, and keys

Clearing Windows Event Logs breaks incident response and can break a duty to keep
records. The default sweep does not do it. `local-artifacts/clear-local.ps1
-ClearEventLogs` is a separate opt-in with the phrase `CLEAR EVENT LOGS`. It is not
included in `-AllOptIn` or `clear-all`. The audit reports channel sizes and does not
print messages.

USBSTOR device subkeys are ACL'd to `NT AUTHORITY\SYSTEM`. An elevated terminal still
cannot list them, and this repo will not take ownership of that key. Deleting USB
history is not a default action.

Keychain extraction, password-vault extraction, and mass deletion of login records
(`utmp`, `wtmp`, `btmp`, `lastlog`) are out of scope. The audits report presence and
size only.

## What actually reduces what an examiner can read

Full-disk encryption for the life of the disk, and destroying that key (or the drive
vendor's erase) when you retire the drive. A free-space fill on an SSD does not do
that. See [leave-no-trace.md](leave-no-trace.md) and [SECURITY.md](../SECURITY.md).
