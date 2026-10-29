{
  flake.modules.nixos.full = {
    services.smartd = {
      enable = true;
      # no smart disks, as in a vm, is not an error
      extraOptions = [
        "-q"
        "nodev0"
      ];
      notifications = {
        wall.enable = false;
        x11.enable = false;
        systembus-notify.enable = true;
      };
    };
  };
}
