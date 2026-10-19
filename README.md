# EphemeralOS Config
[![ci](https://github.com/the-wittch/ephemeral-nixos-config/actions/workflows/ci.yml/badge.svg)](https://github.com/the-wittch/ephemeral-nixos-config/actions/workflows/ci.yml)

Post-install flake for [ephemeral-nixos](https://github.com/the-wittch/ephemeral-nixos). Root rolls back every boot. `/home` and a few paths stay on `/persist`.

Opinionated: desktop apps and services are included that you may want to trim in a private `host.nix` or fork.

Personal machines: private flake that takes this repo as an input (`examples/private-flake/`). Packages in private git. Hostname, disk, and resolver id in gitignored `settings.nix` or Pass.

Or clone this tree and use `customize/` for extras.

## New machine (private flake)

1. Install from [ephemeral-nixos](https://github.com/the-wittch/ephemeral-nixos).
2. Boot, unlock LUKS, log in. The password hash is already in `/persist/passwords/`.
3. Put a private flake on the installed system (copy from `examples/private-flake/`):

   ```bash
   cd /persist/etc/nixos
   cp /path/to/ephemeral-nixos-config/settings.example.nix settings.nix
   # plus hardware-configuration.nix from the install
   sudo nixos-rebuild switch --flake path:.#nixos
   ```

4. Edit `host.nix`. Set `inputs.ephemeral.url` if it is not already correct.

`path:.` is required so Nix sees gitignored `settings.nix` and `hardware-configuration.nix`.

Leave password hashes and SSH host keys on `/persist`.

## Rebuild

```bash
cd /persist/etc/nixos
sudo nixos-rebuild switch --flake path:.#nixos
```

## Updates (private flake)

```bash
nix flake update ephemeral
sudo nixos-rebuild switch --flake path:.#nixos
```

## Fork with customize/ (optional)

If you clone this repo directly, put extras in `customize/` (see `customize/apps.example.nix`). `customize/default.nix` imports every other `.nix` in that folder. Update with `git pull upstream main`.

## Layout

| path | what |
|------|------|
| `flake.nix` | inputs; exports `lib.mkNixos` |
| `lib/mk-nixos.nix` | builds the system for this tree or a private wrapper |
| `lib/load-settings.nix` | defaults, then `settings.nix`, then the pass overlay |
| `disko.nix` | disk layout |
| `configuration.nix` | imports, ssh, nix settings |
| `boot.nix` | bootloader, plymouth, root rollback |
| `persist.nix` | impermanence |
| `users.nix` | user, sudo, chezmoi |
| `desktop.nix` | plasma, gnome, or niri |
| `dns.nix` | Control D |
| `apps.nix` | packages |
| `smb.nix` | CIFS mounts from `smb-setup` |
| `home.nix` | home-manager |
| `packages/pass-cli.nix` | Proton Pass CLI binary |
| `settings.example.nix` | copy to `settings.nix` next to the *host* flake |
| `customize/` | optional extras when using this tree directly |
| `examples/private-flake/` | tiny private host flake on top of this template |
| `scripts/check-no-secrets.sh` | hook and CI secret scan |
| `.githooks/` | `git config core.hooksPath .githooks` |
| `.github/workflows/ci.yml` | same secret scan, plus `nix flake check` |

## settings.nix

```bash
cp settings.example.nix settings.nix
```

See `settings.example.nix` for the fields. Rebuild with `path:.#nixos` after you edit it.

### Hooks

```bash
git config core.hooksPath .githooks
```

Hooks refuse `settings.nix`, `settings.from-pass.nix`, user files under `customize/`, `*.creds`, private keys, and Control D hostnames. CI runs the same scan, so skipping the hook locally still fails on GitHub. `SKIP_SECRET_CHECK=1` skips it on purpose.

### Proton Pass

`useFlakePassCli` picks `packages/pass-cli.nix`. Set it false when nixpkgs has `pkgs.pass-cli`.

`settings-from-pass` writes `settings.from-pass.nix`. Merge order is defaults, then `settings.nix`, then that file. Missing Pass fields are left out, so the file or the defaults stay. `usePassSettings = false` ignores the overlay.

Scripts default to vault `Personal` and item `nixos-settings`. Override with `PASS_SETTINGS_VAULT`, `PASS_SETTINGS_ITEM`, and `PASS_SSH_VAULT`.

1. Make a Pass item `nixos-settings` with custom fields for whatever you want pulled: `hostname`, `username`, `diskDevice`, `swapSize`, `timeZone`, `desktop`, `chezmoiRepo`, `controldResolver`. Bools `allowUnfree` and `useFlakePassCli` are the strings `true` or `false`.
2. `pass-cli login`
3. `usePassSettings = true;` in `settings.nix`
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

Asks for server, share, user, and password. Creds go to `/persist/etc/smb/<label>.creds` (mode 600). Mounts are written to gitignored `smb-shares.nix`. Options are `vers=3.1.1`, `seal`, `nofail`, `_netdev`, and your uid/gid.

## Login password

`passwd` does not stick. The hash is a file:

```bash
mkpasswd -m sha-512
sudo tee /persist/passwords/$USER
sudo chmod 600 /persist/passwords/$USER
```

Hibernation is off. Suspend is fine. SSH is installed and the firewall is closed. Host keys are under `/persist/etc/ssh`.

