{
  flake.modules.nixos.full =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      hardware.sane = {
        enable = true;
        extraBackends = [ pkgs.sane-airscan ];
      };
      users.users.${config.ephemeral.settings.username}.extraGroups = [ "scanner" ];
      environment.systemPackages = lib.optional (
        config.ephemeral.settings.desktop != "none"
      ) pkgs.simple-scan;
    };
}
