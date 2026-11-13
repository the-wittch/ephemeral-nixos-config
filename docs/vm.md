# Try it in a VM

`nix run path:.#vm` boots a machine's config in a throwaway QEMU window. `/` is in memory, so it's wiped at every boot as on a real machine, and `/persist` is on a scratch disk that's gone when the VM closes. Log in with your username and the password `ephemeral`. It needs KVM and about 4 GB of free memory.

On an installed machine, run it in `/persist/etc/nixos` to check a change, such as switching profiles, before you rebuild. To try this repo without installing anything:

```bash
git clone https://github.com/the-wittch/ephemeral-nixos-config
cd ephemeral-nixos-config
cp settings.example.json settings.json
cp hardware-configuration.example.nix hardware-configuration.nix
nix run path:.#vm
```

The user is `nixuser`; change `username`, `desktop` or anything else in `settings.json` first to try something else.
