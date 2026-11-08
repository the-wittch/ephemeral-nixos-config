# Working on this repo

| path | what |
|------|------|
| `modules/flake/` | flake outputs: checks, formatter, and `lib.mkFlake` for machine flakes |
| `modules/host-builder.nix`, `modules/hosts/` | builds machines from `settings.json` |
| `modules/first-boot.nix` | what the small install (profile `minimal`) has instead of the full system |
| `modules/vm.nix` | the VM used by `nix run .#vm` and the boot test |
| `modules/settings/` | the settings options, their defaults (`_defaults.nix`) and the loader |
| `modules/desktop/` | Plasma, GNOME, niri, Umbriel, and the Noctalia shell niri and Umbriel share |
| `modules/dotfiles/` | Home Manager dotfiles |
| `modules/packages/` | the helper commands, the pinned pass-cli, and `app-catalog`, which the installer reads |
| `modules/apps/` | the app catalog for `ephemeral-apps`, one file per category |
| `modules/tests/` | the VM boot tests, full and minimal |
| `tests/` | machines CI evaluates, and `upgrade/previous.json`, the release the upgrade test starts from |
| `docs/` | the user docs; the README links each page |
| `scripts/` | the helper commands' source and the secret scanner |

The installer has no modules of its own: its `flake.nix` is the machine flake from the [README](../README.md#rebuild-and-update), pinned to a release of this repo. A change here reaches new installs once the installer pins a release with it.

Turn on the git hooks once per clone:

```bash
git config core.hooksPath .githooks
```

They refuse machine files (`settings.json`, `smb-shares.json`, `hardware-configuration.nix`), `modules/local/`, credentials, private keys and API tokens. pre-push checks every commit you're pushing, so a secret that was added and later deleted is still caught, and CI scans the whole history. `SKIP_SECRET_CHECK=1` skips them on purpose.

CI runs the secret scan, shellcheck, nixfmt and `nix flake check` on every pull request. The boot tests run on `v*` tags and manual runs, and on a pull request once you add the `boot-test` label: `boot` boots the full profile three times with a wiped root and checks services, persistence, snapshots, theming and the LUKS header backup; `boot-minimal` boots the first-boot system twice and checks the wipe, the login screen and that nothing failed; `upgrade` boots a machine on the previous release (`tests/upgrade/previous.json`) and switches it to the current code. To run them locally:

```bash
cp settings.example.json settings.json
cp hardware-configuration.example.nix hardware-configuration.nix
nix build path:.#checks.x86_64-linux.boot path:.#checks.x86_64-linux.boot-minimal path:.#checks.x86_64-linux.upgrade -L
```
