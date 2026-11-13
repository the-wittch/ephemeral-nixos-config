{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        firefox
        ghostty
        git
        curl
        wget
        ripgrep
        wl-clipboard
        htop
        dig
        mkpasswd
        unzip
        zip
        file
        usbutils
        pciutils
        wireguard-tools
      ];

      environment.sessionVariables.TERMINAL = "ghostty";
    };
}
