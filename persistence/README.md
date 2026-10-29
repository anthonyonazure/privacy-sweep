# Persistence audit (never deletes)

Autoruns-style checks exist because a program can start again after you close it.
Hands-on incident-response material and macOS persistence notes look at launch
agents, launch daemons, and login items. Windows registry texts look at Run keys
and non-Microsoft scheduled tasks. Linux material looks at user systemd units,
cron, and autostart `.desktop` files. A WMI permanent event subscription is the
quiet Windows variant; this corpus is thin on the query text, so the tool counts
filters and does not print the query.

## What this tool does

It lists paths and names: plist files, task names that are not under `\Microsoft\`,
Run-key **value names** (not the command line), startup-folder file names, user
units, and autostart desktop-file paths. Cron commands are not printed. WMI filter
queries are not printed.

It never deletes, disables, or unloads anything. There is no flag that changes that.

## What it cannot do

- It cannot tell a wanted login item from an unwanted one. That is your call, one
  item at a time, in the OS settings.
- It does not unload a launch agent or unregister a scheduled task.
- A WMI count of "unavailable" means this account could not read
  `root\subscription`. It does not mean the count is zero.
- System LaunchDaemons shipped with macOS are counted, not listed one by one, so
  the report stays about the entries you or an installer added.

## Residual risk

Persistence that lives in a kernel extension, a firmware implant, or an account
you did not list is outside this report. Deleting a login item by hand does not
remove the program, and removing the program does not always remove the login item.
