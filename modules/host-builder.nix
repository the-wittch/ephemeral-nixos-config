{
  config,
  inputs,
  lib,
  ...
}:

let
  readData = import ./settings/_read-data.nix { inherit lib; };
  loadSettings = flakeRoot: import ./settings/_load.nix { inherit lib flakeRoot; };

  build =
    name: host:
    let
      settings = loadSettings host.root;
      appsFile = host.root + "/apps.json";
      picked = if builtins.pathExists appsFile then lib.importJSON appsFile else [ ];
      known =
        lib.throwIfNot (builtins.isList picked && lib.all builtins.isString picked)
          "apps.json has to be a list of app names"
          (builtins.filter (id: config.ephemeral.apps ? ${id}) picked);
      hardware = host.root + "/hardware-configuration.nix";
      full = settings.profile == "full";
      nixos = config.flake.modules.nixos;
      # settings that only do something on the full profile, by the module they add
      fullOnly = {
        controld = "useControlD";
        extras = "extras";
        passSshAgent = "usePassSshAgent";
      };
      ignored = lib.optionals (!full) (
        lib.filter (key: settings.${key}) (lib.attrValues fullOnly ++ [ "useFlakePassCli" ])
        ++ lib.optional (known != [ ]) "the apps in apps.json"
      );
      system = inputs.nixpkgs.lib.nixosSystem {
        modules = [
          nixos.pc
        ]
        ++ (
          if full then
            [
              nixos.full
              nixos.${settings.desktop}
              nixos.dotfiles
            ]
          else
            [
              nixos.minimal
              nixos."minimal-${settings.desktop}"
            ]
        )
        ++ [
          {
            warnings = lib.optional (ignored != [ ]) ''
              ${lib.concatStringsSep ", " ignored}: only on the full profile, so nothing happens on this machine (profile is minimal).
              Set "profile": "full" in settings.json to use them.
            '';
          }
          {
            ephemeral.settings = settings;
            ephemeral.smbShares = readData (host.root + "/smb-shares") [ ];
            ephemeral.pickedApps = picked;
          }
          (
            if builtins.pathExists hardware then
              hardware
            else
              {
                warnings = [
                  "no hardware-configuration.nix in ${toString host.root}; building without initrd modules or microcode"
                ];
              }
          )
        ]
        ++ map (name: nixos.${name}) (
          lib.attrNames (
            lib.filterAttrs (_: on: on) (
              {
                nvidia = settings.nvidia != "none";
                laptop = settings.laptop;
                fingerprint = settings.fingerprint;
                tailscale = settings.useTailscale;
                opensnitch = full && settings.useOpenSnitch;
              }
              // lib.mapAttrs (_: key: full && settings.${key}) fullOnly
            )
          )
        )
        ++ lib.optionals full (map (id: config.ephemeral.apps.${id}.nixos) known)
        ++ host.modules;
      };
    in
    {
      ${name} = system;
    }
    // lib.optionalAttrs (settings.hostname != name) { ${settings.hostname} = system; };
in
{
  options.ephemeral.hosts = lib.mkOption {
    description = "Machines. Each reads settings.json, smb-shares.json and hardware-configuration.nix from its root.";
    default = { };
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          root = lib.mkOption {
            type = lib.types.path;
            description = "Directory holding the machine files, usually the flake root.";
          };
          modules = lib.mkOption {
            type = lib.types.listOf lib.types.deferredModule;
            default = [ ];
            description = "Extra NixOS modules for this host only.";
          };
        };
      }
    );
  };

  config.flake.nixosConfigurations = lib.concatMapAttrs build config.ephemeral.hosts;
}
