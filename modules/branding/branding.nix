# The wallpaper and the welcome screen's logo, for the installer, which takes them from the
# release it pins instead of from files inside it
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        wallpaper = pkgs.runCommand "wallpaper.svg" { } "cp ${../../assets/wallpaper.svg} $out";
        welcome-logo = import ./_logo.nix {
          inherit pkgs;
          cols = 48;
          rows = 14;
        };
      };
    };
}
