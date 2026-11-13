{ config, withSystem, ... }:
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
    let
      packages = withSystem pkgs.stdenv.hostPlatform.system ({ config, ... }: config.packages);
    in
    {
      options.ephemeral.passCli = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "The pass-cli build in use, picked by useFlakePassCli.";
      };

      config = {
        ephemeral.passCli =
          if config.ephemeral.settings.useFlakePassCli then packages.pass-cli else pkgs.proton-pass-cli;

        environment.systemPackages = [ config.ephemeral.passCli ];

        environment.sessionVariables = {
          PROTON_PASS_LINUX_KEYRING = "dbus";
          PASS_SSH_VAULT = config.ephemeral.settings.passSshVault;
        };
      };
    };
}
