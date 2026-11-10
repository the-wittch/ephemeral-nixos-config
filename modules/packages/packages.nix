{ config, lib, ... }:
let
  catalog = lib.mapAttrs (_: app: {
    inherit (app)
      label
      category
      description
      flatpak
      warn
      ;
    unfree = app.unfree != [ ];
  }) config.ephemeral.apps;
in
{
  perSystem =
    { pkgs, ... }:
    let
      catalogJson = pkgs.writeText "app-catalog.json" (builtins.toJSON catalog);
      tools = with pkgs; {
        ephemeral-report = {
          description = "system details to paste into a bug report";
          deps = [
            coreutils
            gnugrep
            gnused
            jq
            pciutils
          ];
        };
        ephemeral-setup = {
          description = "switch profile and turn the main options on or off, then rebuild";
          deps = [
            gum
            jq
            coreutils
            gnugrep
          ];
        };
        ephemeral-update = {
          description = "rebuild and switch to /persist/etc/nixos, offering newer releases first";
          deps = [
            nh
            curl
            jq
            gnused
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
          description = "pick extra apps, then rebuild";
          deps = [
            gum
            jq
            coreutils
          ];
          env.CATALOG = catalogJson;
        };
        luks-header-backup = {
          description = "copy the LUKS header to a USB stick";
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
            python3
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
            + builtins.readFile ../../scripts/lib.sh
            + builtins.readFile ../../scripts/${name}.sh;
          meta.description = tool.description;
        };

      width = lib.foldl' lib.max 0 (map lib.stringLength (lib.attrNames tools));
      help = pkgs.writeShellApplication {
        name = "ephemeral-help";
        meta.description = "list these commands";
        text = ''
          cat <<'EOF'
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              name: tool:
              "${name}${lib.strings.replicate (width - lib.stringLength name) " "}  ${tool.description}"
            ) tools
          )}

          Most of them ask what to do. --help on one shows its options.
          EOF
        '';
      };
      commands = lib.mapAttrs script tools // {
        ephemeral-help = help;
      };
    in
    {
      # what machines install; packages a machine flake defines itself stay out
      legacyPackages.ephemeralTools = commands;

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
      };
    };
}
