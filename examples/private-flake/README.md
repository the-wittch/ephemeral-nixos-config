# Private host flake

Private repo. Template is an input. Packages and overrides go in `host.nix`. Machine identity stays in gitignored `settings.nix` or Pass.

## Setup

1. Copy this directory into a private git repo (or use it as `/persist/etc/nixos`).
2. Set `inputs.ephemeral.url` if needed.
3. On an installed machine, copy the files the installer already wrote:

   ```bash
   cp /persist/etc/nixos/settings.nix settings.nix
   cp /persist/etc/nixos/hardware-configuration.nix hardware-configuration.nix
   ```

   `settings.example.nix` is only for a machine that has no `/persist/etc/nixos` yet.

4. Edit `host.nix`.
5. Rebuild the installed tree, which is the one that contains `settings.nix`:

   ```bash
   sudo nixos-rebuild switch --flake path:/persist/etc/nixos#nixos
   ```

   `path:.#nixos` from another checkout is a different flake. If `settings.nix` is missing there, the build stops.

## Updates

```bash
nix flake update ephemeral
sudo nixos-rebuild switch --flake path:.#nixos
```

`path:.` is required so Nix sees gitignored `settings.nix` and `hardware-configuration.nix`.
