# Scheduled backups with borgmatic, as root, to the repositories in backup.json. backup-setup
# makes root's SSH key and writes the passphrase to /persist/etc/borg, out of the Nix store.
{
  flake.modules.nixos.pc =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (import ./_backup.nix) dir;
      cfg = config.ephemeral.backup;
      repositories = config.ephemeral.backupRepositories;
      ssh = lib.getExe pkgs.openssh;
      patterns = pkgs.writeText "backup-patterns.lst" (
        lib.concatLines cfg.patterns + builtins.readFile ./backup-patterns.lst
      );
      hosts = lib.unique (
        lib.concatMap (
          r:
          let
            m = builtins.match "ssh://([^@/]*@)?([^:/]+).*" r.path;
          in
          lib.optional (m != null) (lib.elemAt m 1)
        ) repositories
      );
    in
    {
      options.ephemeral.backup = {
        patterns = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [
            "R /persist/var/lib/jellyfin"
            "! persist/var/lib/jellyfin/transcodes"
          ];
          description = ''
            Borg pattern lines read before the built-in ones in backup-patterns.lst: an R line
            backs up another area, and a + line keeps something the built-in lines leave out.
          '';
        };
        schedule = lib.mkOption {
          type = lib.types.str;
          default = "*-*-* 00/6:00:00";
          description = ''
            When to back up, as systemd's OnCalendar. A run is skipped on battery, and a missed one
            runs at the next start.
          '';
        };
      };

      config = lib.mkIf (repositories != [ ]) {
        services.borgmatic = {
          enable = true;
          settings = {
            repositories = map (r: { inherit (r) label path; }) repositories;
            # the R lines in it are the areas to back up
            patterns_from = [ "${patterns}" ];
            exclude_caches = true;
            exclude_if_present = [ ".nobackup" ];
            compression = "auto,zstd";
            encryption_passcommand = "${pkgs.coreutils}/bin/cat ${dir}/passphrase";
            # root's own key: the Proton Pass agent is only there while someone's logged in. The
            # host key is taken the first time and checked from then on.
            ssh_command = "${ssh} -i ${dir}/ssh_key -o UserKnownHostsFile=${dir}/known_hosts -o StrictHostKeyChecking=accept-new";
            # root's home is wiped at every boot, and without its cache borg reads every file again
            borg_base_directory = "/var/lib/borg";
            keep_hourly = 24;
            keep_daily = 7;
            keep_weekly = 4;
            keep_monthly = 6;
            checks = [
              {
                name = "repository";
                frequency = "2 weeks";
              }
              {
                name = "archives";
                frequency = "1 month";
              }
            ];
          };
        };

        # the empty entry drops the package's own daily
        systemd.timers.borgmatic.timerConfig.OnCalendar = [
          ""
          cfg.schedule
        ];

        systemd.tmpfiles.rules = [ "d ${dir} 0700 root root -" ];

        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/borg";
            mode = "0700";
          }
          # when each check last ran
          {
            directory = "/var/lib/borgmatic";
            mode = "0700";
          }
        ];

        services.opensnitch.rules.borgmatic-ssh = lib.mkIf (hosts != [ ]) {
          name = "borgmatic-ssh";
          enabled = true;
          action = "allow";
          duration = "always";
          operator = {
            type = "list";
            operand = "list";
            list = [
              {
                type = "simple";
                sensitive = false;
                operand = "process.path";
                data = ssh;
              }
              {
                type = "regexp";
                sensitive = false;
                operand = "dest.host";
                data = "^(${lib.concatMapStringsSep "|" lib.escapeRegex hosts})$";
              }
            ];
          };
        };
      };
    };
}
