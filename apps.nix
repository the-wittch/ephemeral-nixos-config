{
  lib,
  pkgs,
  settings,
  ...
}:

let
  # scripts/lib.sh goes first so every command gets die and nix_escape
  mkScript =
    name: file: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile ./scripts/lib.sh + builtins.readFile file;
    };

  # true: packages/pass-cli.nix. false: pkgs.proton-pass-cli
  pass-cli =
    if settings.useFlakePassCli or false then
      pkgs.callPackage ./packages/pass-cli.nix { }
    else
      pkgs.proton-pass-cli;

  scripts = with pkgs; [
    (mkScript "ephemeral-update" ./scripts/ephemeral-update.sh [ ])
    (mkScript "flatpak-apps" ./scripts/flatpak-tui.sh [
      gum
      flatpak
      gnugrep
      coreutils
    ])
    (mkScript "smb-setup" ./scripts/smb-setup.sh [
      gum
      coreutils
      gnugrep
      gnused
    ])
    (mkScript "controld-setup" ./scripts/controld-setup.sh [
      gum
      coreutils
      gnugrep
      gnused
      gawk
    ])
    (mkScript "update-pass-cli" ./scripts/update-pass-cli.sh [
      curl
      python3
      gnused
      gnugrep
      gawk
      coreutils
      nix
    ])
    (mkScript "settings-from-pass" ./scripts/settings-from-pass.sh [
      pass-cli
      coreutils
      gnused
    ])
    (mkScript "ssh-pubs-from-pass" ./scripts/ssh-pubs-from-pass.sh [
      pass-cli
      coreutils
      python3
      gnused
    ])
  ];
in
{
  environment.persistence."/persist".directories = [
    "/var/lib/flatpak"
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

  environment.systemPackages =
    scripts
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
