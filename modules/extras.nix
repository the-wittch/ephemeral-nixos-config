{ config, ... }:
let
  inherit (config.ephemeral.aspects) nixos;
  hm = config.ephemeral.aspects.homeManager;
in
{
  flake.modules.nixos.extras =
    { pkgs, ... }:
    {
      imports = [ nixos.home-manager ];
      home-manager.sharedModules = [ hm.extras ];

      ephemeral.unfreePackages = [
        "steam"
        "steam-unwrapped"
        "vscode"
        "unrar"
      ];

      programs.steam = {
        enable = true;
        remotePlay.openFirewall = false;
        dedicatedServer.openFirewall = false;
      };

      environment.systemPackages = with pkgs; [
        vscode
        brave-origin
        vlc
        distrobox
        syncthingtray-minimal
        p7zip
        unrar
        git-crypt
        age
      ];
    };
}
