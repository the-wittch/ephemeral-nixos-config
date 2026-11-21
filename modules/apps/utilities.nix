{
  ephemeral.apps = {
    # VPN types for NetworkManager, so their connections are set up in the network settings
    networkmanager-openvpn = {
      label = "OpenVPN";
      category = "Utilities";
      description = "OpenVPN connections in the network settings; imports .ovpn files";
      nixos =
        { pkgs, ... }:
        {
          networking.networkmanager.plugins = [ pkgs.networkmanager-openvpn ];
        };
    };
    networkmanager-openconnect = {
      label = "OpenConnect";
      category = "Utilities";
      description = "Cisco AnyConnect and GlobalProtect and Fortinet and Pulse VPNs in the network settings";
      nixos =
        { pkgs, ... }:
        {
          networking.networkmanager.plugins = [ pkgs.networkmanager-openconnect ];
        };
    };
    networkmanager-strongswan = {
      label = "strongSwan";
      category = "Utilities";
      description = "IPsec and IKEv2 VPNs in the network settings";
      nixos =
        { pkgs, ... }:
        {
          networking.networkmanager.plugins = [ pkgs.networkmanager_strongswan ];
        };
    };
    gnome-tweaks = {
      label = "GNOME Tweaks";
      category = "Utilities";
      description = "fonts and window buttons GNOME's settings don't show";
      package = "gnome-tweaks";
      desktops = [ "gnome" ];
      default = true;
    };
    gnome-extension-manager = {
      label = "Extension Manager";
      category = "Utilities";
      description = "find and install GNOME Shell extensions";
      package = "gnome-extension-manager";
      desktops = [ "gnome" ];
      default = true;
    };
    discover = {
      label = "Discover";
      category = "Utilities";
      description = "KDE's app store for Flathub apps";
      package = "kdePackages.discover";
      desktops = [ "plasma" ];
      default = true;
    };
    partitionmanager = {
      label = "Partition Manager";
      category = "Utilities";
      description = "KDE's disk and partition editor";
      package = "kdePackages.partitionmanager";
      desktops = [ "plasma" ];
      default = true;
    };
    syncthingtray = {
      label = "Syncthing Tray";
      category = "Utilities";
      description = "Syncthing's status and folders in the tray";
      package = "syncthingtray-minimal";
      default = true;
    };
    p7zip = {
      label = "7-Zip";
      category = "Utilities";
      description = "7z and other archives in the terminal";
      package = "p7zip";
      default = true;
    };
    unrar = {
      label = "unrar";
      category = "Utilities";
      description = "extract RAR archives";
      package = "unrar";
      unfree = [ "unrar" ];
    };
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
    rustdesk = {
      label = "RustDesk";
      category = "Utilities";
      description = "remote desktop that works through NAT";
      package = "rustdesk-flutter";
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
