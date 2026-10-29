# Cloud sync metadata (audit only)

Digital forensics writing on cloud accounts makes one point that a disk wipe does not:
the service keeps its own timestamps, device list, version history, and activity log.
Clearing a folder on the laptop does not clear the account. An Apress-style look at
Dropbox, and the cloud chapter of the Digital Forensics Cookbook, both treat the
provider's copy as the one that survives the machine.

## What this tool does

It reports whether the local sync logs and databases are present, and how large they
are. It does not open them, so it does not print file names from inside your drive,
and it does not print tokens.

File Provider and iCloud Drive roots (`~/Library/CloudStorage`, `~/Library/Mobile Documents`,
and OneDrive or SharePoint folders on Windows) are a presence line plus a top-level
entry count. They are not walked, and `du` is not run on them, because a recursive
listing can download files that were only online.

It does not delete those files. There is no clear flag.

If this session's profile is missing OneDrive, OneDrive for Business, or SharePoint roots that another profile under `C:\Users` has, the report names that profile and the counts. It does not list files or organization names inside those folders. `-ProfilePath` points the same report at one other profile and does not recommend that profile again. It still deletes nothing.

## What it cannot do

It cannot sign you out, delete versions, or remove a device from the account. That is
a website you have to open yourself. The checklist below is the whole action.

## Checklists

Do these in a browser, signed in as you. Order does not matter. None of them are run
by this repository.

### OneDrive

- onedrive.live.com or the work tenant: delete files you mean to delete, then empty the recycle bin.
- Version history on a file is separate from the current copy. Open the file's version history if a prior copy should go.
- Review account devices and remove this PC if you are handing the machine on.
- Activity and sharing links are on the account, not in the local log folder.

### iCloud

- icloud.com: delete files, then the Recently Deleted folder (it keeps items for about 30 days).
- Settings on each Apple device: the device list. Removing a device does not by itself delete iCloud Drive.
- Photos, Mail, and Drive are separate buckets. Clearing CloudDocs on disk does not clear them.

### Dropbox

- dropbox.com: deleted files, then the trash, then version history if you need an older copy gone.
- Settings: security, devices, and connected apps. Unlink this computer.
- The local `.dropbox` database is a cache of that account. Deleting it signs the app out only after you quit Dropbox; the website still has the files.

### Google Drive

- drive.google.com: trash, then version history on files that keep old bytes.
- Google Account: devices, and My Activity if searches and views matter to you.
- Drive for desktop's local database is not the account.

## Residual risk

A file that was shared, emailed, or opened on a phone is still there. This audit only
tells you the local cache exists.
