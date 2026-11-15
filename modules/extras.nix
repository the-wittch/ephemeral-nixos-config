{ config, ... }:
let
  inherit (config.ephemeral.aspects) nixos;
  hm = config.ephemeral.aspects.homeManager;
in
{
  flake.modules.nixos.extras = {
    imports = [ nixos.home-manager ];
    home-manager.sharedModules = [ hm.extras ];
  };
}
