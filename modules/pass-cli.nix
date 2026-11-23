{ config, ... }:
let
  inherit (config.ephemeral.aspects) nixos;
in
{
  flake.modules.nixos.full.imports = [ nixos.pass-cli ];

  flake.modules.nixos.pass-cli =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.ephemeral.passCli = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        default = pkgs.proton-pass-cli;
        description = "The pass-cli package, for the SSH agent and its OpenSnitch rule.";
      };

      config = {
        environment.systemPackages = [ config.ephemeral.passCli ];

        environment.sessionVariables = {
          PROTON_PASS_LINUX_KEYRING = "dbus";
          PASS_SSH_VAULT = config.ephemeral.settings.passSshVault;
        };
      };
    };
}
