{
  lib,
  pkgs,
  settings,
  ...
}:

let
  # true: packages/pass-cli.nix. false: pkgs.proton-pass-cli
  pass-cli =
    if settings.useFlakePassCli or false then
      pkgs.callPackage ./packages/pass-cli.nix { }
    else
      pkgs.proton-pass-cli;

  scripts = import ./packages/scripts.nix { inherit pkgs pass-cli; };
in
{
  ephemeral.unfreePackages = [
    "steam"
    "steam-unwrapped"
    "vscode"
    "unrar"
  ];

  environment.persistence."/persist".directories = [
    "/var/lib/containers"
    "/var/lib/opensnitch"
  ];

  programs.steam = {
    enable = true;
    # firewall holes; leave off unless you use them
    remotePlay.openFirewall = false;
    dedicatedServer.openFirewall = false;
  };

  # programs.gamemode.enable = true;

  # rules persist under /var/lib/opensnitch
  services.opensnitch = {
    enable = true;
    settings = {
      DefaultAction = "deny";
      InterceptUnknown = true;
    };
  };

  environment.etc."xdg/autostart/opensnitch-ui.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=OpenSnitch
    Exec=${lib.getExe pkgs.opensnitch-ui}
    Icon=opensnitch-ui
    Comment=Interactive application firewall
    Terminal=false
    Categories=System;Security;Network;
    X-GNOME-Autostart-Delay=3
    X-GNOME-Autostart-enabled=true
  '';

  services.syncthing = {
    enable = true;
    user = settings.username;
    group = "users";
    dataDir = "/home/${settings.username}/Syncthing";
    configDir = "/home/${settings.username}/.config/syncthing";
    # true opens 22000 and 21027
    openDefaultPorts = false;
    overrideDevices = false;
    overrideFolders = false;
  };

  # rootless. group podman is the root socket, so the user is not in it.
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" ];
    };
  };

  # a dynamic loader at /lib64 for prebuilt binaries, like the ones VS Code
  # extensions download. nixpkgs ships curl, openssl, zlib and libstdc++ for it.
  programs.nix-ld.enable = true;

  environment.systemPackages =
    (with scripts; [
      ephemeral-update
      flatpak-apps
      smb-setup
      controld-setup
      update-pass-cli
      settings-from-pass
      ssh-pubs-from-pass
      luks-header-backup
    ])
    ++ (with pkgs; [
      vscode
      firefox
      brave-origin
      ghostty
      vlc
      git
      chezmoi
      curl
      wget
      ripgrep
      wl-clipboard
      htop
      dig
      mkpasswd
      unzip
      zip
      p7zip
      file
      usbutils
      pciutils
      wireguard-tools
      distrobox
      syncthingtray-minimal
      opensnitch-ui
      gum
      pass-cli

      neovim
      git-crypt
      age
      starship
      zoxide
      yazi
      btop
      fastfetch
      unrar
    ]);

  environment.sessionVariables = {
    TERMINAL = "ghostty";
    PROTON_PASS_LINUX_KEYRING = "dbus";
  };
}
