{
  flake.modules.nixos.minimal =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        vim
        distrobox
        vlc
        p7zip
      ];

      # no home manager on first boot, so the system zshrc does completion
      programs.zsh.enableCompletion = true;
    };
}
