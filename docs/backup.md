# Backups

Snapshots undo a delete, but they live on the same disk. A reinstall, a dead disk or a lost laptop takes them with everything else, so keep a copy somewhere else.

## What to back up

- **Your home folder.** All your files, and the settings of every app.
- **The machine config.** `/persist/etc/nixos` is best kept in a private git repo. What git leaves out is saved by `ephemeral-backup`, below.
- **Secrets you can't download again:** the Control D id, SMB and Wi-Fi passwords, and the SSH host key. They're root-only, so a backup app running as you can't read them; `ephemeral-backup` saves them too.
- **The LUKS header**, once, with [`luks-header-backup`](features.md#luks-header-backup).

Skip `/persist/.snapshots`, which is old copies of all of the above, along with `/persist/var` and `/nix`. A rebuild brings those back.

## How

For the settings and secrets, run this with a USB stick plugged in:

```bash
ephemeral-backup /run/media/$USER/<stick>
```

It saves `settings.json`, `hardware-configuration.nix`, `apps.json`, `smb-shares.json` and the secrets above into one file, encrypted with a passphrase you pick, and prints how to restore it.

For your home folder, use Vorta or Pika Backup, in `ephemeral-apps` under Utilities. Both make encrypted, deduplicated Borg backups to a USB disk or a server. Point them at your home folder and leave out `.cache`, `.local/share/Trash` and `.var/app/*/cache`. Keep the repository passphrase somewhere other than this laptop.

Test a restore now and then.

## After a reinstall

1. Install with the same username.
2. Restore your home folder from the backup.
3. Put your config back: clone your private repo into `/persist/etc/nixos`, then restore the `ephemeral-backup` file as it says (`age -d <file> | sudo tar -C / -xf -`). If the hardware changed, keep the `hardware-configuration.nix` the installer just wrote: copy it aside first and back after.
4. Rebuild with `ephemeral-update`.
