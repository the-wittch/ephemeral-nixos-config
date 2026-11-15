# cp modules/local/_example.nix modules/local/apps.nix
{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        # helix
      ];
    };

  # flake.modules.homeManager.base =
  #   { pkgs, ... }:
  #   {
  #     home.packages = [ pkgs.hello ];
  #   };

  # Apps GNOME installs on its own, left out
  # flake.modules.nixos.gnome =
  #   { pkgs, ... }:
  #   {
  #     environment.gnome.excludePackages = with pkgs; [
  #       epiphany
  #       gnome-contacts
  #       gnome-maps
  #       gnome-music
  #       gnome-tour
  #       gnome-weather
  #     ];
  #   };

  # The same for Plasma
  # flake.modules.nixos.plasma =
  #   { pkgs, ... }:
  #   {
  #     environment.plasma6.excludePackages = with pkgs.kdePackages; [
  #       elisa
  #       khelpcenter
  #       konsole
  #     ];
  #   };

  # Services this repo turns on
  # flake.modules.nixos.pc =
  #   { lib, ... }:
  #   {
  #     services.printing.enable = lib.mkForce false;
  #     services.syncthing.enable = lib.mkForce false;
  #   };

  # Shell tools and dotfiles
  # flake.modules.homeManager.base =
  #   { lib, ... }:
  #   {
  #     programs.starship.enable = lib.mkForce false;
  #     programs.atuin.enable = lib.mkForce false;
  #   };
}
