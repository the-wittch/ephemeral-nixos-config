# Every command this repo builds. apps.nix and greeter.nix install them from
# here, and the flake exports them so CI builds each one, which also runs
# shellcheck on the exact text that gets installed.
{
  pkgs,
  pass-cli ? pkgs.proton-pass-cli,
}:

let
  # scripts/lib.sh goes first so every command gets the shared helpers
  mkScript =
    name: file: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile ../scripts/lib.sh + builtins.readFile file;
    };
in
with pkgs;
{
  ephemeral-update = mkScript "ephemeral-update" ../scripts/ephemeral-update.sh [ ];

  flatpak-apps = mkScript "flatpak-apps" ../scripts/flatpak-tui.sh [
    gum
    flatpak
    gnugrep
    coreutils
  ];

  smb-setup = mkScript "smb-setup" ../scripts/smb-setup.sh [
    gum
    coreutils
    gnugrep
    gnused
    jq
  ];

  controld-setup = mkScript "controld-setup" ../scripts/controld-setup.sh [
    gum
    coreutils
    jq
  ];

  update-pass-cli = mkScript "update-pass-cli" ../scripts/update-pass-cli.sh [
    curl
    jq
    gawk
    coreutils
    git
    nix
  ];

  settings-from-pass = mkScript "settings-from-pass" ../scripts/settings-from-pass.sh [
    pass-cli
    coreutils
    gnused
    jq
  ];

  ssh-pubs-from-pass = mkScript "ssh-pubs-from-pass" ../scripts/ssh-pubs-from-pass.sh [
    pass-cli
    coreutils
    python3
    gnused
  ];

  luks-header-backup = mkScript "luks-header-backup" ../scripts/luks-header-backup.sh [
    coreutils
    cryptsetup
    gawk
    gnugrep
    util-linux
  ];

  greeter-sync = writeShellApplication {
    name = "greeter-sync";
    runtimeInputs = [
      coreutils
      dconf
      util-linux
    ];
    text = builtins.readFile ../scripts/greeter-sync.sh;
  };

  check-no-secrets = writeShellApplication {
    name = "check-no-secrets";
    runtimeInputs = [
      coreutils
      gawk
      git
      gnugrep
      gnused
    ];
    text = builtins.readFile ../scripts/check-no-secrets.sh;
  };
}
