# _load.nix also evaluates these on their own, so a bad value is caught before the machine is put together
{ lib, ... }:
let
  inherit (lib) mkOption types;
  flag =
    default: description:
    mkOption {
      type = types.bool;
      inherit default description;
    };
  # these end up in shell scripts, such as the login environment
  vaultName = types.strMatching "[^\"$`\\\\[:cntrl:]]+";
in
{
  options.ephemeral.settings = {
    hostname = mkOption {
      type = types.nonEmptyStr;
      default = "nixos";
      description = "Hostname.";
    };
    username = mkOption {
      type = types.strMatching "[a-z_][a-z0-9_-]{0,31}";
      description = "The one login user.";
    };
    timeZone = mkOption {
      type = types.strMatching "[A-Za-z0-9_/+-]+";
      default = "UTC";
      description = "Time zone, e.g. Europe/Berlin.";
    };
    locale = mkOption {
      type = types.strMatching "[A-Za-z_]+\\.UTF-8";
      default = "en_US.UTF-8";
      description = "System language, e.g. de_DE.UTF-8.";
    };
    keyboardLayout = mkOption {
      type = types.strMatching "[a-z]{2,3}(,[a-z]{2,3})*";
      default = "us";
      description = "XKB layout, also used for the console and the LUKS prompt, e.g. de or us,de.";
    };
    keyboardVariant = mkOption {
      type = types.strMatching "[a-z0-9_-]*(,[a-z0-9_-]*)*";
      default = "";
      description = "XKB variant, e.g. nodeadkeys. Empty for the default.";
    };
    diskDevice = mkOption {
      type = types.addCheck (types.strMatching "/dev/[A-Za-z0-9/_.:+-]+") (d: !lib.hasInfix ".." d);
      default = "/dev/nvme0n1";
      description = "Whole disk the system is installed on.";
    };
    swapSize = mkOption {
      type = types.strMatching "[0-9]+[KMGT]?";
      default = "16G";
      description = "Swap file size, e.g. 16G.";
    };
    desktop = mkOption {
      type = types.enum [
        "plasma"
        "gnome"
        "niri"
        "umbriel"
      ];
      default = "plasma";
      description = "Desktop environment.";
    };
    profile = mkOption {
      type = types.enum [
        "minimal"
        "full"
      ];
      default = "full";
      description = "minimal is the small first-boot system the installer sets up; full is everything here.";
    };
    nvidia = mkOption {
      type = types.enum [
        "none"
        "open"
        "legacy"
      ];
      default = "none";
      description = "NVIDIA driver: open for RTX 20 / GTX 16 and newer, legacy (580) for GTX 900 and 10 series.";
    };
    extras = flag false "Extra apps and tools: Steam, VS Code, Brave, VLC, atuin, fzf, bat, comma and more.";
    laptop = flag false "Laptop extras: thermald on Intel, battery reporting, sensors.";
    fingerprint = flag false "Fingerprint login and sudo through fprintd.";
    useControlD = flag false "DNS over TLS to Control D; the id is in /persist/etc/controld-resolver.";
    useTailscale = flag false "Tailscale VPN.";
    useOpenSnitch = flag true "OpenSnitch: outgoing connections need your OK (full profile).";
    useFlakePassCli = flag false "Build modules/packages/_pass-cli.nix instead of nixpkgs proton-pass-cli.";
    usePassSettings = flag false "Merge settings.from-pass.json.";
    passSettingsVault = mkOption {
      type = vaultName;
      default = "Personal";
      description = "Proton Pass vault for settings-from-pass.";
    };
    passSettingsItem = mkOption {
      type = vaultName;
      default = "nixos-settings";
      description = "Proton Pass item for settings-from-pass.";
    };
    usePassSshAgent = flag false "Proton Pass SSH agent at login, serving the keys in passSshVault.";
    passSshVault = mkOption {
      type = vaultName;
      default = "Personal";
      description = "Proton Pass vault the SSH agent and ssh-pubs-from-pass read keys from.";
    };
  };
}
