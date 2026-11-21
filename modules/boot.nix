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
          # a copy at the fallback path, for firmware that loses its entries or the disk in another
          # machine. Without firmware variables Limine installs itself there. cp and mv because FAT
          # refuses the chmod that install -m does.
          extraInstallCommands = lib.optionalString (!config.boot.loader.limine.efiInstallAsRemovable) ''
            ${pkgs.coreutils}/bin/mkdir -p ${esp}/efi/boot
            ${pkgs.coreutils}/bin/cp ${esp}/efi/limine/BOOTX64.EFI ${esp}/efi/boot/BOOTX64.EFI.tmp
            ${pkgs.coreutils}/bin/mv ${esp}/efi/boot/BOOTX64.EFI.tmp ${esp}/efi/boot/BOOTX64.EFI
          '';
        };
        # The background's first byte is its transparency. With no branding set, the title line
        # is Limine's version, in the branding colour.
        loader.limine.style = {
          graphicalTerminal = {
            background = lib.mkForce "8c0d0b26";
            margin = 240;
            marginGradient = 32;
          };
          interface = {
            brandingColor = "c084fc";
            helpColor = "38bdf8";
          };
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
