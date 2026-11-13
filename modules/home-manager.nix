{ config, inputs, ... }:
let
  inherit (config.ephemeral.aspects) nixos homeManager;
in
{
  # import this, not home-manager's module, from anything that sets home-manager options
  flake.modules.nixos.home-manager =
    { config, ... }:
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "hm-backup";
        sharedModules = [
          homeManager.base
          homeManager.dotfiles
        ];
        users.${config.ephemeral.settings.username} = { };
      };
    };

  flake.modules.nixos.full.imports = [ nixos.home-manager ];

  flake.modules.homeManager.base =
    { osConfig, ... }:
    let
      user = osConfig.ephemeral.settings.username;
    in
    {
      home.username = user;
      home.homeDirectory = "/home/${user}";
      home.stateVersion = "25.05";
    };
}
