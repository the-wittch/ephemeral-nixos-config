# cp settings.example.nix settings.nix
# sudo nixos-rebuild switch --flake path:.#nixos

{
  hostname = "nixos";
  username = "nixuser";

  # whole disk, not a partition
  diskDevice = "/dev/nvme0n1";

  swapSize = "16G";
  timeZone = "UTC";

  # plasma | gnome | niri
  desktop = "plasma";

  # https://github.com/you/dotfiles.git
  chezmoiRepo = "";

  allowUnfree = true;

  controldResolver = ""; # "" = off. id from the Control D panel

  useFlakePassCli = true; # false once nixpkgs has pass-cli

  # true: settings-from-pass writes settings.from-pass.nix and it gets merged
  usePassSettings = false;
  passSettingsVault = "Personal"; # or PASS_SETTINGS_VAULT
  passSettingsItem = "nixos-settings";
}
