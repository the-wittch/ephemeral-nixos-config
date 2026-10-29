{
  flake.modules.nixos.full =
    { config, ... }:
    let
      user = config.ephemeral.settings.username;
    in
    {
      services.syncthing = {
        enable = true;
        inherit user;
        group = config.users.users.${user}.group;
        dataDir = "/home/${user}/Syncthing";
        configDir = "/home/${user}/.config/syncthing";
        openDefaultPorts = false;
        overrideDevices = false;
        overrideFolders = false;
      };
    };
}
