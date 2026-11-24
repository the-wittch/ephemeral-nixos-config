{ inputs, ... }:
{
  flake.modules.nixos.full = {
    programs.nh = {
      enable = true;
      flake = "path:/persist/etc/nixos";
    };

    # `, <program>` runs anything in nixpkgs once without installing it, which suits a system
    # whose / is wiped anyway; the same database names the package for a command that isn't there
    imports = [ inputs.nix-index-database.nixosModules.nix-index ];
    programs.nix-index.enable = true;
    programs.nix-index-database.comma.enable = true;
  };
}
