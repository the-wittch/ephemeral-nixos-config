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
      # the words that reach each command, for ephemeral
      commandsJson = pkgs.writeText "ephemeral-commands.json" (
        builtins.toJSON (
          lib.mapAttrsToList (name: tool: {
            inherit name;
            inherit (tool) words description;
            minimal = tool.minimal or false;
          }) tools
        )
      );
      # the one command, and the persistence explorer and menu; the commands it runs stay shell
      ephemeral = pkgs.buildGoModule {
        pname = "ephemeral";
        version = "1";
        src = ../../scripts/ephemeral;
        ldflags = [ "-X main.manifest=${commandsJson}" ];
        vendorHash = "sha256-rp0wYd9JLN3KL3W++Sjcebsbbo7Ru8OsTi70nbiO6AI=";
        # the tests run as part of the build; these fail it on unformatted code or vet's findings
        preCheck = ''
          unformatted=$(gofmt -l ./*.go)
          [[ -z $unformatted ]] || { echo "not gofmt-formatted: $unformatted"; exit 1; }
          go vet ./...
        '';
        meta.mainProgram = "ephemeral";
      };
      tools = with pkgs; {
        ephemeral-report = {
          description = "system details to paste into a bug report";
          words = [ "report" ];
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
          words = [ "doctor" ];
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
            ephemeral
            util-linux
          ];
        };
        ephemeral-backup = {
          description = "save the settings and secrets a reinstall needs, encrypted";
          words = [
            "backup"
            "save"
          ];
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
          words = [ "setup" ];
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
          words = [ "password" ];
          minimal = true;
          deps = [
            mkpasswd
            coreutils
            shadow
          ];
        };
        ephemeral-update = {
          description = "rebuild after a change and get new releases; also --check, --previous, --list and --as-installed";
          words = [ "update" ];
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
          words = [ "dns" ];
          deps = [
            gum
            coreutils
            jq
          ];
        };
        smb-setup = {
          description = "add or remove SMB shares";
          words = [ "shares" ];
          deps = [
            gum
            coreutils
            gnugrep
            gnused
            jq
          ];
        };
        backup-setup = {
          description = "set up scheduled backups: root's SSH key, the passphrase and where they go";
          words = [
            "backup"
            "setup"
          ];
          minimal = true;
          deps = [
            coreutils
            gnused
            jq
            openssh
          ];
        };
        ephemeral-apps = {
          description = "pick apps by category or search for them, then rebuild";
          words = [ "apps" ];
          deps = [
            gum
            jq
            coreutils
          ];
          env.CATALOG = catalogJson;
        };
        ephemeral-restore = {
          description = "bring back a file or folder from an hourly snapshot";
          words = [
            "snapshot"
            "restore"
          ];
          deps = [
            coreutils
            findutils
            gnused
            gum
          ];
        };
        luks-header-backup = {
          description = "copy the LUKS header to a USB stick";
          words = [
            "backup"
            "header"
          ];
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
          words = [
            "pass"
            "settings"
          ];
          deps = [
            coreutils
            gnused
            jq
          ];
        };
        ssh-pubs-from-pass = {
          description = "write SSH public keys from Proton Pass to ~/.ssh";
          words = [
            "pass"
            "ssh-keys"
          ];
          deps = [
            coreutils
            jq
            gnused
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
        inherit ephemeral;
        ephemeral-help = helpFor tools;
      };
      smallTools = lib.filterAttrs (_: tool: tool.minimal or false) tools;
    in
    {
      # what machines install; packages a machine flake defines itself stay out
      legacyPackages.ephemeralTools = commands;
      legacyPackages.ephemeralToolsSmall = lib.mapAttrs script smallTools // {
        inherit ephemeral;
        ephemeral-help = helpFor smallTools;
      };

      packages = commands // {
        # the installer reads it to offer the same apps
        app-catalog = catalogJson;

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
