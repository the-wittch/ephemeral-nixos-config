# What a machine with a screen has besides pc: sound, fonts, the user picture, Flathub, the
# user folders and the welcome notification. Each desktop imports it; a headless server doesn't.
{ config, ... }:
{
  flake.modules.nixos.graphical.imports = [ config.ephemeral.aspects.nixos.pc ];
}
