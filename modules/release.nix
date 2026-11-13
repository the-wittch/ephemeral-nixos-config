{ lib, ... }:
let
  # the newest heading in CHANGELOG.md; a release isn't tagged without one
  version = lib.pipe ../CHANGELOG.md [
    builtins.readFile
    (lib.splitString "\n")
    (map (builtins.match "## ([0-9]+\\.[0-9]+\\.[0-9]+).*"))
    (lib.findFirst (m: m != null) (throw "CHANGELOG.md has no ## X.Y.Z heading"))
    lib.head
  ];
in
{
  # ephemeral-update --list reads it from each generation
  flake.modules.nixos.base.environment.etc."ephemeral/release".text = "v${version}\n";
}
