{
  lib,
  pkgs,
  settings,
  ...
}:

{
  imports = [
    ./boot.nix
    ./persist.nix
    ./users.nix
    ./unfree.nix
    ./hardening.nix
    ./flathub.nix
    ./desktop.nix
    ./dns.nix # Control D
    ./apps.nix
    ./smb.nix # mounts from smb-setup
    ./snapshots.nix # snapper on /persist
  ];

  networking.hostName = settings.hostname;

  hardware.enableRedistributableFirmware = true;

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.power-profiles-daemon.enable = true;

  services.printing.enable = true;
  services.avahi = {
    enable = false;
    nssmdns4 = true;
    openFirewall = true;
  };

  services.fwupd.enable = true;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableSystemSlice = true;
    enableUserSlices = true;
  };

  fonts.packages = with pkgs; [
    noto-fonts-color-emoji
    noto-fonts-cjk-sans
    liberation_ttf
  ];

  programs.dconf.enable = true;

  # /etc, not ~/.zshrc, so chezmoi can keep the rc file
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    settings.global = {
      strict_env = true;
      disable_stdin = true;
    };
  };

  networking.networkmanager = {
    enable = true;
    plugins = with pkgs; [
      networkmanager-openvpn
    ];
  };
  networking.firewall.enable = true;

  # off unless a host turns it on. keys stay on /persist either way.
  services.openssh = {
    enable = lib.mkDefault false;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
      AllowAgentForwarding = false;
    };
    hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  time.timeZone = settings.timeZone;
  i18n.defaultLocale = "en_US.UTF-8";

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [ "root" ];
      # only admins talk to the nix daemon
      allowed-users = [ "@wheel" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  system.stateVersion = "25.05";
}
