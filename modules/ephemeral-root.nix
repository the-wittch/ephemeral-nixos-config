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

          if [[ -e /btrfs_tmp/root ]]; then
            # nested subvolumes first
            list=$(btrfs subvolume list -o /btrfs_tmp/root)
            if [[ -n $list ]]; then
              mapfile -t subvols < <(printf '%s\n' "$list" | cut -d' ' -f9-)
              for ((i = ''${#subvols[@]} - 1; i >= 0; i--)); do
                subvolume=''${subvols[i]}
                [[ -n $subvolume ]] || continue
                btrfs subvolume delete "/btrfs_tmp/$subvolume"
              done
            fi
            btrfs subvolume delete /btrfs_tmp/root
          fi

          btrfs subvolume snapshot /btrfs_tmp/root-blank /btrfs_tmp/root
          cat /proc/sys/kernel/random/boot_id > /btrfs_tmp/root/.root-reset
        '';
      };

      # a failed rollback doesn't stop the boot, so report it here
      systemd.services.root-reset-check = {
        inherit (config.boot.initrd.systemd.services.rollback) enable;
        description = "Check that / was reset on this boot";
        wantedBy = [ "multi-user.target" ];
        # missing until the first boot with this initrd
        unitConfig.ConditionPathExists = "/.root-reset";
        serviceConfig = config.ephemeral.sandbox // {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          if [[ $(</.root-reset) != "$(</proc/sys/kernel/random/boot_id)" ]]; then
            echo "/ was not reset on this boot, so it isn't ephemeral now. See journalctl -b -u rollback." >&2
            exit 1
          fi
        '';
      };
    };
}
