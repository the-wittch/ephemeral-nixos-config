# Private flake

A starting point for your own config on top of [ephemeral-nixos-config](https://github.com/the-wittch/ephemeral-nixos-config). Keep it in a private repo.

- `flake.nix` pins the template and passes its inputs through.
- `modules/ephemeral.nix` pulls in every module from the template and defines the `nixos` machine.
- `modules/apps.nix` is where your own packages go. Add more files next to it as you like; each one is picked up automatically.

It follows the [dendritic pattern](https://github.com/mightyiam/dendritic): every `.nix` file under `modules/` is a flake-parts module for one feature, loaded automatically. Files don't import each other; they add to the template's shared modules, like `flake.modules.nixos.pc` or `flake.modules.homeManager.base`. The template's README lists them.

`settings.json` and `hardware-configuration.nix` come from the installed machine and stay out of git. The template's README has the full setup steps.

Rebuild:

```bash
sudo nixos-rebuild switch --flake path:/persist/etc/nixos#nixos
```

Move to a newer template:

```bash
nix flake update ephemeral --flake /persist/etc/nixos
sudo nixos-rebuild switch --flake path:/persist/etc/nixos#nixos
```

Build with `path:`. Without it, Nix only sees files tracked by git and misses `settings.json`.
