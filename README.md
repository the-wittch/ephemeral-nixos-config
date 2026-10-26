# Ephemeral Nix Config
[![CI](https://github.com/the-wittch/ephemeral-nixos-config/actions/workflows/ci.yml/badge.svg)](https://github.com/the-wittch/ephemeral-nixos-config/actions/workflows/ci.yml)

<img width="3840" height="2160" alt="wallpaper" src="https://github.com/user-attachments/assets/b4e08080-876a-4ab3-911f-4055a4f2de0d" />

Post-install flake for [ephemeral-nixos](https://github.com/the-wittch/ephemeral-nixos). Root rolls back every boot. `/home` and a few paths stay on `/persist`.

Opinionated: desktop apps and services are included that you may want to trim in a private `host.nix` or fork.

Personal machines: private flake that takes this repo as an input (`examples/private-flake/`). Packages in private git. Hostname, disk, and resolver id in gitignored `settings.json` or Pass.

Or clone this tree and use `customize/` for extras.

## New machine (private flake)

1. Install from [ephemeral-nixos](https://github.com/the-wittch/ephemeral-nixos).
2. Boot, unlock LUKS, log in. The password hash is already in `/persist/passwords/`.
3. Put a private flake on the installed system:

   ```bash
   cd /persist/etc/nixos

   BASE=https://raw.githubusercontent.com/the-wittch/ephemeral-nixos-config/main
   curl -fsSL -o flake.nix "$BASE/examples/private-flake/flake.nix"
   curl -fsSL -o host.nix "$BASE/examples/private-flake/host.nix"
   curl -fsSL -o .gitignore "$BASE/examples/private-flake/.gitignore"
   curl -fsSL -o settings.json "$BASE/settings.example.json"

   # hardware-configuration.nix from the install (keep or copy into this directory)

   nix flake update
   sudo nixos-rebuild switch --flake path:.#nixos
   ```

4. Edit `settings.json` and `host.nix`. `flake.nix` already points at this template.

`path:.` is required so Nix sees gitignored `settings.json` and `hardware-configuration.nix`.

Leave password hashes and SSH host keys on `/persist`.

## Rebuild

```bash
ephemeral-update
```

That runs `sudo nixos-rebuild switch --flake path:/persist/etc/nixos#nixos`.

## Updates (private flake)

```bash
nix flake update ephemeral --flake /persist/etc/nixos
ephemeral-update
```

## Fork with customize/ (optional)

If you clone this repo directly, put extras in `customize/` (see `customize/apps.example.nix`). `customize/default.nix` imports every other `.nix` in that folder. Update with `git pull upstream main`.

## Layout

| path | what |
|------|------|
| `flake.nix` | inputs; exports `lib.mkNixos` |
| `lib/mk-nixos.nix` | builds the system for this tree or a private wrapper |
| `lib/load-settings.nix` | defaults, then `settings.json`, then the pass overlay |
| `lib/read-data.nix` | loads a JSON machine file (or its legacy `.nix`) |
| `unfree.nix` | unfree allowlist (`ephemeral.unfreePackages`) |
| `packages/scripts.nix` | every packaged command; also exported as flake packages |
| `disko.nix` | disk layout |
| `configuration.nix` | imports, ssh, nix settings |
| `boot.nix` | bootloader, plymouth, root rollback |
| `persist.nix` | impermanence |
| `users.nix` | user, sudo, chezmoi |
| `desktop.nix` | plasma, gnome, or niri |
| `dns.nix` | Control D (`controld-setup`) |
| `apps.nix` | packages |
| `smb.nix` | CIFS mounts from `smb-setup` |
| `snapshots.nix` | hourly/daily/weekly snapper snapshots of `/persist` |
| `hardening.nix` | kernel sysctls and module blacklist (shared with the installer) |
| `flathub.nix` | Flathub remote from a pinned repo file (shared with the installer) |
| `wallpaper.nix`, `assets/wallpaper.svg` | default wallpaper and login background (shared with the installer) |
| `tests/boot.nix` | VM test: three boots with a wiped root, checks units, persistence, snapshots |
| `home.nix` | home-manager |
| `packages/pass-cli.nix` | local pass-cli fallback (`useFlakePassCli = true`); pin in `pass-cli.json` |
| `settings.example.json` | copy to `settings.json` next to the *host* flake |
| `customize/` | optional extras when using this tree directly |
| `examples/private-flake/` | tiny private host flake on top of this template |
| `scripts/lib.sh` | helpers built into the packaged commands |
| `scripts/check-no-secrets.sh` | hook and CI secret scan |
| `scripts/check-shared.sh` | CI check that the shared modules match the installer |
| `.githooks/` | `git config core.hooksPath .githooks` |
| `.github/workflows/ci.yml` | secret scan over full history, shellcheck, nixfmt, `nix flake check` |

## settings.json

```bash
cp settings.example.json settings.json
```

Rebuild with `path:.#nixos` after you edit it.

| key | what |
|-----|------|
| `hostname`, `username`, `timeZone` | machine identity |
| `diskDevice`, `swapSize` | disk layout; the whole disk, not a partition |
| `desktop` | `plasma`, `gnome`, or `niri` |
| `useControlD` | DNS over TLS to Control D; the id lives in `/persist/etc/controld-resolver` (`controld-setup`) |
| `useFlakePassCli` | `true` builds `packages/pass-cli.nix` instead of nixpkgs `proton-pass-cli` |
| `usePassSettings`, `passSettingsVault`, `passSettingsItem` | merge `settings.from-pass.json` from Proton Pass |

An older `settings.nix` still loads, with a warning. Convert it once:

```bash
cd /persist/etc/nixos
nix eval --json --file settings.nix | nix run nixpkgs#jq -- . > settings.json && rm settings.nix
```

The scripts (`controld-setup` and friends) only edit `settings.json`, with `jq`, so convert before using them. Generated files (`settings.from-pass.json`, `smb-shares.json`) are JSON too, so nothing the scripts write is ever run as Nix code.

### Unfree packages

Nothing unfree builds unless it's listed. Each module lists the unfree packages it adds, for example `apps.nix`:

```nix
ephemeral.unfreePackages = [ "steam" "steam-unwrapped" "vscode" "unrar" ];
```

Add your own in `host.nix` the same way. An unlisted package fails the build and names the package.

### Hooks

```bash
git config core.hooksPath .githooks
```

Hooks refuse `settings.json`, `settings.from-pass.json`, `smb-shares.json` (and their old `.nix` names), user files under `customize/`, `*.creds`, private keys, and Control D hostnames. pre-push checks every commit being pushed, so a secret added and then deleted is still caught. CI scans the whole history, so skipping the hook locally still fails on GitHub. `SKIP_SECRET_CHECK=1` skips it on purpose.

### Proton Pass

`pass-cli` comes from nixpkgs `proton-pass-cli`. `useFlakePassCli = true` keeps the local package in `packages/pass-cli.nix`. `update-pass-cli` updates its pin in `packages/pass-cli.json`; run it from a checkout of this repo.

`settings-from-pass` writes `settings.from-pass.json`. Merge order is defaults, then `settings.json`, then that file. Missing Pass fields are left out, so the file or the defaults stay. `usePassSettings = false` ignores the overlay.

Scripts default to vault `Personal` and item `nixos-settings`. Override with `PASS_SETTINGS_VAULT`, `PASS_SETTINGS_ITEM`, and `PASS_SSH_VAULT`.

1. Make a Pass item `nixos-settings` with custom fields for whatever you want pulled: `hostname`, `username`, `diskDevice`, `swapSize`, `timeZone`, `desktop`. The bool `useFlakePassCli` is the string `true` or `false`. `chezmoiRepo` plus `chezmoiRev` (the full 40-character commit hash) are written to `/persist/etc/chezmoi-repo`. `controldResolver` is written to `/persist/etc/controld-resolver` and sets `useControlD = true`.
2. `pass-cli login`
3. `"usePassSettings": true` in `settings.json`
4. Pull and rebuild:

```bash
settings-from-pass
sudo nixos-rebuild switch --flake path:.#nixos
```

```bash
update-pass-cli
update-pass-cli --check

ssh-pubs-from-pass --list
ssh-pubs-from-pass
```

`ssh-pubs-from-pass` writes `~/.ssh/<title>.pub` for IdentityFile.

Dotfiles (zsh, git, editors) belong in chezmoi. Nix experiments go in `home.nix`.

## direnv

`home.nix` turns on direnv and nix-direnv. The zsh hook is `programs.direnv` in `configuration.nix`, so it lands in `/etc` and chezmoi can keep `~/.zshrc`.

```bash
echo 'use flake' > .envrc
direnv allow
```

## Flatpak

```bash
flatpak-apps
```

User Flatpaks. The list is in `scripts/flatpak-tui.sh`.

## SMB

```bash
smb-setup
sudo nixos-rebuild switch --flake path:.#nixos
```

Asks for server, share, user, and password. Creds go to `/persist/etc/smb/<label>.creds` (mode 600). Mounts are written to gitignored `smb-shares.json`. Options are `vers=3.1.1`, `seal`, `nofail`, `_netdev`, and your uid/gid.

## Login password

`passwd` does not stick. The hash is a file:

```bash
mkpasswd -m yescrypt
sudo tee /persist/passwords/$USER
sudo chmod 600 /persist/passwords/$USER
```

Hibernation is off. Suspend is fine. SSH is off; `services.openssh.enable = true` in `host.nix` turns it on with the firewall still closed. The ed25519 host key is under `/persist/etc/ssh`.


## Login screen

The login screen is dark on all three desktops. Its wallpaper and your avatar come from the desktop's own settings: GNOME Settings, Plasma System Settings (Login Screen, Users), or Noctalia's greeter sync on niri. GDM shows the default GNOME background.

## Snapshots

snapper keeps read-only snapshots of `/persist`, and so of your home: 24 hourly, 7 daily, 4 weekly. They undo deletes and bad edits. They live on the same disk, so they don't replace a backup.

```bash
sudo snapper -c persist list
sudo cp -a /persist/.snapshots/<n>/snapshot/home/$USER/path/to/file ~/path/to/
```

Only root can read them, since old snapshots still hold old password hashes and keys. Exclude `/persist/.snapshots` from Borg (or any other backup of `/persist`), or every snapshot gets backed up again.

## LUKS header backup

If the LUKS header at the start of the disk is damaged, the disk can't be unlocked, even with the right passphrase. Keep a copy on a USB stick:

```bash
luks-header-backup /run/media/$USER/<stick>/luks-header.img
```

It refuses a destination on the encrypted disk itself or in memory. The copy unlocks with every passphrase that existed when it was made, so after changing or removing a passphrase, make a new copy and destroy the old ones.

## Wallpaper

`assets/wallpaper.svg` is rendered to a 4K PNG at build time and installed at `/run/current-system/sw/share/backgrounds/ephemeral/wallpaper.png`. It's the default on GNOME (desktop, lock screen, and the GDM login screen) and on the Plasma login screen; on Plasma's desktop or niri, pick that file in the wallpaper settings. A wallpaper you choose yourself always wins.

The snowflake is the [NixOS logo](https://github.com/NixOS/nixos-artwork) by Tim Cuthbertson, used under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) and recoloured.
