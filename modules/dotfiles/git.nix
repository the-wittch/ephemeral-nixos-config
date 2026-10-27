{
  flake.modules.homeManager.dotfiles = {
    programs.git = {
      enable = true;
      settings = {
        init.defaultBranch = "main";
        push.autoSetupRemote = true;
      };
    };
  };
}
