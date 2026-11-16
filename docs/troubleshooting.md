# When something breaks

Start with `ephemeral-doctor`. It checks the usual suspects and prints the command that fixes each problem it finds.

**A rebuild broke something.** Go back to the system before it:

```bash
ephemeral-update --previous
```

`ephemeral-update --list` shows the older ones, with the date and config release of each. If the desktop doesn't come up at all, pick the previous entry in the boot menu instead: press a key while it shows, for 3 seconds at start-up. Then fix what broke in `/persist/etc/nixos`, and `ephemeral-update --check` tells you whether it builds before you switch to it.

**You want the system exactly as it was installed.** Installs from v3.0.0 on keep a read-only copy of the config they installed. This rebuilds from it, which resets the system but not your files:

```bash
ephemeral-update --as-installed
```

Your own config in `/persist/etc/nixos` is untouched, so a plain `ephemeral-update` takes you back to it.

**You deleted or broke a file in your home folder.** Copy it back from a snapshot; see [Snapshots](features.md#snapshots).

**The graphical login doesn't come up.** Press Ctrl+Alt+F3 for a text console, log in, and look at `journalctl -b -p err`. Rolling back as above is usually the quickest fix.

**The firmware refuses to start the machine after you turned Secure Boot on**, or after a reinstall. Turn Secure Boot off in the firmware setup and it starts again. Then `ephemeral-doctor` says what's missing; the steps are in [Secure Boot](security.md#secure-boot).

**The disk won't unlock with the right passphrase.** The LUKS header may be damaged. Boot the NixOS installer USB and restore the copy you made with [`luks-header-backup`](features.md#luks-header-backup):

```bash
sudo cryptsetup luksHeaderRestore /dev/disk/by-partlabel/disk-main-luks --header-backup-file /path/to/luks-header.img
```

**`ephemeral-doctor` says `/` wasn't wiped.** The machine works, but it isn't resetting its root, so files outside the kept ones stay. Your files are fine: they're on `/persist`, which the reset never touches. The usual cause is a missing empty snapshot the reset starts from, and this makes it again (it asks first):

```bash
sudo ephemeral-doctor --fix-root-reset
```

Reboot afterwards. If it says the snapshot is there, `journalctl -b -u rollback` shows what else stopped the reset.

**A device stopped working after v3.4.0.** That release turned on the IOMMU for every device. To turn it back off, save this as `/persist/etc/nixos/modules/iommu.nix` and run `ephemeral-update`:

```nix
{ lib, ... }:
{
  flake.modules.nixos.pc.boot.kernelParams = lib.mkAfter [ "iommu.passthrough=1" ];
}
```

**An old program or a debugging tool stopped working after v3.10.0.** That release turned off the legacy vsyscall page, which some very old binaries need, and debugfs, which tools such as `powertop` read. The last setting on the kernel command line wins, so to turn either back on, save this as `/persist/etc/nixos/modules/kernel.nix` and run `ephemeral-update`:

```nix
{ lib, ... }:
{
  flake.modules.nixos.pc.boot.kernelParams = lib.mkAfter [
    "vsyscall=xonly"
    "debugfs=on"
  ];
}
```

**A Wi-Fi login page won't open, or nothing loads on hotel or airport Wi-Fi.** With encrypted DNS or Control D on, the network can't redirect you to its login page. Turn it off for a moment, log in, and turn it back on:

```bash
sudo resolvectl dnsovertls "$(ip -o route get 1.1.1.1 | awk '{ print $5 }')" no
```

That only lasts until the network reconnects. If it still doesn't load, run `ephemeral-setup`, pick the network's DNS, and switch back once you're through.

**An app can't connect.** Check OpenSnitch's rules first (see the note in the [README](../README.md)).

**Nothing can connect, and `systemctl status opensnitchd` shows it failed.** When OpenSnitch crashes, new connections out are refused until it's running again, so one that keeps crashing leaves you offline. `sudo systemctl restart opensnitchd` tries again; if it still fails, `sudo nft destroy table inet opensnitch-down` lets traffic through until the next reboot, and `ephemeral-report` collects what's needed to report it.

## Reporting a problem

Run `ephemeral-report`, read it, and paste it into a [new issue](https://github.com/the-wittch/ephemeral-nixos-config/issues/new/choose). It lists versions, settings, what `ephemeral-doctor` found, the last lines of each failed service and recent errors, and leaves out user, host and vault names. It's on the small install too.

## What's tested

This is a personal project shared as-is. x86_64 machines with UEFI are supported. Every change is evaluated on GNOME, Plasma, niri and Umbriel with both profiles, with each optional feature, and with every app in the picker. Each release builds every desktop, boots each of them in a VM, and moves a machine from the previous release to the new one, both by switching and by booting. A small install is also switched to the full system and back, as `ephemeral-setup` does it. NVIDIA is only evaluated, not run. Secure Boot is tested on the VM's firmware, not on real hardware.
