{
  flake.modules.homeManager.dotfiles =
    { lib, ... }:
    {
      home.sessionVariables = {
        EDITOR = lib.mkDefault "code --wait";
        VISUAL = lib.mkDefault "code --wait";
      };
    };
}
