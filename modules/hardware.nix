{
  flake.modules.nixos.base = {
    hardware.enableRedistributableFirmware = true;

    services.fwupd.enable = true;
    preservation.preserveAt."/persist".directories = [
      {
        directory = "/var/lib/fwupd";
        user = "fwupd-refresh";
        group = "fwupd-refresh";
      }
    ];
  };

  flake.modules.nixos.pc =
    { config, lib, ... }:
    {
      hardware.graphics.enable = true;

      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
      };

      services.power-profiles-daemon.enable = true;

      preservation.preserveAt."/persist".directories = [
        {
          directory = "/var/lib/bluetooth";
          mode = "0700";
        }
      ]
      # bolt.service sets 0755 itself, the default
      ++ lib.optional config.services.hardware.bolt.enable "/var/lib/boltd"
      ++ lib.optional config.services.power-profiles-daemon.enable "/var/lib/power-profiles-daemon"
      ++ lib.optional config.services.upower.enable "/var/lib/upower"
      ++ lib.optional config.services.colord.enable {
        directory = "/var/lib/colord";
        user = "colord";
        group = "colord";
      };
    };
}
