# Thread: Linux

**Hook**
> Linux feels clean, but your desktop still keeps thumbnails of deleted photos, a list of recent files, and every command you've typed.
>
> Where the traces live and how to clear each one:

**1/ Thumbnail cache**
> GNOME, KDE and most file managers cache image previews in `~/.cache/thumbnails`. A preview can outlive the photo.
> Clear it: `rm -rf ~/.cache/thumbnails/*` (it rebuilds as you browse).

**2/ Recently used files**
> Your recent-documents list lives in `~/.local/share/recently-used.xbel`.
> Clear it: empty that file. In GNOME Files you can also turn off File History in Privacy settings.

**3/ Shell command history**
> `~/.bash_history` or `~/.zsh_history` holds every command, sometimes with paths and secrets. `.viminfo`, `.lesshst` and `.python_history` too.
> Clear it: truncate the files, then `history -c` in the open shell.

**4/ Trash**
> `~/.local/share/Trash` keeps deleted files AND a timestamp of when you binned each one.
> Clear it: empty the files and info subfolders.

**5/ Login and system logs**
> `/var/log/auth.log`, the systemd journal, and `wtmp`/`btmp` record logins, crashes, and daemon activity.
> These are how you catch a break-in, so treat wiping them as deliberate admin work, not routine cleanup. My repo keeps this step separate and admin-only for that reason.

**6/ The real fix**
> Full-disk encryption (LUKS). When the machine is off, every store above is unreadable without your passphrase. Set it at install, or add it later on a spare disk.

**7/ I scripted the cleanup**
> Free, open source. One script per store, previews what it'll delete, asks first. Linux, plus Mac and Windows:
> github.com/anthonyonazure/privacy-sweep
