{ config, inputs, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos.base =
    { config, ... }:
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "hm-backup";
        sharedModules = [ hm.base ];
        users.${config.ephemeral.settings.username} = { };
      };
    };

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
