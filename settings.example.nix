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

  allowUnfree = true;

  # id file: /persist/etc/controld-resolver
  # chezmoi file: /persist/etc/chezmoi-repo
  #   <git-url> <commit>
  useControlD = false;

  useFlakePassCli = false; # true keeps packages/pass-cli.nix

  # true: settings-from-pass writes settings.from-pass.nix and it gets merged
  usePassSettings = false;
  passSettingsVault = "Personal"; # or PASS_SETTINGS_VAULT
  passSettingsItem = "nixos-settings";
}
