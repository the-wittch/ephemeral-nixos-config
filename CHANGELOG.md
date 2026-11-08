# Changelog

Breaking changes are listed first in each release, with what to do about them. Releases before 3.0.0 are on the [releases page](https://github.com/the-wittch/ephemeral-nixos-config/releases).

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
