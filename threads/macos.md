# Thread: macOS

**1/ (hook + link)**
> Your Mac remembers every file you opened, every photo you deleted, the download link for every file you saved, and every Wi-Fi password you've ever used.
>
> I open-sourced scripts that clear all of it: github.com/anthonyonazure/privacy-sweep
>
> Prefer to do it by hand? Here's each one:

**2/ Deleted-photo previews**
> macOS caches a thumbnail of nearly everything it displays. Delete the photo and the preview can stay.
> Clear it: open Terminal, run `qlmanage -r cache`.
> Then: Photos > Recently Deleted > Select > Delete All (it holds deleted shots 30 days).

**3/ Your browser history is only half the story**
> Safari also keeps cookies and a cache that a "clear history" in a hurry can miss.
> Clear it all: Safari > Settings > Privacy > Manage Website Data > Remove All. Or Safari menu > Clear History > all history.
> Chrome/Firefox: their own Clear Browsing Data, set to All time.

**4/ Saved Wi-Fi passwords, in the clear**
> Open the Passwords app > Wi-Fi. Touch ID reveals every network password stored.
> Forget one: System Settings > Wi-Fi > Details next to the network > Forget This Network.

**5/ What you copied**
> One clipboard item is normal, but macOS 26 added an optional clipboard history: Spotlight (Cmd+Space) then Cmd+4.
> Empty it and turn it off: System Settings > Spotlight > Clipboard history > off.

**6/ Every document you've opened**
> Apple menu > Recent Items. Each app also keeps its own Open Recent list (I found 71 of these on my Mac).
> Clear: Apple menu > Recent Items > Clear Menu.
> Stop it: System Settings > Desktop & Dock > Recent documents, applications, and servers > None.

**7/ The one nobody mentions: your download log**
> macOS records every file you downloaded and the web address it came from. Clearing browser history does NOT touch it.
> Mine had 1,718 entries. In Terminal:
> `sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 'delete from LSQuarantineEvent'`

**8/ Terminal command history**
> If you use Terminal, `~/.zsh_history` holds every command, sometimes with passwords typed inline.
> Clear it: `: > ~/.zsh_history` then `history -c`, or just open a fresh window after.

**9/ The real fix**
> Turn on FileVault (System Settings > Privacy & Security). It encrypts the whole disk, so every store above is unreadable when the Mac is off or locked. One switch covers all of them.
> Scripts for Mac, Windows and Linux: github.com/anthonyonazure/privacy-sweep
