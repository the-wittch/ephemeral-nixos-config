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
      loaderInfo = "/sys/firmware/efi/efivars/LoaderInfo-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f";
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
          extraInstallCommands =
            lib.optionalString (!config.boot.loader.limine.efiInstallAsRemovable) ''
              ${pkgs.coreutils}/bin/mkdir -p ${esp}/efi/boot
              ${pkgs.coreutils}/bin/cp ${esp}/efi/limine/BOOTX64.EFI ${esp}/efi/boot/BOOTX64.EFI.tmp
              ${pkgs.coreutils}/bin/mv ${esp}/efi/boot/BOOTX64.EFI.tmp ${esp}/efi/boot/BOOTX64.EFI
            ''
            # systemd-boot's files from before v4.7.0 stay as a way back until this machine has
            # started from Limine once; the firmware says which bootloader started it
            + ''
              loader=$(${pkgs.coreutils}/bin/tail -c +5 ${loaderInfo} 2>/dev/null | ${pkgs.coreutils}/bin/tr -d '\0' || true)
              if [[ $loader == Limine* ]]; then
                ${pkgs.coreutils}/bin/rm -rf ${esp}/loader ${esp}/efi/systemd ${esp}/efi/nixos
                ${lib.optionalString config.boot.loader.efi.canTouchEfiVariables ''
                  for entry in $(${pkgs.efibootmgr}/bin/efibootmgr |
                    ${pkgs.gawk}/bin/awk -F '\t' '$1 ~ /^Boot[0-9A-Fa-f]{4}[* ] Linux Boot Manager$/ { print substr($1, 5, 4) }'); do
                    ${pkgs.efibootmgr}/bin/efibootmgr -q -B -b "$entry"
                  done
                ''}
              fi
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

      # Secure Boot's keys (secure-boot.nix). Kept on every machine, not only once it's turned on:
      # the rebuild that turns it on makes the keys before the new system mounts what's kept.
      environment.persistence."/persist".directories = [
        {
          directory = "/var/lib/sbctl";
          mode = "0700";
        }
      ];

      services.fstrim.enable = true;

      systemd.sleep.settings.Sleep = {
        AllowHibernation = "no";
        AllowHybridSleep = "no";
        AllowSuspendThenHibernate = "no";
      };
    };
}
