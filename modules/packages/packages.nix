{
  config,
  lib,
  withSystem,
  ...
}:
let
  catalog = lib.mapAttrs (_: app: {
    inherit (app)
      label
      category
      description
      flatpak
      warn
      default
      desktops
      ;
    unfree = app.unfree != [ ];
  }) config.ephemeral.apps;

  prelude = import ./_prelude.nix { inherit lib; };

  toolsFor =
    pkgs:
    withSystem pkgs.stdenv.hostPlatform.system ({ config, ... }: config.legacyPackages.ephemeralTools);
in
{
  flake.modules.nixos.full =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = lib.attrValues (toolsFor pkgs) ++ [ pkgs.gum ];
    };

  flake.modules.nixos.minimal =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = lib.attrValues (
        withSystem pkgs.stdenv.hostPlatform.system (
          { config, ... }: config.legacyPackages.ephemeralToolsSmall
        )
      );
    };

  perSystem =
    { pkgs, ... }:
    let
      catalogJson = pkgs.writeText "app-catalog.json" (builtins.toJSON catalog);
      tools = with pkgs; {
        ephemeral-report = {
          description = "system details to paste into a bug report";
          minimal = true;
          deps = [
            coreutils
            gawk
            gnugrep
            gnused
            jq
            pciutils
          ];
        };
        ephemeral-doctor = {
          description = "check the machine and say how to fix what isn't right";
          minimal = true;
          deps = [
            btrfs-progs
            coreutils
            cryptsetup
            curl
            findutils
            gawk
            gnugrep
            gnused
            jq
            util-linux
          ];
        };
        ephemeral-backup = {
          description = "save the settings and secrets a reinstall needs, encrypted";
          minimal = true;
          deps = [
            age
            coreutils
            cryptsetup
            gawk
            gnugrep
            gnutar
            util-linux
          ];
        };
        ephemeral-setup = {
          description = "switch between the full system and the small install, and turn the main options on or off";
          minimal = true;
          deps = [
            gum
            jq
            coreutils
            cryptsetup
            gawk
            gnugrep
            findutils
            gnused
          ];
        };
        ephemeral-passwd = {
          description = "change your login password";
          minimal = true;
          deps = [
            mkpasswd
            coreutils
            shadow
          ];
        };
        ephemeral-update = {
          description = "rebuild after a change and get new releases; also --check, --previous, --list and --as-installed";
          minimal = true;
          deps = [
            nh
            openssh
            curl
            gawk
            gnugrep
            jq
            gnused
            findutils
            coreutils
          ];
        };
        controld-setup = {
          description = "set or turn off the Control D resolver id";
          deps = [
            gum
            coreutils
            jq
          ];
        };
        smb-setup = {
          description = "add or remove SMB shares";
          deps = [
            gum
            coreutils
            gnugrep
            gnused
            jq
          ];
        };
        ephemeral-apps = {
          description = "pick apps by category, then rebuild";
          deps = [
            gum
            jq
            coreutils
          ];
          env.CATALOG = catalogJson;
        };
        ephemeral-restore = {
          description = "bring back a file or folder from an hourly snapshot";
          deps = [
            coreutils
            findutils
            gnused
            gum
          ];
        };
        luks-header-backup = {
          description = "copy the LUKS header to a USB stick";
          minimal = true;
          deps = [
            coreutils
            cryptsetup
            gawk
            gnugrep
            util-linux
          ];
        };
        settings-from-pass = {
          description = "pull settings from Proton Pass";
          deps = [
            coreutils
            gnused
            jq
          ];
        };
        ssh-pubs-from-pass = {
          description = "write SSH public keys from Proton Pass to ~/.ssh";
          deps = [
            coreutils
            jq
            gnused
          ];
        };
        update-pass-cli = {
          description = "bump or check the pinned pass-cli (run in a config checkout)";
          deps = [
            curl
            jq
            gawk
            coreutils
            git
            nix
          ];
        };
      };

      script =
        name: tool:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = tool.deps;
          text =
            lib.concatStrings (lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg v}\n") (tool.env or { }))
            + prelude
            + builtins.readFile ../../scripts/${name}.sh;
          meta.description = tool.description;
        };

      # each profile lists only the commands it has
      helpFor =
        set:
        let
          width = lib.foldl' lib.max 0 (map lib.stringLength (lib.attrNames set));
        in
        pkgs.writeShellApplication {
          name = "ephemeral-help";
          meta.description = "list these commands";
          text = ''
            cat <<'EOF'
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (
                name: tool:
                "${name}${lib.strings.replicate (width - lib.stringLength name) " "}  ${tool.description}"
              ) set
            )}

            Most of them ask what to do. --help on one shows its options.
            EOF
          '';
        };
      commands = lib.mapAttrs script tools // {
        ephemeral-help = helpFor tools;
      };
      smallTools = lib.filterAttrs (_: tool: tool.minimal or false) tools;
    in
    {
      # what machines install; packages a machine flake defines itself stay out
      legacyPackages.ephemeralTools = commands;
      legacyPackages.ephemeralToolsSmall = lib.mapAttrs script smallTools // {
        ephemeral-help = helpFor smallTools;
      };

      packages = commands // {
        # the installer reads it to offer the same apps
        app-catalog = catalogJson;
        pass-cli = pkgs.callPackage ./_pass-cli.nix { };

        check-no-secrets = pkgs.writeShellApplication {
          name = "check-no-secrets";
          runtimeInputs = with pkgs; [
            coreutils
            gawk
            git
            gnugrep
            gnused
          ];
          text = builtins.readFile ../../scripts/check-no-secrets.sh;
        };

        # the installer runs it too, from the config release it pins
        check-links = pkgs.writers.writePython3Bin "check-links" {
          flakeIgnore = [ "E501" ];
        } (builtins.readFile ../../scripts/check-links.py);
      };
    };
}
