# privacy-sweep - macOS

Bash scripts that clear the history stores macOS keeps about you. Tested on macOS 26. Each script is
standalone: download one and run it, or run them all with `clear-all.sh`.

## Setup

```bash
cd macos
chmod +x *.sh
```

Then always try `--dry-run` first to see what a script would touch:

```bash
./clear-quarantine.sh --dry-run
```

Run it for real (it asks before deleting):

```bash
./clear-quarantine.sh
```

Run everything without prompts:

```bash
./clear-all.sh --yes
```

## The stores and how each script clears them

| Store | What it remembers | Script | How it clears it |
| --- | --- | --- | --- |
| Quick Look cache | Thumbnail previews of files, including ones you deleted | [clear-quicklook.sh](clear-quicklook.sh) | `qlmanage -r cache` |
| Download log | Every file downloaded and the URL it came from | [clear-quarantine.sh](clear-quarantine.sh) | Deletes all rows from the QuarantineEventsV2 database |
| Recent items | Recent documents, apps, servers, Open Recent menus | [clear-recent.sh](clear-recent.sh) | Removes the sharedfilelist files, restarts Finder and Dock |
| Trash | Files you sent to the Trash | [clear-trash.sh](clear-trash.sh) | Empties `~/.Trash` |
| Shell history | Every Terminal command you typed | [clear-shell-history.sh](clear-shell-history.sh) | Truncates the zsh/bash history files |
| Clipboard | What you last copied, plus optional history | [clear-clipboard.sh](clear-clipboard.sh) | Empties the pasteboard |

## What these scripts deliberately do NOT touch

- **Spotlight index, unified logs, knowledgeC.db, Biome.** These are protected by System Integrity
  Protection and/or needed by the OS. macOS trims them on its own, and fighting them by hand risks
  breaking Spotlight or Screen Time. There is no safe user-space script for them.
- **Keychain.** Your saved passwords. Clearing it would lock you out of Wi-Fi and apps. Manage it in
  the Passwords app instead.
- **APFS snapshots and Time Machine.** Managed with `tmutil`; out of scope here so a stray run can't
  destroy your backups.

## Manual step scripts can't do well

Photos keeps deleted images for 30 days in **Recently Deleted**. Open Photos, go to Recently
Deleted, and choose Delete All.
