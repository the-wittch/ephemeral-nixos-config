# When something breaks

Start with `ephemeral doctor`, which checks the machine and prints the command that fixes each problem it finds.

**A rebuild broke something.** Go back to the system before it:

```bash
ephemeral update --previous
```

`ephemeral update --list` shows the older ones, with the date and config release of each. If the desktop doesn't come up at all, pick the previous entry in the boot menu instead: press a key while it shows, for 3 seconds at start-up. Then fix what broke in `/persist/etc/nixos`, and `ephemeral update --check` tells you whether it builds before you switch to it.

**You want the system exactly as it was installed.** Installs from v3.0.0 on keep a read-only copy of the config they installed. This rebuilds from it, which resets the system but not your files:

```bash
ephemeral update --as-installed
```

Your own config in `/persist/etc/nixos` is untouched, so a plain `ephemeral update` takes you back to it.

**You deleted or broke a file in your home folder.** Copy it back from a snapshot; see [Snapshots](features.md#snapshots).

**The graphical login doesn't come up.** Press Ctrl+Alt+F3 for a text console, log in, and look at `journalctl -b -p err`. Rolling back as above is usually the quickest fix.

**The firmware refuses to start the machine after you turned Secure Boot on**, or after a reinstall. Turn Secure Boot off in the firmware setup and it starts again. Then `ephemeral doctor` says what's missing; the steps are in [Secure Boot](security.md#secure-boot).

**`ephemeral update` says the firmware doesn't say whether it's in Setup Mode**, and `bootctl status` shows `Secure Boot: disabled (unsupported)`. The firmware has stopped reporting Secure Boot at all. On Framework laptops, "Erase all Secure Boot Settings" does this. In the firmware setup, under Administer Secure Boot, pick "Restore Secure Boot to Factory Settings" and save with F10. Then delete the PK by hand: under PK Options, delete each entry. If `bootctl status` doesn't show `disabled (setup)` after that, delete the KEK and DB entries the same way. Then run `ephemeral update`.

**`bootctl status` shows `Secure Boot: disabled (unsupported)` although Secure Boot is on**, and `ls /sys/firmware/efi/efivars` lists only a few variables. Some firmware hides most of its variables from Linux; a Framework started doing it after a firmware update, and after "Erase all Secure Boot Settings" before that. Secure Boot still works. `sudo journalctl -k -b | grep -i "secure boot"` shows what the firmware told the kernel at boot, and `ephemeral doctor` and `ephemeral setup` read the same thing, so the TPM PIN is still offered. Only the revocation list (dbx) can't be checked while it's hidden.

**The disk asks for the passphrase although you set up a TPM PIN.** The TPM didn't unlock it: wrong PINs locked it out for a while, Secure Boot is off, or a firmware update changed its keys or revocation list. The passphrase works as always. Once the machine is up, run `sudo ephemeral doctor`, then `ephemeral setup` to enroll the PIN again if it says so.

**The disk keeps asking for the TPM PIN.** The PIN was wrong. Once the TPM has had enough wrong ones it stops taking them, and the boot asks for the passphrase. See [TPM unlock](security.md#tpm-unlock).

**The right password doesn't log you in.** The login password is the hash in `/persist/passwords/<user>`, so a missing or broken file locks you out. Boot the installer USB, unlock the disk, and write the hash again, with your own username in place of `nixuser`:

```bash
sudo cryptsetup open /dev/disk/by-partlabel/disk-main-luks cryptroot
sudo mount -o subvolid=5 /dev/mapper/cryptroot /mnt
mkpasswd -m yescrypt | sudo tee /mnt/persist/passwords/nixuser
sudo chmod 600 /mnt/persist/passwords/nixuser
sudo umount /mnt
sudo cryptsetup close cryptroot
```

If the USB has no `mkpasswd`, run `nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#mkpasswd` first. To change a password you still know, use `ephemeral password` instead.

**The disk won't unlock with the right passphrase.** The LUKS header may be damaged. Boot the NixOS installer USB and restore the copy you made with [`ephemeral backup header`](features.md#luks-header-backup):

```bash
sudo cryptsetup luksHeaderRestore /dev/disk/by-partlabel/disk-main-luks --header-backup-file /path/to/luks-header.img
```

**The boot menu doesn't come up at all**, after a firmware update or reset, or a change to the boot partition. If the firmware lost only its boot entry, nothing is broken: firmware with no entries starts Limine from the fallback path anyway, so check the firmware's boot order first. If Limine itself is damaged, boot the installer USB and install the boot loader again from the system on the disk:

```bash
sudo cryptsetup open /dev/disk/by-partlabel/disk-main-luks cryptroot
sudo mount -o subvol=/root /dev/mapper/cryptroot /mnt
sudo mkdir -p /mnt/nix /mnt/persist /mnt/var/log /mnt/boot
sudo mount -o subvol=/nix /dev/mapper/cryptroot /mnt/nix
sudo mount -o subvol=/persist /dev/mapper/cryptroot /mnt/persist
sudo mount -o subvol=/log /dev/mapper/cryptroot /mnt/var/log
sudo mount /dev/disk/by-partlabel/disk-main-ESP /mnt/boot
sudo nixos-enter --root /mnt -c 'NIXOS_INSTALL_BOOTLOADER=1 /nix/var/nix/profiles/system/bin/switch-to-configuration boot'
sudo umount -R /mnt
sudo cryptsetup close cryptroot
```

It puts back the newest system's boot menu and entry; your files aren't touched. With Secure Boot, it signs with this machine's keys from `/persist`, which is why that has to be mounted.

**`ephemeral doctor` says `/` wasn't wiped.** The machine works, but it isn't resetting its root, so files outside the kept ones stay. Your files are fine: they're on `/persist`, which the reset never touches. The usual cause is a missing empty snapshot the reset starts from, and this makes it again (it asks first):

```bash
sudo ephemeral doctor --fix-root-reset
```

Reboot afterwards. If it says the snapshot is there, `journalctl -b -u rollback` shows what else stopped the reset.

**A device stopped working after v3.4.0.** That release turned on the IOMMU for every device. To turn it back off, save this as `/persist/etc/nixos/modules/iommu.nix` and run `ephemeral update`:

```nix
{ lib, ... }:
{
  flake.modules.nixos.pc.boot.kernelParams = lib.mkAfter [ "iommu.passthrough=1" ];
}
```

**An old program or a debugging tool stopped working after v3.10.0.** That release turned off the legacy vsyscall page, which some very old binaries need, and debugfs, which tools such as `powertop` read. The last setting on the kernel command line wins, so to turn either back on, save this as `/persist/etc/nixos/modules/kernel.nix` and run `ephemeral update`:

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

That only lasts until the network reconnects. If it still doesn't load, run `ephemeral setup`, pick the network's DNS, and switch back once you're through.

**An app can't connect.** Check OpenSnitch's rules first (see the note in the [README](../README.md)).

**Nothing can connect, and `systemctl status opensnitchd` shows it failed.** New connections out are refused at boot until OpenSnitch is filtering, and after it crashes until it's running again, so one that doesn't start or keeps crashing leaves you offline. `sudo systemctl restart opensnitchd` tries again; if it still fails, `sudo nft destroy table inet opensnitch-down` lets traffic through until the next reboot, and `ephemeral report` collects what's needed to report it.

## Reporting a problem

Run `ephemeral report`, read it, and paste it into a [new issue](https://github.com/the-wittch/ephemeral-nixos-config/issues/new/choose). It lists versions, settings, what `ephemeral doctor` found, the last lines of each failed service and recent errors, and leaves out user, host and vault names. It's on the small install too.

## What's tested

This is a personal project shared as-is. x86_64 machines with UEFI are supported. Every change is evaluated on GNOME, Plasma, niri, Umbriel and a server with no desktop, with both profiles, with each optional feature, and with every app in the picker. Each release builds every desktop, boots each of them in a VM, and moves a machine from the previous release to the new one, both by switching and by booting. A small install is also switched to the full system and back, as `ephemeral setup` does it. NVIDIA is only evaluated, not run. Secure Boot and TPM unlock are tested on the VM's firmware every release, and have been run by hand on one Framework laptop.
