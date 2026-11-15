{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        ghostty
        git
        curl
        wget
        wl-clipboard
        mkpasswd
        unzip
        zip
        file
        usbutils
        pciutils
      ];

      environment.sessionVariables.TERMINAL = "ghostty";
    };
}
