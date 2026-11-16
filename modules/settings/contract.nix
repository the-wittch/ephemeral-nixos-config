# The settings contract for the installer, which reads it from the release it pins: what each
# setting may be (from _rules.nix), its default, and which settings are on/off switches. Built
# from the schema itself, so it can't say anything the rebuild wouldn't accept.
{ lib, ... }:
let
  options =
    (lib.evalModules {
      modules = [ ./_schema.nix ];
    }).options.ephemeral.settings;
in
{
  perSystem =
    { pkgs, ... }:
    {
      packages.settings-contract = pkgs.writeText "settings-contract.json" (
        builtins.toJSON {
          rules = import ./_rules.nix;
          defaults = lib.mapAttrs (_: option: option.default) (
            lib.filterAttrs (_: option: option ? default) options
          );
          switches = lib.attrNames (lib.filterAttrs (_: option: option.type.name == "bool") options);
        }
      );
    };
}
