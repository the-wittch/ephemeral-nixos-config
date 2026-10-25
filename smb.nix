{
  lib,
  pkgs,
  config,
  settings,
  flakeRoot,
  ...
}:

let
  sharesFile = flakeRoot + "/smb-shares.nix";
  shares = if builtins.pathExists sharesFile then import sharesFile else [ ];
  # names, not numbers. users.users.<name>.uid is null unless set.
  user = config.users.users.${settings.username};
in
{
  environment.systemPackages = [ pkgs.cifs-utils ];

  system.activationScripts.smbSecrets.text = ''
    mkdir -p /persist/etc/smb
    chmod 700 /persist/etc/smb
    for f in /persist/etc/smb/*; do
      if [ -e "$f" ]; then
        chmod 600 "$f"
      fi
    done
  '';

  # smb-setup writes smb-shares.nix. example:
  # { server = "nas.local"; share = "files"; mountPoint = "/mnt/files"; credentials = "/persist/etc/smb/files.creds"; }
  fileSystems = lib.mkMerge (
    map (s: {
      ${s.mountPoint} = {
        device = "//${s.server}/${s.share}";
        fsType = "cifs";
        options = [
          "credentials=${s.credentials}"
          "_netdev"
          "nofail"
          "seal"
          "vers=3.1.1"
          "sec=ntlmssp"
          "uid=${user.name}"
          "gid=${user.group}"
        ];
      };
    }) shares
  );
}
