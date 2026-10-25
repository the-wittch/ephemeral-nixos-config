{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # helix
  ];

  # unfree packages must be named, e.g. for pkgs.vscode-fhs:
  # ephemeral.unfreePackages = [ "vscode" ];

  # services.syncthing.openDefaultPorts = true;
}
