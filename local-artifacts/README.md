# Office MRU, screenshots, clipboard managers, and the other named stores

Registry-analysis texts (Specialized DFIR and the Windows forensics references) look at
Office MRU and RecentDocs because they name files you opened after the Recent folder
was emptied. Thumbnail and screenshot folders are the picture that outlived the
window. Practical Linux Forensics notes persistent clipboard managers (Klipper and
the same idea in other desktops): the OS clipboard clear does not empty them.

This folder is the audit, plus the opt-in clears, for those stores and for the other
section-4 items that did not already have a script: notifications, `.DS_Store`, DNS
cache flush, printer spool, Office autosave temps, chat **caches**, event-log
**sizes**, and the audit-only stores (mail, pcaps, VM memory, Timeline, TCC, ADS).

## What this tool does

`audit-local.sh` and `audit-local.ps1` print presence, counts, sizes, and paths.
They do not print mail bodies, clipboard text, packet contents, MRU paths stored
as registry values, or stream bytes.

`clear-local.sh` and `clear-local.ps1` delete only when you pass a flag **and**
`--apply` / `-Apply`. `--yes` does not delete. `--all-opt-in` turns on the ordinary
clears for a dry run. It does **not** include event-log clearing or the search-index
reset. Those have their own flags and their own typed phrases:

| Flag | Phrase |
| --- | --- |
| `-ClearEventLogs` | `CLEAR EVENT LOGS` |
| `-ResetSearchIndex` | `RESET SEARCH INDEX` |
| `--vacuum-auditd` | `VACUUM AUDIT LOGS` |

Ordinary history that the owning app rebuilds has its own flags and is included in
`--all-opt-in`:

| Flag | What it clears |
| --- | --- |
| `--clear-tool-history` (macOS, Linux) | `.viminfo`, `.lesshst`, and the Python, Node, MySQL, psql, and sqlite history files, plus `.zsh_sessions` and `.bash_sessions`. Shell history, `known_hosts`, and cloud CLI folders are left alone. |
| `-ClearTypedPaths` (Windows) | Explorer address-bar paths, File Explorer search terms, the Win+R Run box, and the open/save dialog history. |
| `-ClearRdpHistory` (Windows) | Remote Desktop recent servers, the saved-server settings, the screen bitmap cache, and `Default.rdp`. Connection files you saved yourself are not touched. |

Windows Recall is not cleared by file deletion. Use Settings > Privacy & security >
Recall & snapshots to delete snapshots or turn it off; the audit reports whether the
data folder exists.

Mail stores (PST, OST, MBOX, Mail.app, Thunderbird) are **never** deleted. There is
no flag for that. Message databases for Teams, Slack, Discord, and Telegram
(`IndexedDB`, `Local Storage`, Telegram `tdata`) are not deleted. Only directories
whose names are caches (`Cache`, `GPUCache`, `Code Cache`, `Cache_Data`,
`CacheStorage`) are eligible.

## What it cannot do

- It cannot rebuild a truthful Timeline or undo an Event Log clear. Event Log
  clearing breaks incident response and some compliance duties. It is opt-in,
  loud, and off the default sweep. Mass wipe is not the default.
- It does not edit TCC.db. That database is which app may use the camera or the
  disk. Changing it to hide a grant is out of scope; clearing it breaks the
  prompts you already answered.
- It does not delete USBSTOR, and it does not rewrite the MFT or `$UsnJrnl`.
  Those are documented as out of scope in [SECURITY.md](../SECURITY.md).
- DNS flush drops the local resolver cache only. The router and the resolver
  still have their own logs.
- `.DS_Store` files come back the next time Finder opens a folder.
- Alternate Data Streams are counted on a shallow pass of Desktop, Documents,
  and Downloads. The stream bytes are not read. NTFS journal carving is not
  something a userspace cleaner can honestly offer.

## Residual risk

Office can recreate the MRU on the next save. Screenshots you synced are in the
cloud. A pcap you leave in Downloads is still a full transcript until you delete
that file yourself; this tool will not delete it for you. Event logs on another
machine, and the USN journal, can still describe what this PC did.
