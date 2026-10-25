{
  description = "Ephemeral NixOS with impermanence, LUKS, btrfs (Plasma / GNOME / niri)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    impermanence.url = "github:nix-community/impermanence";
    impermanence.inputs.nixpkgs.follows = "nixpkgs";
    impermanence.inputs.home-manager.follows = "home-manager";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      impermanence,
      disko,
      home-manager,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      mkNixos = import ./lib/mk-nixos.nix {
        inherit
          nixpkgs
          impermanence
          disko
          home-manager
          ;
      };

      settings = import ./lib/load-settings.nix { flakeRoot = ./.; };
      mkSystem = mkNixos { flakeRoot = ./.; };
    in
    {
      lib.mkNixos = mkNixos;

      formatter.${system} = pkgs.nixfmt-tree;

      packages.${system}.pass-cli = pkgs.callPackage ./packages/pass-cli.nix { };

      checks.${system}.config-eval = pkgs.runCommand "config-eval" { } ''
        echo ${lib.escapeShellArg mkSystem.config.networking.hostName} > "$out"
      '';

      nixosConfigurations = {
        nixos = mkSystem;
      }
      // lib.optionalAttrs (settings.hostname != "nixos") {
        ${settings.hostname} = mkSystem;
      };
    };
}
