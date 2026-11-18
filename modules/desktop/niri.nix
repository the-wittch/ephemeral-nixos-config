{ config, ... }:
let
  nixos = config.ephemeral.aspects.nixos;

  niri =
    { config, pkgs, ... }:
    let
      package = config.programs.niri.package;

      # only that file, so the system doesn't keep the rest of niri's source
      defaults = pkgs.runCommand "niri-default-config.kdl" { } ''
        cp ${package.src}/resources/default-config.kdl $out
      '';

      # binds in a later file replace the same keys before it; Super+Alt+L started swaylock, which
      # isn't installed
      niriConfig = pkgs.writeText "niri-config.kdl" ''
        include "${defaults}"

        binds {
            Super+Alt+L hotkey-overlay-title="Lock the Screen" { spawn "noctalia" "msg" "session" "lock"; }
        }

        include optional=true "~/.config/niri/local.kdl"
      '';
    in
    {
      programs.niri.enable = true;
      environment.systemPackages = with pkgs; [
        xwayland-satellite
        fuzzel
      ];

      # niri reads this only while ~/.config/niri/config.kdl doesn't exist; your own changes go
      # in ~/.config/niri/local.kdl
      environment.etc."niri/config.kdl".source =
        pkgs.runCommand "niri-config.kdl" { nativeBuildInputs = [ package ]; }
          ''
            HOME=$TMPDIR niri validate -c ${niriConfig}
            cp ${niriConfig} $out
          '';
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
