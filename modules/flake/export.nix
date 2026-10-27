{ inputs, ... }:

let
  # not for private flakes
  templateOnly = path: builtins.match ".*/(flake|hosts|local|tests)/.*" (toString path) != null;
in
{
  imports = [ inputs.flake-parts.flakeModules.flakeModules ];

  flake.flakeModules.default = {
    imports = [
      inputs.flake-parts.flakeModules.modules
      (inputs.import-tree.filterNot templateOnly ../.)
    ];
  };
}
