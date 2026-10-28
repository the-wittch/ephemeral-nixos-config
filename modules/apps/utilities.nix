{
  ephemeral.apps = {
    flatseal = {
      label = "Flatseal";
      category = "Utilities";
      description = "change Flatpak permissions";
      flatpak = "com.github.tchx84.Flatseal";
    };
    gearlever = {
      label = "Gear Lever";
      category = "Utilities";
      description = "manage AppImages";
      flatpak = "it.mijorus.gearlever";
    };
    vorta = {
      label = "Vorta";
      category = "Utilities";
      description = "Borg backups";
      flatpak = "com.borgbase.Vorta";
    };
    pikabackup = {
      label = "Pika Backup";
      category = "Utilities";
      description = "simple Borg backups";
      flatpak = "org.gnome.World.PikaBackup";
    };
    remmina = {
      label = "Remmina";
      category = "Utilities";
      description = "remote desktop client";
      flatpak = "org.remmina.Remmina";
    };
    localsend = {
      label = "LocalSend";
      category = "Utilities";
      description = "send files to nearby devices";
      warn = "opens port 53317 on the local network";
      nixos.programs.localsend = {
        enable = true;
        openFirewall = true;
      };
    };
    gparted = {
      label = "GParted";
      category = "Utilities";
      description = "partition editor";
      package = "gparted";
    };
    qbittorrent = {
      label = "qBittorrent";
      category = "Utilities";
      description = "torrent client";
      package = "qbittorrent";
    };
  };
}
