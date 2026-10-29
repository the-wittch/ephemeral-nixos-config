{
  flake.modules.nixos.full = {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
      settings.global = {
        strict_env = true;
        disable_stdin = true;
      };
    };
  };
}
