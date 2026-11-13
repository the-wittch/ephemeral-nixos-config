{
  flake.modules.nixos.base =
    { config, ... }:
    let
      settings = config.ephemeral.settings;
    in
    {
      users.mutableUsers = false;
      users.users.${settings.username} = {
        isNormalUser = true;
        extraGroups = [
          "wheel"
          "networkmanager"
          "video"
          "audio"
          "lp"
          "dialout"
        ];
        hashedPasswordFile = "/persist/passwords/${settings.username}";
      };
      users.users.root.hashedPassword = "!";

      systemd.tmpfiles.rules = [
        "d /persist/passwords 0700 root root -"
        "z /persist/passwords/* 0600 - - -"
      ];

      security.sudo = {
        execWheelOnly = true;
        extraConfig = ''
          Defaults lecture = never
        '';
      };
    };
}
