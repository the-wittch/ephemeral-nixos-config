# The apps host-builder.nix picks for one of tests/'s machines, as a module, so a test machine
# put together from aspects gets the same apps as an install instead of drifting from it.
{ config, lib }:
host:
let
  picked = config.flake.nixosConfigurations.${host}.config.ephemeral.pickedApps;
  catalog = config.ephemeral.apps;
in
{
  imports = map (id: catalog.${id}.nixos) (builtins.filter (id: catalog ? ${id}) picked);
  ephemeral.pickedApps = picked;
}
