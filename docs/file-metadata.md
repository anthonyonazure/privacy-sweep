# What your files say about you

Clearing history does not touch what is written inside the files you keep and share.
Photos and Office documents carry their own record, and it travels with the file.

## What is inside

| File type | What it can carry |
| --- | --- |
| Photos and video | Camera make and model, the time it was taken, GPS position, the software that edited it, and often a small embedded preview of the original image |
| Word, Excel, PowerPoint | Author and last-saved-by names, company, creation and edit times, revision history, and comments |
| PDF | Author, producing software, and creation and modification times |

Two points worth knowing:

- **The embedded preview can outlive an edit.** A cropped or blurred photo may still hold a
  small, unedited thumbnail of the original frame inside its metadata.
- **Encryption hides this too.** A password-protected Office file shows only file-system
  details until it is opened, because the metadata is encrypted with the contents.

## See it before you share a file

ExifTool is free and works on macOS, Windows, and Linux.

```
exiftool photo.jpg            # everything the file says about itself
exiftool -gps:all photo.jpg   # only the location fields
```

For Office files, File > Info > Inspect Document removes author names, comments, and
revision history from your copy. Most phones can strip location when you share a photo
(a share-sheet option on iOS and Android).

## Why this repo does not rewrite metadata

privacy-sweep clears history stores that the operating system rebuilds. Rewriting metadata
changes files you chose to keep and often need to be accurate (a photo date, a contract
author). It is also easy to get wrong in a way that looks worse than leaving it alone.
Check a file with ExifTool, and strip or edit it yourself when you decide to share it.
