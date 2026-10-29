{ inputs, lib, ... }:
let
  template = inputs;

  # files that only make sense in this repo: its own host, checks and flake plumbing
  templateOnly = path: builtins.match ".*/(flake|hosts|local|tests)/.*" (toString path) != null;

  default = {
    imports = [
      template.flake-parts.flakeModules.modules
      (template.import-tree.filterNot templateOnly ../.)
    ];
  };

  mkFlake =
    # root is ./. from the machine's flake.nix; reading it off self would recurse
    { inputs, root }:
    let
      own = root + "/modules";
      # the machine's own inputs win, so it can override nixpkgs or add more
      merged = removeAttrs template [ "self" ] // inputs;
    in
    template.flake-parts.lib.mkFlake
      {
        # flake-parts reads inputs off self too
        inputs = merged // {
          self = inputs.self // {
            inputs = merged;
          };
        };
      }
      {
        imports = [ default ] ++ lib.optional (builtins.pathExists own) (template.import-tree own);
        systems = [ "x86_64-linux" ];
        ephemeral.hosts.nixos.root = root;
      };
in
{
  imports = [ inputs.flake-parts.flakeModules.flakeModules ];

  flake.flakeModules.default = default;
  flake.lib = { inherit mkFlake; };
}
