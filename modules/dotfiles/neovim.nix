{
  flake.modules.homeManager.dotfiles = {
    programs.neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      withPython3 = false;
      withRuby = false;
    };
  };
}
