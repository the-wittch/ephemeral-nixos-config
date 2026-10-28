{
  flake.modules.homeManager.extras = {
    programs.fzf = {
      enable = true;
      # atuin owns ctrl-r
      historyWidget.command = "";
    };
  };
}
