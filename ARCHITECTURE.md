# Architecture

This is how Ephemeral Nix is built, and the rules every change is checked against. It covers this repo and the installer, [ephemeral-nixos](https://github.com/the-wittch/ephemeral-nixos), which has its own [ARCHITECTURE.md](https://github.com/the-wittch/ephemeral-nixos/blob/main/ARCHITECTURE.md) for the install itself.

A change that breaks one of these rules needs a reason, written in the pull request and in this file. Without one, it doesn't go in, however small it is.

## What it is

An opinionated NixOS for one person on one machine. `/` is wiped at every boot; what's kept lives on `/persist`. One disk layout, one user, four desktops, two profiles. Anything that would make it a general installer, such as other layouts, dual boot, more users or other file systems, is out of scope.

## The pieces

| piece | what it is |
|---|---|
| this repo | every NixOS and Home Manager module a machine gets, its helper commands, and its tests |
| a machine's flake, `/persist/etc/nixos` | `flake.nix` pinning a release of this repo, plus `settings.json`, `hardware-configuration.nix`, `apps.json` and its own `modules/` |
| the installer | the ISO, the screens, and `install.sh`, which writes the machine's flake and installs it |
| releases | immutable tags here; the installer pins one, and each machine pins one |

A machine only ever builds a pinned, released tag. Nothing builds from a branch.

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
7. **Settings are evaluated once, on their own, before anything is composed.** Their options and defaults are in `settings/_schema.nix`, and nowhere else.
8. **Prefer the module system to scripts.** Use options, tmpfiles and systemd units. An activation script needs a reason it can't be one of those, written next to it.
9. **Priorities have names.** Use `mkDefault`, `mkOptionDefault` and `mkForce`. A number in `mkOverride` needs a comment saying why.
10. **A full and a minimal variant of the same thing agree**, except where `allowedDrift` in `flake/checks.nix` says why they don't.

## The ephemeral root

1. **`/` is reset to the empty, read-only `root-blank` at every boot**, in the initrd, before `/` is mounted.
2. **A failed reset doesn't stop the boot, but it's never silent.** `root-reset-check` fails, and `ephemeral-doctor` says so and how to fix it.
3. **Everything that has to survive a reboot is listed in `environment.persistence."/persist"`**, by the feature that needs it. The boot test reads that list and checks each entry survives.
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
5. **The firewall is on, SSH is off, and no port opens without an explicit setting.** On the full profile, OpenSnitch denies outgoing connections that haven't been allowed.
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
| 5 | `exposure-eval`: firewall on, no open ports, SSH off and OpenSnitch on, on every desktop and profile; `boot`: IPv4 and IPv6 refuse what isn't allowed, `sshd` isn't running, nothing new listens beyond loopback; `network-filter`: an unapproved program can't reach another machine while OpenSnitch runs, before it filters at boot, or after it crashes |
| 6 | `sandbox-eval`, which finds the services from where they're defined |
| 7, 8 | `settings-reject`, the installer's validation cases (shared by its Go and shell tests), and the script tests |
| 9 | `boot`: the sysctls, kernel command line and blocked modules are in effect |
| 10 | `features-eval`: `tpmUnlock` without `secureBoot` doesn't build; `scripts-behaviour`: enrolling binds to PCR 7 with a PIN and wipes only TPM slots; `tpm-unlock`: the PIN unlocks the disk, and the passphrase still does after a wrong one |

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
