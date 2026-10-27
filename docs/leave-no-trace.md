# Leave no trace

This is a plain-language map of what a careful look at a machine still finds after a
normal delete, and what actually reduces that. It is advice. It does not run anything,
and it is not a promise that a file is gone.

privacy-sweep's default sweep only clears a short list of **named stores** (thumbnails,
recent items, shell history, and the like). It does not purge snapshots or shadow copies,
and it does not fill free space. Those are separate decisions. Read
[SECURITY.md](../SECURITY.md) before you delete anything you might have a duty to keep.

## The five layers

Think of "leaving less behind" as five different jobs. Mixing them up is how people
either miss the copies that matter, or destroy a backup they still needed.

### (a) Reduce future logging

The cheapest record is the one the system never writes. That means turning down
telemetry and search indexing where the OS gives you a switch, keeping a sensitive
volume out of an index, and not sending a smart TV's lookups through the same resolver
you use for everything else.

On a Mac, a volume can be kept out of Spotlight. On Windows, Indexing Options decides
what Windows Search reads into its database. Those are settings, not something this
repo flips silently in the registry.

For a TV, the useful step is upstream of the PC: a guest network, and DNS you
administer. See [network/pihole-tv/](../network/pihole-tv/) (on-TV settings, then
blocklists and a client report) and [network/router-hygiene/](../network/router-hygiene/).
A Pi-hole log is itself a record. Clearing the laptop does not clear it.

### (b) Clear named stores

This is what the per-OS `clear-*` scripts do. They remove caches and histories the
operating system keeps **by name**: recent documents, thumbnail caches, shell history,
browser history when you opt in, and so on. The audit in [audit/](../audit/) counts
those stores and prints paths. It does not print command lines, download URLs, or
file contents.

Clearing a named store drops the index entry and, for a real file, the directory
pointer. It does not make older bytes unrecoverable, and it does not reach a copy
that still lives in a snapshot or in the cloud.

### (c) Purge recovery structures

Some copies exist specifically so a delete can be undone:

- **Windows Volume Shadow Copies** (the storage behind Previous Versions and restore
  points) can still hold a file after you delete it and even after free space on the
  live volume is overwritten.
- **APFS local snapshots**, including local Time Machine snapshots, can resurrect a
  deleted file on a Mac.
- **Document Revisions** (`.DocumentRevisions-V100`) keep earlier versions of documents.

The audit **reports** these: shadow-copy counts, snapshot names, Document Revisions
size, and whether pagefile, hiberfil, sleepimage, or swap is present. It does not
delete them, and it does not read the bytes inside them.

Removing them throws away the rollback copy. That is a real backup, not a cache, so
this repository does not ship that step. A later opt-in tool would need a loud warning
and would stay out of `clear-all`. Until then, if you remove snapshots yourself, know
that you are deleting restore points.

### (d) Free space on a hard disk

When a small file replaces a large one, or a file is deleted, the old bytes can sit in
unallocated space until something else is written there. On a spinning hard disk, filling
that free space with a new file and then deleting the filler covers a lot of what a
casual recovery would still see.

That is a separate, opt-in module: [hdd-free-space/](../hdd-free-space/). It is **not**
part of `clear-all` or `privacy-sweep.sh`. It asks before it writes, it can show a dry
run first, and it refuses SSDs unless you override it. It does **not** clear shadow
copies or snapshots. Do the recovery-structure decision with your eyes open; do not
assume a free-space fill did it for you.

### (e) Full-disk encryption, and destroying the key when you retire a drive

The control that covers every store at once, including the ones the scripts never touch,
is full-disk encryption for the life of the disk: FileVault, BitLocker, or LUKS. The
audit reports **protection status only**. It does not print recovery keys, and this
repo will not destroy a key for you.

When you are actually giving the drive away or throwing it out, the honest end of the
story is to throw the key away (or use the drive's own erase), not to hope a file copy
overwrote every old sector. If firmware erase is available, the vendor's tool or a
secure-erase / crypto-erase command is the retirement path. Userspace cannot scrub
storage the controller keeps hidden. For the highest sensitivity, physical destruction
is the step software should not pretend to replace.

## SSDs: free-space fill is theater

Solid-state drives do not keep a stable map from "this free cluster" to "this physical
chip." Three mechanisms get in the way:

- **TRIM** tells the drive a block is unused so the controller may recycle it. That is
  the drive's decision, on the drive's schedule.
- **Wear leveling** moves data between physical pages so no cell is worn out early.
  The page that used to hold a file may no longer be the page a new file is written to.
- **Overprovisioning** is spare capacity the computer cannot address. A fill file never
  sees it.

So a program that writes a huge file of zeros until the volume is "full" only overwrites
free space the filesystem can see today. It does not reliably destroy the old NAND, and
it can still leave the fingerprints below. Do not describe that as a forensic wipe.

Day to day, keep encryption on and clear the named stores you actually mean to clear.
For disposal, destroy the encryption key or use the vendor erase tool.

## When a hard-disk fill is still useful

On a spinning disk, unallocated space is closer to what the heads can still read. A fill
then a delete is a reasonable extra step **after** you have decided what to do about
snapshots, and only on a disk you are willing to thrash for a while. It is slow, it
leaves the fingerprints below, and it still does not replace encryption.

The Linux script writes a directory named `privacy-sweep-free-space-fill`, syncs, and
deletes it. On the root filesystem it stops about 128 MiB short so the machine can still
remove that directory. The Windows script uses the built-in `cipher /w` on a folder you
name. macOS is documented here and in the module README; there is no macOS fill script
that pretends an APFS SSD can be scrubbed this way.

## Fingerprints examiners are trained to notice

Free-space tools leave names behind when they are interrupted, and sometimes even when
they finish. People who do this work are taught to look for:

| Leftover name | Where it comes from |
| --- | --- |
| `EFSTMPWP` | Windows `cipher /w` temporary directory |
| `!FSTMPWP` | That directory renamed, then left behind if cipher was interrupted |
| `SDELTEMP` | SDelete, often a zero-byte file on the volume |
| a long run of `z` characters | cleaners that rewrite a deleted file's name |
| `privacy-sweep-free-space-fill` | this repo's Linux fill, if a run did not finish |

The audit's remnant scan looks for those names at a **shallow** depth (volume roots, temp,
and home). It is not a search of every directory on the disk, and it does not read the
files. It reports paths so you can see your own leftovers. It does not delete them.

Wiping free space is also something ordinary people do before selling a computer. Finding
one of these names is not, by itself, proof of wrongdoing. Stacked with other signs that
records were altered, it is simply one more thing a careful person will notice. This
tool will not pretend otherwise.

## Do not plant decoys

Do not add fake Prefetch entries, fake UserAssist counts, or any other "this will look
normal" record. Examiners compare artifacts with each other. A program-execution entry
that does not line up with the rest of the system is itself a signal. Timestamps that
disagree across stores are a signal. This repository does not write decoys, and you
should not either.

The same applies to selectively deleting one history while leaving the others. The audit
exists so you can **see** the set. It is not a kit for inventing a different past.

## The cloud, the router, and the TV outlive the disk

OneDrive, iCloud, Dropbox, mail hosts, and browser sync keep their own copies and their
own version history. Emptying a laptop does not empty the account. Sign in on another
device and the files can come back.

The network keeps its own logs: the router, the resolver, and devices that were on the
LAN. A smart TV in particular will keep talking to its own services. The DNS work in
[network/pihole-tv/](../network/pihole-tv/) and the router checklist in
[network/router-hygiene/](../network/router-hygiene/) are about that path. They are not a
wipe of the TV, and they are not a wipe of the router's admin log.

## What this page will not help you do

Mass-deleting Windows Event Logs, deleting USB device history, extracting a keychain or
a password manager, and damaging the filesystem journal are out of scope. See
[SECURITY.md](../SECURITY.md). If you are under a legal hold or a workplace retention
rule, do not run the destructive parts of this repo at all.
