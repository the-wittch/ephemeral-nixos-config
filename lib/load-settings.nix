# settings.nix and settings.from-pass.nix are gitignored.

{ flakeRoot }:

let
  defaults = {
    hostname = "nixos";
    username = "nixuser";
    diskDevice = "/dev/nvme0n1";
    swapSize = "16G";
    timeZone = "UTC";
    desktop = "gnome"; # plasma | gnome | niri
    allowUnfree = true;
    useControlD = false; # id is /persist/etc/controld-resolver
    useFlakePassCli = true; # false once nixpkgs has pass-cli
    usePassSettings = false; # true merges settings.from-pass.nix
    passSettingsVault = "Personal";
    passSettingsItem = "nixos-settings";
  };

  settingsPath = flakeRoot + "/settings.nix";
  passPath = flakeRoot + "/settings.from-pass.nix";

  fromSettings = if builtins.pathExists settingsPath then import settingsPath else { };

  # pass file can't flip this on by itself
  usePass =
    (defaults // fromSettings).usePassSettings or false;

  fromPass =
    if usePass && builtins.pathExists passPath then import passPath else { };

  merged = defaults // fromSettings // fromPass;
  merged' =
    if (merged.controldResolver or "") != "" || (merged.chezmoiRepo or "") != "" then
      throw ''
        Don't put controldResolver or chezmoiRepo in settings.
        Control D id: /persist/etc/controld-resolver and useControlD = true.
        chezmoi: /persist/etc/chezmoi-repo as "<git-url> <commit>".
      ''
    else
      merged;
in
assert merged'.hostname != "";
assert merged'.username != "";
assert merged'.diskDevice != "";
assert merged'.swapSize != "";
assert merged'.timeZone != "";
assert builtins.elem merged'.desktop [
  "plasma"
  "gnome"
  "niri"
];
removeAttrs merged' [
  "controldResolver"
  "chezmoiRepo"
]
