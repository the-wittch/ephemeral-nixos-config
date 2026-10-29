{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos.extras = {
    home-manager.sharedModules = [ hm.extras ];
  };
}
