# Changelog

Breaking changes are listed first in each release, with what to do about them. Releases before 3.0.0 are on the [releases page](https://github.com/the-wittch/ephemeral-nixos-config/releases).

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
