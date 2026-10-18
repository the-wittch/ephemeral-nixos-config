{
  lib,
  pkgs,
  settings,
  ...
}:

let
  chezmoiRepo = settings.chezmoiRepo or "";
  chezmoiEnabled = chezmoiRepo != "";
in
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
  };
  users.defaultUserShell = pkgs.zsh;

  users.mutableUsers = false;
  users.users.${settings.username} = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "lp"
      "dialout"
    ];
    hashedPasswordFile = "/persist/passwords/${settings.username}";
  };
  users.users.root.hashedPassword = "!";

  security.sudo = {
    execWheelOnly = true;
    extraConfig = ''
      Defaults lecture = never
    '';
  };

  systemd.user.services.chezmoi-init = lib.mkIf chezmoiEnabled {
    description = "Initialize chezmoi from settings.chezmoiRepo";
    wantedBy = [ "default.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecCondition = "${pkgs.bash}/bin/bash -c '! test -d %h/.local/share/chezmoi'";
      ExecStart = "${pkgs.chezmoi}/bin/chezmoi init --apply ${lib.escapeShellArg chezmoiRepo}";
      RemainAfterExit = true;
    };
  };
}
