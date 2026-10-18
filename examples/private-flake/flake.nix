{
  description = "Private host flake on top of ephemeral-nixos-config";

  inputs = {
    ephemeral.url = "github:the-wittch/ephemeral-nixos-config";
    nixpkgs.follows = "ephemeral/nixpkgs";
  };

  outputs =
    { ephemeral, ... }:
    {
      nixosConfigurations.nixos = ephemeral.lib.mkNixos {
        flakeRoot = ./.;
        modules = [
          ./host.nix
        ];
      };
    };
}
