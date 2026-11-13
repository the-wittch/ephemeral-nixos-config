{
  flake.modules.nixos.base = {
    boot = {
      loader.systemd-boot.enable = true;
      loader.systemd-boot.editor = false;
      loader.systemd-boot.configurationLimit = 5;
      loader.efi.canTouchEfiVariables = true;
      loader.timeout = 3;

      plymouth.enable = true;

      consoleLogLevel = 3;
      kernelParams = [
        "quiet"
        "splash"
        "rd.udev.log_level=3"
        "rd.systemd.show_status=auto"
      ];

      tmp.useTmpfs = true;
      tmp.cleanOnBoot = true;

      supportedFilesystems = [
        "btrfs"
        "ntfs"
        "exfat"
        "vfat"
      ];
    };

    services.fstrim.enable = true;

    systemd.sleep.settings.Sleep = {
      AllowHibernation = "no";
      AllowHybridSleep = "no";
      AllowSuspendThenHibernate = "no";
    };
  };
}
