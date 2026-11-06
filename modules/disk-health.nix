{
  flake.modules.nixos.full = {
    services.smartd = {
      enable = true;
      # a VM has no SMART disks; that's not an error
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
