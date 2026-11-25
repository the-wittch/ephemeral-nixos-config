# The controller as a keyboard for the disk passphrase at boot
{ buildGoModule, writeText }:
buildGoModule {
  pname = "handheld-input";
  version = "1";
  src = ../../scripts/handheld-input;
  vendorHash = null;
  # static, so the initrd needs nothing else for it
  env.CGO_ENABLED = 0;
  preCheck = ''
    unformatted=$(gofmt -l .)
    [[ -z $unformatted ]] || { echo "not gofmt-formatted: $unformatted"; exit 1; }
    go vet ./...
    # the table the installer shows, which the program has to type the same as
    export HANDHELD_BUTTONS=${writeText "handheld-buttons.json" (builtins.toJSON (import ./_buttons.nix))}
  '';
  meta.mainProgram = "handheld-input";
}
