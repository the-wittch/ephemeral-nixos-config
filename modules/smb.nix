{
  flake.modules.nixos.full =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      shares = config.ephemeral.smbShares;
      user = config.users.users.${config.ephemeral.settings.username};
    in
    {
      assertions = map (s: {
        assertion = !lib.hasInfix ".." s.mountPoint;
        message = "smb-shares.json: ${s.mountPoint} can't contain ..";
      }) shares;

      environment.systemPackages = [ pkgs.cifs-utils ];

      systemd.tmpfiles.rules = [
        "d /persist/etc/smb 0700 root root -"
        "z /persist/etc/smb/* 0600 - - -"
      ];

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
    };
}
