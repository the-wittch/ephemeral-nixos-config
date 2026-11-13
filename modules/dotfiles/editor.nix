{
  # weakest priority: VS Code from extras wins over it, and a value of yours over both
  flake.modules.homeManager.dotfiles =
    { lib, ... }:
    {
      home.sessionVariables = {
        EDITOR = lib.mkOptionDefault "nvim";
        VISUAL = lib.mkOptionDefault "nvim";
      };
    };

  flake.modules.homeManager.extras =
    { lib, ... }:
    {
      home.sessionVariables = {
        EDITOR = lib.mkDefault "code --wait";
        VISUAL = lib.mkDefault "code --wait";
      };
    };
}
