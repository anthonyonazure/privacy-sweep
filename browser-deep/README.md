# Browser deep stores

A history wipe removes the history database and often the cookie jar. Web forensics
and the Chromium profile layout described in browser-forensics references still leave
LevelDB (local storage), IndexedDB, Cache_Data, service-worker caches, session-restore
files (`Current Session`, `Current Tabs`, Firefox `sessionstore`), and Crashpad dumps.
Those can hold site data, the list of tabs that were open, and crash contents.

Bookmarks are a different store. This tool **counts** them and **never deletes** them.

## What this tool does

With no flags it reports paths, counts, and sizes. `--clear-browser-deep` / `-ClearBrowserDeep`
adds the delete plan. Nothing is deleted unless you also pass `--apply` / `-Apply` and
confirm. `--yes` / `-Yes` does not delete. If that browser is running, the script
refuses it even with `--apply`.

```bash
./clear-browser-deep.sh --dry-run --clear-browser-deep
./clear-browser-deep.sh --clear-browser-deep --apply
```

```powershell
.\clear-browser-deep.ps1 -DryRun -ClearBrowserDeep
.\clear-browser-deep.ps1 -ClearBrowserDeep -Apply
```

Not part of `clear-all`. The older [browsers/](../browsers/) clearer still only does
history, cookies, and the ordinary cache, and it is also outside `clear-all`.

## What it cannot do

- It does not read or print page contents, URLs, or cookie values.
- It does not delete bookmarks, `Login Data`, Firefox `places.sqlite`, or password stores.
- It cannot clear a browser that is still open, because the browser would rewrite the files.
- Sync will bring site data back if the account still has it. See [cloud-sync/](../cloud-sync/).

## Residual risk

Session restore and site storage are one layer. The profile can still hold bookmarks,
passwords, and extension data. The network, the account, and crash reports uploaded to
the vendor are outside this folder.
