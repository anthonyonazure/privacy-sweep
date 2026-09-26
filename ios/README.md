# privacy-sweep - iOS / iPadOS

**There is no cleanup script here, and that is the honest answer, not a gap.**

iOS runs every app in a sandbox and encrypts the whole device with a key tied to your passcode. A
normal app, including anything you could sideload, cannot read another app's data, cannot reach the
system databases where history lives, and cannot run a shell. So a "run this to wipe your traces"
tool is not possible on a stock iPhone. That sandbox is exactly why iPhones are hard to extract data
from in the first place: when the device is locked or off, the stores below are encrypted and
unreadable without your passcode.

What that means in practice: **your passcode plus Face ID / Touch ID is the whole game.** A strong
passcode and a device that auto-locks protects all of this at once. These are the manual controls
that actually move the needle.

## What iOS keeps, and how you clear each one from Settings

| Store | What it holds | How to clear it |
| --- | --- | --- |
| Recently Deleted (Photos) | Deleted photos, kept 30 days | Photos > Albums > Recently Deleted > Select > Delete All |
| Safari history & website data | Sites visited, cookies, caches | Settings > Apps > Safari > Clear History and Website Data |
| Messages | Texts and attachments | Settings > Apps > Messages > Keep Messages > 30 Days (auto-deletes older), or delete threads |
| Keyboard learned text | Typed words, some sensitive | Settings > General > Transfer or Reset iPhone > Reset > Reset Keyboard Dictionary |
| Significant Locations | A log of places you frequent | Settings > Privacy & Security > Location Services > System Services > Significant Locations > Clear History |
| Siri & Dictation history | Voice request history | Settings > Apps > Siri > Siri & Dictation History > Delete |
| Analytics data | Diagnostic logs | Settings > Privacy & Security > Analytics & Improvements > turn off Share iPhone Analytics |
| Per-app caches | Downloaded/cached content | Delete and reinstall the app, or use its in-app "clear cache" if it has one |

## The two that matter most

- **Set a 6-digit-or-longer passcode** (Settings > Face ID & Passcode > Change Passcode > Passcode
  Options > Custom Alphanumeric Code). This is the encryption key for everything above.
- **Erase All Content and Settings** (Settings > General > Transfer or Reset iPhone > Erase All
  Content and Settings) before selling or giving the device away. Because the disk is encrypted,
  this throws away the key and makes the entire contents unrecoverable in one step. That is the iOS
  equivalent of running every clear script at once, and Apple designed it to be the clean way out.
