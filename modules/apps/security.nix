{
  ephemeral.apps = {
    keepassxc = {
      label = "KeePassXC";
      category = "Security";
      description = "offline password manager";
      package = "keepassxc";
    };
    bitwarden = {
      label = "Bitwarden";
      category = "Security";
      description = "password manager";
      package = "bitwarden-desktop";
    };
    wireshark = {
      label = "Wireshark";
      category = "Security";
      description = "network traffic analyser";
      warn = "you're added to the wireshark group; it can capture all traffic";
      nixos =
        { config, pkgs, ... }:
        {
          programs.wireshark = {
            enable = true;
            package = pkgs.wireshark;
          };
          users.users.${config.ephemeral.settings.username}.extraGroups = [ "wireshark" ];
        };
    };
  };
}
