{
  flake.modules.nixos.minimal =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        vim
        git
        curl
        wget
        firefox
        mkpasswd
        ghostty
        distrobox
        vlc
        wl-clipboard
        htop
        file
        unzip
        zip
        p7zip
        usbutils
        pciutils
        dig
        ripgrep
        wireguard-tools
        xdg-user-dirs
      ];

      environment.sessionVariables.TERMINAL = "ghostty";

      # no home manager on first boot, so the system zshrc does completion
      programs.zsh.enableCompletion = true;

      systemd.user.services.xdg-user-dirs = {
        description = "Create default XDG user directories";
        wantedBy = [ "default.target" ];
        unitConfig.ConditionUser = "!@system";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.xdg-user-dirs}/bin/xdg-user-dirs-update";
        };
      };
    };
}
