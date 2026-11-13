{
  flake.modules.nixos.base =
    { config, lib, ... }:
    {
      networking.hostName = config.ephemeral.settings.hostname;
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      system.stateVersion = "25.05";
    };
}
