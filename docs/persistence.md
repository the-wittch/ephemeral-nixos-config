# Keeping things across reboots

Your files are in your home folder, which is kept. Everything else on `/` is built again from the config at every boot, so what a program writes outside `/home`, a database in `/var/lib` or a file you edited in `/etc`, is gone after a reboot. Apps from `ephemeral apps` already keep what they need.

## What survives a reboot

`ephemeral persistence` shows it, path by path. In a terminal it opens an explorer of the whole file system:

```bash
sudo ephemeral persistence
```

Folders open with → or Enter and close with ←. The right side, or the lines below the tree in a narrow window, says what happens to the selected path. `/` searches the names shown, `f` shows only one class, `g` goes to a path you type, `?` explains the rest, and `q` quits. Without sudo it works too, but can't see into folders only root can read, and says so.

Each path gets one of these, from the list of kept paths the config builds and the mounts as they are now:

| class | means |
|---|---|
| ● PERSISTENT | still there after a reboot: on `/persist`, mounted or linked from it, or on `/nix`, `/var/log` or `/boot` |
| ○ EPHEMERAL | gone at the next boot: on the part of the disk that's reset, or held in memory like `/tmp` and `/run` |
| ◐ MIXED | a folder that holds both, such as `/var/lib`: the folder itself is reset, some of what's in it is kept |
| ? UNKNOWN | it can't tell: another disk, a network share, a FUSE view such as `/run/user/1000/doc`, firmware storage like the EFI variables, or something it can't read |
| ! UNVERIFIED | the config keeps it, but it isn't set up that way now, so what's written there now is lost |

Nothing is guessed from a folder's name. A path the config doesn't list is classified by what holds it, and a listed one only counts as kept once its mount or link is really there. At every boot `/` is reset, so a reboot and a reset are the same thing here.

For one path, or several:

```text
$ ephemeral persistence inspect ~/Documents /etc
● /home/you/Documents
  class          PERSISTENT
  after a reboot still there
  how            a bind mount of /persist/home
  on             /home (btrfs, subvolume /persist)
  exists         yes, directory
  owner, mode    you:users 755
  kept as        part of /home, from modules/persist.nix
  backups        backed up: it's in /home, which the backups read
◐ /etc
  class          MIXED (what holds it now is ephemeral)
  after a reboot some of it is still there
  how            the /root subvolume, reset from root-blank at every boot
  on             / (btrfs, subvolume /root)
  declared       no
  backups        not backed up: it isn't in an area the backups read (/home, /persist/etc, /persist/var/lib/sbctl)
  kept inside    2: /etc/NetworkManager/system-connections, /etc/machine-id
```

Outside a terminal, or as `ephemeral persistence summary`, it prints how many paths are declared and set up, and a tree of where the kept ones are.

### Kept isn't backed up

A kept path survives a reboot, not a lost or broken disk. The backups line says whether the [scheduled backups](backup.md#scheduled-backups) read it, from their own list: `/home`, `/persist/etc` and `/persist/var/lib/sbctl`, less caches and the rest that list leaves out, and less any folder with a `.nobackup` file or a `CACHEDIR.TAG`. `/var/lib/bluetooth` is kept and not backed up, for one. A folder can be partly backed up, like `/home/you` without `.cache`. Without scheduled backups it says so; other backup tools, such as Vorta, aren't seen.

The summary has the last backup that finished, from the journal, and the last check of the repository that passed, which borgmatic records; that one needs sudo to read.

### Checking it

```bash
sudo ephemeral persistence audit
```

lists what isn't as the config says, worst first:

| mark | severity | for example |
|---|---|---|
| ✗ | CRITICAL | a kept path that isn't mounted, its copy on `/persist` gone, or `/` not from the subvolume that's reset |
| ! | WARNING | a kept folder whose owner or mode isn't the config's, a mount from `/persist` the config doesn't list, a service's state folder that isn't kept, a leftover on `/persist` |
| · | INFORMATIONAL | a kept path that isn't backed up, other folders in `/var/lib` that go at a reboot |
| ? | UNKNOWN | something it couldn't read; run it with sudo |

Each finding says what it saw and what to do. It exits 1 when something is CRITICAL, so a script can check it. `ephemeral doctor audit` is the same.

A folder that isn't kept isn't a problem by itself: most of `/var/lib` is made again when it's needed. The service check goes by the state folders services tell systemd about, so it misses a program that writes somewhere without saying so. To see everything the next reboot removes, written since this boot:

```bash
sudo ephemeral doctor lost
```

`ephemeral doctor kept` prints the list of kept paths alone.

None of these change anything. Adding a path to what's kept is up to you, as below.

### For scripts

`ephemeral persistence export` prints it as JSON: for the paths given after it, or without any for what the summary covers. `ephemeral persistence inspect --json` and `ephemeral persistence audit --json` print theirs the same way. The explorer reads `ephemeral persistence --children <folder>`, a folder and what's directly in it, up to 2000 entries. The fields, in version 1:

- `version` (1, raised when a field changes meaning or goes), `generated_at`, `as_root`, and `truncated` when `--children` listed only part of a folder
- `system`: `config_release`, `persist_root`, `reset_subvolume`
- `backup`: `configured`, `last_result`, `last_success`, `last_check`
- `summary`: how many of the paths are each class, and `paths`, `declared`, `declared_verified`
- `paths`, one per path:
  - `path`, `exists` (`yes`, `no`, `unknown`), `type` (`directory`, `file`, `link`, `other`), `owner`, `group`, `mode`, `link`
  - `classification` (`persistent`, `ephemeral`, `mixed`, `unknown`, `unverified`), and `own_classification`, what holds the path itself
  - `survives_reboot` (true, false, or null when it can't tell or it's mixed), `mechanism`, `backing` (`mount`, `fs_type`, `source`, `subvolume`)
  - `declared`, `declaration` (`kind`, `how`, `in_initrd`, `user`, `group`, `mode`), `declared_in` (the modules), `inside_declared`, `verified` (null when it isn't declared)
  - `kept_inside`, `unknown_inside`
  - `backup_coverage` (`included`, `partial`, `excluded`, `unknown`, `not-configured`), `backup_reason`, `backup_via` (the path as the backups read it)
  - `notes`
- `findings`, from `audit --json`: `severity` (`critical`, `warning`, `informational`, `unknown`), `path`, `finding`, `explanation`, `evidence`, `remediation`

A field that can't be known is null, never left out. File contents are never read, and the host name isn't in it.

### What it can't tell

- What's on another disk or a network share, or in firmware storage.
- What's inside a folder only root can read, without sudo.
- Backups by anything but the scheduled ones, and borg patterns in the `re:` style, which it reports as unknown.
- Whether a program will write somewhere new later. `lost` shows what has been written since boot.

| | reboot | rebuild or update | go back to an older system | reinstall |
|---|---|---|---|---|
| `/` outside what's kept | gone | kept until the next reboot | kept until the next reboot | gone |
| `/home` | kept | kept | kept | gone |
| the other kept paths | kept | kept | kept, but not mounted if that system doesn't keep them | gone |
| `/var/log`, snapshots of `/persist` | kept | kept | kept | gone |
| installed packages (`/nix`) | kept | kept | kept | reinstalled |

A reinstall erases the whole disk, `/persist` included. Make a [backup](backup.md) before one.

To keep more, save this as `/persist/etc/nixos/modules/keep.nix`, with your own paths, and run `ephemeral update`:

```nix
{
  flake.modules.nixos.pc.preservation.preserveAt."/persist" = {
    directories = [
      {
        directory = "/var/lib/postgresql";
        user = "postgres";
        group = "postgres";
        mode = "0750";
      }
    ];
    files = [ "/etc/machine-info" ];
  };
}
```

They're kept from the next reboot. Whatever was in them before isn't copied over, so copy it to `/persist` first if you need it; `/persist/var/lib/postgresql` for the example above.

A kept folder gets the owner and mode given here at every boot, root and `0755` unless you say otherwise, so give them for a folder a service owns, as above. `ls -ld` on the folder shows what they are now, and `sudo ephemeral persistence audit` suggests the entry for a service's folder with them filled in. The options are [preservation's](https://nix-community.github.io/preservation/configuration-options.html).

A service with `DynamicUser` keeps its data in `/var/lib/private/<name>`, and systemd refuses to start it unless that folder and `/var/lib/private` are mode `0700`:

```nix
{
  flake.modules.nixos.pc.preservation.preserveAt."/persist".directories = [
    {
      directory = "/var/lib/private/i2pd";
      mode = "0700";
      configureParent = true;
      parent.mode = "0700";
    }
  ];
}
```

Taking a path off the list doesn't delete anything. Its files stay in `/persist`, no longer mounted. The same goes for an app you unpick in `ephemeral apps` that kept data, such as Docker. `sudo ephemeral persistence audit` lists those leftovers in `/persist/var/lib`, with their sizes, and how to remove each:

```bash
sudo rm -rf /persist/var/lib/docker
```

It only looks in `/persist/var/lib`. Other folders on `/persist`, like `/persist/etc/ssh` and `/persist/passwords`, are used where they are, never mounted, so they'd all look like leftovers.

Snapshots still hold a copy for up to four weeks, so the space comes back as they expire.
