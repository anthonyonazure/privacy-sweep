# Memory residue

Digital Forensics Cookbook treats `pagefile.sys`, `hiberfil.sys`, and crash dumps as
RAM that was written to disk: paths, process state, and sometimes secrets. OS X
incident-response notes treat `sleepimage` the same way, with the caveat that macOS
has encrypted that file since 10.7. Practical Linux Forensics treats swap as a
carvable copy of memory.

## What this tool does

It reports presence and size. It does not read the bytes and it does not print them.

Opt-in actions, each dry-run unless `--apply` / `-Apply`, each with its own flag
and a typed phrase. `--yes` does not run them. None of them are part of `clear-all`.

| Flag | Phrase | Action |
| --- | --- | --- |
| `-DisableHibernation` | `DISABLE HIBERNATION` | `powercfg /h off` (this deletes `hiberfil.sys`) |
| `-ClearPageFileAtShutdown` | `CLEAR PAGEFILE AT SHUTDOWN` | registry DWORD `ClearPageFileAtShutdown=1` (takes effect on reboot) |
| `--remove-sleepimage` | `REMOVE SLEEPIMAGE` | removes `/private/var/vm/sleepimage` only when `hibernatemode` is 0 |
| `--purge-swap` | `PURGE SWAP` | `swapoff`, `mkswap`, `swapon` for the listed swap devices (root) |

## What it cannot do

- It does not extract strings, passwords, or process lists from these files.
- Sleepimage removal is refused unless hibernation mode is already 0. This script
  does not change `hibernatemode` for you. If the mode cannot be read, it refuses.
- Pagefile clearing is a shutdown-time Windows setting. Until you reboot, the
  current pagefile is still there.
- `powercfg /h off` needs an administrator. The script does not elevate itself.
- Swap purge needs root and rewrites the swap header. A failed `mkswap` can leave
  swap off. The dry run only prints the commands.

## Residual risk

Full-disk encryption covers these files when the machine is off. While you are
logged in, they are part of the running system. A crash dump you delete can be
recreated by the next crash. Copies can also sit in cloud crash-reporting if that
was turned on.
