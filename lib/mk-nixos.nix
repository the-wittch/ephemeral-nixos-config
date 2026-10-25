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
  settings = import ./load-settings.nix { inherit lib flakeRoot; };
  baseModules = import ./base-modules.nix { inherit impermanence disko home-manager; };

  hardware = flakeRoot + "/hardware-configuration.nix";
  customize = flakeRoot + "/customize/default.nix";
in
nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = {
    inherit settings flakeRoot;
  };
  modules =
    baseModules { inherit settings flakeRoot; }
    ++ (
      if builtins.pathExists hardware then
        [ hardware ]
      else
        [
          {
            warnings = [
              "no hardware-configuration.nix next to the flake; building without initrd modules or microcode"
            ];
          }
        ]
    )
    ++ lib.optional (builtins.pathExists customize) (flakeRoot + "/customize")
    ++ modules;
}
