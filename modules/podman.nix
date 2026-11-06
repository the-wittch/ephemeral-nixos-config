{
  flake.modules.nixos.pc = {
    environment.persistence."/persist".directories = [ "/var/lib/containers" ];

    # rootless; don't add yourself to the podman group, it's root-equivalent
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
        flags = [ "--all" ];
      };
    };
  };
}
