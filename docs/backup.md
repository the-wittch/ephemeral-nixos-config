# Backups

Snapshots undo a delete, but they live on the same disk. A reinstall, a dead disk or a lost laptop takes them with everything else, so keep a copy somewhere else.

## What to back up

- **Your home folder.** All your files, and the settings of every app.
- **The machine config.** `/persist/etc/nixos` is best kept in a private git repo. What git leaves out is saved by `ephemeral backup save`, below.
- **Secrets you can't download again:** the Control D id, SMB and Wi-Fi passwords, the SSH host key, the Secure Boot keys, and the passphrase of your scheduled backups. They're root-only, so a backup app running as you can't read them; `ephemeral backup save` saves them too.
- **The LUKS header**, once, with [`ephemeral backup header`](features.md#luks-header-backup).

Skip `/persist/.snapshots`, which is old copies of all of the above, along with `/persist/var` and `/nix`. A rebuild brings those back.

## How

For the settings and secrets, run this with a USB stick plugged in, with its name in place of `STICK` (`ls /run/media/$USER` shows it):

```bash
ephemeral backup save /run/media/$USER/STICK
```

It saves `settings.json`, `hardware-configuration.nix`, `apps.json`, `smb-shares.json`, `backup.json` and the secrets above into one file, encrypted with a passphrase you pick, and prints how to restore it.

For your home folder, set up scheduled backups, below, or use Vorta or Pika Backup from `ephemeral apps` under Utilities. All three make encrypted, deduplicated Borg backups, so they can share a repository.

Test a restore now and then.

## Scheduled backups

The system backs up every 6 hours with [borgmatic](https://torsion.org/borgmatic/), as root, whether anyone is logged in or not. A run is skipped while a laptop is on battery, and one missed while it was off runs at the next start. It goes to a [Hetzner Storage Box](https://www.hetzner.com/storage/storage-box/), [BorgBase](https://www.borgbase.com/), another machine you can reach over SSH, or a folder such as a USB disk's.

```bash
ephemeral backup setup
```

It makes an SSH key for root and asks for a passphrase for the backups, both kept in `/persist/etc/borg`, readable only by root. Then it asks where the backups go, and shows the key to add at the storage box or BorgBase. `ephemeral backup setup --from-pass` takes the passphrase from Proton Pass instead, from the `password` field of the `borg` item in the `Personal` vault, or from another one given as `pass://VAULT/ITEM/FIELD`. Then, once:

```bash
ephemeral update                                         # puts the backups on the schedule
sudo borgmatic repo-create --encryption repokey-blake2   # once, for a new repository
sudo systemctl start borgmatic                           # the first backup, now
```

The repositories are in `backup.json` next to `settings.json`, which git ignores, since the address has your account name in it. `ephemeral backup setup add LABEL REPOSITORY` and `ephemeral backup setup remove LABEL` change it, and with none left, the schedule stops at the next `ephemeral update`. The first connection takes the server's host key, and later ones refuse a different one.

Keep the passphrase somewhere other than this machine: without it the backups can't be read. `ephemeral backup save` saves a copy.

### What's in them

Your home folder, `/persist/etc` (the machine config and its secrets) and the Secure Boot keys, without caches and what can be fetched or built again: `.cache`, the trash, Steam's games, Flatpak and Podman's downloads, the language package managers' caches, `node_modules`, `.venv` and `.direnv`. A folder with a `CACHEDIR.TAG` file, as Rust's `target` has, or a `.nobackup` file you put there, is left out. [`modules/backup-patterns.lst`](../modules/backup-patterns.lst) has the full list.

To back up more, such as a server's data in `/persist/var/lib`, add lines in a module of your own. They're read before the built-in ones, so a `+` line keeps something they'd leave out:

```nix
{
  flake.modules.nixos.pc.ephemeral.backup.patterns = [
    "R /persist/var/lib/jellyfin"
    "! persist/var/lib/jellyfin/transcodes"
  ];
}
```

`ephemeral.backup.schedule` changes when it runs, as systemd's `OnCalendar`.

### Checking on them

`ephemeral doctor` says when the passphrase or key is missing, or the last run failed. Then:

```bash
journalctl -u borgmatic           # how the last runs went
sudo borgmatic list               # the archives
sudo borgmatic list --archive latest --find notes.txt
sudo borgmatic extract --archive latest --path home/$USER/Documents --destination /tmp/restore
```

borgmatic keeps the last 24 runs, then one a day for a week, one a week for a month and one a month for six months, and checks the repository every two weeks.

## After a reinstall

1. Install with the same username.
2. Restore your home folder from the backup. For scheduled backups, restore the file from `ephemeral backup save` first, which has their passphrase and key, then rebuild and `borgmatic extract` as above.
3. Put your config back: clone your private repo into `/persist/etc/nixos`, then restore the file from `ephemeral backup save` as it says (`nix run nixpkgs#age -- -d <file> | sudo tar -C / -xf -`). If the hardware changed, keep the `hardware-configuration.nix` the installer just wrote: copy it aside first and back after.
4. Rebuild with `ephemeral update`.
