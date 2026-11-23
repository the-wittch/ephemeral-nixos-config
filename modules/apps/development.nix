{
  ephemeral.apps = {
    vscode = {
      label = "VS Code";
      category = "Development";
      description = "Microsoft's code editor (also set as $EDITOR)";
      package = "vscode";
      unfree = [ "vscode" ];
      homeManager =
        { lib, ... }:
        {
          home.sessionVariables = {
            EDITOR = lib.mkDefault "code --wait";
            VISUAL = lib.mkDefault "code --wait";
          };
        };
    };
    distrobox = {
      label = "Distrobox";
      category = "Development";
      description = "other Linux distros in Podman containers";
      package = "distrobox";
    };
    git-crypt = {
      label = "git-crypt";
      category = "Development";
      description = "encrypt chosen files in a git repo";
      package = "git-crypt";
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
          # the mode dockerd gives it when it starts
          preservation.preserveAt."/persist".directories = [
            {
              directory = "/var/lib/docker";
              mode = "0710";
            }
          ];
          users.users.${config.ephemeral.settings.username}.extraGroups = [ "docker" ];
        };
    };
  };
}
