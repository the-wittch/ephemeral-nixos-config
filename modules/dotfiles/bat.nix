{
  flake.modules.homeManager.extras = {
    programs.bat.enable = true;
    programs.tealdeer = {
      enable = true;
      settings.updates.auto_update = true;
    };
  };
}
