{
  # GNOME and Plasma make ~/Documents and the rest themselves; niri and Umbriel don't
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xdg-user-dirs ];
      systemd.packages = [ pkgs.xdg-user-dirs ];

      # the package's unit only starts with a graphical session; this also covers a console login
      systemd.user.services.xdg-user-dirs = {
        wantedBy = [ "default.target" ];
        unitConfig.ConditionUser = "!@system";
      };
    };
}
