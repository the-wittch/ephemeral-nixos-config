{
  flake.modules.nixos.full =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      user = config.ephemeral.settings.username;
      group = config.users.users.${user}.group;
      dir = "/persist/etc/syncthing";
      passwordFile = "${dir}/gui-password";
      gui = lib.splitString ":" config.services.syncthing.guiAddress;
      guiIp = lib.head gui;
      guiPort = lib.last gui;
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
        guiPasswordFile = passwordFile;
        settings.gui.user = user;
      };

      # syncthing-init sets the user and password through Syncthing's API with curl at every start,
      # and OpenSnitch holds back loopback connections too
      services.opensnitch.rules.syncthing-init = {
        name = "syncthing-init";
        enabled = true;
        action = "allow";
        duration = "always";
        operator = {
          type = "list";
          operand = "list";
          list = [
            {
              type = "simple";
              sensitive = false;
              operand = "process.path";
              data = "${pkgs.curl}/bin/curl";
            }
            {
              type = "simple";
              sensitive = false;
              operand = "dest.ip";
              data = guiIp;
            }
            {
              type = "simple";
              sensitive = false;
              operand = "dest.port";
              data = guiPort;
            }
          ];
        };
      };

      systemd.tmpfiles.rules = [
        "d ${dir} 0700 ${user} ${group} -"
        "z ${passwordFile} 0600 ${user} ${group} -"
      ];

      systemd.services.syncthing-gui-password = {
        description = "Make the password for Syncthing's web page";
        requiredBy = [ "syncthing-init.service" ];
        before = [ "syncthing-init.service" ];
        unitConfig.ConditionPathExists = "!${passwordFile}";
        path = [ pkgs.coreutils ];
        serviceConfig = config.ephemeral.sandbox // {
          Type = "oneshot";
          User = user;
          Group = group;
          UMask = "0077";
          ReadWritePaths = [ dir ];
        };
        script = ''
          printf '%s' "$(head -c 18 /dev/urandom | base64)" >${passwordFile}.new
          mv -f ${passwordFile}.new ${passwordFile}
        '';
      };
    };
}
