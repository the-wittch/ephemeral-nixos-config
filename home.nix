{
  lib,
  pkgs,
  settings,
  ...
}:

let
  desktop = settings.desktop;
  isPlasma = desktop == "plasma";
  isNiri = desktop == "niri";
  kwriteconfig = lib.getExe' pkgs.kdePackages.kconfig "kwriteconfig6";
  kdeDark = import ./lib/kde-dark.nix { inherit lib; };
in
{
  home.username = settings.username;
  home.homeDirectory = "/home/${settings.username}";
  home.stateVersion = "25.05";

  gtk = {
    enable = true;
    colorScheme = "dark";
    theme =
      if isPlasma then
        {
          name = "Breeze-Dark";
          package = pkgs.kdePackages.breeze-gtk;
        }
      else
        {
          name = "Adwaita-dark";
          package = pkgs.gnome-themes-extra;
        };
    gtk4.theme = null; # css here restyles libadwaita
  };

  # kwriteconfig, not a symlink. plasma rewrites this file.
  home.activation = lib.mkIf isPlasma {
    plasmaColorScheme = lib.hm.dag.entryAfter [ "writeBoundary" ] (kdeDark.kwriteScript kwriteconfig);
  };

  # nixos already starts the user service
  programs.noctalia = lib.mkIf isNiri {
    enable = true;
    settings = {
      theme = {
        mode = "dark";
        shell_mode = "dark";
      };
      shell.greeter_sync.auto_sync = true;
    };
  };

  # chezmoi owns zsh/git/editors. zsh hook is programs.direnv in configuration.nix.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = false;
    enableBashIntegration = false;
    enableFishIntegration = false;
    config.global = {
      strict_env = true;
      disable_stdin = true;
    };
  };
}
