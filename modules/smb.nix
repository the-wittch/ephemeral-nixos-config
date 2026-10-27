{
  flake.modules.nixos.base =
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
