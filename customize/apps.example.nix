# cp customize/apps.example.nix customize/apps.nix
# sudo nixos-rebuild switch --flake path:.#nixos
{ pkgs, settings, ... }:
{
  environment.systemPackages = with pkgs; [
    # helix
  ];

  # home-manager.users.${settings.username} = {
  #   home.packages = [ pkgs.hello ];
  # };
}
