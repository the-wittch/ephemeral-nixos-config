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
  rules = import ./_rules.nix;
  matching = key: types.strMatching rules.${key};
in
{
  options.ephemeral.settings = {
    hostname = mkOption {
      type = matching "hostname";
      default = "nixos";
      description = "Hostname.";
    };
    username = mkOption {
      type = matching "username";
      description = "The one login user.";
    };
    timeZone = mkOption {
      type = matching "timeZone";
      default = "UTC";
      description = "Time zone, e.g. Europe/Berlin.";
    };
    locale = mkOption {
      type = matching "locale";
      default = "en_US.UTF-8";
      description = "System language, e.g. de_DE.UTF-8.";
    };
    keyboardLayout = mkOption {
      type = matching "keyboardLayout";
      default = "us";
      description = "XKB layout, also used for the console and the LUKS prompt, e.g. de or us,de.";
    };
    keyboardVariant = mkOption {
      type = matching "keyboardVariant";
      default = "";
      description = "XKB variant, e.g. nodeadkeys. Empty for the default.";
    };
    diskDevice = mkOption {
      type = types.addCheck (matching "diskDevice") (d: !lib.hasInfix ".." d);
      default = "/dev/nvme0n1";
      description = "Whole disk the system is installed on.";
    };
    swapSize = mkOption {
      type = matching "swapSize";
      default = "16G";
      description = "Swap file size, e.g. 16G.";
    };
    desktop = mkOption {
      type = types.enum rules.desktop;
      default = "plasma";
      description = "Desktop environment.";
    };
    profile = mkOption {
      type = types.enum rules.profile;
      default = "full";
      description = "minimal is the small first-boot system the installer sets up; full is everything here.";
    };
    nvidia = mkOption {
      type = types.enum rules.nvidia;
      default = "none";
      description = "NVIDIA driver: open for RTX 20 / GTX 16 and newer, legacy (580) for GTX 900 and 10 series.";
    };
    extras = flag false "Extra shell tools: atuin, fzf, bat, yazi, btop, fastfetch, comma and more.";
    laptop = flag false "Laptop extras: thermald on Intel, battery reporting, sensors.";
    fingerprint = flag false "Fingerprint login and sudo through fprintd.";
    secureBoot = flag false "Secure Boot with keys made on this machine. The firmware steps are in docs/security.md.";
    tpmUnlock = flag false "Unlock the disk with the TPM and a PIN, the passphrase as a fallback. Needs secureBoot; ephemeral-setup turns it on.";
    useControlD = flag false "DNS over TLS to Control D; the id is in /persist/etc/controld-resolver.";
    encryptedDns = mkOption {
      type = types.enum rules.encryptedDns;
      default = "none";
      description = "DNS over TLS to a public resolver, without an account, or to the servers in customDns. Use useControlD for Control D.";
    };
    customDns = mkOption {
      type = types.listOf (matching "customDns");
      default = [ ];
      description = "DNS over TLS servers for encryptedDns = \"custom\", each as address#name, e.g. 194.242.2.2#dns.mullvad.net.";
    };
    server = flag false "A server: SSH on with sshKeys, no sleep, and the disk unlocked over SSH after a reboot. desktop = \"none\" needs it.";
    sshKeys = mkOption {
      type = types.listOf (matching "sshKeys");
      default = [ ];
      description = "SSH public keys that may log in, such as \"ssh-ed25519 AAAA… you@laptop\". A server needs at least one.";
    };
    useTailscale = flag false "Tailscale VPN.";
    useOpenSnitch = flag true "OpenSnitch: outgoing connections need your OK (full profile).";
    flatpakUpdates = flag true "Update the Flatpak apps once a week (full profile, with a desktop).";
    usePassSettings = flag false "Merge settings.from-pass.json.";
    passSettingsVault = mkOption {
      type = matching "passSettingsVault";
      default = "Personal";
      description = "Proton Pass vault for settings-from-pass.";
    };
    passSettingsItem = mkOption {
      type = matching "passSettingsItem";
      default = "nixos-settings";
      description = "Proton Pass item for settings-from-pass.";
    };
    usePassSshAgent = flag false "Proton Pass SSH agent at login, serving the keys in passSshVault.";
    passSshVault = mkOption {
      type = matching "passSshVault";
      default = "Personal";
      description = "Proton Pass vault the SSH agent and ssh-pubs-from-pass read keys from.";
    };
  };
}
