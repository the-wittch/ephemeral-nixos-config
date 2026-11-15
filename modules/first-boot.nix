{
  flake.modules.nixos.minimal =
    { pkgs, ... }:
    {
      # the full profile gets apps from ephemeral-apps
      environment.systemPackages = with pkgs; [
        firefox
        htop
        ripgrep
        dig
        wireguard-tools
        vim
        distrobox
        vlc
        p7zip
      ];

      # no home manager on first boot, so the system zshrc does completion
      programs.zsh.enableCompletion = true;
    };
}
