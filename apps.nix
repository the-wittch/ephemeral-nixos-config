{
  lib,
  pkgs,
  settings,
  ...
}:

let
  flatpak-apps = pkgs.writeShellApplication {
    name = "flatpak-apps";
    runtimeInputs = with pkgs; [
      gum
      flatpak
      gnugrep
      coreutils
    ];
    text = builtins.readFile ./scripts/flatpak-tui.sh;
  };

  smb-setup = pkgs.writeShellApplication {
    name = "smb-setup";
    runtimeInputs = with pkgs; [
      gum
      coreutils
      gnugrep
      gnused
    ];
    text = builtins.readFile ./scripts/smb-setup.sh;
  };

  update-pass-cli = pkgs.writeShellApplication {
    name = "update-pass-cli";
    runtimeInputs = with pkgs; [
      curl
      python3
      gnused
      gnugrep
      gawk
      coreutils
      nix
    ];
    text = builtins.readFile ./scripts/update-pass-cli.sh;
  };

  # Flip settings.useFlakePassCli = false when nixpkgs ships pkgs.pass-cli.
  pass-cli =
    if settings.useFlakePassCli or true then
      pkgs.callPackage ./packages/pass-cli.nix { }
    else
      pkgs.pass-cli or (throw ''
        settings.useFlakePassCli = false but pkgs.pass-cli is missing.
        Keep useFlakePassCli = true, or wait for nixpkgs.
      '');

  settings-from-pass = pkgs.writeShellApplication {
    name = "settings-from-pass";
    runtimeInputs = [
      pass-cli
      pkgs.coreutils
      pkgs.gnused
    ];
    text = builtins.readFile ./scripts/settings-from-pass.sh;
  };

  ssh-pubs-from-pass = pkgs.writeShellApplication {
    name = "ssh-pubs-from-pass";
    runtimeInputs = [
      pass-cli
      pkgs.coreutils
      pkgs.python3
      pkgs.gnused
    ];
    text = builtins.readFile ./scripts/ssh-pubs-from-pass.sh;
  };
in
{
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

  services.flatpak.enable = true;

  systemd.services.flatpak-flathub = {
    description = "Add Flathub Flatpak remote";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      flatpak remote-add --system --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    '';
  };

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

  environment.systemPackages = with pkgs; [
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
    flatpak-apps
    smb-setup
    pass-cli
    update-pass-cli
    settings-from-pass
    ssh-pubs-from-pass

    neovim
    git-crypt
    age
    starship
    zoxide
    yazi
    btop
    fastfetch
    unrar
  ];

  environment.sessionVariables = {
    TERMINAL = "ghostty";
    PROTON_PASS_LINUX_KEYRING = "dbus";
  };
}

