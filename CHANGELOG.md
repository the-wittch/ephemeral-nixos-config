# Changelog

Breaking changes are listed first in each release, with what to do about them. Releases before 3.0.0 are on the [releases page](https://github.com/the-wittch/ephemeral-nixos-config/releases).

## 5.0.0

### Breaking

- What's kept across reboots is set up by [preservation](https://github.com/nix-community/preservation) instead of impermanence, with preservation's own option. In your own modules, rename `environment.persistence."/persist"` to `preservation.preserveAt."/persist"`. `directories` and `files` keep their fields (`directory`, `file`, `user`, `group`, `mode`). A module that still uses the old name stops the rebuild with a message saying so.
- A kept folder now gets its owner and mode at every boot, root and `0755` unless the entry gives others. impermanence only set them when it made the folder. For a folder a service owns, give `user`, `group` and `mode` as it has them now (`ls -ld` shows them), or the service may lose access to it. `sudo ephemeral-doctor audit` suggests entries with them filled in. For a `DynamicUser` folder in `/var/lib/private`, add `configureParent = true; parent.mode = "0700";`, which replaces a separate tmpfiles rule for `/var/lib/private`. [Keeping things across reboots](docs/persistence.md) has examples.
- The update takes a reboot. A running system can't move from impermanence's mounts to preservation's, so switching to 5.0.0 straight away is refused, with nothing changed. `ephemeral-update` stops there, after asking about the new version, and its advice about going back can be ignored. Set the update up for the next boot instead, then reboot:

  ```sh
  nh os boot path:/persist/etc/nixos --hostname nixos
  systemctl reboot
  ```

  To go back afterwards, pick the previous entry in the boot menu; `ephemeral-update --previous` would switch back on the running system, which has the same problem. A folder added to the list later is kept from the next reboot.

### Changed

- `/etc/machine-id` is a link to `/persist/etc/machine-id`, made in the initrd, and a new machine gets its id there on its first boot, as preservation's first-boot setup does. `/var/lib/systemd/random-seed` is a link too. `/home` and `/var/lib/nixos` are mounted in the initrd, so users keep their uid and their home folder is in place before NixOS sets them up.
- The kept folders that belong to a service user keep that owner: the Plasma and Noctalia greeters' (`0750`), colord's, fwupd's and systemd-timesyncd's. `AccountsService` keeps `0775` and Docker's folder `0710`.
- The two activation scripts that set `/persist`'s folder modes and the home folder's owner are gone. preservation makes missing folders itself, and the home folder on `/persist` is a tmpfiles rule. Installs from before installer v3.7.3 that left `/persist/etc/nixos` readable by root alone are no longer fixed at boot; `ephemeral-update` says how to fix it if it can't read the folder.
- `ephemeral-doctor audit` suggests entries in the new form, with the folder's owner and mode when they aren't root and `0755`.

## 4.20.0

### Added

- Flatpak apps are updated once a week on the full system with a desktop, along with the runtimes they use, and runtimes nothing uses any more are removed. It runs at a random time in the week, only on mains power, and catches up after a week the machine was off. Nothing updated them before unless a software centre happened to be open. `ephemeral-doctor` says when the last update failed. `"flatpakUpdates": false` turns it off. [Flatpak](docs/features.md#flatpak) has more.
- An OpenSnitch rule lets `flatpak` reach Flathub, so installing the apps picked with `ephemeral-apps` and updating them no longer asks.

### Removed

- `useFlakePassCli`, the `pass-cli` downloaded from Proton's releases, and `update-pass-cli`. nixpkgs has the same version, so `pass-cli` always comes from there now. A `settings.json` that still sets it gets a warning to delete it; nothing else changes.

## 4.19.0

### Changed

- Syncthing's web page asks for a password. Before, anything that could reach 127.0.0.1:8384 could change what Syncthing shares, an app sandboxed by Flatpak included. Log in with your username and the password in `/persist/etc/syncthing/gui-password`, made the first time Syncthing starts after the update, and let the browser remember it. Syncthing Tray uses Syncthing's API key, so it isn't affected. OpenSnitch lets the start-up step that sets the password through Syncthing's API reach it on 127.0.0.1, so it doesn't ask about curl. [Syncthing](docs/features.md#syncthing) has more.
- `ephemeral-backup` also saves Syncthing's web page password.
- The secret check in CI catches more: GitHub's other token types (`gho_`, `ghu_`, `ghs_`, `ghr_`), and DSA and encrypted private keys, the same as the check `ephemeral-update` runs before a rebuild.

## 4.18.0

### Added

- `ephemeral-apps` has a search: "Search all apps" at the top of its menu finds apps by the start of any word in their name or description, across the categories, and adds the ones you tick.

### Changed

- The Security category is split in two: Passwords, for Bitwarden, KeePassXC and age, and Security testing, for the penetration-testing tools. Picked apps stay picked.
- `ephemeral-apps` shows the categories in the same order as the installer, which now both read from the config.
- A machine without a desktop gets the terminal apps ticked by default (htop, ripgrep, dig and the WireGuard tools), as the installer already ticked them. It got none before.
- Shorter lines in the desktop and install-type menus, so they fit an 80-column screen: the headless choice is now just "None".

### Fixed

- `ephemeral-apps` on a machine without a desktop offered every app and showed Firefox and VLC ticked, though they're never installed there. It now offers the terminal apps only, as the installer does.
- `ephemeral-apps` showed 10 lines of its category menu, so "Review and save" and "Quit without saving" were on a second page. The menu is now tall enough for all of them.

## 4.17.0

### Added

- Scheduled backups with borgmatic, every 6 hours, as root: your home folder, `/persist/etc` and the Secure Boot keys, without caches and what can be fetched or built again. They go to a Hetzner Storage Box, BorgBase, another machine over SSH, or a disk. `backup-setup` makes root's SSH key, keeps the passphrase root-only in `/persist/etc/borg`, typed or from Proton Pass, and writes the repositories to the gitignored `backup.json`. A module can back up more through `ephemeral.backup.patterns`. Nothing changes until `backup-setup` has been run. [Backups](docs/backup.md#scheduled-backups) has the details.
- `ephemeral-doctor` says when scheduled backups are missing their passphrase or key, or the last one failed.
- `ephemeral-backup` also saves `backup.json` and the scheduled backups' passphrase and key, which a restore needs.

## 4.16.0

### Added

- Servers. `"server": true` turns SSH on for the public keys in the new `sshKeys` setting, on every network, keys only, and turns sleep off. It works with a desktop, or with the new `"desktop": "none"` for a machine with no screen, which leaves out the desktop, sound, Flatpak, the boot splash, the default apps and OpenSnitch. After a reboot, `ssh -p 2222 root@<server>` asks for the disk passphrase, over Ethernet, with a host key of its own, sealed to the TPM when Secure Boot is on. [Servers](docs/servers.md) has the details.

## 4.15.0

### Added

- `ephemeral-restore <path>` brings back a file or folder, in your home folder or anywhere on `/persist`, as it was in one of the hourly snapshots. It lists the snapshots that have it, with their dates, and moves what's there now aside first, so a restore can be undone.
- The Orca screen reader on niri and Umbriel, as GNOME and Plasma already have it. On niri, Super+Alt+S starts it. [Features](docs/features.md#accessibility) covers the accessibility settings on each desktop.
- [Security notes](docs/security.md#changing-secrets) say how to change each secret: the login password, the disk passphrase, the TPM PIN, SSH keys, and the rest.
- [Features](docs/features.md#virtual-machines) lists ways to run something that's gone again when you stop it: `distrobox ephemeral`, `podman run --rm`, QEMU's `-snapshot` and the VM of your own config.
- OpenVPN, OpenConnect and strongSwan in `ephemeral-apps`, under Utilities, for VPNs set up in the desktop's network settings. [Features](docs/features.md#other-vpns-and-proxies) also says how to set a proxy.
- ROCm OpenCL in `ephemeral-apps`, under System, for compute on AMD graphics. [Features](docs/features.md#gpu-compute) covers NVIDIA too, containers included.
- [Features](docs/features.md#reaching-the-machine-from-your-other-devices) shows how to turn SSH on for Tailscale only, with keys, to reach or fix the machine from another device.

## 4.14.5

### Changed

- The boot menu's line under the selected generation names the config release instead of the nixpkgs version and commit: `NixOS Zokor 4.14.5 (Linux 6.18.58), built on …`. `nixos-version` still shows the nixpkgs version. The system's store path is named after the release too.

## 4.14.4

### Changed

- The boot menu shows only the snowflake, with its glow and glitches, at its own size in the middle of the screen, on the wallpaper's navy. Limine used to stretch the whole wallpaper to fit the screen without smoothing, so on a screen that isn't 16:9 the snowflake was pulled out of shape, with jagged edges. Now nothing is scaled, so it's sharp and the right shape on any screen.

## 4.14.3

### Changed

- The boot menu shows the wallpaper without its words, just the snowflake and the background, and drops the "EPHEMERAL NIX" title; Limine's version line is back in its place. The desktop wallpaper is unchanged.

## 4.14.2

### Changed

- The boot menu lets the wallpaper show through: its box is mostly transparent and further in from the screen's edges, with soft edges, and its title and key help are in the wallpaper's neon. [Dotfiles and appearance](docs/appearance.md#boot-menu) says how to change it.

## 4.14.1

### Changed

- On Plasma, `Meta+L` always locks the screen. Krohnkite asked for it too, to move the focus right, and which one got it depended on which asked first. KWin's own `Meta+Alt+Right` moves the focus right.

### Added

- `checks.docs-examples` loads every `nix` example in `docs/` into a GNOME machine on the full profile, so an example that uses a missing or renamed option fails CI.
- `check-links` checks the links between the docs, headings included; CI runs it on every change, docs-only ones too, and the installer runs it from the release it pins.
- `lib.mkFlake` takes `modules`, flake-parts modules to load besides the machine's `modules/` folder.

### Fixed

- [When something breaks](docs/troubleshooting.md) has the steps for a login that fails with the right password: writing the password hash again from the installer USB. The installer's troubleshooting pointed to steps that didn't exist.
- The security notes name OpenSnitch's boot guard among the services that run with most of the sandbox, and say which desktops lock with Super+Alt+L in one place.

## 4.14.0

### Changed

- The lock key on niri and Umbriel is Super+Alt+L, niri's own, and Super+L moves focus right again, as both desktops have it. GNOME takes Super+Alt+L too, beside its own Super+L. Plasma keeps Super+L only; there, Super+Alt+L switches the keyboard layout.

## 4.13.1

### Fixed

- Some firmware hides most of its variables from Linux, Secure Boot's included, and then `ephemeral-doctor` said Secure Boot wasn't reported, `ephemeral-setup` didn't offer the TPM PIN, and `ephemeral-update` said the keys couldn't be enrolled, all while Secure Boot was on. They now read what the firmware told the kernel at boot when the variables are missing. `ephemeral-doctor` says the revocation list can't be checked then, instead of calling it missing.

## 4.13.0

### Added

- `ephemeral-doctor` lists firmware updates that are waiting, with how to install them. With TPM unlock on, it also says that after a system firmware or dbx update, the boot may ask for the passphrase until the PIN is enrolled again. It only reads the list fwupd already downloads; nothing installs on its own, since a firmware update mustn't be cut off.

## 4.12.0

### Changed

- Super+L locks the screen on niri and Umbriel. It used to move focus to the window on the right, which Super+Right still does. On niri, Super+Alt+L locks too; it started swaylock, which isn't installed.
- niri gets its config from `/etc/niri/config.kdl`: niri's own defaults with the keys above, and `~/.config/niri/local.kdl` for your own changes. niri only reads it while `~/.config/niri/config.kdl` doesn't exist, and niri wrote that file at its first start. If you've used niri before, move any changes of yours from it into `local.kdl`, then delete it.

## 4.11.2

### Fixed

- Turning on `secureBoot` failed with "File is immutable" when the firmware kept its KEK or db after the PK was deleted, as the Secure Boot steps say to do. Linux marks those variables immutable, and sbctl won't write over them; the rebuild now clears that mark just before it enrolls the keys.
- With `secureBoot` on, `ephemeral-update` now says why it didn't put the keys into the firmware, instead of skipping that without a word: the firmware isn't in Setup Mode, or doesn't report Secure Boot at all. `ephemeral-doctor` tells the second case apart too. On Framework laptops, "Erase all Secure Boot Settings" causes it; [troubleshooting](docs/troubleshooting.md) has the fix.

## 4.11.1

### Fixed

- `ephemeral-doctor` could report that the disk has no TPM slot when it has one, `ephemeral-backup` and `luks-header-backup` could miss that the folder they write to is on the disk being backed up, and `smb-setup` could miss that a share label already exists. Each piped a command into `grep -q`, which stops at the first match; the command was then cut off, and that counted as a failure, so a match read as none.

## 4.11.0

### Added

- With Secure Boot on, the disk can be unlocked with the TPM and a short PIN. `ephemeral-setup` asks how to unlock it when the machine has a TPM 2.0 and Secure Boot is on, and enrolls the PIN; the passphrase stays, and the boot asks for it once the TPM won't unlock the disk, after enough wrong PINs to lock the TPM out among other things. The TPM is bound to the Secure Boot state (PCR 7), so it asks for the passphrase again after Secure Boot's keys or revocation list change; `ephemeral-setup` enrolls the PIN again. `"tpmUnlock"` in `settings.json` refuses to build without `"secureBoot"`. See [TPM unlock](docs/security.md#tpm-unlock).
- The boot splash says "TPM PIN" when it asks for the PIN.
- `ephemeral-doctor` reports TPM unlock that can't work: with Secure Boot off, or, run with sudo, without a TPM slot on the disk.
- A test that unlocks a LUKS root with a software TPM and a PIN, and with the passphrase after wrong PINs have locked the TPM out.
- Outputs for the installer, so it reads from the release it pins instead of keeping its own copies: `settings-contract`, a JSON file with what each setting may be, its default, which settings are on/off switches, and the menus (each desktop, NVIDIA driver, profile and DNS choice in order, with its name and description); `settings`, each machine's settings checked the way a rebuild checks them, without building the system; and the `wallpaper` and `welcome-logo` packages.
- CI fails when `docs/settings.md` doesn't describe a setting, or a row leaves out a value its setting can have.
- A test that runs `settings-from-pass` against a fake Proton Pass and checks it copies every key the settings loader takes from it.

### Changed

- What each setting may be is written once, in `modules/settings/_rules.nix`, and the menus once, in `_choices.nix`, which the allowed values come from. The schema, the Control D id check at boot, `controld-setup`, `settings-from-pass` and `ephemeral-setup`'s profile and DNS menus and its checks of DNS servers and the SSH vault name all take them from there.
- What `settings-from-pass` copies from Proton Pass is listed once, in `modules/settings/_pass-keys.nix`, which the settings loader reads too.
- The helper commands start with one prelude, `modules/packages/_prelude.nix`, which the script tests use too: the rules and menus as shell variables, then every file in `scripts/lib/`.
- The fastfetch logo and the installer's welcome logo come from one script, `modules/branding/_logo.sh`.
- The test machines for each desktop and profile follow from the menus, so a new desktop without them fails CI.
- `hostname` in `settings.json` is checked with NixOS's own rule for `networking.hostName` when the settings are read. A name NixOS would refuse now stops the rebuild with an error that names the setting, instead of failing later in the build.
- Every VM test and every CI step has a time limit of about three times how long it usually takes, so a test that hangs fails in minutes instead of running for up to an hour.

### Fixed

- The reset of `/` at boot deleted the old root before making the new one, so a failure in between left no root to boot. It makes the new one first now, and a failure at any step leaves a root that boots, with `ephemeral-doctor` reporting that it wasn't reset.
- `systemctl stop opensnitchd` sometimes left the network blocked: OpenSnitch 1.8.0 can crash while it stops, and the guard took that for a crash and held new connections out. A stop asked for lets traffic through now however the daemon exits; a crash still holds them out until it's back.

## 4.10.0

### Added

- `ephemeral-doctor` warns when Secure Boot is on but the firmware has no list of revoked bootloaders (dbx), which "Delete all keys" in the firmware setup also wipes. `fwupdmgr refresh && fwupdmgr update` puts it back.

### Removed

- The clean-up of systemd-boot's files and firmware entries from before v4.7.0. Every rebuild on v4.8.0 to v4.9.0 did it once Limine had started the machine. A machine that skipped those releases keeps them; they do no harm, and once it has started from Limine, `sudo rm -rf /boot/loader /boot/EFI/systemd /boot/EFI/nixos` removes the files, and the "Linux Boot Manager" entries can be deleted in the firmware's boot settings.
- The test of the update from systemd-boot, which booted v4.6.0 every time.

### Fixed

- `ephemeral-doctor` stopped partway if `/nix/var/nix/profiles` couldn't be read.

## 4.9.0

### Changed

- On the full system with OpenSnitch on, new outgoing connections are refused at boot until OpenSnitch is filtering, with the same rules as after a crash. Until now the network came up first, so for the first seconds of each boot nothing was asked about. If OpenSnitch doesn't start, the machine stays offline; `sudo nft destroy table inet opensnitch-down` lets traffic through until the next boot.
- That guard now lets DHCP and IPv6 neighbour discovery through, so the network can come up behind it.

### Fixed

- A weekly release could pick a version older than one released while it waited, as v4.6.1 did after v4.7.0. CI now fails such a pull request, and no tag older than the latest release is made.

## 4.8.2

### Fixed

- With `secureBoot` on, a rebuild from a chroot, such as a repair from the installer ISO, made new keys and signed Limine with them, because `/var/lib/sbctl` is only mounted from `/persist` on the running system. With Secure Boot on, the machine then didn't start. sbctl now reads and writes its keys on `/persist` directly, the signature is checked against the key there, and a rebuild with `/persist` not mounted stops.

### Changed

- [Secure Boot](docs/security.md#secure-boot) says to enter Setup Mode by deleting only the platform key where the firmware allows it. "Delete all keys" also removes the list of revoked bootloaders, which `fwupdmgr update` puts back.

## 4.8.1

### Fixed

- The systemd-boot cleanup left the "Fallback Linux Boot Manager" firmware entry, which newer systemd-boot adds beside its own and which pointed at a file the cleanup had removed. The next rebuild removes it. Only entries on this machine's boot partition are touched; one on another disk stays.

## 4.8.0

### Added

- Secure Boot, with `"secureBoot": true` in `settings.json`. It's off unless you turn it on, and it needs two visits to the firmware setup, before and after the rebuild: the steps are in [Secure Boot](docs/security.md#secure-boot). The keys are made on the machine, kept in `/persist/var/lib/sbctl` and saved by `ephemeral-backup`. Microsoft's keys and the firmware's own stay trusted. `ephemeral-doctor` says which step a machine is on.
- With `secureBoot` on, a rebuild stops if Limine isn't signed with this machine's key, so it never leaves one behind that the firmware would refuse.
- A test that turns `secureBoot` on after an update from the previous release, boots with Secure Boot enforced, also from the fallback path alone, and checks that Limine refuses a changed kernel.

### Changed

- systemd-boot's files (`/boot/loader`, `/boot/EFI/systemd`, `/boot/EFI/nixos`) and its "Linux Boot Manager" firmware entry are removed by the first rebuild after the machine has started from Limine. A machine that hasn't started from Limine yet keeps them as a way back.
- `/var/lib/sbctl` is kept on every machine, so that turning `secureBoot` on later has its keys on `/persist` from the start.
- The bootloader switch test now always starts from v4.6.0, the last release on systemd-boot, and checks that systemd-boot is only removed once Limine has started the machine.

## 4.7.0

### Breaking

- Machines boot with Limine instead of systemd-boot. **If a module of your own sets `boot.loader.systemd-boot.enable`, remove it**: the rebuild stops with "Only one bootloader can be enabled at a time" until you do. Other `boot.loader.systemd-boot` settings no longer do anything; most have a `boot.loader.limine` counterpart.

### Changed

- The next rebuild installs Limine and puts it first in the firmware's boot order. It's also copied to the path firmware falls back on, so it starts on firmware that loses its boot entries, or with the disk in another machine. The boot menu works as before: a key stops the 3-second countdown, and older generations are listed under the newest.
- systemd-boot's files and its firmware entry are left alone for now, as a way back if Limine doesn't start: pick "Linux Boot Manager" in the firmware's own boot menu. It only lists the generations from before the switch, and those stop working once they're more than 30 days old and cleaned up. A later release removes it.

### Added

- A test of the update from the previous release on a real boot partition, with firmware entries that survive a reboot: Limine has to come first in the boot order, boot this code, list the generations from before, and still start once every firmware entry is deleted. The disk test boots with no firmware entries at all, from the fallback path.

## 4.6.0

### Changed

- `ssh-pubs-from-pass` reads its vault from `passSshVault` in `settings.json`, the one the SSH agent serves, instead of always using `Personal`. `PASS_SSH_VAULT` and `--vault` still override it. It no longer needs Python.
- `ephemeral-setup`, `ephemeral-apps`, `controld-setup` and `smb-setup` stop with an error when there's no terminal to ask in. Before, they exited with 0 having done nothing, so a script running them couldn't tell.
- Every helper command exits with 2 on an option it doesn't know, before doing anything. `ephemeral-setup` and `ephemeral-passwd` exited with 1, `ephemeral-report` ignored it, and `ephemeral-backup`, `luks-header-backup` and `update-pass-cli` took it for a path or a version. `controld-setup`, `smb-setup` and `settings-from-pass` have `--help` now.
- `ephemeral-doctor --fix-root-reset` only goes ahead when its question is answered in a terminal.
- `ephemeral-apps` stops on a leftover `settings.nix`, as a rebuild does, instead of showing every desktop's apps.
- The root services this repo adds run with a system call filter, and Control D's also gets a private `/tmp` and no device access.

### Fixed

- A program running as any user could stop `/` from being reset at every boot, by making subvolumes in `/var/tmp` nested more than 64 levels deep, or inside a folder whose name has a newline. The reset read the list of subvolumes as text; btrfs now deletes them itself, at any depth and whatever they're named. `/persist` was never at risk, and `ephemeral-doctor` reported the failed reset.
- A rebuild copies `/persist/etc/nixos` into the Nix store, `.git` included, but the check for secrets there only looked at file names. It now also stops on a private key or token inside a file and on a token in a git remote URL. A secret committed and deleted again is still in `.git`, and still can't be seen; [Security notes](docs/security.md) says what to do.
- If `/` had never been reset since the install, `root-reset-check` skipped itself instead of failing, so `ephemeral-doctor` didn't say so. A missing reset marker now fails it.
- `ephemeral-backup` wrote to the encrypted disk itself when asked, though a reinstall erases it with everything else. It refuses that now, as `luks-header-backup` already did. A backup that's stopped partway is removed instead of left looking like a finished one.
- `settings.from-pass.json` could turn Control D off, so someone who could edit your Proton Pass settings item could send DNS back to the network unencrypted. It can still turn Control D on.
- When OpenSnitch's daemon crashed, every program could connect out until it restarted 30 seconds later, because its own rules let traffic past while nothing is listening. New connections out are now refused until it's filtering again, and it restarts after 2 seconds. Stopping it with `systemctl stop` still lets everything through.
- A pull request titled `release vX.Y.Z` would have been released when merged. Only a merge from the `release/vX.Y.Z` branch makes a release now.
- `ephemeral-apps` and `controld-setup` could leave a temp file behind when they failed, and an interrupted settings edit could leave one in `/persist/etc/nixos`, where the next rebuild would copy it into the store. Files in the flake are now replaced in one step, and the Control D id goes to its file from a pipe.

### Added

- Checks for the security rules in [ARCHITECTURE.md](ARCHITECTURE.md#security), each listed there: no open port, no SSH and no root password on any desktop or profile; every root service from `modules/` sandboxed; the firewall refusing traffic over IPv4 and IPv6 on a running machine; and a VM test of OpenSnitch against a second machine.
- The boot and profile-switch tests take their apps from the same place a real install does, so they can't drift from it again.

## 4.5.1

### Fixed

- The boot test now gets the apps ticked by default, as a real install does. On 4.5.0 it stopped at the Extension Manager check, so its last checks, the small-install boot, the upgrade test and the disk test didn't run; this release has all of them. Nothing changes on machines.

## 4.5.0

### Breaking

- On the full system, apps now come from `ephemeral-apps`. Steam, VS Code, Brave, distrobox, unrar, git-crypt and age no longer come with `"extras": true`. **If you had `extras` on and want them back, tick them in `ephemeral-apps` after updating**, or add their names to `apps.json`: `steam`, `vscode`, `brave`, `distrobox`, `unrar`, `git-crypt`, `age`. Until then the rebuild removes them. Your home folder keeps their settings and game libraries.
- `extras` is now just the shell tools: atuin, fzf, bat, tealdeer, yazi, btop, fastfetch, comma and command-not-found.

### Added

- Apps ticked by default: Firefox, VLC, 7-Zip, Syncthing Tray, htop, ripgrep, dig and the WireGuard tools, plus GNOME Tweaks and Extension Manager on GNOME, or Discover and Partition Manager on Plasma. They're installed unless you untick them, which `ephemeral-apps` saves as `-name` in `apps.json`. Firefox and the tools were built in before, so they stay through the update; VLC, 7-Zip and Syncthing Tray are new on machines that didn't have `extras`.
- Apps for one desktop are only offered and installed on that desktop.
- A Fonts category with common Nerd Fonts: JetBrains Mono, Fira Code, Hack, Meslo, CaskaydiaCove, SauceCodePro, Iosevka, Ubuntu Mono, Victor Mono, Commit Mono, Geist Mono, and the symbols on their own.
- [Leaving things out](docs/customizing.md#leaving-things-out): how to drop the desktop's own apps, services and shell tools from your own modules, with more examples in `modules/local/_example.nix`.

### Changed

- The small install keeps its fixed set of apps, as before.

### Fixed

- The restore command `ephemeral-backup` prints used `age`, which a fresh install doesn't have. It runs it with `nix run nixpkgs#age` now.

## 4.4.0

### Changed

- A boot splash of our own, drawn from the wallpaper and in the website's colours. The snowflake gathers out of drifting pixels at boot, sheds a few while it waits for the disk passphrase, and breaks up into pixels once it's typed, and at shutdown. A wrong passphrase brings it back with a note. It replaces Stylix's splash on the full profile and the plain or Breeze one on the small install, so every desktop and profile looks the same. [Dotfiles and appearance](docs/appearance.md#boot-splash) shows how to use another theme.

## 4.3.0

### Added

- Encrypted DNS without an account: `"encryptedDns"` can be `cloudflare`, `quad9` or `adguard`, and sends all DNS over TLS to that provider, on both profiles. `"custom"` uses your own servers from `"customDns"`, each as `address#name`, such as Mullvad's or one at home. `ephemeral-setup` asks which DNS to use, with the network's own as the first choice and "Other" for your own servers last, and Control D moved into that question. The default stays the network's DNS, so nothing changes on machines that don't set it.
- `encryptedDns` and `useControlD` can't both be on; the rebuild says which to turn off. `controld-setup` turns `encryptedDns` off when it turns Control D on.

## 4.2.0

### Added

- `sudo ephemeral-doctor audit` lists services whose data in `/var/lib` isn't kept, so they start over at every boot, and folders in `/persist/var/lib` nothing uses any more, like one left behind by an app you removed. It goes by what services tell systemd, so it can't catch everything.

### Fixed

- Battery history started over at every boot, so the desktops' battery charts only ever showed the current one. `/var/lib/upower` is kept now.
- The security notes now say what the wiped `/` doesn't protect against: malware that hides in the home folder, anything with root, and anything before the next reboot.

## 4.1.0

### Added

- `ephemeral-doctor` checks the machine and prints the command that fixes each problem it finds: whether `/` was wiped at this boot, failed services, free space on `/persist` and `/nix`, the last snapshot, a newer release, secret files in the config folder, and a missing LUKS header backup. `ephemeral-doctor kept` lists what's kept across reboots, `ephemeral-doctor lost` what the next reboot removes, and `sudo ephemeral-doctor --fix-root-reset` makes `/` reset again when it doesn't.
- `ephemeral-update --check` builds a change without switching to it, `--previous` goes back to the system before the last rebuild, `--list` shows the systems you can go back to with their config releases, and `--as-installed` rebuilds the system as it was installed.
- Before moving to a new release, `ephemeral-update` shows what changed since yours, from the changelog. For a new major version it names that in the question.
- `ephemeral-backup <folder>` saves what a reinstall needs and git doesn't keep, the settings files and the root-only secrets, in one file encrypted with a passphrase you pick.
- A notification at the first login says where to start, on every desktop.

### Changed

- The small install has `ephemeral-update`, `ephemeral-doctor`, `ephemeral-backup`, `ephemeral-report` and `luks-header-backup` too, and `ephemeral-help` lists only the commands a machine has.
- `ephemeral-report` includes what `ephemeral-doctor` found, the last lines of each failed service, and the systems you can go back to, and keeps user and host names out of every line.
- Every command that used to say `sudo nixos-rebuild switch --flake path:...` now says `ephemeral-update`, and so do the docs. The troubleshooting page uses the new commands, and says where to save a fix.

- More tests, so mistakes are caught before a release goes out:
  - every pull request evaluates each optional feature on its own and all together, checks that bad settings stay refused, runs `ephemeral-update` and `ephemeral-passwd` against fake commands, and checks the installer still evaluates against the change;
  - release pull requests also build every desktop, boot Plasma, niri and Umbriel to their login screen, and boot the new code on a `/persist` the previous release wrote;
  - the disk test checks the LUKS and btrfs setup itself (LUKS2, argon2id, the subvolumes, the mount options, `/boot` readable by root only), and that a subvolume made inside `/` is wiped too;
  - the boot test checks that every folder the config keeps survives a reboot, and the upgrade test switches back to the previous release afterwards;
  - the workflows are linted with actionlint and zizmor.
- `ephemeral-update` honours `FLAKE_DIR`, like the other commands.

## 4.0.0

### Breaking

- `settings.nix`, `settings.from-pass.nix` and `smb-shares.nix` aren't read any more, only their `.json` forms. If a machine still has one without the `.json`, the rebuild stops and prints the command that converts it. To check before moving, `ls /persist/etc/nixos/*.nix` should list only `flake.nix` and `hardware-configuration.nix`.
- The undocumented `flake.modules.nixos.dotfiles` is gone. Home Manager now turns on `flake.modules.homeManager.dotfiles` itself, so a machine flake that imported the NixOS one has to drop it.

### Added

- `ephemeral-passwd` changes your login password, on the small install too. It asks twice and only replaces `/persist/passwords/$USER` once it has a valid hash, so a typo or a cancelled prompt can't lock you out at the next boot as the old instructions could. The new password works straight away.

### Changed

- `ephemeral-update` and `ephemeral-setup` refuse to rebuild when `/persist/etc/nixos` has files that look like secrets, such as `*.key`, `*.pem`, `id_ed25519`, `.env` or a `passwords` folder. A rebuild copies the whole folder into the Nix store, where any user can read it, whatever `.gitignore` says. Move them to `/persist/etc/<name>`, owned by root with mode 600, or set `EPHEMERAL_ALLOW_SECRET_FILES=1` to rebuild anyway.
- On niri and Umbriel, the screen locks after 10 idle minutes, as Plasma and GNOME already do, and the config now sets Noctalia's lock before sleep instead of relying on its default.
- The Noctalia login screen no longer copies the shell's look by itself. The copy runs a helper as root, which the config allowed without your password. You can still copy it from Noctalia's settings, and it asks for the password now. The config sets the login screen's dark theme either way.
- The weekly release only brings in a new nixpkgs. The other inputs, such as Home Manager and Stylix, come in a separate monthly pull request that's read before it's merged, because their code runs as root on every machine.
- The release workflow keeps its GitHub token out of the repository checkout.
- Files moved so each feature has its settings, persistence and permissions in one place. Machines get the same packages, settings and kept folders as before.
- The permissions on the login password, the SSH host key, the Control D id and the SMB passwords are set by `systemd-tmpfiles` at every boot, in place of shell loops during activation. The boot test checks that files written with the wrong permissions are root-only after the next boot.
- Shared modules that need another one import it themselves, through `config.ephemeral.aspects`, which applies each one only once. Your own modules can do the same; [Customizing](docs/customizing.md#your-own-modules) shows how.
- A wrong value in `settings.json`, such as `"desktop": "kde"`, is reported with the allowed values and the file it's in, in place of "attribute 'kde' missing".

### Fixed

- The security notes now list every sandboxed service, the `docker` and `libvirtd` groups, and that the Control D resolver id is visible on the network.
- On the small niri and Umbriel installs, the login screen's state is kept across reboots, as on the full ones.

## 3.11.1

### Changed

- `root-reset-check` and `snapper-persist-setup` run in the same sandbox as the config's other root services: a read-only system, no network and no capabilities. `systemd-analyze security` rates them 2.8 instead of 9.6.

## 3.11.0

### Added

- `ephemeral-update` checks for a newer release before it rebuilds. If there is one, it links the changelog, warns when it's a new major version, and asks whether to move to it; on yes it changes the tag in `flake.nix`, updates the lock and rebuilds. Offline, or when GitHub doesn't answer within 5 seconds, it rebuilds what's pinned.
- When `/persist/etc/nixos` still belongs to root, `ephemeral-update` offers to make it yours, the way `ephemeral-setup` does. Say no and it uses `sudo` for the changes it makes there.

### Fixed

- `ephemeral-update` said "no flake at /persist/etc/nixos" on machines from installer v3.0.0 to v3.7.3, which left the folder readable only by root. Rebuilding with this release makes it readable again. Until a machine has this release, run `sudo chmod 755 /persist/etc/nixos` first.
- Umbriel showed its keybind cheatsheet at every login. It shows at the first login only now, and `Mod+/` opens it again.
- `ephemeral-apps` and `ephemeral-setup` said to tick with space, but their lists tick with `x`, as the line under them says. They say `x` now, like the installer.

## 3.10.0

### Changed

- A release comes out every Monday with the newest nixpkgs, so security fixes reach machines within a week instead of up to a month. The first Monday of the month updates every input, as the monthly release did.
- Releases are immutable: once published, a release's tag can't be moved. `gh release verify v3.10.0 -R the-wittch/ephemeral-nixos-config` checks one.
- More kernel hardening: freed memory is wiped (`init_on_free=1`), kernel caches aren't shared between object types (`slab_nomerge`), page allocation is randomised, the legacy vsyscall page is gone and debugfs is off. Expect a few percent slower on memory-heavy work. Very old binaries that need vsyscall won't run, and tools that read debugfs, such as `powertop`, lose those readings. [When something breaks](docs/troubleshooting.md) shows how to turn either back on.

### Fixed

- niri and Umbriel had no file manager, and on the full profile `~/Documents`, `~/Music` and the other home folders were never made. Both desktops now come with Nautilus, plus the apps GNOME has for opening what's in it: Loupe for images, Papers for PDFs, Text Editor, File Roller for archives and Calculator. Nautilus shows thumbnails for videos and PDFs and has the trash, network shares and phones. Folders, images, PDFs, text and archives open in these by default, rather than in VS Code or a browser.
- The home folders are made on both profiles and every desktop. Before, the full profile relied on GNOME and Plasma making them.

## 3.9.0

### Added

- `ephemeral-apps` has security and penetration testing tools under Security: Metasploit, Nmap, ZAP, Burp Suite Community (unfree), sqlmap, ffuf, Gobuster, mitmproxy, Hashcat, John the Ripper, SecLists, Exploit-DB, NetExec, Ghidra, radare2 and binwalk, plus Lynis to audit the machine itself. SecLists' wordlists are in `/run/current-system/sw/share/wordlists/seclists`. Nmap warns that with OpenSnitch on, you're asked about each host a scan reaches.

## 3.8.3

### Fixed

- Formatting a disk that already has the layout no longer fails: the `root-blank` snapshot is only made when it's missing. The new disk test found this.
- `ssh-pubs-from-pass` only reads SSH key items. Before, it opened every item in the vault, logins and notes included, while looking for public keys.
- `settings-from-pass` says when `settings.json` doesn't have `"usePassSettings": true`, since the rebuild ignores the file without it. The Control D id no longer passes through a temporary file.

### Changed

- A VM test installs the real disk layout and checks the wipe, what survives it, and the `root-blank` recovery steps in Troubleshooting.
- The README and appearance docs show an animated screenshot.

## 3.8.2

### Changed

- The README and the appearance docs show a screenshot of a new Ghostty window.

## 3.8.1

### Changed

- A new Ghostty window opens with fastfetch in boxed sections (System, Hardware, Desktop, Terminal), next to the wallpaper's glitchy snowflake drawn in colored characters with EPHEMERAL under it. Ghostty opens at 151×43 so both fit. The pre-rendered spin from 3.8.0 is gone.
- Troubleshooting shows how to make a missing `root-blank` again. The security notes now say what the unencrypted `/boot`, TRIM and the IOMMU do and don't protect against.

## 3.8.0

### Added

- Umbriel as a fourth desktop, with the Noctalia shell and greeter like niri. Set `"desktop": "umbriel"` in `settings.json`, or pick it in the installer. Your own Umbriel settings go in `~/.config/umbriel/local.toml`.
- Plasma on the full profile is set up with plasma-manager: Krohnkite tiles windows, and matugen makes the color scheme from the desktop wallpaper, again whenever the wallpaper changes. See [Plasma](docs/appearance.md#plasma).

### Changed

- Plasma no longer uses Stylix's Catppuccin colors; fonts and the cursor stay the same.
- The Ghostty splash is drawn from the official Nix snowflake: it spins once in its two blues above EPHEMERAL, then settles into the fastfetch logo beside the system info. areofyl's `fetch` is gone; its 3D shading broke the flake into specks. fastfetch now cuts long lines at the window edge instead of wrapping them.

## 3.7.0

### Added

- A Virtualization category in `ephemeral-apps`: virt-manager with a TPM and Secure Boot firmware for Windows 11 guests, VM Curator, and single-GPU passthrough for virt-manager VMs on desktops. See [Virtual machines](docs/features.md#virtual-machines).
- A System category, all off unless picked: profile-sync-daemon, ananicy-cpp with the CachyOS rules, and bpftune.
- RustDesk under Utilities.
- With `extras`, a new Ghostty window opens with the Nix snowflake and EPHEMERAL spinning in 3D next to the system info, until you press a key.

## 3.6.2

### Changed

- Zork lists your saves when you start a game, newest first. Enter continues the newest, a number loads that one, N starts a new game.

## 3.6.1

### Changed

- Zork has one entry in the app menu, which opens its menu. Set `programs.zork-nix.gameEntries = true` to list Zork I, II and III as well.

## 3.6.0

### Added

- Zork I-III in `ephemeral-apps`, under Gaming: the Infocom text adventures in cool-retro-term with an amber CRT look. It comes from [zork-nix](https://github.com/the-wittch/zork-nix); set `programs.zork-nix.phosphor`, `fullscreen` or `profile` in a module of your own to change the look.

## 3.5.0

### Added

- `root-reset-check` fails, and shows up in `systemctl --failed`, when `/` wasn't reset on this boot. The reset never stops a boot, so before this a broken one went unnoticed. The check starts from the second boot after updating.
- Backups and "what survives what" in the docs, plus CONTRIBUTING.md and SECURITY.md.

### Changed

- Thunderbolt approvals, the power profile and colour profiles survive a reboot.
- The full and small installs of each desktop share one module for what they have in common, so they can't drift apart. The systems they build are unchanged, apart from the niri fix below.
- The monthly release stops at its first step with a clear message when `FLAKE_UPDATE_TOKEN` has expired.
- The pinned pass-cli, used with `useFlakePassCli`, moves from 2.4.2 to 2.5.1.

### Fixed

- On the full niri profile, logging in didn't unlock the GNOME keyring, so apps that keep passwords in it asked for it again.
- A Proton Pass vault name in `settings.json` went unescaped into the login shell's environment, so one containing `"$(...)"` would run that command in every shell. Vault names can't contain quotes, `$`, backticks or backslashes now. Neither can the disk, swap size or timezone have anything a shell would act on. If a rebuild says a setting "is not of type", fix that value in `settings.json`.
- `settings.from-pass.json` could set any setting, not just the ones `settings-from-pass` writes. The rebuild now ignores the rest, so the file can't turn off OpenSnitch.
- `passSettingsVault` and `passSettingsItem` did nothing; `settings-from-pass` only read `PASS_SETTINGS_VAULT` and `PASS_SETTINGS_ITEM`. It now reads both settings, and the variables still win.
- `ephemeral-report` left your username in the error log it includes, though it says it leaves it out. Check reports you've already posted.
- The secret scanner missed newer OpenAI and Anthropic keys (`sk-proj-`, `sk-ant-`). It now catches them, and Tailscale auth keys too.
- The docs' way to turn Stylix's VS Code theming back on failed to build. It needs `lib.mkForce`.
- When the CHANGELOG already had an entry for the next version, the monthly release would have added a second heading for it.

## 3.4.0

### Changed

- Wi-Fi uses a different MAC address on each network, the same one every time you join it, so networks can't follow the laptop from place to place. Routers see it as a new device once; update any fixed IP or MAC filter you set for it. To keep the hardware address, set `networking.networkmanager.wifi.macAddress = "preserve"` in a private module.
- LLMNR is off. Local `.local` names still work through mDNS.
- The IOMMU is on and translates every device's memory access, so a Thunderbolt or USB4 device can't read memory it wasn't given. If a device stops working after the update, see [When something breaks](docs/troubleshooting.md) and open an issue.

### Added

- The app catalog is a package, `app-catalog`, so the installer can offer the same apps as `ephemeral-apps`.

## 3.3.1

### Fixed

- `$EDITOR` pointed at VS Code even without `extras`, which is what installs it. It's now neovim, and VS Code with `extras`.
- lazydocker works when `XDG_RUNTIME_DIR` isn't set, as under `sudo`.

## 3.3.0

### Added

- A Terminal category in `ephemeral-apps`: lazydocker, k9s, tmux, Zellij, Helix, NeoMutt, aerc, Browsh, Newsboat, WeeChat, cmus, VisiData, bottom, nix-tree and more. lazydocker works with the rootless Podman socket when Docker isn't installed.

### Changed

- lazygit moves from Development to Terminal. It stays picked if you had it.

## 3.2.1

### Fixed

- Stylix's `gnome-shell` source comes from GNOME's GitHub mirror instead of gitlab.gnome.org, which turns away CI runners with HTTP 406. Same commit, same system. The monthly release keeps the mirror on the version Stylix pins.

## 3.2.0

### Added

- `ephemeral-setup`, on both profiles: switch profile, turn the main options on or off, and rebuild.
- The installer (from v3.2.0) asks what to install and installs the full system by default; the README's Setup section is rewritten around that.
- An upgrade test: CI boots a machine on the previous release and switches it to the new code.
- A monthly patch release with updated inputs, merged and tagged on its own once the boot tests pass. It replaces the weekly lock-update PR.
- [The first hour](docs/first-hour.md), and a short list of limits in the README.
- The README is split: the overview stays, the reference moves to `docs/`, one topic per page.

### Fixed

- The full profile installed every package a machine flake defined, not just this repo's commands.

## 3.1.1

### Added

- A rebuild warning when `settings.json` turns on something the `minimal` profile ignores: `extras`, `useControlD`, `usePassSshAgent`, `useFlakePassCli` or apps in `apps.json`.

### Changed

- The README's Setup section is split into switching to the full profile and keeping the config in git.

## 3.1.0

### Added

- `useOpenSnitch` setting, on by default. `false` turns off the outgoing-connection prompts.
- A boot test for the minimal profile, and CI evaluation of every desktop on both profiles.
- README sections on keeping data across reboots and on how updates reach a machine.

## 3.0.0

### Breaking

- **chezmoi is gone.** Home Manager writes the dotfiles on every machine. `useChezmoi`, `chezmoiRepo` and `chezmoiRev` in `settings.json` still load, with a warning; delete them. Files chezmoi wrote stay where they are, and Home Manager renames any it replaces to `<name>.hm-backup`. `/persist/etc/chezmoi-repo` is no longer read and can be deleted.
- **Machine flakes use `lib.mkFlake`.** The old way (`flakeModules.default` plus eight `follows` lines) still works, but the new one is three lines. To switch, replace `flake.nix` in `/persist/etc/nixos` with:

  ```nix
  {
    inputs.ephemeral.url = "github:the-wittch/ephemeral-nixos-config/v3.0.0";
    outputs = inputs: inputs.ephemeral.lib.mkFlake { inherit inputs; root = ./.; };
  }
  ```

  then delete `modules/ephemeral.nix` (the file that imported `flakeModules.default`), run `nix flake lock` and rebuild. Your other files in `modules/` are loaded as before.

### Added

- `profile` setting: `minimal` is the small system the installer sets up, `full` is everything else. Existing machines default to `full` and don't change.
- `nix run .#vm` boots a machine's config in a throwaway VM, to try this repo or check a change before switching.
- `ephemeral-report` prints system details for a bug report, and the repo has issue templates.
- README sections on recovering from a broken rebuild, what's tested, and OpenSnitch blocking new connections.

### Changed

- The installer no longer carries its own copy of the modules; it installs the minimal profile from a release of this repo. `scripts/check-shared.sh` is gone.
