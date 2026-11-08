# Features

## Snapshots

snapper keeps read-only snapshots of `/persist`, and with it your home folder: 24 hourly, 7 daily and 4 weekly. They undo deletes and bad edits, but they're on the same disk, so they aren't a [backup](backup.md).

```bash
sudo snapper -c persist list
sudo cp -a /persist/.snapshots/<n>/snapshot/home/$USER/path/to/file ~/path/to/
```

Only root can read them, because old snapshots still contain old password hashes and keys. Exclude `/persist/.snapshots` from Borg or any other backup of `/persist`, or every snapshot is backed up again.

## LUKS header backup

If the LUKS header at the start of the disk gets damaged, the disk can't be unlocked even with the right passphrase. Keep a copy on a USB stick:

```bash
luks-header-backup /run/media/$USER/<stick>/luks-header.img
```

It refuses to write onto the encrypted disk itself or into memory. The copy unlocks with every passphrase the disk had when it was made, so after changing or removing one, make a new copy and destroy the old ones.

## Disk health

smartd watches the disks and sends a desktop notification when one starts to fail.

## Control D

```bash
controld-setup
ephemeral-update
```

Stores your resolver id in `/persist/etc/controld-resolver` (root only, never in the Nix store) and sets `useControlD`. All DNS then goes over TLS to Control D, with no fallback servers.

## SMB shares

```bash
smb-setup
ephemeral-update
```

Asks for the server, share, user and password. The password goes to `/persist/etc/smb/<label>.creds` (root only) and the mount to the gitignored `smb-shares.json`. Mounts use SMB 3.1.1 with encryption (`seal`), and don't block booting if the server is away.

## NVIDIA

The installer asks about drivers when it finds an NVIDIA card, and writes the answer to `nvidia` in `settings.json`. To change it later, edit that key and rebuild. `open` uses the current driver with NVIDIA's open kernel modules; `legacy` uses the 580 driver, the last one for GTX 900 and 10 series cards. The driver isn't in the NixOS binary cache, since it's unfree, so the first build compiles its kernel module and takes a few minutes.

Laptops with both an NVIDIA and an Intel or AMD GPU also need [PRIME](https://wiki.nixos.org/wiki/NVIDIA) set up in a private module, with the bus IDs from `lspci`.

## GNOME extensions

Extension Manager is installed in place of GNOME's own Extensions app. The tray (AppIndicator) and Caffeine extensions come from Nix and are on by default. A copy of an extension in `~/.local/share/gnome-shell/extensions` takes precedence over the Nix one, so remove it there to use the version from this repo.

## Laptops and fingerprint login

The installer sets `laptop` when it finds a battery, and asks about `fingerprint` when it sees a USB device from a fingerprint reader maker. Enroll a finger once with `fprintd-enroll`; after that the login screen and sudo accept it. Enrolled prints are kept on `/persist`.

## WireGuard

NetworkManager handles WireGuard itself, so there's nothing extra to install. On GNOME or Plasma, import a `.conf` file from the network settings (VPN, then import from file); `nmcli connection import type wireguard file wg0.conf` does the same from a terminal.

## Tailscale

Set `"useTailscale": true`, rebuild, then sign in once with `sudo tailscale up`. Its state stays on `/persist`, and OpenSnitch gets a rule that lets `tailscaled` through.

## Scanners

SANE is set up with the driverless `sane-airscan` backend, and Document Scanner is installed on every desktop, so most USB scanners just work. Network scanners aren't found automatically, because mDNS discovery (Avahi) is off on purpose. Add yours by address in a private module:

```nix
{
  flake.modules.nixos.pc.environment.etc."sane.d/airscan.d/local.conf".text = ''
    [devices]
    "Office scanner" = http://192.168.1.50/eSCL
  '';
}
```

## Running things without installing them

With `extras` on: type a command that isn't installed and the shell names the package that has it. `, cowsay hello` runs it once without installing anything. Both use a prebuilt package index from [nix-index-database](https://github.com/nix-community/nix-index-database).

## Shell

With `extras` on, each new Ghostty window opens with fastfetch: the wallpaper's snowflake breaking up into pixels, in colored characters with EPHEMERAL under it, next to the system info in boxed sections (System, Hardware, Desktop, Terminal). Ghostty opens at 151×43 so both fit. The logo is drawn from `assets/wallpaper.svg` when the system is built (`modules/dotfiles/fastfetch/`), so it follows the wallpaper if you change that file. fzf adds Ctrl-T (pick a file) and Alt-C (jump to a directory). atuin owns Ctrl-R: a searchable history that stays on this machine, with no account or sync. Import your existing history once with `atuin import auto`. `bat` is `cat` with syntax highlighting, and `tldr <command>` shows short examples.

## Extra apps

`ephemeral-apps` offers over 80 common apps by category: browsers, chat, office, media, graphics, games, development, security, terminal apps, utilities, system tuning and virtual machines. Labels show which ones are unfree, which come from Flathub, and which carry a warning (Docker and Wireshark add you to a powerful group, LocalSend opens a port). Every warning is shown again before anything is saved.

The installer offers the same list. Your picks are saved to `apps.json` next to `settings.json`, a plain list such as `["discord", "obsidian", "docker"]`. Commit it with the rest of your private flake; it isn't a secret, and it brings the same apps to your next machine. On a rebuild:

- Nix packages are installed system-wide, and unfree ones are added to the allowlist for you.
- Apps that need more (Docker, Wireshark, GameMode, LocalSend) get their settings, groups and `/persist` folders.
- Flathub apps are installed for your user at login, from the same pinned Flathub file as the system remote. Unpicking one removes it, but only if it was installed this way; Flatpaks you installed yourself are left alone.

A name in `apps.json` that's no longer in the catalog gives a warning, not a failed build.

Your private flake can add its own apps to the picker:

```nix
{
  ephemeral.apps.anki = {
    label = "Anki";
    category = "Office";
    description = "flashcards";
    package = "anki";
  };
}
```

CI evaluates a machine with every app picked, so a package renamed upstream shows up there before it breaks a rebuild.

## System tuning

zram swap and systemd-oomd are always on. Three more are in `ephemeral-apps` under System, off unless you pick them:

- **Profile-sync-daemon** keeps Firefox and Chromium-based browser profiles in RAM and copies them back every 10 minutes and at logout. It helps on slow disks; on an SSD you won't notice much.
- **ananicy-cpp** raises or lowers the CPU and IO priority of known programs, using CachyOS's rules: games and audio up, compilers and indexers down.
- **bpftune** watches the network and memory and adjusts kernel settings such as TCP buffer sizes as the load changes. None of what it changes overlaps with the hardening settings.

## Virtual machines

`ephemeral-apps` has a Virtualization category:

- **virt-manager** runs VMs through libvirt. Windows 11 works out of the box: pick Windows 11 as the OS and virt-manager adds the TPM 2.0 it needs. For Secure Boot, tick "Customize configuration before install" and check that Firmware under Overview is the `secure` UEFI image. The Secure Boot keys aren't enrolled, which Windows 11 accepts. VM disks and settings are kept in `/var/lib/libvirt`.
- **VM Curator** is a terminal UI that runs QEMU directly, with ready-made profiles for over 130 systems. Its VMs live in a folder in your home, and it finds the UEFI firmware and TPM on its own.
- **GPU passthrough** gives a virt-manager VM the only graphics card on a desktop. In the VM's settings, add the card and its HDMI audio as PCI host devices. Starting the VM logs you out, unloads the GPU driver and hands the card to the guest, so its monitor shows the guest. When the guest shuts down, the card comes back and the login screen returns. If the driver won't let go, the start fails and you're back at the login screen; `journalctl -u libvirtd` says what held it. NVIDIA cards often need their vBIOS as a ROM file on the host device. A VM that gets a second GPU instead isn't affected.

## Flatpak

Flathub is added system-wide from a pinned copy of its repo file, so its signing key can't be swapped. Install Flathub apps through `ephemeral-apps`, or with `flatpak install --user flathub <id>` for anything that isn't in the list.

## direnv

direnv and nix-direnv are on, with the hook in the system zshrc:

```bash
echo 'use flake' > .envrc
direnv allow
```

## Proton Pass

`settings-from-pass` reads an item (vault `passSettingsVault` and item `passSettingsItem`, by default `Personal` and `nixos-settings`) and writes `settings.from-pass.json`, which is merged over `settings.json` when `usePassSettings` is true. Fields it understands, and the only ones the rebuild takes from that file:

- `hostname`, `username`, `diskDevice`, `swapSize`, `timeZone`, `desktop`
- `useFlakePassCli`, as the text `true` or `false`
- `controldResolver`, written to `/persist/etc/controld-resolver`; it also turns on `useControlD`

```bash
pass-cli login
settings-from-pass
ephemeral-update
```

`ssh-pubs-from-pass` writes the public half of each SSH key item in `passSshVault` to `~/.ssh/<title>.pub`, for `IdentityFile` lines. `--list` shows what it would write. `PASS_SETTINGS_VAULT`, `PASS_SETTINGS_ITEM` and `PASS_SSH_VAULT` change where they look.

### SSH agent

With `"usePassSshAgent": true`, a user service starts `pass-cli ssh-agent` when you log in and serves the SSH keys in `passSshVault`, so the private keys never have to sit in `~/.ssh`. New keys added to the vault show up within 30 seconds. OpenSnitch gets a rule that lets `pass-cli` reach `proton.me`.

It replaces the desktop's own SSH agent (GNOME's gcr), so every app uses it, Flatpaks with SSH access like Pika Backup and Vorta included. While you're logged out of `pass-cli` the service skips itself and there's no agent; `ssh` then only has the key files in `~/.ssh`. After `pass-cli login`, start it without logging out:

```bash
systemctl --user start proton-pass-ssh-agent
ssh-add -l
```

Turning the setting on takes effect for apps at the next login. `journalctl --user -u proton-pass-ssh-agent` shows why the agent didn't start.
