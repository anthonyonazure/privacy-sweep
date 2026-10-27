# privacy-sweep - Linux

Bash scripts that clear the history stores a Linux desktop keeps about you. Works on GNOME, KDE and
most XDG-compliant desktops. Each script is standalone.

## Setup

```bash
cd linux
chmod +x *.sh
```

Preview first:

```bash
./clear-all.sh --dry-run
```

Run for real (asks per step):

```bash
./clear-all.sh
```

No prompts:

```bash
./clear-all.sh --yes
```

## The stores and how each script clears them

| Store | What it remembers | Script | How it clears it |
| --- | --- | --- | --- |
| Thumbnail cache | Image previews, including of deleted files | [clear-thumbnails.sh](clear-thumbnails.sh) | Empties `~/.cache/thumbnails` |
| Recently used | Documents you opened | [clear-recent.sh](clear-recent.sh) | Clears `recently-used.xbel` |
| Trash | Files you deleted | [clear-trash.sh](clear-trash.sh) | Empties `~/.local/share/Trash` |
| Shell history | Commands you typed | [clear-shell-history.sh](clear-shell-history.sh) | Truncates bash/zsh/vim/less/python history |
| Your temp files | Leftover working files | [clear-temp.sh](clear-temp.sh) | Removes files you own in `/tmp` and `/var/tmp` |
| System logs | Logins, crashes, daemon activity | [clear-logs.sh](clear-logs.sh) | **Admin, opt-in.** Vacuums the journal, truncates `/var/log/*.log` |

## Why `clear-logs.sh` is separate

`clear-all.sh` does **not** run `clear-logs.sh`. Files like `/var/log/auth.log` and the systemd
journal are how you diagnose a crash or spot an intruder. Wiping them is legitimate when you
administer the box and are deliberately resetting it, but it is system administration, not everyday
privacy cleanup, so you invoke it on purpose with `sudo`. Do not run it on a machine you do not
administer.

## Other scripts (not part of `clear-all`)

| Script | What it does |
| --- | --- |
| [forget-wifi.sh](forget-wifi.sh) | Lists NetworkManager Wi-Fi profiles and forgets them. Keeps the one you are using unless you pass `--include-current`. |
| [../audit/audit-linux.sh](../audit/audit-linux.sh) | Report only: thumbnail, recent, and shell-history counts, plus swap, LUKS status, and wipe-tool remnant names. |
| [../hdd-free-space/wipe-linux.sh](../hdd-free-space/wipe-linux.sh) | Opt-in free-space fill for a hard disk. Not part of `clear-all`. Refuses SSDs unless you override. |
| [../browsers/clear-browsers.sh](../browsers/clear-browsers.sh) | History, cookies, and cache. Quits if that browser is open. |

## Login records this set does NOT touch

`utmp`, `wtmp`, `btmp` and `lastlog` (the who-logged-in-when records) are managed by the system and
edited only by admins. They are out of scope here on purpose. Swap and LUKS are reported by
the audit (status only, no keys) and are not cleared by these scripts.
