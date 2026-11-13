{ lib }:

base: default:
let
  name = baseNameOf (toString base);
  json = base + ".json";
in
if builtins.pathExists json then
  builtins.fromJSON (builtins.readFile json)
# stopping is safer than carrying on without it: a forgotten smb-shares.nix would drop the mounts
else if builtins.pathExists (base + ".nix") then
  throw ''
    ${name}.nix isn't read since v4.0.0. Convert it once, then rebuild:
      nix eval --json --file ${name}.nix | nix run nixpkgs#jq -- . > ${name}.json && rm ${name}.nix
  ''
else
  default
