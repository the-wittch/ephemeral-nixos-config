# When something breaks

**A rebuild broke the desktop or won't boot.** Every rebuild is a new boot entry, and the last five are kept. Press a key during the 3-second boot menu and pick the previous one. Once you're back in, either fix the config and rebuild, or make the old one stick:

```bash
sudo nixos-rebuild switch --rollback
```

**You want the system exactly as it was installed.** Since v3.0.0 the installer keeps a read-only copy of the config it installed in `/persist/etc/nixos-install`, pinned to the same release. Rebuilding from it resets the system, not your files:

```bash
sudo nixos-rebuild switch --flake path:/persist/etc/nixos-install#nixos
```

Your own config in `/persist/etc/nixos` is untouched, so switching back to it is a normal rebuild.

**You deleted or broke a file in your home folder.** Copy it back from a snapshot; see [Snapshots](features.md#snapshots).

**The graphical login doesn't come up.** Press Ctrl+Alt+F3 for a text console, log in, and look at `journalctl -b -p err`. Rolling back as above is usually the quickest fix.

**The disk won't unlock with the right passphrase.** The LUKS header may be damaged. Boot the NixOS installer USB and restore the copy you made with [`luks-header-backup`](features.md#luks-header-backup):

```bash
sudo cryptsetup luksHeaderRestore /dev/disk/by-partlabel/disk-main-luks --header-backup-file /path/to/luks-header.img
```

**A device stopped working after v3.4.0.** That release turned on the IOMMU for every device. To turn it back off, add this to a module of your own and rebuild:

```nix
{ lib, ... }:
{
  flake.modules.nixos.pc.boot.kernelParams = lib.mkAfter [ "iommu.passthrough=1" ];
}
```

**An app can't connect.** Check OpenSnitch's rules first (see the note in the [README](../README.md)).

## Reporting a problem

Run `ephemeral-report`, read it, and paste it into a [new issue](https://github.com/the-wittch/ephemeral-nixos-config/issues/new/choose). It lists versions, settings, failed services and recent errors, and leaves out user, host and vault names. On the minimal profile it isn't installed; include the output of `nixos-version` and `systemctl --failed` instead.

## What's tested

This is a personal project shared as-is. x86_64 machines with UEFI are supported. CI evaluates both profiles on GNOME, Plasma and niri, and every app in the picker. On each release it boots both profiles on GNOME in a VM and switches a machine from the previous release to the new one. NVIDIA isn't tested, and there's no Secure Boot.
