# Adds the picked launchers to Steam as non-Steam games, before Steam starts
{ buildGoModule }:
buildGoModule {
  pname = "steam-shortcuts";
  version = "1";
  src = ../../scripts/steam-shortcuts;
  vendorHash = null;
  env.CGO_ENABLED = 0;
  preCheck = ''
    unformatted=$(gofmt -l .)
    [[ -z $unformatted ]] || { echo "not gofmt-formatted: $unformatted"; exit 1; }
    go vet ./...
  '';
  meta.mainProgram = "steam-shortcuts";
}
