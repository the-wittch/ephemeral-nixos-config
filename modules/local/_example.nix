# cp modules/local/_example.nix modules/local/apps.nix
{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        # helix
      ];
    };

  # flake.modules.homeManager.base =
  #   { pkgs, ... }:
  #   {
  #     home.packages = [ pkgs.hello ];
  #   };
}
