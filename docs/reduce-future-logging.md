# Reduce future logging

This page is advice. It does not change a setting, write a registry value, or create a
file. The cheapest record is the one the system never writes. Turning a switch off does
not erase what was already written. Use the audit to see what is already there, and
[leave-no-trace.md](leave-no-trace.md) for the rest of the layers.

## Telemetry opt-outs

These are Settings and Group Policy switches. privacy-sweep does not flip them.

- **Windows.** Settings > Privacy & security > Diagnostics & feedback. Optional diagnostic
  data can be set to the smaller required set where the edition allows it. Activity history
  (Timeline) is a separate switch. A domain or MDM policy can override both.
- **macOS.** System Settings > Privacy & Security > Analytics & Improvements. Share Mac
  Analytics and Share with App Developers are separate. Siri and dictation history is
  another switch.
- **Linux.** The desktop's "problem reporting" toggle (for example `whoopsie` or a
  distro's equivalent) is the usual one. The systemd journal still records local
  service output. That is an administration log, not a telemetry upload.
- **iOS and Android.** The Settings tables in [ios/README.md](../ios/README.md) and
  [android/README.md](../android/README.md) list the analytics and advertising-ID switches.
  A desktop script cannot reach those stores.

A TV's viewing data is upstream of the PC. Start with the set's own ACR and viewing
settings, then DNS you administer. See [network/pihole-tv/](../network/pihole-tv/). A
Pi-hole log is itself a record.

## Index exclusions

An index is a second copy of names and, for full-text indexes, of file contents.

- **Spotlight.** A volume can be kept out of the index by adding it in System Settings >
  Spotlight > Search Privacy, or by a `.metadata_never_index` file at the volume root.
  That file is a setting you create yourself. No script in this repo creates it.
- **Windows Search.** Indexing Options decides which folders Windows.edb reads. Excluding
  a folder stops new content from being indexed. It does not delete the existing database.
  The opt-in reset in `local-artifacts/clear-local.ps1` (`-ResetSearchIndex`, dry-run
  unless `-Apply`, and a typed phrase) is a separate decision and is not part of
  `clear-all`.
- **Linux.** Tracker / localsearch and the desktop's recent-files list are the usual
  equivalents. Disabling the indexer is a desktop setting.

## What still gets written

Shell history, browser profiles, cloud-sync clients, and the filesystem journal keep
their own logs. Excluding a folder from Spotlight does not stop iCloud, OneDrive,
Dropbox, or Google Drive from uploading it. Clearing the local sync cache does not
clear the account. The checklist is in [cloud-sync/README.md](../cloud-sync/README.md).

Full-disk encryption (FileVault, BitLocker, LUKS) is the control that covers the copies
this page cannot stop. See [SECURITY.md](../SECURITY.md).
