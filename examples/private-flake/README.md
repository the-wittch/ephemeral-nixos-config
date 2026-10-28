# Private flake

A starting point for your own config on top of [ephemeral-nixos-config](https://github.com/the-wittch/ephemeral-nixos-config). Keep it in a private repo.

- `flake.nix` pins the template and passes its inputs through.
- `modules/ephemeral.nix` pulls in every module from the template and defines the `nixos` machine.
- `modules/apps.nix` is where your own packages go. Add more files next to it as you like; each one is picked up automatically.

It follows the [dendritic pattern](https://github.com/mightyiam/dendritic): every `.nix` file under `modules/` is a flake-parts module for one feature, loaded automatically. Files don't import each other; they add to the template's shared modules, like `flake.modules.nixos.pc` or `flake.modules.homeManager.base`. The template's README lists them.

`settings.json` and `hardware-configuration.nix` come from the installed machine and stay out of git. `apps.json`, written by `ephemeral-apps`, is the opposite: commit it, so your apps come along to the next machine. The template's README has the full setup steps.

Rebuild with `ephemeral-update`. Move to a newer template with:

```bash
nix flake update ephemeral --flake /persist/etc/nixos
ephemeral-update
```

Building by hand works too, as long as it's with `path:`: `sudo nixos-rebuild switch --flake path:/persist/etc/nixos#nixos`. Without `path:`, Nix only sees files tracked by git and misses `settings.json`.
