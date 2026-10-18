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
  user = config.users.users.${settings.username};
  uidStr = toString user.uid;
  gidStr = toString config.users.groups.${user.group}.gid;
in
{
  environment.systemPackages = [ pkgs.cifs-utils ];

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
          "uid=${uidStr}"
          "gid=${gidStr}"
        ];
      };
    }) shares
  );
}
