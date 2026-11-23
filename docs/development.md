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
| `modules/desktop/` | Plasma, GNOME, niri, Umbriel, `none` for a server without a screen, and the Noctalia shell niri and Umbriel share |
| `modules/dotfiles/` | Home Manager dotfiles |
| `modules/packages/` | the helper commands, and `app-catalog`, which the installer reads |
| `modules/apps/` | the app catalog for `ephemeral-apps`, one file per category |
| `flake/tests/` | the VM tests (boot, upgrade, disk layout, desktops, switching profiles) and the helper command tests |
| `tests/` | machines CI evaluates (each desktop with both profiles, each optional feature, and settings that have to be refused), and `upgrade/previous.json`, the release the upgrade test starts from |
| `docs/` | the user docs; the README links each page |
| `scripts/` | the helper commands' source and the secret scanner; `scripts/lib/` has what they share |

The installer adds no modules to the machines it installs: its `flake.nix` is the machine flake from the [README](../README.md#rebuild-and-update), pinned to a release of this repo. A change here reaches new installs once the installer pins a release with it.

Each helper command is a Bash script. `modules/packages/packages.nix` builds it with `writeShellApplication`, with `modules/packages/_prelude.nix` in front of it: the settings rules and menus the scripts need, as shell variables, then every file in `scripts/lib/`. The script tests run the scripts with the same prelude. So the commands share one way of finding the flake, reading settings, writing files, checking release tags and asking questions:

| file | what |
|------|------|
| `core.sh` | `die`, `usage_error` (exit 2), `require_tty`, `ask`, which is a no without a terminal, and `pick_setting`, a menu of a setting's values with their names from `_choices.nix` |
| `flake.sh` | the flake folder, `settings.json`, writing into the flake atomically, and the secret check |
| `release.sh` | the release a flake pins, the newest one, and comparing them |
| `files.sh` | writing a root-only file from a pipe, and checking a backup goes somewhere that outlives this disk |
| `apps.sh` | the rules for `apps.json`, without the screens |
| `tpm.sh` | the firmware's Secure Boot state, whether there's a TPM, and enrolling or removing the disk's TPM slot |

A command's `deps` in `packages.nix` lists every tool it runs, the ones the `scripts/lib/` functions it calls run included. Five come from the system instead and aren't listed: `sudo`, which has to be the setuid wrapper in `/run/wrappers`, `nix` and `systemctl`, which have to match the running daemon and systemd, and `systemd-cryptenroll` and `systemd-creds`, which have to match the systemd in the initrd that unlocks the disk or opens the sealed SSH key. The commands with questions use gum, and stop when there's no terminal rather than do nothing.

Turn on the git hooks once per clone:

```bash
git config core.hooksPath .githooks
```

They refuse machine files (`settings.json`, `smb-shares.json`, `hardware-configuration.nix`), `modules/local/`, credentials, private keys and API tokens. pre-push checks every commit you're pushing, so a secret that was added and later deleted is still caught, and CI scans the whole history. `SKIP_SECRET_CHECK=1` skips them on purpose.

On every pull request, CI runs the secret scan, the link check (`scripts/check-links.py`), actionlint and zizmor on the workflows, shellcheck, shfmt (`-i 2 -ci`) and nixfmt. Then `.github/eval-checks.sh` evaluates every check and builds the ones that don't boot a VM, which takes a few minutes. Among them:

- `features-eval` evaluates a machine with each optional feature on by itself, and one with all of them, and checks each really is on.
- `exposure-eval` checks every desktop and profile for an open port, SSH, a root password, users that can change outside the config, and OpenSnitch turned off where it should be on. A server may have port 22 open, and only with keys.
- `sandbox-eval` finds each root service a file in `modules/` defines, and fails on one without the sandbox unless `flake/checks-security.nix` says why.
- `settings-reject` checks that bad `settings.json` values stay refused: an unknown desktop, a disk path with `..`, a vault name with `$`, an old `settings.nix`.
- `docs-examples` loads every `nix` block in `docs/` into a GNOME machine on the full profile and evaluates it. So each block has to be a whole module for `modules/`, and they can't contradict each other; show a fragment in a `text` block instead.
- `scripts-behaviour` runs `ephemeral-update`, `ephemeral-passwd`, `ephemeral-doctor` and `ssh-pubs-from-pass` against fake `curl`, `nh`, `sudo`, `systemctl` and `fwupdmgr`: what gets offered, what gets refused, which secrets stop a rebuild, that a bad password never replaces the old one, what the audit reports, and what the doctor says about Secure Boot, the TPM and firmware updates. It also tests the `scripts/lib/` functions on their own, and every command's `--help`, its refusal of an unknown option (exit 2, nothing run), and that the ones with questions stop without a terminal.
- the installer still evaluates against this code, so a change that would break it shows before the installer moves to the release.

When only docs changed (Markdown, `docs/`, the license, issue templates), the secret scan and the link check are all that run; `.github/changed.sh` decides, and counts a change inside a `nix` block in `docs/` as code, since `docs-examples` evaluates it. The boot tests run on manual runs, and on a pull request once you add the `boot-test` label. Release pull requests always get the label, so every release is boot-tested before it's merged:

- `boot` boots the full profile three times with a wiped root and checks services, persistence, snapshots, theming and the LUKS header backup.
- `boot-minimal` boots the first-boot system twice and checks the wipe, the login screen, that nothing failed, and that the boot splash draws its passphrase prompt.
- `upgrade` boots a machine on the previous release (`tests/upgrade/previous.json`) and switches it to the current code.
- `disk` formats a VM disk with the real layout (LUKS, btrfs, the rollback the other tests switch off), checks the wipe and what survives it, then deletes `root-blank` and brings it back with the steps `ephemeral-doctor --fix-root-reset` runs.
- `secure-boot` turns `secureBoot` on after an update from the previous release, boots with Secure Boot enforced, also from the fallback path alone, and checks Limine refuses a changed kernel.

Beside them:

- `desktop-build` builds every desktop and most feature hosts.
- `desktop-boot-plasma`, `-niri` and `-umbriel` boot those desktops to their login screen.
- `upgrade-boot` boots the current code on the `/persist` a VM of the previous release wrote.
- `profile-switch` switches a running small install to the full system, as `ephemeral-setup` does, then back.
- `network-filter` checks OpenSnitch against a second machine: what it blocks, what the guard holds back at boot and after a crash, and that a requested stop lets traffic through, even when the daemon dies on the way out.
- `tpm-unlock` unlocks a LUKS root with a software TPM and a PIN, then with the passphrase once wrong PINs have locked the TPM out.
- `remote-unlock` unlocks a server's LUKS root over SSH from a second machine, with the host key the boot loader adds to the initrd, then logs in with a key and has a password refused. `remote-unlock-sealed` does the same with that key sealed to a software TPM.
- `backups` backs up over SSH to a second machine, as a storage box, with the key and passphrase `backup-setup` made, then checks the archive has what the patterns keep and none of what they leave out.

To run the checks locally, use the same script as CI:

```bash
cp settings.example.json settings.json
cp hardware-configuration.example.nix hardware-configuration.nix
.github/eval-checks.sh
```

`--no-build` only evaluates them. Don't run a plain `nix flake check`: it evaluates every check in one process, which needs more than 16 GB of memory and can freeze a laptop. A check you add is picked up by the script on its own.

Build the VM tests one at a time:

```bash
for t in boot boot-minimal upgrade disk secure-boot desktop-boot-plasma desktop-boot-niri desktop-boot-umbriel upgrade-boot profile-switch network-filter tpm-unlock remote-unlock remote-unlock-sealed backups; do
  nix build "path:.#checks.x86_64-linux.$t" -L --no-link
done
```

Building `checks.x86_64-linux.<test>.driver` instead type-checks a test's script the way CI does, without starting a VM. A new VM test gets a `globalTimeout` of about three times what it usually takes, 10 minutes at least, and its CI step a `timeout-minutes` the same way, building included, so a test that hangs fails in minutes.

`desktop-parity` checks that each desktop's full and minimal variants agree on the login manager, keyring, wallet, first-login wizard and persisted folders. A difference has to be fixed or listed in `allowedDrift` in `flake/checks.nix` with its reason, and a listed difference that's gone fails the check too.

Before a change that should only move code, record every host's system, then compare after it:

```bash
.github/drv-diff.sh save /tmp/before.json
# make the change
.github/drv-diff.sh compare /tmp/before.json
```

Every host should say `same`. For one that changed, `nix-diff` shows what.
