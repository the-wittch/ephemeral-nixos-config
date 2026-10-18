{
  nixpkgs,
  impermanence,
  disko,
  home-manager,
}:
{
  flakeRoot,
  system ? "x86_64-linux",
  modules ? [ ],
}:
let
  inherit (nixpkgs) lib;
  settings = import ./load-settings.nix { inherit flakeRoot; };

  hardware = flakeRoot + "/hardware-configuration.nix";
  customize = flakeRoot + "/customize/default.nix";
in
nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = {
    inherit settings flakeRoot;
  };
  modules = [
    disko.nixosModules.disko
    ../disko.nix
    ../configuration.nix
  ]
  ++ lib.optional (builtins.pathExists hardware) hardware
  ++ [
    impermanence.nixosModules.impermanence
    home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "hm-backup";
      home-manager.extraSpecialArgs = {
        inherit settings flakeRoot;
      };
      home-manager.users.${settings.username} = import ../home.nix;
    }
  ]
  ++ lib.optional (builtins.pathExists customize) (flakeRoot + "/customize")
  ++ modules;
}
