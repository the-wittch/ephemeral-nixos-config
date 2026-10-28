{
  flake.modules.homeManager.extras = {
    programs.atuin = {
      enable = true;
      flags = [ "--disable-up-arrow" ];
      settings = {
        auto_sync = false;
        update_check = false;
        style = "compact";
      };
    };
  };
}
