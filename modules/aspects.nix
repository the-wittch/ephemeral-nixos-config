{ config, lib, ... }:
{
  # flake-parts gives flake.modules no key, so a module imported from two places is applied twice
  options.ephemeral.aspects = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.raw);
    readOnly = true;
    description = "flake.modules, each wrapped with a key so importing it again is a no-op.";
    default = lib.mapAttrs (
      class: modules:
      lib.mapAttrs (name: module: {
        key = "ephemeral/${class}/${name}";
        imports = [ module ];
      }) modules
    ) config.flake.modules;
  };
}
