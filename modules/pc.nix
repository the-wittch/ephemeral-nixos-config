{ config, ... }:
{
  flake.modules.nixos.pc.imports = [ config.ephemeral.aspects.nixos.base ];
}
