{
  flake.modules.nixos.base =
    { config, ... }:
    {
      boot.initrd.systemd.services.rollback = {
        description = "Rollback Btrfs root to blank snapshot";
        wantedBy = [ "initrd.target" ];
        after = [ "systemd-cryptsetup@cryptroot.service" ];
        before = [ "sysroot.mount" ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        script = ''
          set -euo pipefail
          mkdir -p /btrfs_tmp
          mount -o subvolid=5 /dev/mapper/cryptroot /btrfs_tmp
          trap 'umount /btrfs_tmp' EXIT

          if [[ ! -e /btrfs_tmp/root-blank ]]; then
            echo "ERROR: root-blank subvolume missing" >&2
            exit 1
          fi

          # The new root is ready before the old one goes, so a failure at any step still leaves a
          # root to boot; root-reset-check then reports that it wasn't reset. -R also deletes the
          # subvolumes nested inside, at any depth.
          if [[ -e /btrfs_tmp/root-new ]]; then
            btrfs subvolume delete -R /btrfs_tmp/root-new
          fi
          btrfs subvolume snapshot /btrfs_tmp/root-blank /btrfs_tmp/root-new
          cat /proc/sys/kernel/random/boot_id > /btrfs_tmp/root-new/.root-reset
          if [[ -e /btrfs_tmp/root ]]; then
            btrfs subvolume delete -R /btrfs_tmp/root
          fi
          mv /btrfs_tmp/root-new /btrfs_tmp/root
        '';
      };

      # a failed rollback doesn't stop the boot, so report it here
      systemd.services.root-reset-check = {
        inherit (config.boot.initrd.systemd.services.rollback) enable;
        description = "Check that / was reset on this boot";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = config.ephemeral.sandbox // {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        # the reset writes the marker, so a missing one means it hasn't worked since this was installed
        script = ''
          if [[ ! -e /.root-reset ]]; then
            echo "/ has no reset marker, so it wasn't reset at this boot and isn't ephemeral now. See journalctl -b -u rollback." >&2
            exit 1
          fi
          if [[ $(</.root-reset) != "$(</proc/sys/kernel/random/boot_id)" ]]; then
            echo "/ was not reset on this boot, so it isn't ephemeral now. See journalctl -b -u rollback." >&2
            exit 1
          fi
        '';
      };
    };
}
