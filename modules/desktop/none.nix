let
  headless =
    { config, lib, ... }:
    {
      assertions = [
        {
          assertion = config.ephemeral.settings.server;
          message = ''"desktop": "none" needs "server": true; without a screen, SSH is the only way in.'';
        }
      ];
      # no splash without a screen; the passphrase is asked on the console, or over SSH
      boot.plymouth.enable = lib.mkForce false;
    };
in
{
  flake.modules.nixos.none = headless;
  flake.modules.nixos."minimal-none" = headless;
}
