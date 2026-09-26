# Thread: Linux

**1/ (hook + link)**
> Linux feels clean, but your desktop still keeps thumbnails of deleted photos, a list of recent files, every command you've typed, and your saved passwords in a keyring.
>
> I open-sourced scripts that clear it: github.com/anthonyonazure/privacy-sweep
>
> Prefer to do it by hand? Here's each one:

**2/ Thumbnail cache**
> GNOME, KDE and most file managers cache image previews in `~/.cache/thumbnails`. A preview can outlive the photo it came from.
> Clear it: `rm -rf ~/.cache/thumbnails/*` (it rebuilds as you browse).

**3/ Recently used files**
> Your recent-documents list lives in `~/.local/share/recently-used.xbel`.
> Clear it: `: > ~/.local/share/recently-used.xbel`. In GNOME Files you can also turn off File History under Privacy.

**4/ Shell command history**
> `~/.bash_history` or `~/.zsh_history` holds every command, sometimes with paths and secrets. `.viminfo`, `.lesshst`, `.python_history` too.
> Clear it: `: > ~/.bash_history` (or `.zsh_history`), then `history -c` in the open shell.

**5/ Trash (with timestamps)**
> `~/.local/share/Trash` keeps deleted files AND a record of exactly when you binned each one.
> Clear it: `rm -rf ~/.local/share/Trash/files/* ~/.local/share/Trash/info/*`.

**6/ Your browser**
> History, cookies and cache all persist. In Chrome or Firefox press Ctrl+Shift+Delete, set the range to All / Everything, tick all types, clear.

**7/ Saved passwords & location history**
> GNOME Keyring / KDE Wallet store app and Wi-Fi passwords; the desktop can also keep a location history via GeoClue.
> Manage the keyring in Seahorse ("Passwords and Keys"). Turn off location: Settings > Privacy > Location Services.

**8/ System & login logs**
> `/var/log/auth.log`, the systemd journal, and `wtmp`/`btmp` record logins, crashes and daemon activity.
> These are how you catch an intruder, so treat wiping them as deliberate admin work, not routine cleanup. My repo keeps that step separate and admin-only for exactly that reason.

**9/ The real fix**
> Full-disk encryption (LUKS). When the machine is off, every store above is unreadable without your passphrase. Set it at install, or add it on a spare disk.
> Scripts for Linux, Mac and Windows: github.com/anthonyonazure/privacy-sweep
