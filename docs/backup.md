# Backups

Snapshots undo a delete, but they live on the same disk. A reinstall, a dead disk or a lost laptop takes them with everything else, so keep a copy somewhere else.

## What to back up

- **Your home folder.** All your files, and the settings of every app.
- **The machine config.** `/persist/etc/nixos` is best kept in a private git repo, but `settings.json` and `hardware-configuration.nix` are gitignored, so copy those two as well. Add `apps.json` and `smb-shares.json` if you commit neither.
- **Secrets you can't download again:** the Control D id in `/persist/etc/controld-resolver`, SMB passwords and Wi-Fi passwords. They're root-only, so a backup app running as you can't read them. Keeping them in a password manager is simpler.
- **The LUKS header**, once, with [`luks-header-backup`](features.md#luks-header-backup).

Skip `/persist/.snapshots`, which is old copies of all of the above, along with `/persist/var` and `/nix`. A rebuild brings those back.

## How

Vorta and Pika Backup are in `ephemeral-apps` under Utilities. Both make encrypted, deduplicated Borg backups to a USB disk or a server. Point them at your home folder and leave out `.cache`, `.local/share/Trash` and `.var/app/*/cache`. Keep the repository passphrase somewhere other than this laptop.

Test a restore now and then.

## After a reinstall

1. Install with the same username.
2. Restore your home folder from the backup.
3. Put your config back: clone your private repo, or copy your files, into `/persist/etc/nixos`, then add the saved `settings.json` and `hardware-configuration.nix`. Keep the `hardware-configuration.nix` the installer just wrote if the hardware changed.
4. Rebuild with `ephemeral-update`.
