# Private host flake

Private repo. Template is an input. Packages and overrides go in `host.nix`. Machine identity stays in gitignored `settings.json` or Pass. Unfree packages you add go in `ephemeral.unfreePackages`.

## Setup

1. Copy this directory into a private git repo (or use it as `/persist/etc/nixos`).
2. Set `inputs.ephemeral.url` if needed.
3. On an installed machine, copy the files the installer already wrote:

   ```bash
   cp /persist/etc/nixos/settings.json settings.json
   cp /persist/etc/nixos/hardware-configuration.nix hardware-configuration.nix
   ```

   `settings.example.json` is only for a machine that has no `/persist/etc/nixos` yet. An older install has `settings.nix`; the main README shows how to convert it.

4. Edit `host.nix`.
5. Rebuild the installed tree, which is the one that contains `settings.json`:

   ```bash
   sudo nixos-rebuild switch --flake path:/persist/etc/nixos#nixos
   ```

   `path:.#nixos` from another checkout is a different flake. If `settings.json` is missing there, the build stops.

## Updates

```bash
nix flake update ephemeral
sudo nixos-rebuild switch --flake path:.#nixos
```

`path:.` is required so Nix sees gitignored `settings.json` and `hardware-configuration.nix`.
