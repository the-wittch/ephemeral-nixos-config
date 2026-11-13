{
  # once, at the first graphical login, on every desktop and both profiles
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      systemd.user.services.ephemeral-welcome = {
        description = "Say where to start, once";
        wantedBy = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        unitConfig.ConditionPathExists = "!%S/ephemeral/welcomed";
        serviceConfig.Type = "oneshot";
        path = [ pkgs.libnotify ];
        # marked only once the notification was shown, so a desktop still starting gets it next time
        script = ''
          sleep 5
          notify-send --app-name="Ephemeral Nix" "Welcome to Ephemeral Nix" \
            "ephemeral-help lists the commands, and ephemeral-apps adds apps. / is wiped at every boot; your home folder is kept."
          mkdir -p "$STATE_DIRECTORY"
          touch "$STATE_DIRECTORY/welcomed"
        '';
        serviceConfig.StateDirectory = "ephemeral";
      };
    };
}
