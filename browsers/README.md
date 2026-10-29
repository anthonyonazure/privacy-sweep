# Browser history, cookies, and cache

Clears three stores for the browsers you actually have installed:

| Browser | Windows | macOS | Linux |
| --- | --- | --- | --- |
| Chrome | yes | yes | yes |
| Edge | yes | yes | yes |
| Firefox | yes | yes | yes |
| Brave | yes | yes | yes |
| Safari |  | yes |  |
| Chromium |  | yes | yes |

```bash
cd browsers
chmod +x clear-browsers.sh
./clear-browsers.sh --dry-run
./clear-browsers.sh --only firefox
./clear-browsers.sh --yes
```

```powershell
.\clear-browsers.ps1 -DryRun
.\clear-browsers.ps1 -Only chrome,edge
.\clear-browsers.ps1 -Yes
```

The script refuses a browser that is still running, and `--yes` does not override that. Quit
the browser, then run it again. Other closed browsers in the same run can still be cleared.

What is removed:

- Chromium-family (Chrome, Edge, Brave, Chromium): the `History` file, the `Cookies` file
  (including `Network\Cookies`), and the cache directories. Bookmarks, `Login Data`, and
  `Preferences` stay.
- Firefox: history rows inside `places.sqlite`, via SQL, so bookmarks in that same file stay.
  `cookies.sqlite` and `cache2` are removed. This needs `sqlite3` (macOS and Linux) or, on
  Windows, `sqlite3` or `python`. If neither is available, Firefox history is skipped rather
  than deleting `places.sqlite`.
- Safari: `History.db`, the cookies file, and the Safari cache directories. `Bookmarks.plist`
  stays.

Local Storage is left alone, so a site that kept you logged in there may still recognize the
profile. Saved passwords are left alone. These scripts are not part of `clear-all`, because
clearing cookies signs you out of the web.
