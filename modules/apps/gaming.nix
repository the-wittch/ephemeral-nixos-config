{
  ephemeral.apps = {
    lutris = {
      label = "Lutris";
      category = "Gaming";
      description = "game launcher for many stores and emulators";
      flatpak = "net.lutris.Lutris";
    };
    heroic = {
      label = "Heroic";
      category = "Gaming";
      description = "Epic and GOG and Amazon games";
      flatpak = "com.heroicgameslauncher.hgl";
    };
    prismlauncher = {
      label = "Prism Launcher";
      category = "Gaming";
      description = "Minecraft launcher";
      flatpak = "org.prismlauncher.PrismLauncher";
    };
    gamemode = {
      label = "GameMode";
      category = "Gaming";
      description = "raise performance while a game runs";
      nixos.programs.gamemode.enable = true;
    };
    mangohud = {
      label = "MangoHud";
      category = "Gaming";
      description = "FPS and temperature overlay";
      package = "mangohud";
    };
    protonup-qt = {
      label = "ProtonUp-Qt";
      category = "Gaming";
      description = "install Proton-GE and Wine-GE";
      package = "protonup-qt";
    };
  };
}
