{ config, lib, ... }:
let
  nixos = config.flake.nixosConfigurations.nixos;
in
{
  perSystem =
    { config, pkgs, ... }:
    {
      checks = {
        config-eval = pkgs.runCommand "config-eval" { } ''
          echo ${lib.escapeShellArg nixos.config.networking.hostName} > "$out"
        '';
        scripts = pkgs.linkFarmFromDrvs "scripts" (
          lib.attrValues (removeAttrs config.packages [ "pass-cli" ])
        );
      };
    };
}
