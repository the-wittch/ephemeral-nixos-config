{
  # weakest priority: VS Code from ephemeral-apps wins over it, and a value of yours over both
  flake.modules.homeManager.dotfiles =
    { lib, ... }:
    {
      home.sessionVariables = {
        EDITOR = lib.mkOptionDefault "nvim";
        VISUAL = lib.mkOptionDefault "nvim";
      };
    };
}
