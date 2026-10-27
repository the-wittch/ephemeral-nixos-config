# Ephemeral Nix Config

[![CI](https://github.com/the-wittch/ephemeral-nixos-config/actions/workflows/ci.yml/badge.svg)](https://github.com/the-wittch/ephemeral-nixos-config/actions/workflows/ci.yml)

<img width="3840" height="2160" alt="wallpaper" src="https://github.com/user-attachments/assets/b4e08080-876a-4ab3-911f-4055a4f2de0d" />

The full NixOS config for machines installed with [ephemeral-nixos](https://github.com/the-wittch/ephemeral-nixos). `/` is wiped on every boot; `/home` and a short list of system paths live on `/persist`.

On top of the installer's base system it adds:

- Home Manager dotfiles: zsh, git, starship, zoxide, neovim, ghostty, yazi, btop, fastfetch. chezmoi is supported instead, if you prefer it.
- A dark Catppuccin Mocha theme everywhere, through [Stylix](https://github.com/nix-community/stylix).
- Hourly snapper snapshots of `/persist`.
- OpenSnitch, Syncthing, Podman, Flatpak with Flathub, Steam and the usual desktop apps.
- Optional DNS over TLS through Control D, SMB mounts, and machine settings pulled from Proton Pass.

It's opinionated. Trim what you don't want in your own modules (see below).

## Setup

Keep your changes in a private flake that uses this repo as an input. Your packages and tweaks stay in your own git repo, and updates here are one command away. Machine details stay in the gitignored `settings.json` the installer already wrote.

On an installed machine:

```bash
mkdir -p ~/nixos/modules
cd ~/nixos
BASE=https://raw.githubusercontent.com/the-wittch/ephemeral-nixos-config/main/examples/private-flake
curl -fsSL -o flake.nix "$BASE/flake.nix"
curl -fsSL -o .gitignore "$BASE/.gitignore"
curl -fsSL -o modules/ephemeral.nix "$BASE/modules/ephemeral.nix"
curl -fsSL -o modules/apps.nix "$BASE/modules/apps.nix"
cp /persist/etc/nixos/settings.json /persist/etc/nixos/hardware-configuration.nix .
nix flake lock
sudo nixos-rebuild switch --flake path:.#nixos
```

Once that works, make it the system config and put it in git:

```bash
sudo mv /persist/etc/nixos /persist/etc/nixos.installer
sudo mv ~/nixos /persist/etc/nixos
cd /persist/etc/nixos
git init
git add -A
git commit -m "private flake"
```

`settings.json` and `hardware-configuration.nix` are gitignored, so they stay on the machine. Always build with `path:`; a plain `.#nixos` only sees files tracked by git and won't find them.

## Rebuild and update

```bash
ephemeral-update
```

That's `sudo nixos-rebuild switch --flake path:/persist/etc/nixos#nixos`. To move to a newer version of this repo:

```bash
nix flake update ephemeral --flake /persist/etc/nixos
ephemeral-update
```

## How it's organized

The config follows the [dendritic pattern](https://github.com/mightyiam/dendritic):

- Every `.nix` file under `modules/` is a [flake-parts](https://flake.parts) module. [import-tree](https://github.com/vic/import-tree) loads all of them, so there's no import list to keep up to date. Paths containing `/_` are skipped.
- Each file is one feature: Syncthing, the boot splash, zsh, the theme. A single file can set NixOS and Home Manager options together.
- Files don't import each other. They add to a few shared modules, such as `flake.modules.nixos.pc` or `flake.modules.homeManager.dotfiles`, and a machine is built by combining those.
- Settings are a normal NixOS option (`config.ephemeral.settings`), not extra function arguments.

Adding a feature means adding a file, and removing one means deleting it. [mightyiam/infra](https://github.com/mightyiam/infra) and [Bad3r/nixos](https://github.com/Bad3r/nixos) are larger configs built the same way.

## Your own modules

Your private flake works the same way. These are the shared modules you can add to:

| module | applies to |
|--------|------------|
| `flake.modules.nixos.base` | every machine |
| `flake.modules.nixos.pc` | desktop machines (all of them, here) |
| `flake.modules.nixos.gnome`, `.plasma`, `.niri` | the desktop chosen in `settings.json` |
| `flake.modules.homeManager.base` | your user, always |
| `flake.modules.homeManager.dotfiles` | your user, unless chezmoi manages the dotfiles |

A file in your private flake can add to any of them:

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

The private flake has to declare the `impermanence`, `disko`, `home-manager` and `stylix` inputs as `follows` of `ephemeral`, as the example does, because the modules here refer to them by name.

If you'd rather work in a clone of this repo, put your files in `modules/local/` instead. That folder is gitignored; `modules/local/_example.nix` shows the shape.

## settings.json

| key | what |
|-----|------|
| `hostname`, `username`, `timeZone` | who and where the machine is |
| `diskDevice`, `swapSize` | the whole disk (not a partition) and the swap file size |
| `desktop` | `plasma`, `gnome` or `niri` |
| `useChezmoi` | chezmoi writes the dotfiles instead of Home Manager |
| `useControlD` | DNS over TLS through Control D |
| `usePassSettings`, `passSettingsVault`, `passSettingsItem` | merge settings from Proton Pass |
| `useFlakePassCli` | build pass-cli from the pinned release here instead of nixpkgs |

Every key but `username` has a default. Rebuild after changing it. An older `settings.nix` still loads with a warning; convert it once with:

```bash
cd /persist/etc/nixos
nix eval --json --file settings.nix | nix run nixpkgs#jq -- . > settings.json
rm settings.nix
```

All the helper commands edit JSON with `jq`, so nothing they write is ever evaluated as Nix code.

## Dotfiles

Each file in `modules/dotfiles/` sets up one program in Home Manager: zsh with autosuggestions and syntax highlighting, git, starship, zoxide, neovim as the default editor, ghostty, yazi (`y`), btop and fastfetch. Change them from your own modules, as in the example above. When Home Manager has to replace a file that's already there, it renames the old one to `<name>.hm-backup` first.

### chezmoi instead

Set `"useChezmoi": true` and write `<git-url> <full-commit-hash>` to `/persist/etc/chezmoi-repo` (mode 600), or let the installer or `settings-from-pass` do both. After a rebuild, `chezmoi-init` clones the repo once and runs `chezmoi init --apply`. The Home Manager dotfiles are left out so the two don't fight over the same files; the programs themselves are still installed.

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

Some Stylix features are switched off:

- Its package overlays rebuild GNOME Shell and a few libraries from source on every update. Without them the GDM login screen isn't themed, but it is still dark.
- The VS Code target replaces `settings.json` with a read-only file. Turn it back on with `stylix.targets.vscode.enable = true` in `homeManager.base`.
- The browser target sets a Chromium/Brave policy, which locks the theme colour and shows "managed by your organization".
- Setting the wallpaper on every login, so that one you pick yourself sticks.

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

### Flatpak

`flatpak-apps` offers a short list of Flatpaks (Flatseal, Heroic, Thunderbird, Vorta and others) to install for your user. Flathub itself is added system-wide from a pinned copy of its repo file, so its signing key can't be swapped.

### direnv

direnv and nix-direnv are on, with the hook in the system zshrc, so they work with either dotfile manager:

```bash
echo 'use flake' > .envrc
direnv allow
```

### Proton Pass

`settings-from-pass` reads an item (default: vault `Personal`, item `nixos-settings`) and writes `settings.from-pass.json`, which is merged over `settings.json` when `usePassSettings` is true. Fields it understands:

- `hostname`, `username`, `diskDevice`, `swapSize`, `timeZone`, `desktop`
- `useFlakePassCli`, as the text `true` or `false`
- `chezmoiRepo` and `chezmoiRev`, written to `/persist/etc/chezmoi-repo`; they also turn on `useChezmoi`
- `controldResolver`, written to `/persist/etc/controld-resolver`; it also turns on `useControlD`

```bash
pass-cli login
settings-from-pass
ephemeral-update
```

`ssh-pubs-from-pass` writes the public half of each SSH key item to `~/.ssh/<title>.pub`, for `IdentityFile` lines. `--list` shows what it would write. `PASS_SETTINGS_VAULT`, `PASS_SETTINGS_ITEM` and `PASS_SSH_VAULT` change where they look.

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
- The setup services this repo adds (Control D, chezmoi, Flathub) run sandboxed by systemd.

## Working on this repo

| path | what |
|------|------|
| `modules/flake/` | flake outputs: packages, checks, formatter, and the module private flakes import |
| `modules/host-builder.nix`, `modules/hosts/` | builds machines from `settings.json` |
| `modules/settings/` | the settings options and loader |
| `modules/desktop/` | Plasma, GNOME, niri |
| `modules/dotfiles/` | Home Manager dotfiles and chezmoi |
| `modules/packages/` | the helper commands and the pinned pass-cli |
| `modules/tests/boot.nix` | the VM boot test |
| `examples/private-flake/` | the starting point for a private flake |
| `scripts/` | the helper commands' source, the secret scanner and the shared-file check |

Most of the base system is shared byte for byte with the installer; `scripts/check-shared.sh` lists the files and CI fails if they differ. Change them in both repos together.

Turn on the git hooks once per clone:

```bash
git config core.hooksPath .githooks
```

They refuse machine files (`settings.json`, `smb-shares.json`, `hardware-configuration.nix`), `modules/local/`, credentials, private keys and API tokens. pre-push checks every commit you're pushing, so a secret that was added and later deleted is still caught, and CI scans the whole history. `SKIP_SECRET_CHECK=1` skips them on purpose.

CI runs the secret scan, shellcheck, nixfmt and `nix flake check` on every pull request. The VM boot test boots three times with a wiped root and checks services, persistence, snapshots, theming and the LUKS header backup. It runs on `v*` tags and manual runs, and on a pull request once you add the `boot-test` label. To run it locally:

```bash
cp settings.example.json settings.json
cp hardware-configuration.example.nix hardware-configuration.nix
nix build path:.#checks.x86_64-linux.boot -L
```
