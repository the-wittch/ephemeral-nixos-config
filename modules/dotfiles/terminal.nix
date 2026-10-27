{
  flake.modules.homeManager.dotfiles = {
    programs.ghostty = {
      enable = true;
      # installed with the desktop apps
      package = null;
      systemd.enable = false;
      enableZshIntegration = true;
    };

    programs.yazi = {
      enable = true;
      shellWrapperName = "y";
    };
    programs.btop.enable = true;
    programs.fastfetch.enable = true;
  };
}
