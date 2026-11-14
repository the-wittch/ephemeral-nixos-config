{ lib, ... }:
let
  check =
    settings:
    (builtins.tryEval (
      builtins.deepSeq
        (lib.evalModules {
          modules = [
            ../modules/settings/_schema.nix
            { ephemeral.settings = settings; }
          ];
        }).config.ephemeral.settings
        true
    )).success;
  load =
    root:
    (builtins.tryEval (
      builtins.deepSeq (import ../modules/settings/_load.nix {
        inherit lib;
        flakeRoot = root;
      }) true
    )).success;

  ok = {
    username = "alice";
  };
  # several of these end up in shell scripts or paths, so each has to stay refused
  refused = {
    "an unknown desktop" = ok // {
      desktop = "kde";
    };
    "a username with capitals" = ok // {
      username = "Alice";
    };
    "no username" = { };
    "a disk path with .." = ok // {
      diskDevice = "/dev/../etc/passwd";
    };
    "a disk outside /dev" = ok // {
      diskDevice = "/tmp/disk";
    };
    "a swap size that isn't a size" = ok // {
      swapSize = "16 G";
    };
    "a vault name with $" = ok // {
      passSshVault = "x$(reboot)";
    };
    "a vault name with a quote" = ok // {
      passSettingsVault = "a\"b";
    };
    "a locale that isn't UTF-8" = ok // {
      locale = "de_DE";
    };
    "a keyboard layout with spaces" = ok // {
      keyboardLayout = "us de";
    };
    "an unknown DNS provider" = ok // {
      encryptedDns = "google";
    };
    "a DNS server without a name to check its certificate against" = ok // {
      customDns = [ "194.242.2.2" ];
    };
    "a DNS server address with shell characters" = ok // {
      customDns = [ "1.2.3.4;reboot#dns.example.com" ];
    };
    "a DNS server name with a space" = ok // {
      customDns = [ "1.2.3.4#dns example.com" ];
    };
    "a setting that doesn't exist" = ok // {
      desktpo = "gnome";
    };
  };
  accepted =
    check ok
    && check (
      ok
      // {
        keyboardLayout = "us,de";
        diskDevice = "/dev/disk/by-id/nvme-x";
        encryptedDns = "custom";
        customDns = [
          "194.242.2.2#dns.mullvad.net"
          "2a07:e340::2#dns.mullvad.net"
        ];
      }
    );
  wronglyAccepted = lib.attrNames (lib.filterAttrs (_: check) refused);
  loaderAccepts = lib.filter load [
    ../tests/reject-legacy
    ../tests/reject-controld
  ];
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.settings-reject =
        assert lib.assertMsg accepted "valid settings were refused";
        assert lib.assertMsg (wronglyAccepted == [ ])
          "these settings are accepted but have to be refused: ${lib.concatStringsSep ", " wronglyAccepted}";
        assert lib.assertMsg (loaderAccepts == [ ]) "the loader accepted ${toString loaderAccepts}";
        pkgs.runCommand "settings-reject" { } "touch $out";
    };
}
