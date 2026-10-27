{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos.dotfiles = {
    home-manager.sharedModules = [ hm.dotfiles ];
  };
}
