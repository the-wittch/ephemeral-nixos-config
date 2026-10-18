# Extra modules in this directory are imported automatically.
{ lib, ... }:
let
  entries = builtins.readDir ./.;
  names = lib.attrNames (
    lib.filterAttrs (
      name: type:
      type == "regular"
      && lib.hasSuffix ".nix" name
      && name != "default.nix"
      && !lib.hasSuffix ".example.nix" name
    ) entries
  );
in
{
  imports = map (name: ./. + "/${name}") names;
}
