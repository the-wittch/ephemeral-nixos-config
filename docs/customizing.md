# Customizing

## How it's organized

The config follows the [dendritic pattern](https://github.com/mightyiam/dendritic):

- Every `.nix` file under `modules/` is a [flake-parts](https://flake.parts) module. [import-tree](https://github.com/vic/import-tree) loads all of them, so there's no import list to keep up to date. Paths containing `/_` are skipped.
- Each file is one feature: Syncthing, the boot splash, zsh, the theme. A single file can set NixOS and Home Manager options together.
- Files don't import each other. They add to a few shared modules, such as `flake.modules.nixos.pc` or `flake.modules.homeManager.dotfiles`, and a machine is built by combining those.
- Settings are a normal NixOS option (`config.ephemeral.settings`), not extra function arguments.

Adding a feature means adding a file, and removing one means deleting it. [mightyiam/infra](https://github.com/mightyiam/infra) and [Bad3r/nixos](https://github.com/Bad3r/nixos) are larger configs built the same way.

## Your own modules

Every `.nix` file in `/persist/etc/nixos/modules/` is loaded the same way. These are the shared modules you can add to:

| module | applies to |
|--------|------------|
| `flake.modules.nixos.base`, `flake.modules.nixos.pc` | every machine, both profiles |
| `flake.modules.nixos.full` | the full profile |
| `flake.modules.nixos.minimal` | the minimal profile |
| `flake.modules.nixos.gnome`, `.plasma`, `.niri` | the desktop chosen in `settings.json`, full profile |
| `flake.modules.nixos.minimal-gnome`, `.minimal-plasma`, `.minimal-niri` | the same, minimal profile |
| `flake.modules.homeManager.base`, `flake.modules.homeManager.dotfiles` | your user (full profile; minimal has no Home Manager) |
| `flake.modules.nixos.extras`, `flake.modules.homeManager.extras` | full profile with `"extras": true` |

A file in `modules/` can add to any of them:

```nix
{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.helix ];
      services.openssh.enable = true;
    };

  flake.modules.homeManager.dotfiles = {
    programs.git.settings.user = {
      name = "Your Name";
      email = "you@example.com";
    };
  };
}
```

Settings are `config.ephemeral.settings` in NixOS modules and `osConfig.ephemeral.settings` in Home Manager. To turn off something this repo sets, use `lib.mkForce`.

`lib.mkFlake` brings this repo's inputs along, so `flake.nix` only names `ephemeral`. Add your own inputs next to it and they're available to your modules as `inputs.<name>`; one named like this repo's (say `nixpkgs`) replaces it.

If you'd rather work in a clone of this repo, put your files in `modules/local/` instead. That folder is gitignored; `modules/local/_example.nix` shows the shape.
