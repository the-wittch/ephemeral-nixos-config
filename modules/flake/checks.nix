{ config, lib, ... }:
let
  nixos = config.flake.nixosConfigurations.nixos;
  withExtras = nixos.extendModules { modules = [ config.flake.modules.nixos.extras ]; };
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
