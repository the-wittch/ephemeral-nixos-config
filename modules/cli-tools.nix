{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        git
        curl
        wget
        mkpasswd
        unzip
        zip
        file
        usbutils
        pciutils
      ];
    };

  # the terminal and the clipboard need a screen
  flake.modules.nixos.graphical =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        ghostty
        wl-clipboard
      ];
      environment.sessionVariables.TERMINAL = "ghostty";
    };
}
