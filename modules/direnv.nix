{
  flake.modules.nixos.pc = {
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
