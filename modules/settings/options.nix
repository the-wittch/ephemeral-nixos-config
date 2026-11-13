{
  flake.modules.nixos.base =
    { lib, ... }:
    let
      inherit (lib) mkOption types;
    in
    {
      imports = [ ./_schema.nix ];

      options.ephemeral = {
        pickedApps = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Apps from apps.json, picked with ephemeral-apps.";
        };

        smbShares = mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                server = mkOption { type = types.strMatching "[A-Za-z0-9._:-]+"; };
                share = mkOption { type = types.strMatching "[A-Za-z0-9._$ -]+"; };
                mountPoint = mkOption {
                  type = types.strMatching "/(mnt|media|home/[a-z_][a-z0-9_-]*)/[A-Za-z0-9._/-]+";
                };
                credentials = mkOption { type = types.strMatching "/persist/etc/smb/[A-Za-z0-9_-]+\\.creds"; };
              };
            }
          );
          default = [ ];
          description = "CIFS mounts written by smb-setup to smb-shares.json.";
        };
      };
    };
}
