{
  flake.modules.nixos.full =
    {
      config,
      lib,
      pkgs,
      ...
    }:
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
          # the ones ephemeral update takes before it changes anything
          NUMBER_CLEANUP = true;
          NUMBER_LIMIT = "5";
        };
      };

      # a subvolume, so snapshots don't contain each other. Not a tmpfiles v line: that makes a
      # subvolume only when / is one, so where / is in memory, as in the VM tests, it makes a folder.
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

      # Installed games in subvolumes of their own, which snapshots of /persist leave out. Inside,
      # an uninstalled or patched game would keep its old copy on the disk until the last snapshot
      # holding it went, four weeks later. A folder is moved in only once it's there, so Steam and
      # the launchers make their own first, and before anyone logs in, so nothing has it open.
      systemd.services.game-subvolumes = {
        description = "Keep installed games out of the snapshots of /persist";
        wantedBy = [ "multi-user.target" ];
        before = [ "systemd-user-sessions.service" ];
        after = [ "local-fs.target" ];
        path = [
          pkgs.btrfs-progs
          pkgs.coreutils
          pkgs.findutils
        ];
        serviceConfig = config.ephemeral.sandbox // {
          Type = "oneshot";
          RemainAfterExit = true;
          ReadWritePaths = [ "/persist/home" ];
          # to copy files as their owners have them, and read folders only they can
          CapabilityBoundingSet = [
            "CAP_CHOWN"
            "CAP_DAC_OVERRIDE"
            "CAP_DAC_READ_SEARCH"
            "CAP_FOWNER"
          ];
        };
        script = builtins.readFile ./_game-subvolumes.sh;
        scriptArgs = lib.escapeShellArgs [
          "/persist/home/${config.ephemeral.settings.username}/.local/share/Steam/steamapps"
          "/persist/home/${config.ephemeral.settings.username}/Games"
        ];
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
