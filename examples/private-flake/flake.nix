{
  description = "Private host flake on top of ephemeral-nixos-config";

  inputs = {
    ephemeral.url = "github:the-wittch/ephemeral-nixos-config/v2.0.0";
    # the template's modules use these by name
    nixpkgs.follows = "ephemeral/nixpkgs";
    flake-parts.follows = "ephemeral/flake-parts";
    import-tree.follows = "ephemeral/import-tree";
    impermanence.follows = "ephemeral/impermanence";
    disko.follows = "ephemeral/disko";
    home-manager.follows = "ephemeral/home-manager";
    stylix.follows = "ephemeral/stylix";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
