{
  ephemeral.apps = {
    lazygit = {
      label = "lazygit";
      category = "Development";
      description = "git in the terminal";
      package = "lazygit";
    };
    just = {
      label = "just";
      category = "Development";
      description = "command runner";
      package = "just";
    };
    zed = {
      label = "Zed";
      category = "Development";
      description = "fast code editor";
      package = "zed-editor";
    };
    dbeaver = {
      label = "DBeaver";
      category = "Development";
      description = "database client";
      package = "dbeaver-bin";
    };
    docker = {
      label = "Docker";
      category = "Development";
      description = "the real Docker in place of Podman's docker command";
      warn = "you're added to the docker group; it's root-equivalent";
      nixos =
        { config, lib, ... }:
        {
          virtualisation.docker.enable = true;
          virtualisation.podman.dockerCompat = lib.mkForce false;
          environment.persistence."/persist".directories = [ "/var/lib/docker" ];
          users.users.${config.ephemeral.settings.username}.extraGroups = [ "docker" ];
        };
    };
  };
}
