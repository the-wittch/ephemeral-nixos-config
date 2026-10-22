{
  lib,
  pkgs,
  settings,
  ...
}:

let
  home = "/home/${settings.username}";
  chezmoiSource = "${home}/.local/share/chezmoi";
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

  # /persist/etc/chezmoi-repo is "<git-url> <commit>", mode 600, owned by the user.
  systemd.services.chezmoi-init = {
    description = "Initialize chezmoi from /persist/etc/chezmoi-repo";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [
      pkgs.git
      pkgs.chezmoi
      pkgs.coreutils
    ];
    unitConfig.ConditionPathExists = [
      "/persist/etc/chezmoi-repo"
      "!${chezmoiSource}"
    ];
    serviceConfig = {
      Type = "oneshot";
      User = settings.username;
      Group = "users";
      WorkingDirectory = home;
      Environment = "HOME=${home}";
    };
    script = ''
      set -euo pipefail
      line=$(head -n 1 /persist/etc/chezmoi-repo | tr -d '\r')
      read -r url rev extra <<<"$line"
      if [[ -z ''${url:-} || -z ''${rev:-} || -n ''${extra:-} ]]; then
        echo "/persist/etc/chezmoi-repo must be one line: <git-url> <commit>" >&2
        exit 1
      fi
      if [[ ! $rev =~ ^[0-9a-fA-F]{7,64}$ ]]; then
        echo "chezmoi commit must be 7-64 hex chars" >&2
        exit 1
      fi
      case $url in
        https://* | ssh://* | git@*) ;;
        *)
          echo "chezmoi url must start with https://, ssh://, or git@" >&2
          exit 1
          ;;
      esac

      dest=${lib.escapeShellArg chezmoiSource}
      mkdir -p "$(dirname "$dest")"
      cleanup() { rm -rf "$dest"; }
      trap cleanup ERR
      git clone -- "$url" "$dest"
      git -C "$dest" checkout --detach "$rev"
      chezmoi init --apply
      trap - ERR
    '';
  };
}
