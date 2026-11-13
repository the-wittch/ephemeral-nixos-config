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
      owner = lib.escapeShellArg "${settings.username}:${config.users.users.${settings.username}.group}";
    in
    {
      imports = [ inputs.impermanence.nixosModules.impermanence ];

      fileSystems."/persist".neededForBoot = true;
      fileSystems."/var/log".neededForBoot = true;

      environment.persistence."/persist" = {
        hideMounts = true;
        directories = [
          "/home"
          "/var/lib/nixos"
          "/var/lib/AccountsService"
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
          "/etc/machine-id"
          "/var/lib/systemd/random-seed"
          "/var/lib/systemd/credential.secret"
        ];
      };

      # systemd-creds can't run in the initrd, so make the key here and bind-mount it
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
          key=/persist/var/lib/systemd/credential.secret
          dest=/var/lib/systemd/credential.secret
          if [[ ! -s $key ]]; then
            install -d -m 0755 "$(dirname "$key")"
            SYSTEMD_CREDENTIAL_SECRET=$key systemd-creds setup
          fi
          if [[ -L $dest ]]; then
            rm "$dest"
            touch "$dest"
            mount --bind "$key" "$dest"
          fi
        '';
      };

      # impermanence copies these modes to the new root; 0700 locks users out of /etc
      system.activationScripts.persistParentModes = {
        text = ''
          for d in /persist /persist/etc /persist/var /persist/var/lib /persist/home; do
            if [ -d "$d" ]; then
              chmod 0755 "$d"
              chown 0:0 "$d"
            fi
          done
          # installers up to v3.7.3 left the flake root-only, so ephemeral-update couldn't read it
          if [ -d /persist/etc/nixos ] && [ "$(stat -c %u%a /persist/etc/nixos)" = 0700 ]; then
            chmod 0755 /persist/etc/nixos
          fi
        '';
      };
      system.activationScripts.createPersistentStorageDirs.deps = [ "persistParentModes" ];

      system.activationScripts.ensureUserHome = {
        deps = [
          "users"
          "groups"
        ];
        text = ''
          home=${lib.escapeShellArg "/persist/home/${settings.username}"}
          if [ ! -d "$home" ]; then
            mkdir -p "$home"
            chmod 0700 "$home"
          fi
          chown ${owner} "$home"
        '';
      };
    };
}
