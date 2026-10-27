{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        # helix
      ];

      # ephemeral.unfreePackages = [ "vscode" ];

    };

  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        # hello
      ];
    };
}
