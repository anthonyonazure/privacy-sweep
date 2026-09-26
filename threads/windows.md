# Thread: Windows

**1/ (hook + link)**
> Windows keeps a thumbnail of every photo you've deleted, a record of every program you've run, a list of every USB stick you've plugged in, and your Wi-Fi passwords in plain text.
>
> I open-sourced scripts that clear it: github.com/anthonyonazure/privacy-sweep
>
> Want to do it by hand? Here's each one:

**2/ Deleted-photo thumbnails**
> Win+R, paste `%LOCALAPPDATA%\Microsoft\Windows\Explorer`. You'll see thumbcache_*.db. Delete a photo and its preview can linger here.
> Clear it: Win+R, `cleanmgr`, pick your C drive, tick Thumbnails, OK.

**3/ Every program you've opened**
> Win+R, `C:\Windows\Prefetch`. One .pf file per program, with its last launch times and total run count. (Windows keeps a second record called Amcache too.)
> Clear it: delete the .pf files from an Administrator terminal. They rebuild over the next few launches.

**4/ Every USB stick ever plugged in**
> Win+R, `regedit`, go to `HKLM\SYSTEM\CurrentControlSet\Enum\USBSTOR`. Every drive that's touched the machine, by make and model.
> This is woven into Windows; don't hand-edit it. If you care, reducing it is a Group Policy setting, not a delete.

**5/ Saved Wi-Fi passwords in plain text**
> Terminal: `netsh wlan show profiles`, then `netsh wlan show profile name="NETWORK" key=clear` and read the Key Content line.
> Forget one: Settings > Network & internet > Wi-Fi > Manage known networks > Forget.

**6/ Your browser, the full clear**
> History, cookies, and cache each hold traces. In Chrome or Edge press Ctrl+Shift+Delete, set Time range to All time, tick all three, clear.
> Firefox: same shortcut, Everything.

**7/ What you copied**
> Win+V shows everything you copied this session, including anything pasted from a password manager.
> Clear: the three dots > Clear all. Turn it off: Settings > System > Clipboard.

**8/ Recent files & Jump Lists**
> Win+R, `recent`. Every document you've opened. Right-click a taskbar app for its own recent list.
> Clear: delete everything in that folder. Stop it: Settings > Personalization > Start > turn off "Show recently opened items".

**9/ Recycle Bin & temp**
> Right-click the Recycle Bin > Empty. Then Win+R, `%TEMP%`, select all, delete (files in use just skip).

**10/ The real fix**
> Turn on BitLocker (Settings > Privacy & security > Device encryption). It encrypts the disk, so every store above is unreadable when the PC is off or locked.
> Scripts for Windows, Mac and Linux: github.com/anthonyonazure/privacy-sweep
