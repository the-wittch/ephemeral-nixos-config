# Servers

A server is a machine you reach over SSH instead of sitting at it. It can keep a desktop, for a machine that's sometimes used at the keyboard, or have none at all. The same config can build a laptop and a server: only `settings.json` differs between them.

## Turning it on

The installer asks on its Server screen, from version 3.10.0. Paste your public keys there, or type `github:yourname` to fetch the ones on your GitHub account. Picking "None" as the desktop makes it a server. At the end, the install shows the fingerprint of the key for unlocking over SSH (below), to check the first time you connect.

On a machine that's already installed, add to `settings.json`:

```json
{
  "server": true,
  "sshKeys": [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyReplaceWithYours you@laptop"
  ]
}
```

Add `"desktop": "none"` for no desktop at all, then run `ephemeral-update`. Each key is a public key, one line from a `.pub` file or `ssh-pubs-from-pass`. A server needs at least one, and `"desktop": "none"` needs `server`, since nobody could log in to either otherwise; both refuse to build without them.

## What changes

- SSH is on, on every network the machine is on, for the keys in `sshKeys`. Passwords, keyboard-interactive login and root logins are refused, so a key is the only way in. Port 22 is the one port the firewall opens.
- Sleep, suspend and hibernation are off, so the machine stays reachable.
- Its SSH host key is kept in `/persist/etc/ssh`, so it stays the same across reboots.
- Updates stay manual: `ssh you@server ephemeral-update`, as at the keyboard.

With `"desktop": "none"`:

- There's no desktop, display manager, sound, Flatpak or boot splash. The disk passphrase is asked on the console, or over SSH as below.
- Of the apps `ephemeral-apps` ticks by default, only the terminal ones are added: htop, ripgrep, dig and the WireGuard tools. `ephemeral-apps` and the installer offer only the terminal apps.
- OpenSnitch is off, because nobody could answer its questions without a screen. A server with a desktop keeps it.
- Both profiles work. The small install is a console and SSH; `ephemeral-setup` adds the rest later, as on a desktop.

## Unlocking after a reboot

The disk is encrypted, so after a reboot a server waits for its passphrase before anything else starts. You can type it at the machine, or from another one:

```bash
ssh -p 2222 root@<server>
```

That asks for the passphrase straight away, and the boot carries on once it's right. With [TPM unlock](security.md#tpm-unlock), it asks for the PIN first. It's the same `sshKeys`, but a small SSH server that runs only until the disk is open, on port 2222 with a host key of its own, so your SSH client doesn't mistake it for the running system on port 22.

- It needs Ethernet, and an address from DHCP. Wi-Fi isn't up that early.
- The usual network cards' drivers are included. If the server never answers on port 2222, `lspci -k` shows which driver the card uses (the "Kernel driver in use" line); add it in a module of your own with `boot.initrd.availableKernelModules = [ "<driver>" ];`.
- Its host key is made by `ephemeral-update` the first time `server` is on, in `/persist/etc/ssh/initrd/`, and a copy goes into the boot partition with each rebuild. Compare it with what your client shows the first time: `sudo ssh-keygen -lf /persist/etc/ssh/initrd/ssh_host_ed25519_key.pub`.

The boot partition isn't encrypted, so that copy needs protecting: someone who copied it could pretend to be the server at boot and catch the passphrase. With [Secure Boot](security.md#secure-boot) on and a TPM 2.0, `ephemeral-update` seals the copy to the TPM and to Secure Boot's state, so it only opens on this machine, booting what you signed. Run `ephemeral-update` once after turning Secure Boot on in the firmware, so it's sealed. Without Secure Boot, the copy is the key itself, and anyone with the disk in hand can read it.

A firmware update can change Secure Boot's state, as it can for [TPM unlock](security.md#tpm-unlock). Remote unlock then doesn't answer at the next boot: unlock at the keyboard once, and the next `ephemeral-update` seals the copy again. With TPM unlock on as well, what you type over SSH is the PIN, which is no use without this machine's TPM.

If your client ever warns that the key on port 2222 changed, don't type the passphrase.

## Keeping it safe

Anyone with one of the private keys can log in, from anywhere that can reach port 22, and on port 2222 while it waits at boot. Keep the keys in Proton Pass or on a hardware key, which `sk-ssh-ed25519@openssh.com` keys are, and remove a lost device's key from `sshKeys`, then run `ephemeral-update`.

To reach it only over Tailscale, turn on `useTailscale` and close port 22 everywhere else in a module of your own:

```nix
{
  flake.modules.nixos.pc =
    { lib, ... }:
    {
      services.openssh.openFirewall = lib.mkForce false;
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
    };
}
```

A machine that isn't a server can still be reached over SSH: [Reaching the machine from your other devices](features.md#reaching-the-machine-from-your-other-devices).
