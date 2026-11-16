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
      # bootctl adds a "Fallback" entry too; entries for other disks are left alone
      removeSystemdBootEntries = ''
        esp_uuid=$(${pkgs.util-linux}/bin/findmnt -no PARTUUID ${esp} || true)
        for entry in $(${pkgs.efibootmgr}/bin/efibootmgr | ${pkgs.gawk}/bin/awk -F '\t' -v uuid="''${esp_uuid,,}" '
          $1 ~ /^Boot[0-9A-Fa-f]{4}[* ] (Fallback )?Linux Boot Manager$/ && uuid != "" && index(tolower($2), uuid) {
            print substr($1, 5, 4)
          }'); do
          ${pkgs.efibootmgr}/bin/efibootmgr -q -B -b "$entry"
        done
      '';
    in
    {
      boot = {
        loader.limine = {
          enable = true;
          efiSupport = true;
          maxGenerations = 5;
          # a copy at the fallback path, for firmware that loses its entries or the disk in another
          # machine. Without firmware variables Limine installs itself there. cp and mv because FAT
          # refuses the chmod that install -m does.
          extraInstallCommands =
            lib.optionalString (!config.boot.loader.limine.efiInstallAsRemovable) ''
              ${pkgs.coreutils}/bin/mkdir -p ${esp}/efi/boot
              ${pkgs.coreutils}/bin/cp ${esp}/efi/limine/BOOTX64.EFI ${esp}/efi/boot/BOOTX64.EFI.tmp
              ${pkgs.coreutils}/bin/mv ${esp}/efi/boot/BOOTX64.EFI.tmp ${esp}/efi/boot/BOOTX64.EFI
            ''
            # systemd-boot stays as a way back until Limine has started this machine once
            + ''
              loader=$(${pkgs.coreutils}/bin/tail -c +5 ${loaderInfo} 2>/dev/null | ${pkgs.coreutils}/bin/tr -d '\0' || true)
              if [[ $loader == Limine* ]]; then
                ${pkgs.coreutils}/bin/rm -rf ${esp}/loader ${esp}/efi/systemd ${esp}/efi/nixos
                ${lib.optionalString config.boot.loader.efi.canTouchEfiVariables removeSystemdBootEntries}
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

      # for secure-boot.nix, on every machine: the rebuild that turns it on still runs with the
      # old system, so its keys only reach /persist through this
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
