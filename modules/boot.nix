{
  flake.modules.nixos.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      esp = config.boot.loader.efi.efiSysMountPoint;
    in
    {
      boot = {
        loader.limine = {
          enable = true;
          efiSupport = true;
          maxGenerations = 5;
          # Limine boots from its own firmware entry. Firmware that loses its entries, or a disk
          # moved to another machine, only finds the fallback path, so the same binary goes there
          # too. That also replaces systemd-boot's copy from before the switch. Copied and renamed
          # the way Limine copies its own files: FAT refuses the mode change install -m would make.
          # A machine that can't write firmware variables gets Limine at the fallback path alone.
          extraInstallCommands = lib.optionalString (!config.boot.loader.limine.efiInstallAsRemovable) ''
            ${pkgs.coreutils}/bin/mkdir -p ${esp}/efi/boot
            ${pkgs.coreutils}/bin/cp ${esp}/efi/limine/BOOTX64.EFI ${esp}/efi/boot/BOOTX64.EFI.tmp
            ${pkgs.coreutils}/bin/mv ${esp}/efi/boot/BOOTX64.EFI.tmp ${esp}/efi/boot/BOOTX64.EFI
          '';
        };
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
