{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos.extras =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      chezmoi = config.ephemeral.settings.useChezmoi;
    in
    {
      # chezmoi owns the dotfiles there, so just the programs
      home-manager.sharedModules = lib.optional (!chezmoi) hm.extras;
      environment.systemPackages = lib.optionals chezmoi (
        with pkgs;
        [
          yazi
          btop
          fastfetch
          fzf
          atuin
          bat
          tealdeer
        ]
      );
    };
}
