# Architecture

This is how Ephemeral Nix is built, and the rules every change is checked against. It covers this repo and the installer, [ephemeral-nixos](https://github.com/the-wittch/ephemeral-nixos), which has its own [ARCHITECTURE.md](https://github.com/the-wittch/ephemeral-nixos/blob/main/ARCHITECTURE.md) for the install itself.

A change that breaks one of these rules needs a reason, written in the pull request and in this file. Without one, it doesn't go in, however small it is.

## What it is

An opinionated NixOS for one person on one machine. `/` is wiped at every boot; what's kept lives on `/persist`. One disk layout, one user, four desktops or none, two profiles. Anything that would make it a general installer, such as other layouts, dual boot, more users or other file systems, is out of scope.

## The pieces

| piece | what it is |
|---|---|
| this repo | every NixOS and Home Manager module a machine gets, its helper commands, and its tests |
| a machine's flake, `/persist/etc/nixos` | `flake.nix` pinning a release of this repo, plus `settings.json`, `hardware-configuration.nix`, `apps.json` and its own `modules/` |
| the installer | the ISO, the screens, and `install.sh`, which writes the machine's flake and installs it |
| releases | immutable tags here; the installer pins one, and each machine pins one |

A machine only ever builds a pinned, released tag. Nothing builds from a branch.

## One owner for each thing

Every fact the two repos share has one owner. The other side reads it from a release it pins, never from a branch. The installer has its own [ARCHITECTURE.md](https://github.com/the-wittch/ephemeral-nixos/blob/main/ARCHITECTURE.md) for its side of these.

| what | owner | read by |
|---|---|---|
| the settings: names, rules, defaults | `modules/settings/_rules.nix` and `_schema.nix` | the rebuild; `controld.nix` and the helper commands, through `modules/packages/_prelude.nix`; exported for the installer as the `settings-contract` package and the `settings` output |
| the menus: each value a desktop, driver, profile or DNS setting can have, in order, with its name and line | `modules/settings/_choices.nix`, which `_rules.nix` takes the allowed values from | `ephemeral-setup`, through the prelude; the installer's screens and plain prompts, through `settings-contract` |
| what `settings-from-pass` copies from Proton Pass | `modules/settings/_pass-keys.nix` | the settings loader, which takes nothing else from that file, and `settings-from-pass`, through the prelude |
| the wallpaper and the snowflake logo | `assets/wallpaper.svg` and `modules/branding/_logo.sh` | the desktops, the splash, fastfetch, and the installer, through the `wallpaper` and `welcome-logo` packages |
| the app catalog: ids, labels, categories, defaults, desktops | `ephemeral.apps`, one file per category in `modules/apps/` | `ephemeral-apps`, `host-builder.nix`, and the installer, through the `app-catalog` package |
| the disk layout | `modules/_disko-layout.nix` | disko when installing, the rebuild, and the disk test |
| what's kept across reboots | the feature that needs it, in `preservation.preserveAt."/persist"` | preservation, `ephemeral-doctor kept` and `audit`, and the boot test, which reads the same list |
| the version | the newest heading in `CHANGELOG.md` | `modules/release.nix`, `ephemeral-update --list`, and the release scripts |
| the installer's screens, their wording apart from the menus, disk checks and install steps | the installer | nothing here |

`settings-contract`, `settings`, `wallpaper` and `welcome-logo` are a public interface, like the aspect names: renaming or removing what they hold is a breaking change for the installer.

Where things go:

- **A setting**: its rule in `_rules.nix` if it has one, its option in `_schema.nix`, a row in `docs/settings.md`, its default in `settings.example.json`, and the aspect it switches in `host-builder.nix`. CI fails on a missing row or default, or a row that leaves out a value the setting can have. A setting picked from a menu has its values in `_choices.nix` instead. The contract carries the rule to the installer; asking about the setting on its screens is the installer's job.
- **An app**: one entry in `ephemeral.apps`. The installer and `ephemeral-apps` both list it from there.
- **A desktop**: its entry in `_choices.nix`, its aspects in `modules/desktop/`, a test machine in `tests/<desktop>-full` and `tests/<desktop>-minimal`, and its full and minimal variants agreeing as `desktop-parity` checks. The installer offers it once it pins a release with it.
- **Anything else a machine does**: a file in `modules/`, as the module rules below say.

## Layout

- **`modules/` is what machines get.** Every `.nix` file in it is a flake-parts module, loaded by import-tree. Paths with `/_` are skipped, and that is the only exclusion.
- **`flake/` is this repo's own outputs**: checks, VM tests, `lib.mkFlake` and this repo's host. Machines never load it.
- **`tests/`** holds the machines CI evaluates: one per desktop and profile, and one per optional feature.
- **`scripts/`** holds the helper commands' source; `modules/packages/packages.nix` builds them.

## Modules

1. **One feature, one file.** A feature's NixOS config, Home Manager config, persistence, permissions and sandbox live in its file, or its folder when it's large. Reorganizing files to look tidier isn't a reason on its own.
2. **Files add to shared modules; they don't import each other by path.** The shared modules (aspects) are `flake.modules.nixos.<name>` and `flake.modules.homeManager.<name>`.
3. **The aspect names in [Customizing](docs/customizing.md) are a public interface.** Machine flakes add to them. Renaming or removing one is a breaking change.
4. **Dependencies are imports, through `config.ephemeral.aspects`.** An aspect that sets another's options imports it. Each aspect has a key there, so importing one from several places applies it once. Never import `config.flake.modules.<class>.<name>` directly.
5. **Home Manager config is always a named `homeManager.*` aspect.** NixOS aspects only switch it on, with `home-manager.sharedModules`.
6. **`host-builder.nix` is the only place a machine is composed**, from typed settings to a list of aspects.
7. **Settings are evaluated once, on their own, before anything is composed.** What each may be is in `settings/_rules.nix`; their options and defaults, built from it, are in `settings/_schema.nix`. Nothing else, here or in the installer, keeps its own copy.
8. **Prefer the module system to scripts.** Use options, tmpfiles and systemd units. An activation script needs a reason it can't be one of those, written next to it.
9. **Priorities have names.** Use `mkDefault`, `mkOptionDefault` and `mkForce`. A number in `mkOverride` needs a comment saying why.
10. **A full and a minimal variant of the same thing agree**, except where `allowedDrift` in `flake/checks.nix` says why they don't.

## The ephemeral root

1. **`/` is reset to the empty, read-only `root-blank` at every boot**, in the initrd, before `/` is mounted.
2. **A failed reset doesn't stop the boot, but it's never silent.** `root-reset-check` fails, and `ephemeral-doctor` says so and how to fix it.
3. **Everything that has to survive a reboot is listed in `preservation.preserveAt."/persist"`**, by the feature that needs it, with its owner and mode when they aren't root and 0755, since preservation sets them at every boot. The boot test reads that list and checks each entry survives.
4. **`/persist` is never reset or reformatted**, except by a reinstall the user has confirmed.

## Disk and encryption

The layout is in `modules/_disko-layout.nix`, and the disk test checks it:

- GPT, a 1G ESP mounted at `/boot` with `umask=0077`, and the rest LUKS2 with argon2id;
- in it, btrfs with the subvolumes `root`, `root-blank`, `nix`, `persist`, `log` and `swap`, mounted with `compress=zstd,noatime`;
- the swap file inside the encryption; no hibernation.

Changing any of these is a breaking change and needs a migration for existing machines.

## Security

These hold on every machine, in every profile:

1. **The disk passphrase and the login password never appear in a command line, an environment variable, a log, or a file other than the password hash** in `/persist/passwords/<user>`, mode 600, owned by root.
2. **No secret goes into `/persist/etc/nixos`**, or anywhere else built with `path:`. Those are copied into the world-readable Nix store, whatever `.gitignore` says. Secrets live in `/persist/etc/<name>`, owned by root with mode 600, and are read at runtime. `ephemeral-update` refuses to rebuild when the folder has a file named like a secret, a private key or token inside a file, or a token in a git remote URL. It can't see a secret that was committed and later deleted: that stays in `.git`, which goes into the store too.
3. **Secret permissions are set again at every boot**, by tmpfiles rules next to the feature that owns the secret.
4. **Root has no password. sudo is for `wheel`, with a password. The Nix daemon is for `wheel` only. Users are declared by the config** (`mutableUsers = false`).
5. **The firewall is on, SSH is off, and no port opens without an explicit setting.** `server` is that setting for SSH: port 22, for the keys in `sshKeys` only, with passwords and root refused, and port 2222 in the initrd, for the same keys, only until the disk is unlocked. Its host key reaches the initrd through the boot loader, never the Nix store, sealed to the TPM with Secure Boot on. On the full profile, OpenSnitch denies outgoing connections that haven't been allowed, except without a desktop, where nobody could answer it.
6. **Root services this repo adds run in `config.ephemeral.sandbox`**, unless `unsandboxed` in `flake/checks-security.nix` says why they can't.
7. **Anything a user typed reaches a shell only through a validator, `escapeShellArg`, an environment variable or `jq --arg`.** Never through string concatenation.
8. **Every value in `settings.json` that ends up in a script or a path has a type that refuses what would break it.** `settings-reject` checks the refusals.
9. **Kernel hardening only gets stronger.** Turning something off needs a changelog entry saying how to undo it.
10. **The TPM only unlocks the disk with Secure Boot on and a PIN, and never in place of the passphrase.** `tpmUnlock` refuses to build without `secureBoot`, and enrolling never removes a passphrase slot.

What checks each one:

| rule | checked by |
|---|---|
| 1 | the installer's install test: neither is in the install logs, on the installed disk or in its store, and the passphrase unlocks the disk it went to disko with |
| 2 | `scripts-behaviour`: key files, tokens in files and tokens in a git remote stop a rebuild; an ordinary flake doesn't |
| 3 | `boot`: secrets written with loose modes are root-only after a reboot |
| 4 | `exposure-eval`: no root password and `mutableUsers` off on every desktop and profile; `boot`: root locked, sudo refused outside `wheel`, the Nix daemon refused outside `wheel` |
| 5 | `exposure-eval`: firewall on, no open ports, SSH off and OpenSnitch on, on every desktop and profile, and on a server only port 22, with passwords, keyboard-interactive login and root refused; `features-eval`: a server without keys, and no desktop without `server`, don't build, and the initrd host key isn't in the store; `scripts-behaviour`: the boot copy of that key is sealed to PCR 7 with Secure Boot and a TPM; `remote-unlock` and `remote-unlock-sealed`: the passphrase over SSH at boot unlocks the disk, with the plain and the sealed key, and the running server refuses a password; `boot`: IPv4 and IPv6 refuse what isn't allowed, `sshd` isn't running, nothing new listens beyond loopback; `network-filter`: an unapproved program can't reach another machine while OpenSnitch runs, before it filters at boot, or after it crashes |
| 6 | `sandbox-eval`, which finds the services from where they're defined |
| 7, 8 | `settings-reject`, the installer's validation cases (shared by its Go and shell tests), and the script tests |
| 9 | `boot`: the sysctls, kernel command line and blocked modules are in effect |
| 10 | `features-eval`: `tpmUnlock` without `secureBoot` doesn't build; `scripts-behaviour`: enrolling binds to PCR 7 with a PIN and wipes only TPM slots; `tpm-unlock`: the PIN unlocks the disk, and the passphrase still does once wrong PINs have locked the TPM out |

Encrypted DNS and Control D have no plaintext fallback: `boot` checks it with Control D, `features-eval` with a provider.

## Helper commands

1. **One command per job.** `ephemeral-update` rebuilds, checks, rolls back and moves releases; `ephemeral-doctor` diagnoses. Nothing tells a user to type `nixos-rebuild` or `path:` for an everyday job.
2. **Every error says what to do next**, in plain words, with the command when there is one.
3. **Commands that change the machine ask first** and say what they're about to change. Commands that only look don't need sudo.
4. **`ephemeral-update` only offers a newer, well-formed release tag**, shows what changed, and names a new major version before asking.
5. **Commands on the small install** are the ones a machine needs before it has the full system: update, doctor, setup, password, backup, report and the LUKS header backup.

## Releases and updates

1. **Releases are immutable.** A published tag and its files never change.
2. **Only nixpkgs updates merge on their own**, once CI and the boot tests pass. Every other input is updated in a pull request a person reads first, since its code runs as root on every machine.
3. **Every release has a changelog entry.** A breaking change goes first, under Breaking, with what to do about it.
4. **A breaking change gets a new major version**, and the old behaviour gets a clear error or warning that says what to change, not a silent change.
5. **The installer only moves to a config release once its install test passes** with that release.
6. **CI workflows pin every action by commit, ask for their permissions per job, and keep tokens out of the checkout.** zizmor and actionlint check them.
7. **Only a merge from `release/vX.Y.Z` makes a release from a `release vX.Y.Z` commit.** A pull request's title becomes its merge message, and anyone can open one.

A machine moving to a new release trusts GitHub: its answer for the newest release, over TLS, and the rulesets that keep tags from moving. Nothing on the machine checks a signature, and CI makes the weekly tags unsigned. Whoever controls the maintainer's account or `FLAKE_UPDATE_TOKEN`, which can push branches and turn on auto-merge, can publish a release every machine is offered. That's why the token has to be fine-grained: this repository's contents and pull requests only, with an expiry. The user still confirms each move, after seeing what changed.

## Tests

1. **Every bug that's fixed gets a test that fails without the fix**, at the cheapest level that catches it: a Nix evaluation check, then a script test with fake commands, then a VM test.
2. **Cheap checks run on every pull request; VM tests run on release pull requests and manual runs.** A new VM test says in its file what it catches that a cheaper check can't.
3. **A refactor that only moves code leaves every machine's system unchanged.** `.github/drv-diff.sh` shows it. Where a derivation changes only in the order of a list, show that the sorted contents are the same.
4. **A check has to be able to fail.** When adding one, break the thing it checks on purpose and see it fail.
5. **Every security rule names what checks it**, in the table under Security. A rule without a check is a gap to close.

## Documentation

1. **Docs describe what a user does, not how it's built.** Internals go in this file and in [Working on this repo](docs/development.md).
2. **Each doc page answers one question**, and the README links to each.
3. **A change that alters what a user types or sees updates the page that describes it in the same pull request.**
4. **Plain words.** No marketing, no filler, and nothing that reads as generated.
