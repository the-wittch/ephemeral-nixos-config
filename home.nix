{
  settings,
  ...
}:

{
  home.username = settings.username;
  home.homeDirectory = "/home/${settings.username}";
  home.stateVersion = "25.05";

  # chezmoi owns zsh/git/editors. zsh hook is programs.direnv in configuration.nix.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = false;
    enableBashIntegration = false;
    enableFishIntegration = false;
    config.global = {
      strict_env = true;
      disable_stdin = true;
    };
  };
}
