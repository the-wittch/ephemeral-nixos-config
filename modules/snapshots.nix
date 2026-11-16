{
  flake.modules.nixos.full = {
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

    # a subvolume, so snapshots don't contain each other; tmpfiles makes it one on btrfs.
    # root only: old snapshots hold old hashes and keys
    systemd.tmpfiles.rules = [ "v /persist/.snapshots 0750 root root -" ];
  };
}
