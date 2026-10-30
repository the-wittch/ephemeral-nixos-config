# Ephemeral Nix Config

[![CI](https://github.com/the-wittch/ephemeral-nixos-config/actions/workflows/ci.yml/badge.svg)](https://github.com/the-wittch/ephemeral-nixos-config/actions/workflows/ci.yml)

<img width="3840" height="2160" alt="wallpaper" src="https://github.com/user-attachments/assets/b4e08080-876a-4ab3-911f-4055a4f2de0d" />

The NixOS config for machines installed with [ephemeral-nixos](https://github.com/the-wittch/ephemeral-nixos). `/` is wiped on every boot; `/home` and a short list of system paths live on `/persist`.

The installer sets up the small `minimal` profile from this repo. Switching to the `full` profile (see [Setup](#setup)) adds:

- Home Manager dotfiles: zsh, git, starship, zoxide, neovim and ghostty.
- A dark Catppuccin Mocha theme everywhere, through [Stylix](https://github.com/nix-community/stylix), with the snowflake as the default user picture.
- Hourly snapper snapshots of `/persist`, and desktop warnings when a disk starts failing.
- OpenSnitch, Syncthing, Podman, Flatpak with Flathub, Firefox and scanning.
- Rebuilds through [nh](https://github.com/nix-community/nh), with a summary of what changed.
- Laptop extras (thermald, battery reporting, fingerprint login) when the hardware is there.
- Optional NVIDIA drivers, Tailscale, DNS over TLS through Control D, SMB mounts, and machine settings pulled from Proton Pass.

A fresh install stays lean. `"extras": true` adds the bigger things:

- Steam, VS Code, Brave, VLC, distrobox, Syncthing Tray, 7-Zip and unrar.
- atuin, fzf, bat, tealdeer, yazi, btop and fastfetch in the shell.
- `,` to run any program once without installing it, and command-not-found suggestions.

The installer asks about extras. Anything else you don't want can be switched off in your own modules (see below).

> **On the full profile, outgoing connections are blocked until you allow them.** OpenSnitch asks the first time each program connects somewhere. If an app can't connect, a missed or denied prompt is the likely cause: open OpenSnitch and check its Rules. `"useOpenSnitch": false` turns it off.

## Setup

The installer leaves the `minimal` profile: a working desktop and little else. The machine's config is in `/persist/etc/nixos`: `settings.json`, `hardware-configuration.nix`, and a short `flake.nix` that pins a release of this repo.

### Switch to the full profile

```bash
sudo chown -R "$USER": /persist/etc/nixos
cd /persist/etc/nixos
sed -i 's/"profile": "minimal"/"profile": "full"/' settings.json
sudo nixos-rebuild switch --flake path:.#nixos
```

The first rebuild downloads a lot. Log out and back in when it's done, so the desktop session picks up the new environment.

`extras`, `useControlD`, `usePassSshAgent`, `useFlakePassCli` and the apps in `apps.json` only apply to the full profile; on `minimal` the rebuild warns that they're ignored. To go back, set `"profile": "minimal"` and rebuild.

> **Just want to get going?** After switching, run `ephemeral-apps` and tick the apps you want. No Nix files to edit: your picks are saved to `apps.json` and installed on the next rebuild, and you can run it again any time to add or remove apps.

### Keep it in git

```bash
cd /persist/etc/nixos
git init
git add -A
git commit -m "my machine"
```

Push it to a private repo. `settings.json` and `hardware-configuration.nix` are gitignored, so they stay on the machine. Always build with `path:`; a plain `.#nixos` only sees files tracked by git and won't find them.

## Try it in a VM

`nix run path:.#vm` boots a machine's config in a throwaway QEMU window: root on tmpfs as usual, `/persist` on a scratch disk that's gone when the VM closes. Log in with your username and the password `ephemeral`. It needs KVM and about 4 GB of free memory.

On an installed machine, run it in `/persist/etc/nixos` to check a change, such as switching profiles, before you rebuild. To try this repo without installing anything:

```bash
git clone https://github.com/the-wittch/ephemeral-nixos-config
cd ephemeral-nixos-config
cp settings.example.json settings.json
cp hardware-configuration.example.nix hardware-configuration.nix
nix run path:.#vm
```

The user is `nixuser`; change `username`, `desktop` or anything else in `settings.json` first to try something else.

## Rebuild and update

```bash
ephemeral-update
```

That's `nh os switch path:/persist/etc/nixos`: the same rebuild as `nixos-rebuild`, with readable progress and a list of what changed at the end.

`flake.nix` pins a release of this repo:

```nix
{
  inputs.ephemeral.url = "github:the-wittch/ephemeral-nixos-config/v3.1.0";
  outputs = inputs: inputs.ephemeral.lib.mkFlake { inherit inputs; root = ./.; };
}
```

To move to a newer release, change the tag, then:

```bash
nix flake update ephemeral --flake /persist/etc/nixos
ephemeral-update
```

Read [`CHANGELOG.md`](CHANGELOG.md) before a new major version; it lists what you have to change. Settings that were removed still load with a warning that says what to do.

A machine gets new packages, security fixes included, only with a new release here, which comes out about once a month. This repo tracks `nixos-unstable` and moves to the stable 26.11 channel once that's released. For fixes sooner, give your machine its own nixpkgs, which replaces this repo's:

```nix
inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
```

and update it with `nix flake update nixpkgs --flake /persist/etc/nixos`. That combination isn't tested here, so try it with `nix run path:.#vm` first.

## Keeping things across reboots

`/` is wiped on every boot. Your home folder is kept, and so is a short list of system paths (`modules/persist.nix`), but anything else a program writes outside `/home` is gone after a reboot: a database in `/var/lib`, a file you edited in `/etc`. Apps from `ephemeral-apps` already keep what they need.

To keep more, add the paths in a file in `modules/`:

```nix
{
  flake.modules.nixos.pc.environment.persistence."/persist" = {
    directories = [ "/var/lib/postgresql" ];
    files = [ "/etc/machine-info" ];
  };
}
```

Rebuild, and they're kept from then on. Whatever was in them before the rebuild isn't copied over, so copy it to `/persist` first if you need it. To see what's on `/` that would be lost:

```bash
sudo find / -xdev -type f -newermt "$(uptime -s)" -not -path '/tmp/*' 2>/dev/null
```

## Commands

`ephemeral-help` lists these, so there's no need to remember them:

| command | what |
|---------|------|
| `ephemeral-update` | rebuild and switch to `/persist/etc/nixos`, then show what changed |
| `ephemeral-report` | system details to paste into a bug report |
| `controld-setup` | set or turn off the Control D resolver id |
| `smb-setup` | add or remove SMB shares |
| `ephemeral-apps` | pick extra apps by category, then rebuild |
| `luks-header-backup <file>` | copy the LUKS header to a USB stick |
| `settings-from-pass` | pull settings from Proton Pass |
| `ssh-pubs-from-pass` | write SSH public keys from Proton Pass to `~/.ssh` |
| `update-pass-cli` | bump or check the pinned pass-cli (run in a checkout of this repo) |

Most of them ask what to do; `--help` on one shows its options. The ones that change `settings.json` or the shares tell you to rebuild afterwards.

## How it's organized

The config follows the [dendritic pattern](https://github.com/mightyiam/dendritic):

- Every `.nix` file under `modules/` is a [flake-parts](https://flake.parts) module. [import-tree](https://github.com/vic/import-tree) loads all of them, so there's no import list to keep up to date. Paths containing `/_` are skipped.
- Each file is one feature: Syncthing, the boot splash, zsh, the theme. A single file can set NixOS and Home Manager options together.
- Files don't import each other. They add to a few shared modules, such as `flake.modules.nixos.pc` or `flake.modules.homeManager.dotfiles`, and a machine is built by combining those.
- Settings are a normal NixOS option (`config.ephemeral.settings`), not extra function arguments.

Adding a feature means adding a file, and removing one means deleting it. [mightyiam/infra](https://github.com/mightyiam/infra) and [Bad3r/nixos](https://github.com/Bad3r/nixos) are larger configs built the same way.

## Your own modules

Every `.nix` file in `/persist/etc/nixos/modules/` is loaded the same way. These are the shared modules you can add to:

| module | applies to |
|--------|------------|
| `flake.modules.nixos.base`, `flake.modules.nixos.pc` | every machine, both profiles |
| `flake.modules.nixos.full` | the full profile |
| `flake.modules.nixos.minimal` | the minimal profile |
| `flake.modules.nixos.gnome`, `.plasma`, `.niri` | the desktop chosen in `settings.json`, full profile |
| `flake.modules.nixos.minimal-gnome`, `.minimal-plasma`, `.minimal-niri` | the same, minimal profile |
| `flake.modules.homeManager.base`, `flake.modules.homeManager.dotfiles` | your user (full profile; minimal has no Home Manager) |
| `flake.modules.nixos.extras`, `flake.modules.homeManager.extras` | full profile with `"extras": true` |

A file in `modules/` can add to any of them:

```nix
{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.helix ];
      services.openssh.enable = true;
    };

  flake.modules.homeManager.dotfiles = {
    programs.git.settings.user = {
      name = "Your Name";
      email = "you@example.com";
    };
  };
}
```

Settings are `config.ephemeral.settings` in NixOS modules and `osConfig.ephemeral.settings` in Home Manager. To turn off something this repo sets, use `lib.mkForce`.

`lib.mkFlake` brings this repo's inputs along, so `flake.nix` only names `ephemeral`. Add your own inputs next to it and they're available to your modules as `inputs.<name>`; one named like this repo's (say `nixpkgs`) replaces it.

If you'd rather work in a clone of this repo, put your files in `modules/local/` instead. That folder is gitignored; `modules/local/_example.nix` shows the shape.

## settings.json

[`settings.example.json`](settings.example.json) lists every key with its default. CI fails if a setting or a default changes without it.

| key | what |
|-----|------|
| `hostname`, `username`, `timeZone` | who and where the machine is |
| `locale` | language, e.g. `de_DE.UTF-8` |
| `keyboardLayout`, `keyboardVariant` | e.g. `de` and `nodeadkeys`; also used at the LUKS prompt |
| `diskDevice`, `swapSize` | the whole disk (not a partition) and the swap file size |
| `desktop` | `plasma`, `gnome` or `niri` |
| `profile` | `minimal` (what the installer sets up) or `full` (everything in this README) |
| `nvidia` | `none`, `open` (RTX 20 / GTX 16 series and newer) or `legacy` (GTX 900 / 10 series) |
| `extras` | the extra apps and shell tools listed at the top |
| `laptop` | thermald on Intel, battery reporting, screen rotation and light sensors |
| `fingerprint` | fingerprint login and sudo |
| `useControlD` | DNS over TLS through Control D |
| `useTailscale` | the Tailscale VPN |
| `useOpenSnitch` | OpenSnitch asks before programs connect out (on by default) |
| `usePassSettings`, `passSettingsVault`, `passSettingsItem` | merge settings from Proton Pass |
| `usePassSshAgent`, `passSshVault` | the Proton Pass SSH agent at login, serving the keys in that vault |
| `useFlakePassCli` | build pass-cli from the pinned release here instead of nixpkgs |

Every key but `username` has a default. Rebuild after changing it. An older `settings.nix` still loads with a warning; convert it once with:

```bash
cd /persist/etc/nixos
nix eval --json --file settings.nix | nix run nixpkgs#jq -- . > settings.json
rm settings.nix
```

All the helper commands edit JSON with `jq`, so nothing they write is ever evaluated as Nix code.

## Dotfiles

Each file in `modules/dotfiles/` sets up one program in Home Manager: zsh with autosuggestions and syntax highlighting, git, starship, zoxide, neovim and ghostty, plus yazi (`y`), btop, fastfetch, atuin, fzf, bat and tealdeer with `extras`. Change them from your own modules, as in the example above. When Home Manager has to replace a file that's already there, it renames the old one to `<name>.hm-backup` first. VS Code (`code --wait`) is the default editor for git and anything else that reads `$EDITOR`.

## Theme

Stylix applies the [Catppuccin Mocha](https://catppuccin.com) palette to GTK and Qt apps, GNOME Shell, Plasma, Noctalia on niri, the boot splash, the console and the dotfiles above. Fonts are Noto Sans and Noto Serif, with JetBrains Mono for code. The cursor is Catppuccin Mocha Dark.

To use another [base16 scheme](https://github.com/tinted-theming/schemes):

```nix
{
  flake.modules.nixos.pc =
    { lib, pkgs, ... }:
    {
      stylix.base16Scheme = lib.mkForce "${pkgs.base16-schemes}/share/themes/tokyo-night-dark.yaml";
    };
}
```

Pointing at a scheme file means Nix has to build `base16-schemes` while evaluating, which `nix flake check --no-build` refuses. To keep that check working, copy the scheme's colours inline, the way `modules/stylix.nix` does.

Some Stylix features are switched off:

- Its package overlays rebuild GNOME Shell and a few libraries from source on every update. Without them the GDM login screen isn't themed, but it is still dark.
- The VS Code target replaces `settings.json` with a read-only file. Turn it back on with `stylix.targets.vscode.enable = true` in `homeManager.base`.
- The browser target sets a Chromium/Brave policy, which locks the theme colour and shows "managed by your organization".
- Setting the wallpaper on every login, so that one you pick yourself sticks.

## User picture

The snowflake from the wallpaper is the default user picture on the login screen and in the desktop's user settings. It's only filled in when there's no picture yet, so one you pick yourself stays.

## Wallpaper

`assets/wallpaper.svg` is rendered to a 4K PNG at build time and installed at `/run/current-system/sw/share/backgrounds/ephemeral/wallpaper.png`. It's the default on GNOME (desktop, lock screen and login screen), on niri and on the Plasma login screen. On the Plasma desktop, pick that file in the wallpaper settings. GNOME's own wallpapers are still there to choose from.

The snowflake is the "NixOS Logo" by [Simon Frankau](https://github.com/simon-frankau), [Tim Cuthbertson](https://github.com/timbertson) and [Daniel Baker](https://github.com/djacu) (maintained by the [NixOS Marketing Team](https://nixos.org/community/teams/marketing/)), from [NixOS/branding](https://github.com/NixOS/branding), licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). It has been recoloured.

## Features

### Snapshots

snapper keeps read-only snapshots of `/persist`, and with it your home folder: 24 hourly, 7 daily and 4 weekly. They undo deletes and bad edits, but they're on the same disk, so they aren't a backup.

```bash
sudo snapper -c persist list
sudo cp -a /persist/.snapshots/<n>/snapshot/home/$USER/path/to/file ~/path/to/
```

Only root can read them, because old snapshots still contain old password hashes and keys. Exclude `/persist/.snapshots` from Borg or any other backup of `/persist`, or every snapshot is backed up again.

### LUKS header backup

If the LUKS header at the start of the disk gets damaged, the disk can't be unlocked even with the right passphrase. Keep a copy on a USB stick:

```bash
luks-header-backup /run/media/$USER/<stick>/luks-header.img
```

It refuses to write onto the encrypted disk itself or into memory. The copy unlocks with every passphrase the disk had when it was made, so after changing or removing one, make a new copy and destroy the old ones.

### Control D

```bash
controld-setup
ephemeral-update
```

Stores your resolver id in `/persist/etc/controld-resolver` (root only, never in the Nix store) and sets `useControlD`. All DNS then goes over TLS to Control D, with no fallback servers.

### SMB shares

```bash
smb-setup
ephemeral-update
```

Asks for the server, share, user and password. The password goes to `/persist/etc/smb/<label>.creds` (root only) and the mount to the gitignored `smb-shares.json`. Mounts use SMB 3.1.1 with encryption (`seal`), and don't block booting if the server is away.

### NVIDIA

The installer asks about drivers when it finds an NVIDIA card, and writes the answer to `nvidia` in `settings.json`. To change it later, edit that key and rebuild. `open` uses the current driver with NVIDIA's open kernel modules; `legacy` uses the 580 driver, the last one for GTX 900 and 10 series cards. The driver isn't in the NixOS binary cache, since it's unfree, so the first build compiles its kernel module and takes a few minutes.

Laptops with both an NVIDIA and an Intel or AMD GPU also need [PRIME](https://wiki.nixos.org/wiki/NVIDIA) set up in a private module, with the bus IDs from `lspci`.

### GNOME extensions

Extension Manager is installed in place of GNOME's own Extensions app. The tray (AppIndicator) and Caffeine extensions come from Nix and are on by default. A copy of an extension in `~/.local/share/gnome-shell/extensions` takes precedence over the Nix one, so remove it there to use the version from this repo.

### Laptops and fingerprint login

The installer sets `laptop` when it finds a battery, and asks about `fingerprint` when it sees a USB device from a fingerprint reader maker. Enroll a finger once with `fprintd-enroll`; after that the login screen and sudo accept it. Enrolled prints are kept on `/persist`.

### WireGuard

NetworkManager handles WireGuard itself, so there's nothing extra to install. On GNOME or Plasma, import a `.conf` file from the network settings (VPN, then import from file); `nmcli connection import type wireguard file wg0.conf` does the same from a terminal.

### Tailscale

Set `"useTailscale": true`, rebuild, then sign in once with `sudo tailscale up`. Its state stays on `/persist`, and OpenSnitch gets a rule that lets `tailscaled` through.

### Scanning and disk health

SANE is set up with the driverless `sane-airscan` backend, and Document Scanner is installed on every desktop, so most USB scanners just work. Network scanners aren't found automatically, because mDNS discovery (Avahi) is off on purpose. Add yours by address in a private module:

```nix
{
  flake.modules.nixos.pc.environment.etc."sane.d/airscan.d/local.conf".text = ''
    [devices]
    "Office scanner" = http://192.168.1.50/eSCL
  '';
}
```

smartd watches the disks and sends a desktop notification when one starts to fail.

### Running things without installing them

With `extras` on: type a command that isn't installed and the shell names the package that has it. `, cowsay hello` runs it once without installing anything. Both use a prebuilt package index from [nix-index-database](https://github.com/nix-community/nix-index-database).

### Shell

With `extras` on, fzf adds Ctrl-T (pick a file) and Alt-C (jump to a directory). atuin owns Ctrl-R: a searchable history that stays on this machine, with no account or sync. Import your existing history once with `atuin import auto`. `bat` is `cat` with syntax highlighting, and `tldr <command>` shows short examples.

### Extra apps

`ephemeral-apps` offers nearly 50 common apps by category: browsers, chat, office, media, graphics, games, development, security and utilities. Labels show which ones are unfree, which come from Flathub, and which carry a warning (Docker and Wireshark add you to a powerful group, LocalSend opens a port). Every warning is shown again before anything is saved.

Your picks are saved to `apps.json` next to `settings.json`, a plain list such as `["discord", "obsidian", "docker"]`. Commit it with the rest of your private flake; it isn't a secret, and it brings the same apps to your next machine. On a rebuild:

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

### Flatpak

Flathub is added system-wide from a pinned copy of its repo file, so its signing key can't be swapped. Install Flathub apps through `ephemeral-apps`, or with `flatpak install --user flathub <id>` for anything that isn't in the list.

### direnv

direnv and nix-direnv are on, with the hook in the system zshrc:

```bash
echo 'use flake' > .envrc
direnv allow
```

### Proton Pass

`settings-from-pass` reads an item (default: vault `Personal`, item `nixos-settings`) and writes `settings.from-pass.json`, which is merged over `settings.json` when `usePassSettings` is true. Fields it understands:

- `hostname`, `username`, `diskDevice`, `swapSize`, `timeZone`, `desktop`
- `useFlakePassCli`, as the text `true` or `false`
- `controldResolver`, written to `/persist/etc/controld-resolver`; it also turns on `useControlD`

```bash
pass-cli login
settings-from-pass
ephemeral-update
```

`ssh-pubs-from-pass` writes the public half of each SSH key item in `passSshVault` to `~/.ssh/<title>.pub`, for `IdentityFile` lines. `--list` shows what it would write. `PASS_SETTINGS_VAULT`, `PASS_SETTINGS_ITEM` and `PASS_SSH_VAULT` change where they look.

#### SSH agent

With `"usePassSshAgent": true`, a user service starts `pass-cli ssh-agent` when you log in and serves the SSH keys in `passSshVault`, so the private keys never have to sit in `~/.ssh`. New keys added to the vault show up within 30 seconds. OpenSnitch gets a rule that lets `pass-cli` reach `proton.me`.

It replaces the desktop's own SSH agent (GNOME's gcr), so every app uses it, Flatpaks with SSH access like Pika Backup and Vorta included. While you're logged out of `pass-cli` the service skips itself and there's no agent; `ssh` then only has the key files in `~/.ssh`. After `pass-cli login`, start it without logging out:

```bash
systemctl --user start proton-pass-ssh-agent
ssh-add -l
```

Turning the setting on takes effect for apps at the next login. `journalctl --user -u proton-pass-ssh-agent` shows why the agent didn't start.

## When something breaks

**A rebuild broke the desktop or won't boot.** Every rebuild is a new boot entry, and the last five are kept. Press a key during the 3-second boot menu and pick the previous one. Once you're back in, either fix the config and rebuild, or make the old one stick:

```bash
sudo nixos-rebuild switch --rollback
```

**You want the system exactly as it was installed.** Since v3.0.0 the installer keeps a read-only copy of the config it installed in `/persist/etc/nixos-install`, pinned to the same release. Rebuilding from it resets the system, not your files:

```bash
sudo nixos-rebuild switch --flake path:/persist/etc/nixos-install#nixos
```

Your own config in `/persist/etc/nixos` is untouched, so switching back to it is a normal rebuild.

**You deleted or broke a file in your home folder.** Copy it back from a snapshot; see [Snapshots](#snapshots).

**The graphical login doesn't come up.** Press Ctrl+Alt+F3 for a text console, log in, and look at `journalctl -b -p err`. Rolling back as above is usually the quickest fix.

**The disk won't unlock with the right passphrase.** The LUKS header may be damaged. Boot the NixOS installer USB and restore the copy you made with [`luks-header-backup`](#luks-header-backup):

```bash
sudo cryptsetup luksHeaderRestore /dev/disk/by-partlabel/disk-main-luks --header-backup-file /path/to/luks-header.img
```

**An app can't connect.** Check OpenSnitch's rules first (see the note near the top).

### Reporting a problem

Run `ephemeral-report`, read it, and paste it into a [new issue](https://github.com/the-wittch/ephemeral-nixos-config/issues/new/choose). It lists versions, settings, failed services and recent errors, and leaves out user, host and vault names. On the minimal profile it isn't installed; include the output of `nixos-version` and `systemctl --failed` instead.

### What's tested

This is a personal project shared as-is. x86_64 machines with UEFI are supported. CI evaluates both profiles on GNOME, Plasma and niri, and every app in the picker. On each release it boots both profiles on GNOME in a VM. NVIDIA isn't tested, and there's no Secure Boot.

## Security notes

- The disk is LUKS2 with argon2id. `/boot` is not encrypted, and Secure Boot is not set up.
- `/` starts empty on every boot, so anything that isn't explicitly kept on `/persist` disappears.
- Users are defined by the config, so `passwd` doesn't stick. To change your password:

  ```bash
  mkpasswd -m yescrypt | sudo tee /persist/passwords/$USER
  sudo chmod 600 /persist/passwords/$USER
  ```

- Root has no password. sudo is limited to the `wheel` group, and so is the Nix daemon.
- The firewall is on, SSH is off, and OpenSnitch blocks outgoing connections you haven't allowed.
- Kernel hardening: no unprivileged BPF, restricted ptrace and kernel pointers, a few rarely used network protocols blocked, and no kexec. That last one also rules out hibernation.
- Unfree packages must be listed by name in `ephemeral.unfreePackages`.
- The setup services this repo adds (Control D, Flathub, the default user picture) run sandboxed by systemd.
- smartd's desktop warnings go over the system bus, which lets any local process show you a notification. That's fine with the single user this setup has; turn it off with `services.smartd.notifications.systembus-notify.enable = false`.
- With `fingerprint` on, a finger also works for `sudo`. To keep sudo on the password only, set `security.pam.services.sudo.fprintAuth = false` in a private module.

## Working on this repo

| path | what |
|------|------|
| `modules/flake/` | flake outputs: checks, formatter, and `lib.mkFlake` for machine flakes |
| `modules/host-builder.nix`, `modules/hosts/` | builds machines from `settings.json` |
| `modules/first-boot.nix` | what the minimal profile has instead of the full config |
| `modules/vm.nix` | the VM used by `nix run .#vm` and the boot test |
| `modules/settings/` | the settings options, their defaults (`_defaults.nix`) and the loader |
| `modules/desktop/` | Plasma, GNOME, niri |
| `modules/dotfiles/` | Home Manager dotfiles |
| `modules/packages/` | the helper commands and the pinned pass-cli |
| `modules/apps/` | the app catalog for `ephemeral-apps`, one file per category |
| `modules/tests/` | the VM boot tests, full and minimal |
| `tests/` | machines CI evaluates: one built through `lib.mkFlake`, and niri on both profiles |
| `scripts/` | the helper commands' source and the secret scanner |

The installer has no modules of its own: its `flake.nix` is the machine flake above, pinned to a release of this repo. A change here reaches new installs once the installer pins a release with it.

Turn on the git hooks once per clone:

```bash
git config core.hooksPath .githooks
```

They refuse machine files (`settings.json`, `smb-shares.json`, `hardware-configuration.nix`), `modules/local/`, credentials, private keys and API tokens. pre-push checks every commit you're pushing, so a secret that was added and later deleted is still caught, and CI scans the whole history. `SKIP_SECRET_CHECK=1` skips them on purpose.

CI runs the secret scan, shellcheck, nixfmt and `nix flake check` on every pull request. The boot tests run on `v*` tags and manual runs, and on a pull request once you add the `boot-test` label: `boot` boots the full profile three times with a wiped root and checks services, persistence, snapshots, theming and the LUKS header backup; `boot-minimal` boots the first-boot system twice and checks the wipe, the login screen and that nothing failed. To run them locally:

```bash
cp settings.example.json settings.json
cp hardware-configuration.example.nix hardware-configuration.nix
nix build path:.#checks.x86_64-linux.boot path:.#checks.x86_64-linux.boot-minimal -L
```
