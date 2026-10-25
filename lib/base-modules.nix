# The modules every system built from this template gets. mk-nixos.nix adds
# the machine's own files on top; tests/boot.nix boots exactly this list.
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
