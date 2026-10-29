{ config, lib, ... }:
let
  nixos = config.flake.nixosConfigurations.nixos;
  withExtras = nixos.extendModules { modules = [ config.flake.modules.nixos.extras ]; };
  machine =
    (config.flake.lib.mkFlake {
      inputs.self = {
        outPath = ../../tests/machine;
        inputs = { };
      };
      root = ../../tests/machine;
    }).nixosConfigurations.nixos;
  withPassSshAgent = nixos.extendModules { modules = [ config.flake.modules.nixos.passSshAgent ]; };
  withAllApps = nixos.extendModules {
    modules = [
      { ephemeral.pickedApps = lib.attrNames config.ephemeral.apps; }
    ]
    ++ map (app: app.nixos) (lib.attrValues config.ephemeral.apps);
  };
  options = lib.attrNames nixos.options.ephemeral.settings;
  defaults = import ../settings/_defaults.nix;
  example = lib.importJSON ../../settings.example.json;
  differ = lib.filter (name: example.${name} or null != defaults.${name}) (lib.attrNames defaults);
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
        extras-eval = pkgs.writeText "extras-eval" (
          builtins.unsafeDiscardStringContext withExtras.config.system.build.toplevel.drvPath
        );
        pass-ssh-agent-eval = pkgs.writeText "pass-ssh-agent-eval" (
          builtins.unsafeDiscardStringContext withPassSshAgent.config.system.build.toplevel.drvPath
        );
        mkflake-eval =
          assert lib.assertMsg (
            machine.config.environment.etc ? ephemeral-fixture
          ) "lib.mkFlake didn't load the machine's own modules/";
          pkgs.writeText "mkflake-eval" (
            builtins.unsafeDiscardStringContext (
              machine.config.system.build.toplevel.drvPath + "\n" + machine.config.system.build.vm.drvPath
            )
          );
        apps-eval = pkgs.writeText "apps-eval" (
          builtins.unsafeDiscardStringContext withAllApps.config.system.build.toplevel.drvPath
        );
        settings-example =
          assert lib.assertMsg (options == lib.attrNames example && differ == [ ]) ''
            settings.example.json has to list every setting with its default.
              missing: ${toString (lib.subtractLists (lib.attrNames example) options)}
              unknown: ${toString (lib.subtractLists options (lib.attrNames example))}
              different from settings/_defaults.nix: ${toString differ}
          '';
          pkgs.runCommand "settings-example" { } "touch $out";
      };
    };
}
