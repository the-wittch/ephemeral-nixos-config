{
  flake.modules.nixos.full =
    { config, pkgs, ... }:
    {
      hardware.sane = {
        enable = true;
        extraBackends = [ pkgs.sane-airscan ];
      };
      users.users.${config.ephemeral.settings.username}.extraGroups = [ "scanner" ];
      environment.systemPackages = [ pkgs.simple-scan ];
    };
}
