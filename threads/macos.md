# Thread: macOS

**Hook**
> Your Mac remembers every file you opened, every photo you deleted, and every network you joined.
>
> Windows people just learned this. Mac keeps the same records, just in different places, and most cleaner apps never touch them.
>
> Where they live and how to clear them:

**1/ Deleted-photo previews**
> macOS caches a thumbnail of nearly everything it shows, in a hidden Quick Look store. Delete the original and the little preview can stay.
> Clear it: Terminal, `qlmanage -r cache`. And in Photos, empty Recently Deleted (it keeps shots 30 days).

**2/ Every app you've run**
> macOS logs app usage in knowledgeC.db and a newer system called Biome.
> See a readable version: System Settings > Screen Time > App & Website Activity. The system trims it on its own; there's no wipe button.

**3/ Saved Wi-Fi passwords, in the clear**
> Open the Passwords app > Wi-Fi. Touch ID reveals every network password stored.
> Forget one: System Settings > Wi-Fi > Details > Forget This Network.

**4/ What you copied**
> One clipboard item is normal, but macOS 26 added an optional clipboard history: Spotlight (Cmd+Space) then Cmd+4.
> Turn it off: System Settings > Spotlight > Clipboard history.

**5/ Every document you've opened**
> Apple menu > Recent Items. Each app also keeps its own Open Recent list (I found 71 of those).
> Clear: Apple menu > Recent Items > Clear Menu. Stop it: System Settings > Desktop & Dock > Recent documents > None.

**6/ The one nobody mentions: your download log**
> macOS records every file you downloaded and the URL it came from. Clearing browser history does NOT touch it.
> Mine had 1,718 entries. It's a database called QuarantineEventsV2.

**7/ The real fix**
> Turn on FileVault (System Settings > Privacy & Security). It encrypts the whole disk, so every one of these caches is unreadable when the Mac is off or locked. One switch covers all of them.

**8/ I scripted the whole cleanup**
> Free and open source. One script per store, shows you what it'll delete, asks before it does. macOS, Windows, and Linux:
> github.com/anthonyonazure/privacy-sweep
