{
  flake.modules.homeManager.extras = {
    programs.yazi = {
      enable = true;
      shellWrapperName = "y";
    };
    programs.btop.enable = true;
    programs.fastfetch.enable = true;
  };
}
