{
  flake.modules.nixos.full =
    { config, pkgs, ... }:
    let
      user = config.ephemeral.settings.username;
      group = config.users.users.${user}.group;
      dir = "/persist/etc/syncthing";
      password = "${dir}/gui-password";
    in
    {
      services.syncthing = {
        enable = true;
        inherit user group;
        dataDir = "/home/${user}/Syncthing";
        configDir = "/home/${user}/.config/syncthing";
        openDefaultPorts = false;
        overrideDevices = false;
        overrideFolders = false;
        # Without one, anything that can reach localhost could change what's shared, a Flatpak
        # app with network access included. It's kept out of the home folder, which more apps
        # can read.
        guiPasswordFile = password;
        settings.gui.user = user;
      };

      systemd.tmpfiles.rules = [
        "d ${dir} 0700 ${user} ${group} -"
        "z ${password} 0600 ${user} ${group} -"
      ];

      systemd.services.syncthing-gui-password = {
        description = "Make the password for Syncthing's web page";
        requiredBy = [ "syncthing-init.service" ];
        before = [ "syncthing-init.service" ];
        unitConfig.ConditionPathExists = "!${password}";
        path = [ pkgs.coreutils ];
        serviceConfig = config.ephemeral.sandbox // {
          Type = "oneshot";
          User = user;
          Group = group;
          UMask = "0077";
          ReadWritePaths = [ dir ];
        };
        script = ''
          printf '%s' "$(head -c 18 /dev/urandom | base64)" >${password}.new
          mv -f ${password}.new ${password}
        '';
      };
    };
}
