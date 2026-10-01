# privacy-sweep - Android

Android also sandboxes apps and, on modern versions, encrypts storage by default (file-based
encryption tied to your lock screen). So most of the history below sits under `/data/data`, which a
normal app cannot read. There is **no full auto-wipe script for a stock, non-rooted phone.**

Two things are possible without rooting:

1. **Manual clears from Settings** (works on every phone) - the table below.
2. **A helper script over `adb`** (Android Debug Bridge) for the handful of things Google exposes to
   a connected computer. It is included as
   [clear-adb.sh](clear-adb.sh) and is intentionally
   modest, because Android only lets `adb` reach app caches and a few user-space bits, not the
   protected databases.

## What Android keeps, and how you clear each one

| Store | What it holds | How to clear it |
| --- | --- | --- |
| App cache | Thumbnails, downloaded content per app | Settings > Apps > (app) > Storage & cache > Clear cache |
| Chrome / browser | History, cookies, cached pages | Chrome > (three dots) > Delete browsing data |
| Downloads | Files you downloaded | Files app > Downloads > select > delete |
| Photo trash | Deleted photos, kept ~30-60 days | Google Photos > Library > Trash > empty |
| Gallery `.thumbnails` | Image preview cache on storage | Delete the `.thumbnails` folder in internal storage via the Files app |
| Maps / Location history | Places you've been | Google Maps > your photo > Your Timeline > settings > delete |
| Keyboard learned words | Typed personal words | Settings > System > Languages & input > (keyboard) > clear learned words / dictionary |
| Ad ID | Cross-app tracking identity | Settings > Privacy/Security > Ads > Delete advertising ID |

## The adb helper (optional)

Enable **Developer options** (Settings > About phone > tap Build number 7 times), turn on **USB
debugging**, connect the phone, then from a computer with Android platform-tools installed:

```bash
cd android
chmod +x clear-adb.sh
./clear-adb.sh --dry-run     # list what it would do
./clear-adb.sh               # ask, then clear app caches + trim logcat
```

It clears per-app caches and the running log buffer (`logcat -c`). That's the honest ceiling for
non-rooted access.

## The one that matters most

Before selling or handing on the phone: **Settings > System > Reset options > Erase all data
(factory reset).** Because storage is encrypted, the reset discards the key and makes the whole
contents unrecoverable at once, the same idea as iOS. Set a strong lock screen (PIN 6+ digits or a
passphrase) and that key protects everything above while the phone is locked.
