{
  ...
}:

{
  boot = {
    loader.systemd-boot.enable = true;
    loader.systemd-boot.editor = false;
    loader.systemd-boot.configurationLimit = 5;
    loader.efi.canTouchEfiVariables = true;
    loader.timeout = 3;

    initrd.systemd.enable = true;

    plymouth.enable = true;

    consoleLogLevel = 3;
    initrd.verbose = false;
    kernelParams = [
      "quiet"
      "splash"
      "rd.udev.log_level=3"
      "rd.systemd.show_status=auto"
      # "plymouth.use-simpledrm"
    ];

    tmp.useTmpfs = true;
    tmp.cleanOnBoot = true;

    initrd.systemd.services.rollback = {
      description = "Rollback Btrfs root to blank snapshot";
      wantedBy = [ "initrd.target" ];
      after = [ "systemd-cryptsetup@cryptroot.service" ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        mkdir -p /btrfs_tmp
        mount -o subvolid=5 /dev/mapper/cryptroot /btrfs_tmp

        if [[ ! -e /btrfs_tmp/root-blank ]]; then
          echo "ERROR: root-blank subvolume missing" >&2
          exit 1
        fi

        if [[ -e /btrfs_tmp/root ]]; then
          btrfs subvolume list -o /btrfs_tmp/root |
            cut -f9 -d' ' |
            while read -r subvolume; do
              btrfs subvolume delete "/btrfs_tmp/$subvolume"
            done
          btrfs subvolume delete /btrfs_tmp/root
        fi

        btrfs subvolume snapshot /btrfs_tmp/root-blank /btrfs_tmp/root
        umount /btrfs_tmp
      '';
    };

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
}
