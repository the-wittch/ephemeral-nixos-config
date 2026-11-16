# Security notes

Found a security problem? Report it privately, as described in [SECURITY.md](../SECURITY.md).

- The disk is LUKS2 with argon2id. `/boot` is not encrypted, so someone with the laptop in hand could swap the kernel or initrd for one that records the passphrase, unless [Secure Boot](#secure-boot) is on. TRIM passes through the encryption, which shows which blocks are in use but not what's in them.
- `/` starts empty on every boot, so anything that isn't explicitly kept on `/persist` disappears. That undoes a mistake, but it won't get rid of malware. Anything running as you can hide in your home folder, in shell startup files or autostart entries, and the home folder is kept. With root it can also change `/persist`, the empty snapshot `/` is reset from, and the boot partition. And nothing is wiped until the next reboot anyway.
- Users are defined by the config, so `passwd` doesn't stick. Change your password with `ephemeral-passwd`. It asks twice and only replaces `/persist/passwords/$USER` once it has a valid hash, since an empty or broken file there locks you out at the next boot.
- Everything in `/persist/etc/nixos` is copied into the Nix store at every rebuild, where any user and service can read it. `.gitignore` makes no difference, and the `.git` folder is copied too, so your machine flake's history ends up there. Keep secrets in `/persist/etc/<name>`, owned by root with mode 600, the way the Control D id and SMB passwords are kept. `ephemeral-update` and `ephemeral-setup` refuse to rebuild when the folder has a file named like a key or password, a private key or token inside a file, or a token in a git remote URL. They can't see a secret that was committed and deleted again: it's still in `.git`, so rewrite the history or start a fresh repo.
- Root has no password. sudo is limited to the `wheel` group, and so is the Nix daemon.
- The firewall is on and SSH is off. `services.openssh.enable = true` turns SSH on with port 22 still closed, so open it in `networking.firewall.allowedTCPPorts` too. Its host key is kept in `/persist/etc/ssh`. On the full system, OpenSnitch blocks outgoing connections you haven't allowed. At boot, new outgoing connections are refused until its daemon is filtering, and the same happens if the daemon crashes, until it's back a few seconds later. Stopping it with `systemctl stop` lets everything through.
- Wi-Fi uses a different MAC address on each network, and LLMNR is off.
- Kernel hardening: no unprivileged BPF, restricted ptrace and kernel pointers, and a few rarely used network protocols blocked. The kernel image is protected too, which rules out kexec and hibernation.
- The IOMMU limits each device to the memory it's given, which makes DMA attacks over Thunderbolt and USB4 much harder once the kernel is running. It doesn't cover the firmware and boot loader before that.
- Unfree packages must be listed by name in `ephemeral.unfreePackages`.
- On the full system, `nix-ld` lets prebuilt Linux programs run unpatched. Turn it off with `programs.nix-ld.enable = lib.mkForce false`.
- Once `/persist/etc/nixos` is yours, which `ephemeral-update` and `ephemeral-setup` offer, anything running as you can change what the next rebuild installs as root. Leave it owned by root if that matters more than editing it without sudo.
- The root services this repo adds run sandboxed by systemd, with a system call filter: Control D, Flathub, the default user picture, the check that `/` was reset, and the snapshot setup. The one that makes the credential key isn't, because it mounts that key into the running system. A check finds them by where they're defined, so a new one without a sandbox fails CI.
- The firewall, OpenSnitch and the sandbox do different jobs. The firewall refuses connections coming in, OpenSnitch asks about programs connecting out, and the sandbox limits what a service can touch if it's broken into. None of them replaces another.
- The Proton Pass session is in your home folder, so anything running as you can reach it; see [SSH agent](features.md#ssh-agent).
- Docker and virt-manager in `ephemeral-apps` add you to the `docker` or `libvirtd` group, and either one lets anything running as you become root without your password.
- On niri and Umbriel, Noctalia locks the screen after 10 idle minutes and before the laptop sleeps. Plasma and GNOME use their own lock settings.
- smartd's desktop warnings go over the system bus, which lets any local process show you a notification. That's fine with the single user this setup has; turn it off with `services.smartd.notifications.systembus-notify.enable = false`.
- With `fingerprint` on, a finger also works for `sudo`. To keep sudo on the password only, set `security.pam.services.sudo.fprintAuth = false` in a module of your own.

## Secure Boot

Off unless `"secureBoot": true` is in `settings.json`. With it on, the firmware only starts a Limine signed with keys made on this machine, and that Limine only starts the kernels and initrds its signed menu lists, checked by their checksums. It's what stops the swapped kernel or initrd in the first note above.

To turn it on:

1. Restart into the firmware setup and put Secure Boot in Setup Mode. Deleting only the platform key (PK) does that, and keeps the list of revoked bootloaders (dbx). Look for it under Secure Boot; on Dell it's in Expert Key Management. If the firmware only has "Delete all keys" or "Reset to Setup Mode", use that, but the dbx goes with it: after step 3, run `fwupdmgr refresh && fwupdmgr update` to put the current one back; `ephemeral-doctor` warns while it's missing. Secure Boot stays off in Setup Mode, so the machine starts as before.
2. Set `"secureBoot": true` and run `ephemeral-update`. It makes the keys, signs Limine, and puts the keys into the firmware. Microsoft's keys go back in with them, and the firmware's own where it lists them, so docks, graphics cards, firmware updates and Windows on another disk keep working.
3. Restart into the firmware setup again. Turn Secure Boot on, and set a firmware password: without one, anyone can turn Secure Boot off there.

On a new install of the full system, the installer does step 2: do step 1 before you boot the installer, tick Secure Boot on its options screen, and do step 3 at the first reboot. The small install skips that screen, so turn it on afterwards as above. It says at the end whether the keys went into the firmware.

`ephemeral-doctor` says which of these steps the machine is on. If you turn `secureBoot` on in the same rebuild as an update from a release before v4.8.0, the keys aren't put into the firmware yet, because that rebuild still keeps them where the next boot wipes them; it says so, and the next `ephemeral-update` finishes the job.

The keys are kept in `/persist/var/lib/sbctl`, encrypted with the rest of the disk, and `ephemeral-backup` saves them. After a reinstall, restore the backup before you turn `secureBoot` on. Otherwise new keys are made that the firmware doesn't trust, and the machine won't start until you put the firmware in Setup Mode again and rebuild.

To turn it off, turn Secure Boot off in the firmware first, then set `"secureBoot": false` and rebuild. The other way round, the next Limine isn't signed and the firmware refuses it. If that happens, turn Secure Boot off in the firmware, and it starts again.

Secure Boot doesn't help once something has root on the running system: it can read the keys and sign whatever it likes. And the disk is still unlocked by your passphrase, not by the TPM.
