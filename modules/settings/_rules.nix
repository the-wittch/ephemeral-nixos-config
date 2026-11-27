# What each value in settings.json may be: a POSIX extended regular expression matched against
# the whole value, or the list of values allowed, which comes from the menus in _choices.nix.
# _schema.nix builds its types from these, the helper commands get some through
# modules/packages/_prelude.nix, and the installer checks its answers against all of them
# through the settings-contract package of the release it pins.
let
  choices = import ./_choices.nix;
  values = key: map (c: c.value) (builtins.filter (c: !(c.useControlD or false)) choices.${key});
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
  desktop = values "desktop";
  profile = values "profile";
  handheld = values "handheld";
  nvidia = values "nvidia";
  encryptedDns = values "encryptedDns";
  # each entry, address#name: resolved checks the server's certificate against the name
  customDns = "[0-9A-Fa-f.:]+#[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?";
  # an SSH public key: its type, the key, and an optional comment without quotes, $, backticks or
  # backslashes, since the keys are written into sshd's files
  sshKeys = "(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\\.com|sk-ecdsa-sha2-nistp256@openssh\\.com) [A-Za-z0-9+/]+=*( [^\"$`\\\\[:cntrl:]]*)?";
  passSettingsVault = vault;
  passSettingsItem = vault;
  passSshVault = vault;
  # not a setting: the id goes in /persist/etc/controld-resolver, root-only
  controldResolver = "[A-Za-z0-9_-]+";
}
