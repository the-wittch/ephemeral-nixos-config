# What each value in settings.json may be: a POSIX extended regular expression matched against
# the whole value, or the list of values allowed. _schema.nix builds its types from these, the
# helper commands get controldResolver from packages.nix, and the installer checks its answers
# against all of them through the settings-contract package of the release it pins.
let
  # these end up in shell scripts, such as the login environment
  vault = "[^\"$`\\\\[:cntrl:]]+";
in
{
  # NixOS's own rule for networking.hostName, which also refuses an empty name
  hostname = "[[:alnum:]]([[:alnum:]_-]{0,61}[[:alnum:]])?";
  username = "[a-z_][a-z0-9_-]{0,31}";
  timeZone = "[A-Za-z0-9_/+-]+";
  locale = "[A-Za-z_]+\\.UTF-8";
  keyboardLayout = "[a-z]{2,3}(,[a-z]{2,3})*";
  keyboardVariant = "[a-z0-9_-]*(,[a-z0-9_-]*)*";
  diskDevice = "/dev/[A-Za-z0-9/_.:+-]+";
  swapSize = "[0-9]+[KMGT]?";
  desktop = [
    "plasma"
    "gnome"
    "niri"
    "umbriel"
  ];
  profile = [
    "minimal"
    "full"
  ];
  nvidia = [
    "none"
    "open"
    "legacy"
  ];
  encryptedDns = [
    "none"
    "cloudflare"
    "quad9"
    "adguard"
    "custom"
  ];
  # each entry, address#name: resolved checks the server's certificate against the name
  customDns = "[0-9A-Fa-f.:]+#[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?";
  passSettingsVault = vault;
  passSettingsItem = vault;
  passSshVault = vault;
  # not a setting: the id goes in /persist/etc/controld-resolver, root-only
  controldResolver = "[A-Za-z0-9_-]+";
}
