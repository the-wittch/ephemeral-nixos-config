# modules every system gets. mk-nixos adds the machine's files.
{
  impermanence,
  disko,
  home-manager,
}:
{ settings, flakeRoot }:
[
  disko.nixosModules.disko
  ../disko.nix
  ../configuration.nix
  impermanence.nixosModules.impermanence
  home-manager.nixosModules.home-manager
  {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.backupFileExtension = "hm-backup";
    home-manager.extraSpecialArgs = {
      inherit settings flakeRoot;
    };
    home-manager.users.${settings.username} = import ../home.nix;
  }
]
