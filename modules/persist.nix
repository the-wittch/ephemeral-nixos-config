{ inputs, ... }:
{
  flake.modules.nixos.base =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      settings = config.ephemeral.settings;
      user = config.users.users.${settings.username};
      kept = config.preservation.preserveAt."/persist";
      credentialSecret = "/var/lib/systemd/credential.secret";
    in
    {
      imports = [
        inputs.preservation.nixosModules.preservation
        (lib.mkRemovedOptionModule [ "environment" "persistence" ] ''
          It's preservation.preserveAt now, with the same directories and files: rename
          environment.persistence."/persist" to preservation.preserveAt."/persist" in your modules.
          The 5.0.0 CHANGELOG entry has the details.'')
      ];

      fileSystems."/persist".neededForBoot = true;
      fileSystems."/var/log".neededForBoot = true;

      # ephemeral-doctor kept lists them; here they come from every feature that adds one
      environment.etc."ephemeral/kept".text =
        lib.concatMapStrings (d: d.directory + "/\n") kept.directories
        + lib.concatMapStrings (f: f.file + "\n") kept.files
        + credentialSecret
        + "\n";

      # A kept folder's owner and mode are set at every boot, as given here, so a folder a service
      # owns has to say so.
      preservation = {
        enable = true;
        preserveAt."/persist" = {
          # out of the file manager's list of drives
          commonMountOptions = [ "x-gvfs-hide" ];
          directories = [
            # before NixOS sets up the user in the initrd, so its home folder is made in /persist
            {
              directory = "/home";
              inInitrd = true;
            }
            # the uid and gid of every user, read when they're set up in the initrd
            {
              directory = "/var/lib/nixos";
              inInitrd = true;
            }
            {
              directory = "/var/lib/AccountsService";
              mode = "0775";
            }
            "/var/lib/systemd/backlight"
            "/var/lib/systemd/rfkill"
            "/var/lib/systemd/timers"
            "/var/lib/systemd/linger"
            {
              directory = "/var/lib/systemd/timesync";
              user = "systemd-timesync";
              group = "systemd-timesync";
            }
          ];
          files = [
            # preservation's first-boot setup: systemd writes a new id through the link once
            {
              file = "/etc/machine-id";
              inInitrd = true;
              how = "symlink";
              configureParent = true;
            }
            # made only once something has written it, so a link rather than a mount
            {
              file = "/var/lib/systemd/random-seed";
              how = "symlink";
              inInitrd = true;
              configureParent = true;
            }
          ];
        };
      };

      boot.initrd.systemd.tmpfiles.settings.preservation."/sysroot/persist/etc/machine-id".f = {
        argument = "uninitialized";
      };
      systemd.services.systemd-machine-id-commit = {
        unitConfig.ConditionPathIsMountPoint = [
          ""
          "/persist/etc/machine-id"
        ];
        serviceConfig.ExecStart = [
          ""
          "systemd-machine-id-setup --commit --root /persist"
        ];
      };

      systemd.tmpfiles.rules = [
        "d /persist/home/${user.name} 0700 ${user.name} ${user.group} -"
      ];

      # Not left to preservation: it would make an empty key file, which systemd-creds won't
      # replace. systemd-creds can't run in the initrd, so the key is made here and mounted.
      systemd.services.credential-secret-setup = {
        description = "Create the systemd credential key on /persist";
        wantedBy = [ "sysinit.target" ];
        after = [ "local-fs.target" ];
        before = [ "sysinit.target" ];
        unitConfig.DefaultDependencies = false;
        path = [
          config.systemd.package
          pkgs.coreutils
          pkgs.util-linux
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
        };
        script = ''
          key=/persist${credentialSecret}
          dest=${credentialSecret}
          if [[ ! -s $key ]]; then
            install -d -m 0755 "$(dirname "$key")"
            SYSTEMD_CREDENTIAL_SECRET=$key systemd-creds setup
          fi
          if ! mountpoint -q "$dest"; then
            rm -f "$dest"
            touch "$dest"
            mount --bind "$key" "$dest"
          fi
        '';
      };
    };
}
