# Wraps each of a class's modules with a key, so importing one from several places applies it
# once. aspects.nix does this to this repo's own; the upgrade tests to an older release's, which
# its own modules import by the same keys.
lib: class: modules:
lib.mapAttrs (name: module: {
  key = "ephemeral/${class}/${name}";
  imports = [ module ];
}) modules
