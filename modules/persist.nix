{ inputs, ... }:
{
  flake.modules.nixos.base =
    {
      config,
      options,
      pkgs,
      lib,
      ...
    }:
    let
      settings = config.ephemeral.settings;
      user = config.users.users.${settings.username};
      kept = config.preservation.preserveAt."/persist";
      credentialSecret = "/var/lib/systemd/credential.secret";

      # which files declare each path, for ephemeral-doctor persistence; a path a machine's own
      # module adds names that module's file
      declared =
        let
          sub = options.preservation.preserveAt.valueMeta.attrs."/persist".configuration.options or { };
          defs = kind: (sub.${kind} or { definitionsWithLocations = [ ]; }).definitionsWithLocations;
          file =
            d:
            let
              f = builtins.unsafeDiscardStringContext (lib.head (lib.splitString ", via " d.file));
              own = builtins.match "/nix/store/[^/]+/(.*)" f;
            in
            if lib.hasPrefix "${toString ./..}/" f then
              lib.removePrefix "${toString ./..}/" f
            else if own != null then
              "this machine's flake: ${lib.head own}"
            else
              f;
          paths = lib.concatMap (
            d:
            map (e: {
              path = if lib.isString e then e else e.directory or e.file;
              file = file d;
            }) (lib.optionals (lib.isList d.value) d.value)
          ) (defs "directories" ++ defs "files");
        in
        lib.mapAttrs (_: es: lib.unique (map (e: e.file) es)) (lib.groupBy (e: e.path) paths);
      entry = kind: path: e: {
        inherit kind path;
        inherit (e)
          how
          inInitrd
          user
          group
          mode
          ;
        declaredIn = declared.${path} or [ ];
      };
      subvolume =
        fs:
        let
          m = lib.findFirst (o: lib.hasPrefix "subvol=" o) null fs.options;
        in
        if m == null then null else lib.removePrefix "subvol=" m;
      keptJson = {
        version = 1;
        persistRoot = "/persist";
        resetSubvolume = subvolume config.fileSystems."/";
        entries =
          map (d: entry "directory" d.directory d) kept.directories
          ++ map (f: entry "file" f.file f) kept.files
          ++ [
            {
              kind = "file";
              path = credentialSecret;
              how = "bindmount";
              inInitrd = false;
              user = "root";
              group = "root";
              mode = "0400";
              declaredIn = [ "modules/persist.nix" ];
            }
          ];
        filesystems =
          lib.mapAttrsToList
            (mountPoint: fs: {
              inherit mountPoint;
              inherit (fs) fsType;
              subvolume = subvolume fs;
            })
            (
              lib.filterAttrs (
                _: fs:
                lib.elem fs.fsType [
                  "btrfs"
                  "vfat"
                ]
              ) config.fileSystems
            );
      };
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
      environment.etc."ephemeral/kept.json".text = builtins.toJSON keptJson;

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

      # A running system can't move from impermanence's mounts to these: the old ones are taken
      # down before anything puts the initrd's back, /etc/machine-id among them, and the desktop
      # stops. Systems with this key are already on preservation.
      system.switch.inhibitors.ephemeral-persistence = "preservation";
      system.preSwitchChecks.ephemeral-persistence = ''
        case ''${2-} in
          switch | test) ;;
          *) exit 0 ;;
        esac
        running=/run/current-system/switch-inhibitors
        if [[ -e /run/current-system ]] &&
          ! ${lib.getExe pkgs.jq} -e '."ephemeral-persistence"' "$running" >/dev/null 2>&1; then
          cat <<'EOF'

        This release keeps files with preservation instead of impermanence, and a running
        system can't be moved over. Nothing has been changed. Set it up for the next boot
        instead, then reboot:

          nh os boot path:/persist/etc/nixos --hostname nixos
          systemctl reboot

        The release itself is fine, so there's no need to go back to the old one.

        EOF
          exit 1
        fi
      '';

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
