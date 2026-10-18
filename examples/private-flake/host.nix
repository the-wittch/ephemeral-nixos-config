{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # helix
  ];

  # services.syncthing.openDefaultPorts = true;
}
