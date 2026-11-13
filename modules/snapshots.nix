{
  flake.modules.nixos.full =
    { config, pkgs, ... }:
    {
      services.snapper = {
        persistentTimer = true;
        configs.persist = {
          SUBVOLUME = "/persist";
          FSTYPE = "btrfs";
          TIMELINE_CREATE = true;
          TIMELINE_CLEANUP = true;
          TIMELINE_LIMIT_HOURLY = 24;
          TIMELINE_LIMIT_DAILY = 7;
          TIMELINE_LIMIT_WEEKLY = 4;
          TIMELINE_LIMIT_MONTHLY = 0;
          TIMELINE_LIMIT_YEARLY = 0;
        };
      };

      # a subvolume, so snapshots don't contain each other
      # root only: old snapshots hold old hashes and keys
      systemd.services.snapper-persist-setup = {
        description = "Create the snapper subvolume on /persist";
        wantedBy = [ "multi-user.target" ];
        before = [
          "snapper-timeline.service"
          "snapper-cleanup.service"
        ];
        path = [ pkgs.btrfs-progs ];
        serviceConfig = config.ephemeral.sandbox // {
          Type = "oneshot";
          RemainAfterExit = true;
          ReadWritePaths = [ "/persist" ];
        };
        # a subvolume's root is always inode 256, which stat can see without any capabilities
        script = ''
          if [[ $(stat -c %i /persist/.snapshots 2>/dev/null) != 256 ]]; then
            btrfs subvolume create /persist/.snapshots
          fi
          chmod 750 /persist/.snapshots
        '';
      };

      systemd.services.snapper-timeline = {
        requires = [ "snapper-persist-setup.service" ];
        after = [ "snapper-persist-setup.service" ];
      };
      systemd.services.snapper-cleanup = {
        requires = [ "snapper-persist-setup.service" ];
        after = [ "snapper-persist-setup.service" ];
      };
    };
}
