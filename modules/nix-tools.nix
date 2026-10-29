{ inputs, ... }:
{
  flake.modules.nixos.full = {
    programs.nh = {
      enable = true;
      flake = "path:/persist/etc/nixos";
    };
  };

  flake.modules.nixos.extras = {
    imports = [ inputs.nix-index-database.nixosModules.nix-index ];
    programs.nix-index.enable = true;
    programs.nix-index-database.comma.enable = true;
  };
}
