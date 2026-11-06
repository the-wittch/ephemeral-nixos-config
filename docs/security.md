# Security notes

- The disk is LUKS2 with argon2id. `/boot` is not encrypted, and Secure Boot is not set up.
- `/` starts empty on every boot, so anything that isn't explicitly kept on `/persist` disappears.
- Users are defined by the config, so `passwd` doesn't stick. To change your password:

  ```bash
  mkpasswd -m yescrypt | sudo tee /persist/passwords/$USER
  sudo chmod 600 /persist/passwords/$USER
  ```

- Root has no password. sudo is limited to the `wheel` group, and so is the Nix daemon.
- The firewall is on and SSH is off. On the full profile, OpenSnitch blocks outgoing connections you haven't allowed.
- Wi-Fi uses a different MAC address on each network, and LLMNR is off.
- Kernel hardening: no unprivileged BPF, restricted ptrace and kernel pointers, a few rarely used network protocols blocked, and no kexec. That last one also rules out hibernation.
- The IOMMU keeps each device to the memory it's given, which stops DMA attacks over Thunderbolt and USB4.
- Unfree packages must be listed by name in `ephemeral.unfreePackages`.
- The setup services this repo adds (Control D, Flathub, the default user picture) run sandboxed by systemd.
- smartd's desktop warnings go over the system bus, which lets any local process show you a notification. That's fine with the single user this setup has; turn it off with `services.smartd.notifications.systembus-notify.enable = false`.
- With `fingerprint` on, a finger also works for `sudo`. To keep sudo on the password only, set `security.pam.services.sudo.fprintAuth = false` in a private module.
