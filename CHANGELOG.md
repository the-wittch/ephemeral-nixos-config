# Changelog

Breaking changes are listed first in each release, with what to do about them. Releases before 3.0.0 are on the [releases page](https://github.com/the-wittch/ephemeral-nixos-config/releases).

## 4.2.0

### Added

- `sudo ephemeral-doctor audit` lists services whose data in `/var/lib` isn't kept, so they start over at every boot, and folders in `/persist/var/lib` nothing uses any more, like one left behind by an app you removed. It goes by what services tell systemd, so it can't catch everything.

### Fixed

- Battery history started over at every boot, so the desktops' battery charts only ever showed the current one. `/var/lib/upower` is kept now.
- The security notes now say what the wiped `/` doesn't protect against: malware that hides in the home folder, anything with root, and anything before the next reboot.

## 4.1.0

### Added

- `ephemeral-doctor` checks the machine and prints the command that fixes each problem it finds: whether `/` was wiped at this boot, failed services, free space on `/persist` and `/nix`, the last snapshot, a newer release, secret files in the config folder, and a missing LUKS header backup. `ephemeral-doctor kept` lists what's kept across reboots, `ephemeral-doctor lost` what the next reboot removes, and `sudo ephemeral-doctor --fix-root-reset` makes `/` reset again when it doesn't.
- `ephemeral-update --check` builds a change without switching to it, `--previous` goes back to the system before the last rebuild, `--list` shows the systems you can go back to with their config releases, and `--as-installed` rebuilds the system as it was installed.
- Before moving to a new release, `ephemeral-update` shows what changed since yours, from the changelog. For a new major version it names that in the question.
- `ephemeral-backup <folder>` saves what a reinstall needs and git doesn't keep, the settings files and the root-only secrets, in one file encrypted with a passphrase you pick.
- A notification at the first login says where to start, on every desktop.

### Changed

- The small install has `ephemeral-update`, `ephemeral-doctor`, `ephemeral-backup`, `ephemeral-report` and `luks-header-backup` too, and `ephemeral-help` lists only the commands a machine has.
- `ephemeral-report` includes what `ephemeral-doctor` found, the last lines of each failed service, and the systems you can go back to, and keeps user and host names out of every line.
- Every command that used to say `sudo nixos-rebuild switch --flake path:...` now says `ephemeral-update`, and so do the docs. The troubleshooting page uses the new commands, and says where to save a fix.

- More tests, so mistakes are caught before a release goes out:
  - every pull request evaluates each optional feature on its own and all together, checks that bad settings stay refused, runs `ephemeral-update` and `ephemeral-passwd` against fake commands, and checks the installer still evaluates against the change;
  - release pull requests also build every desktop, boot Plasma, niri and Umbriel to their login screen, and boot the new code on a `/persist` the previous release wrote;
  - the disk test checks the LUKS and btrfs setup itself (LUKS2, argon2id, the subvolumes, the mount options, `/boot` readable by root only), and that a subvolume made inside `/` is wiped too;
  - the boot test checks that every folder the config keeps survives a reboot, and the upgrade test switches back to the previous release afterwards;
  - the workflows are linted with actionlint and zizmor.
- `ephemeral-update` honours `FLAKE_DIR`, like the other commands.

## 4.0.0

### Breaking

- `settings.nix`, `settings.from-pass.nix` and `smb-shares.nix` aren't read any more, only their `.json` forms. If a machine still has one without the `.json`, the rebuild stops and prints the command that converts it. To check before moving, `ls /persist/etc/nixos/*.nix` should list only `flake.nix` and `hardware-configuration.nix`.
- The undocumented `flake.modules.nixos.dotfiles` is gone. Home Manager now turns on `flake.modules.homeManager.dotfiles` itself, so a machine flake that imported the NixOS one has to drop it.

### Added

- `ephemeral-passwd` changes your login password, on the small install too. It asks twice and only replaces `/persist/passwords/$USER` once it has a valid hash, so a typo or a cancelled prompt can't lock you out at the next boot as the old instructions could. The new password works straight away.

### Changed

- `ephemeral-update` and `ephemeral-setup` refuse to rebuild when `/persist/etc/nixos` has files that look like secrets, such as `*.key`, `*.pem`, `id_ed25519`, `.env` or a `passwords` folder. A rebuild copies the whole folder into the Nix store, where any user can read it, whatever `.gitignore` says. Move them to `/persist/etc/<name>`, owned by root with mode 600, or set `EPHEMERAL_ALLOW_SECRET_FILES=1` to rebuild anyway.
- On niri and Umbriel, the screen locks after 10 idle minutes, as Plasma and GNOME already do, and the config now sets Noctalia's lock before sleep instead of relying on its default.
- The Noctalia login screen no longer copies the shell's look by itself. The copy runs a helper as root, which the config allowed without your password. You can still copy it from Noctalia's settings, and it asks for the password now. The config sets the login screen's dark theme either way.
- The weekly release only brings in a new nixpkgs. The other inputs, such as Home Manager and Stylix, come in a separate monthly pull request that's read before it's merged, because their code runs as root on every machine.
- The release workflow keeps its GitHub token out of the repository checkout.
- Files moved so each feature has its settings, persistence and permissions in one place. Machines get the same packages, settings and kept folders as before.
- The permissions on the login password, the SSH host key, the Control D id and the SMB passwords are set by `systemd-tmpfiles` at every boot, in place of shell loops during activation. The boot test checks that files written with the wrong permissions are root-only after the next boot.
- Shared modules that need another one import it themselves, through `config.ephemeral.aspects`, which applies each one only once. Your own modules can do the same; [Customizing](docs/customizing.md#your-own-modules) shows how.
- A wrong value in `settings.json`, such as `"desktop": "kde"`, is reported with the allowed values and the file it's in, in place of "attribute 'kde' missing".

### Fixed

- The security notes now list every sandboxed service, the `docker` and `libvirtd` groups, and that the Control D resolver id is visible on the network.
- On the small niri and Umbriel installs, the login screen's state is kept across reboots, as on the full ones.

## 3.11.1

### Changed

- `root-reset-check` and `snapper-persist-setup` run in the same sandbox as the config's other root services: a read-only system, no network and no capabilities. `systemd-analyze security` rates them 2.8 instead of 9.6.

## 3.11.0

### Added

- `ephemeral-update` checks for a newer release before it rebuilds. If there is one, it links the changelog, warns when it's a new major version, and asks whether to move to it; on yes it changes the tag in `flake.nix`, updates the lock and rebuilds. Offline, or when GitHub doesn't answer within 5 seconds, it rebuilds what's pinned.
- When `/persist/etc/nixos` still belongs to root, `ephemeral-update` offers to make it yours, the way `ephemeral-setup` does. Say no and it uses `sudo` for the changes it makes there.

### Fixed

- `ephemeral-update` said "no flake at /persist/etc/nixos" on machines from installer v3.0.0 to v3.7.3, which left the folder readable only by root. Rebuilding with this release makes it readable again. Until a machine has this release, run `sudo chmod 755 /persist/etc/nixos` first.
- Umbriel showed its keybind cheatsheet at every login. It shows at the first login only now, and `Mod+/` opens it again.
- `ephemeral-apps` and `ephemeral-setup` said to tick with space, but their lists tick with `x`, as the line under them says. They say `x` now, like the installer.

## 3.10.0

### Changed

- A release comes out every Monday with the newest nixpkgs, so security fixes reach machines within a week instead of up to a month. The first Monday of the month updates every input, as the monthly release did.
- Releases are immutable: once published, a release's tag can't be moved. `gh release verify v3.10.0 -R the-wittch/ephemeral-nixos-config` checks one.
- More kernel hardening: freed memory is wiped (`init_on_free=1`), kernel caches aren't shared between object types (`slab_nomerge`), page allocation is randomised, the legacy vsyscall page is gone and debugfs is off. Expect a few percent slower on memory-heavy work. Very old binaries that need vsyscall won't run, and tools that read debugfs, such as `powertop`, lose those readings. [When something breaks](docs/troubleshooting.md) shows how to turn either back on.

### Fixed

- niri and Umbriel had no file manager, and on the full profile `~/Documents`, `~/Music` and the other home folders were never made. Both desktops now come with Nautilus, plus the apps GNOME has for opening what's in it: Loupe for images, Papers for PDFs, Text Editor, File Roller for archives and Calculator. Nautilus shows thumbnails for videos and PDFs and has the trash, network shares and phones. Folders, images, PDFs, text and archives open in these by default, rather than in VS Code or a browser.
- The home folders are made on both profiles and every desktop. Before, the full profile relied on GNOME and Plasma making them.

## 3.9.0

### Added

- `ephemeral-apps` has security and penetration testing tools under Security: Metasploit, Nmap, ZAP, Burp Suite Community (unfree), sqlmap, ffuf, Gobuster, mitmproxy, Hashcat, John the Ripper, SecLists, Exploit-DB, NetExec, Ghidra, radare2 and binwalk, plus Lynis to audit the machine itself. SecLists' wordlists are in `/run/current-system/sw/share/wordlists/seclists`. Nmap warns that with OpenSnitch on, you're asked about each host a scan reaches.

## 3.8.3

### Fixed

- Formatting a disk that already has the layout no longer fails: the `root-blank` snapshot is only made when it's missing. The new disk test found this.
- `ssh-pubs-from-pass` only reads SSH key items. Before, it opened every item in the vault, logins and notes included, while looking for public keys.
- `settings-from-pass` says when `settings.json` doesn't have `"usePassSettings": true`, since the rebuild ignores the file without it. The Control D id no longer passes through a temporary file.

### Changed

- A VM test installs the real disk layout and checks the wipe, what survives it, and the `root-blank` recovery steps in Troubleshooting.
- The README and appearance docs show an animated screenshot.

## 3.8.2

### Changed

- The README and the appearance docs show a screenshot of a new Ghostty window.

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
