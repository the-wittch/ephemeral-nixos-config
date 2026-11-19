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
  flake.modules.nixos.base = {
    # ephemeral-update --list reads it from each generation
    environment.etc."ephemeral/release".text = "v${version}\n";
    # the boot menu's line for each entry then has the release in place of nixpkgs' version and
    # commit, which nixos-version still shows
    system.nixos.label = version;
  };
}
