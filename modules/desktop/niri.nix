{ config, ... }:
let
  nixos = config.ephemeral.aspects.nixos;

  niri =
    { pkgs, ... }:
    {
      programs.niri.enable = true;
      environment.systemPackages = with pkgs; [
        xwayland-satellite
        fuzzel
      ];
    };
in
{
  flake.modules.nixos.niri.imports = [
    niri
    nixos.noctalia
  ];

  flake.modules.nixos."minimal-niri".imports = [
    niri
    nixos.noctalia-base
  ];
}
