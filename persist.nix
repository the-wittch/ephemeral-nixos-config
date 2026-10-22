{
  config,
  lib,
  settings,
  ...
}:

{
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/log".neededForBoot = true;

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/home"
      "/var/lib/nixos"
      "/var/lib/AccountsService"
      "/var/lib/systemd"
      "/var/lib/bluetooth"
      "/var/lib/NetworkManager"
      "/var/lib/cups"
      "/var/lib/flatpak"
      "/var/lib/fwupd"
      "/var/lib/containers"
      "/var/lib/opensnitch"
      "/etc/NetworkManager/system-connections"
    ];
    files = [
      "/etc/machine-id"
    ];
  };

  # blank root drops /home/$USER. create it here.
  system.activationScripts.ensureUserHome = {
    deps = [ "users" "groups" ];
    text = ''
      home=${lib.escapeShellArg "/persist/home/${settings.username}"}
      if [ ! -d "$home" ]; then
        mkdir -p "$home"
        chmod 0700 "$home"
      fi
      chown ${
        lib.escapeShellArg "${settings.username}:${config.users.users.${settings.username}.group}"
      } "$home"
    '';
  };

  system.activationScripts.persistSecrets = {
    deps = [ "users" ];
    text = ''
      mkdir -p /persist/passwords
      chmod 700 /persist/passwords
      for f in /persist/passwords/*; do
        if [ -e "$f" ]; then
          chmod 600 "$f"
        fi
      done

      mkdir -p /persist/etc/ssh
      chmod 755 /persist/etc/ssh
      for f in /persist/etc/ssh/ssh_host_*_key; do
        if [ -f "$f" ]; then
          chmod 600 "$f"
        fi
      done
      for f in /persist/etc/ssh/ssh_host_*_key.pub; do
        if [ -f "$f" ]; then
          chmod 644 "$f"
        fi
      done

      mkdir -p /persist/etc/smb
      chmod 700 /persist/etc/smb
      for f in /persist/etc/smb/*; do
        if [ -e "$f" ]; then
          chmod 600 "$f"
        fi
      done

      if [ -f /persist/etc/controld-resolver ]; then
        chown root:root /persist/etc/controld-resolver
        chmod 600 /persist/etc/controld-resolver
      fi
      if [ -f /persist/etc/chezmoi-repo ]; then
        chown ${settings.username}:users /persist/etc/chezmoi-repo
        chmod 600 /persist/etc/chezmoi-repo
      fi
    '';
  };
}
