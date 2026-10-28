{
  flake.modules.homeManager.dotfiles = {
    programs.ghostty = {
      enable = true;
      # installed system-wide
      package = null;
      systemd.enable = false;
      enableZshIntegration = true;
    };
  };
}
