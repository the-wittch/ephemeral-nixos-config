# Working on this repo

| path | what |
|------|------|
| `modules/` | what machines get: every file is one feature, loaded by import-tree |
| `flake/` | this repo's own outputs, which machines never load: checks, formatter, `lib.mkFlake` and this repo's `nixos` host |
| `modules/host-builder.nix` | builds machines from `settings.json` |
| `modules/aspects.nix` | `ephemeral.aspects`: the shared modules with a key, for modules that import each other |
| `modules/ephemeral-root.nix`, `modules/persist.nix` | how `/` is reset at every boot, and what survives it |
| `modules/first-boot.nix` | what the small install (profile `minimal`) has instead of the full system |
| `modules/vm.nix` | the VM used by `nix run .#vm` and the boot test |
| `modules/settings/` | the settings options with their defaults (`_schema.nix`), and the loader that checks `settings.json` against them |
| `modules/desktop/` | Plasma, GNOME, niri, Umbriel, and the Noctalia shell niri and Umbriel share |
| `modules/dotfiles/` | Home Manager dotfiles |
| `modules/packages/` | the helper commands, the pinned pass-cli, and `app-catalog`, which the installer reads |
| `modules/apps/` | the app catalog for `ephemeral-apps`, one file per category |
| `flake/tests/` | the VM tests: boot (full and minimal), upgrade, and the disk layout |
| `tests/` | machines CI evaluates (each desktop, full and minimal), and `upgrade/previous.json`, the release the upgrade test starts from |
| `docs/` | the user docs; the README links each page |
| `scripts/` | the helper commands' source and the secret scanner |

The installer has no modules of its own: its `flake.nix` is the machine flake from the [README](../README.md#rebuild-and-update), pinned to a release of this repo. A change here reaches new installs once the installer pins a release with it.

Turn on the git hooks once per clone:

```bash
git config core.hooksPath .githooks
```

They refuse machine files (`settings.json`, `smb-shares.json`, `hardware-configuration.nix`), `modules/local/`, credentials, private keys and API tokens. pre-push checks every commit you're pushing, so a secret that was added and later deleted is still caught, and CI scans the whole history. `SKIP_SECRET_CHECK=1` skips them on purpose.

CI runs the secret scan, shellcheck, nixfmt and `nix flake check` on every pull request. When only docs changed (Markdown, `docs/`, the license, issue templates), the secret scan is all that runs; `.github/changed.sh` decides. The boot tests run on `v*` tags and manual runs, and on a pull request once you add the `boot-test` label: `boot` boots the full profile three times with a wiped root and checks services, persistence, snapshots, theming and the LUKS header backup; `boot-minimal` boots the first-boot system twice and checks the wipe, the login screen and that nothing failed; `upgrade` boots a machine on the previous release (`tests/upgrade/previous.json`) and switches it to the current code; `disk` formats a VM disk with the real layout (LUKS, btrfs, the rollback the other tests switch off), checks the wipe and what survives it, then deletes `root-blank` and brings it back with the steps in [Troubleshooting](troubleshooting.md). To run them locally:

```bash
cp settings.example.json settings.json
cp hardware-configuration.example.nix hardware-configuration.nix
nix build path:.#checks.x86_64-linux.boot path:.#checks.x86_64-linux.boot-minimal path:.#checks.x86_64-linux.upgrade -L
nix build path:.#checks.x86_64-linux.disk -L
```

`desktop-parity` checks that each desktop's full and minimal variants agree on the login manager, keyring, wallet, first-login wizard and persisted folders. A difference has to be fixed or listed in `allowedDrift` in `flake/checks.nix` with its reason, and a listed difference that's gone fails the check too.

Before a change that should only move code, record every host's system, then compare after it:

```bash
.github/drv-diff.sh save /tmp/before.json
# make the change
.github/drv-diff.sh compare /tmp/before.json
```

Every host should say `same`. For one that changed, `nix-diff` shows what.
