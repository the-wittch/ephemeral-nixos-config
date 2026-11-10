{ withSystem, ... }:
{
  flake.modules.nixos.minimal =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        (withSystem pkgs.stdenv.hostPlatform.system (
          { config, ... }: config.legacyPackages.ephemeralTools.ephemeral-setup
        ))
      ]
      ++ (with pkgs; [
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
      ]);

      environment.sessionVariables.TERMINAL = "ghostty";

      # no home manager on first boot, so the system zshrc does completion
      programs.zsh.enableCompletion = true;
    };
}
