{
  flake.modules.nixos.minimal =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # the full profile gets apps from ephemeral-apps; a headless server has no use for the
      # browser and player
      environment.systemPackages =
        with pkgs;
        [
          htop
          ripgrep
          dig
          wireguard-tools
          vim
          distrobox
          p7zip
        ]
        ++ lib.optionals (config.ephemeral.settings.desktop != "none") [
          firefox
          vlc
        ];

      # no home manager on first boot, so the system zshrc does completion
      programs.zsh.enableCompletion = true;
    };
}
