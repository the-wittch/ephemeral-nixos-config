{ inputs, ... }:
{
  imports = [ inputs.ephemeral.flakeModules.default ];

  systems = [ "x86_64-linux" ];

  ephemeral.hosts.nixos.root = ../.;
}
