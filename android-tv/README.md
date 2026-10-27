# Android TV and Google TV (report only)

[audit-tv.sh](audit-tv.sh) connects to a TV you administer over network `adb` and prints
two package lists: everything installed, and everything enabled. It then flags names in
[packages.txt](packages.txt) that CleanYourTV treats as manufacturer telemetry, ads, or
home-screen content rows.

Nothing is disabled, hidden, or uninstalled. The script is not part of `clear-all` or
`privacy-sweep.sh`.

The package names and the jobs they do are drawn from
[CleanYourTV](https://github.com/Gathin23/cleanyourtv) (`tools/privacy.py` and the debloat
lists under `examples/`), read on 2026-10-27. The notes in `packages.txt` are this repo's
wording. Reversible disabling (`pm disable-user` in their tools) and their replacement
launcher live in that project. This script only points at them:

- https://github.com/Gathin23/cleanyourtv
- https://cleanyour.tv/not-android (Samsung, LG, Roku, Vizio, VIDAA, and Fire TV are settings and DNS, not `adb`)

Voice packages, the stock launcher, setup, and update packages are left off the flag list.
Disabling the voice package turns the microphone off with it, and some update packages are
what the set uses to install firmware.

## Run it

On the TV, turn on network debugging. The usual port is 5555. Accept the prompt on the
screen the first time.

```bash
cd android-tv
chmod +x audit-tv.sh
./audit-tv.sh --host 192.168.1.40
./audit-tv.sh --host 192.168.1.40:5555
./audit-tv.sh --serial 192.168.1.40:5555
```

`--dry-run` and `--yes` are accepted so the flag matches the rest of the repo. Both print
the same report. There is no apply step.

`PRIVACY_SWEEP_ADB_FIXTURE=dir` reads captured `adb` output instead of a TV. That variable
is a test aid.

Phone permission reports stay in [android/audit-permissions.sh](../android/audit-permissions.sh).
