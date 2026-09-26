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
| Thumbnail cache | Image previews, including of deleted files | [/Users/anthony/Projects/privacy-sweep/linux/clear-thumbnails.sh](clear-thumbnails.sh) | Empties `~/.cache/thumbnails` |
| Recently used | Documents you opened | [/Users/anthony/Projects/privacy-sweep/linux/clear-recent.sh](clear-recent.sh) | Clears `recently-used.xbel` |
| Trash | Files you deleted | [/Users/anthony/Projects/privacy-sweep/linux/clear-trash.sh](clear-trash.sh) | Empties `~/.local/share/Trash` |
| Shell history | Commands you typed | [/Users/anthony/Projects/privacy-sweep/linux/clear-shell-history.sh](clear-shell-history.sh) | Truncates bash/zsh/vim/less/python history |
| Your temp files | Leftover working files | [/Users/anthony/Projects/privacy-sweep/linux/clear-temp.sh](clear-temp.sh) | Removes files you own in `/tmp` and `/var/tmp` |
| System logs | Logins, crashes, daemon activity | [/Users/anthony/Projects/privacy-sweep/linux/clear-logs.sh](clear-logs.sh) | **Admin, opt-in.** Vacuums the journal, truncates `/var/log/*.log` |

## Why `clear-logs.sh` is separate

`clear-all.sh` does **not** run `clear-logs.sh`. Files like `/var/log/auth.log` and the systemd
journal are how you diagnose a crash or spot an intruder. Wiping them is legitimate when you
administer the box and are deliberately resetting it, but it is system administration, not everyday
privacy cleanup, so you invoke it on purpose with `sudo`. Do not run it on a machine you do not
administer.

## Login records this set does NOT touch

`utmp`, `wtmp`, `btmp` and `lastlog` (the who-logged-in-when records) are managed by the system and
edited only by admins. They are out of scope here on purpose.
