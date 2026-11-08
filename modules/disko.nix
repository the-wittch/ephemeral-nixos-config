{ inputs, ... }:
{
  flake.modules.nixos.base =
    { config, ... }:
    {
      imports = [ inputs.disko.nixosModules.disko ];

      disko.devices = import ./_disko-layout.nix {
        device = config.ephemeral.settings.diskDevice;
        inherit (config.ephemeral.settings) swapSize;
      };
    };
}
