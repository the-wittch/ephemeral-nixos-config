{
  perSystem =
    { pkgs, ... }:
    let
      script =
        name: file: runtimeInputs:
        pkgs.writeShellApplication {
          inherit name runtimeInputs;
          text = builtins.readFile ../../scripts/lib.sh + builtins.readFile file;
        };
    in
    {
      packages = with pkgs; {
        pass-cli = callPackage ./_pass-cli.nix { };

        ephemeral-update = script "ephemeral-update" ../../scripts/ephemeral-update.sh [ ];

        flatpak-apps = script "flatpak-apps" ../../scripts/flatpak-tui.sh [
          gum
          flatpak
          gnugrep
          coreutils
        ];

        smb-setup = script "smb-setup" ../../scripts/smb-setup.sh [
          gum
          coreutils
          gnugrep
          gnused
          jq
        ];

        controld-setup = script "controld-setup" ../../scripts/controld-setup.sh [
          gum
          coreutils
          jq
        ];

        update-pass-cli = script "update-pass-cli" ../../scripts/update-pass-cli.sh [
          curl
          jq
          gawk
          coreutils
          git
          nix
        ];

        # pass-cli comes from the system, nixpkgs or the pinned build
        settings-from-pass = script "settings-from-pass" ../../scripts/settings-from-pass.sh [
          coreutils
          gnused
          jq
        ];

        ssh-pubs-from-pass = script "ssh-pubs-from-pass" ../../scripts/ssh-pubs-from-pass.sh [
          coreutils
          python3
          gnused
        ];

        luks-header-backup = script "luks-header-backup" ../../scripts/luks-header-backup.sh [
          coreutils
          cryptsetup
          gawk
          gnugrep
          util-linux
        ];

        check-no-secrets = writeShellApplication {
          name = "check-no-secrets";
          runtimeInputs = [
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
