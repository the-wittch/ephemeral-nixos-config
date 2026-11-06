{
  flake.modules.nixos.pc =
    { config, lib, ... }:
    {
      hardware.graphics.enable = true;

      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
      };

      services.power-profiles-daemon.enable = true;

      environment.persistence."/persist".directories =
        lib.optional config.services.hardware.bolt.enable {
          directory = "/var/lib/boltd";
          mode = "0700";
        }
        ++ lib.optional config.services.power-profiles-daemon.enable "/var/lib/power-profiles-daemon"
        ++ lib.optional config.services.colord.enable {
          directory = "/var/lib/colord";
          user = "colord";
          group = "colord";
        };
    };
}
