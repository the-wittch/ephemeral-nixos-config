# Security notes

Found a security problem? Report it privately, as described in [SECURITY.md](../SECURITY.md).

- The disk is LUKS2 with argon2id. `/boot` is not encrypted and Secure Boot is not set up, so someone with the laptop in hand could swap the kernel or initrd for one that records the passphrase. TRIM passes through the encryption, which shows which blocks are in use but not what's in them.
- `/` starts empty on every boot, so anything that isn't explicitly kept on `/persist` disappears. That undoes a mistake, but it won't get rid of malware. Anything running as you can hide in your home folder, in shell startup files or autostart entries, and the home folder is kept. With root it can also change `/persist`, the empty snapshot `/` is reset from, and the boot partition. And nothing is wiped until the next reboot anyway.
- Users are defined by the config, so `passwd` doesn't stick. Change your password with `ephemeral-passwd`. It asks twice and only replaces `/persist/passwords/$USER` once it has a valid hash, since an empty or broken file there locks you out at the next boot.
- Everything in `/persist/etc/nixos` is copied into the Nix store at every rebuild, where any user and service can read it. `.gitignore` makes no difference, and the `.git` folder is copied too, so a private config's history ends up there. Keep secrets in `/persist/etc/<name>`, owned by root with mode 600, the way the Control D id and SMB passwords are kept. `ephemeral-update` and `ephemeral-setup` refuse to rebuild when the folder has files that look like keys or passwords.
- Root has no password. sudo is limited to the `wheel` group, and so is the Nix daemon.
- The firewall is on and SSH is off. `services.openssh.enable = true` turns SSH on with port 22 still closed, so open it in `networking.firewall.allowedTCPPorts` too. Its host key is kept in `/persist/etc/ssh`. On the full profile, OpenSnitch blocks outgoing connections you haven't allowed.
- Wi-Fi uses a different MAC address on each network, and LLMNR is off.
- Kernel hardening: no unprivileged BPF, restricted ptrace and kernel pointers, and a few rarely used network protocols blocked. The kernel image is protected too, which rules out kexec and hibernation.
- The IOMMU limits each device to the memory it's given, which makes DMA attacks over Thunderbolt and USB4 much harder once the kernel is running. It doesn't cover the firmware and boot loader before that.
- Unfree packages must be listed by name in `ephemeral.unfreePackages`.
- On the full profile, `nix-ld` lets prebuilt Linux programs run unpatched. Turn it off with `programs.nix-ld.enable = lib.mkForce false`.
- Once `/persist/etc/nixos` is yours, which `ephemeral-update` and `ephemeral-setup` offer, anything running as you can change what the next rebuild installs as root. Leave it owned by root if that matters more than editing it without sudo.
- The root services this repo adds run sandboxed by systemd: Control D, Flathub, the default user picture, the check that `/` was reset, and the snapshot setup. The one that makes the credential key isn't, because it mounts that key into the running system.
- Docker and virt-manager in `ephemeral-apps` add you to the `docker` or `libvirtd` group, and either one lets anything running as you become root without your password.
- On niri and Umbriel, Noctalia locks the screen after 10 idle minutes and before the laptop sleeps. Plasma and GNOME use their own lock settings.
- smartd's desktop warnings go over the system bus, which lets any local process show you a notification. That's fine with the single user this setup has; turn it off with `services.smartd.notifications.systembus-notify.enable = false`.
- With `fingerprint` on, a finger also works for `sudo`. To keep sudo on the password only, set `security.pam.services.sudo.fprintAuth = false` in a private module.
