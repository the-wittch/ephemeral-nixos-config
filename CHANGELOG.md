# Changelog

Breaking changes are listed first in each release, with what to do about them. Releases before 3.0.0 are on the [releases page](https://github.com/the-wittch/ephemeral-nixos-config/releases).

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
