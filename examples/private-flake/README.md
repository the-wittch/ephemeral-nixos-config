# Private host flake

Private repo. Template is an input. Packages and overrides go in `host.nix`. Machine identity stays in gitignored `settings.nix` or Pass.

## Setup

1. Copy this directory into a private git repo (or use it as `/persist/etc/nixos`).
2. Set `inputs.ephemeral.url` if needed.
3. Add machine files next to this flake:

   ```bash
   cp /path/to/ephemeral-nixos-config/settings.example.nix settings.nix
   # hardware-configuration.nix from the install
   ```

4. Edit `host.nix`.
5. Rebuild:

   ```bash
   sudo nixos-rebuild switch --flake path:.#nixos
   ```

## Updates

```bash
nix flake update ephemeral
sudo nixos-rebuild switch --flake path:.#nixos
```

`path:.` is required so Nix sees gitignored `settings.nix` and `hardware-configuration.nix`.
