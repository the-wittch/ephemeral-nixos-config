{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        # helix
      ];

      # ephemeral.unfreePackages = [ "discord" ];
    };

  flake.modules.homeManager.dotfiles = {
    # programs.git.settings.user = {
    #   name = "Your Name";
    #   email = "you@example.com";
    # };
  };
}
