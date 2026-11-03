{
  flake.modules.homeManager.dotfiles =
    { lib, ... }:
    {
      home.sessionVariables = {
        EDITOR = lib.mkDefault "nvim";
        VISUAL = lib.mkDefault "nvim";
      };
    };

  # VS Code comes with extras
  flake.modules.homeManager.extras =
    { lib, ... }:
    {
      home.sessionVariables = {
        EDITOR = lib.mkOverride 900 "code --wait";
        VISUAL = lib.mkOverride 900 "code --wait";
      };
    };
}
