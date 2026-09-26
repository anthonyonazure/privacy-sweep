# Thread: Windows

**Hook**
> Windows keeps a thumbnail of every photo you've deleted, a record of every program you've run, and a list of every USB stick you've plugged in.
>
> Here's where the traces live and how to clear each one:

**1/ Deleted-photo thumbnails**
> Win+R, paste `%LOCALAPPDATA%\Microsoft\Windows\Explorer`. You'll see thumbcache_*.db. Delete a photo and its preview can stay here.
> Clear it: Win+R, `cleanmgr`, tick Thumbnails.

**2/ Every program you've opened**
> Win+R, `C:\Windows\Prefetch`. One .pf file per program, with its last launch times and total run count.
> Clear it: delete the .pf files (needs an admin terminal). They rebuild over the next few launches.

**3/ Every USB stick ever plugged in**
> Win+R, `regedit`, go to `HKLM\SYSTEM\CurrentControlSet\Enum\USBSTOR`. Every drive that's touched the machine, by make and model.
> This one is woven into Windows; don't hand-edit it. Reducing it is a Group Policy job.

**4/ Saved Wi-Fi passwords in plain text**
> Terminal: `netsh wlan show profiles`, then `netsh wlan show profile name="NETWORK" key=clear`. Read the Key Content line.
> Forget a network: Settings > Network & internet > Wi-Fi > Manage known networks.

**5/ What you copied**
> Win+V shows everything you copied this session, including anything from a password manager.
> Clear: the three dots > Clear all. Turn it off: Settings > System > Clipboard.

**6/ Recent files & Jump Lists**
> Win+R, `recent`. Every document you've opened. Right-click a taskbar app for its own recent list.
> Clear both: my script empties `%APPDATA%\Microsoft\Windows\Recent`. Stop it: Settings > Personalization > Start.

**7/ The real fix**
> Turn on BitLocker (Settings > Privacy & security > Device encryption). It encrypts the disk, so every store above is unreadable when the PC is off or locked.

**8/ I scripted the whole cleanup**
> Free, open source, PowerShell. One script per store, previews what it'll delete, asks first. Windows, Mac, Linux:
> github.com/anthonyonazure/privacy-sweep
