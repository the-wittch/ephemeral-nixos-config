{ config, ... }:
let
  catalog = config.ephemeral.apps;
in
{
  flake.modules.nixos.full =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      picked = config.ephemeral.pickedApps;
      apps = map (id: catalog.${id}) (builtins.filter (id: catalog ? ${id}) picked);
      unknown = builtins.filter (id: !(catalog ? ${id})) picked;
      flatpaks = lib.concatMap (app: lib.optional (app.flatpak != null) app.flatpak) apps;
      # Flathub only comes with a desktop
      withFlathub = config.ephemeral.settings.desktop != "none";
      flatpak = config.services.flatpak.package;
      updates = withFlathub && config.ephemeral.settings.flatpakUpdates;
    in
    {
      warnings = map (id: "apps.json: ${id} isn't in the app catalog, so it's skipped") unknown;

      environment.systemPackages = lib.concatMap (
        app: lib.optional (app.package != null) (lib.getAttrFromPath (lib.splitString "." app.package) pkgs)
      ) apps;
      ephemeral.unfreePackages = lib.concatMap (app: app.unfree) apps;
      home-manager.sharedModules = map (app: app.homeManager) apps;

      systemd.user.services.ephemeral-flatpaks = lib.mkIf withFlathub {
        description = "Install the Flatpaks picked with ephemeral-apps";
        wantedBy = [ "default.target" ];
        unitConfig.ConditionUser = "!@system";
        path = [ flatpak ];
        serviceConfig.Type = "oneshot";
        script = ''
          state=''${XDG_STATE_HOME:-$HOME/.local/state}/ephemeral
          mkdir -p "$state"
          wanted=(${lib.escapeShellArgs flatpaks})
          flatpak remote-add --user --if-not-exists flathub ${config.ephemeral.flathubRepo}
          for id in "''${wanted[@]}"; do
            flatpak info --user "$id" >/dev/null 2>&1 \
              || flatpak install --user --noninteractive flathub "$id" \
              || echo "could not install $id now; it's tried again at the next login" >&2
          done
          # only what this service put there before
          if [[ -f $state/flatpaks ]]; then
            while read -r id; do
              [[ -n $id && " ''${wanted[*]} " != *" $id "* ]] || continue
              flatpak uninstall --user --noninteractive "$id" || true
            done <"$state/flatpaks"
          fi
          printf '%s\n' "''${wanted[@]}" >"$state/flatpaks"
        '';
      };

      # nothing else updates them on niri and Umbriel, or on GNOME and Plasma when their software
      # centre isn't open
      systemd.user.services.flatpak-update = lib.mkIf updates {
        description = "Update the Flatpak apps and runtimes";
        after = [ "ephemeral-flatpaks.service" ];
        unitConfig = {
          ConditionUser = "!@system";
          ConditionACPower = true;
        };
        path = [ flatpak ];
        serviceConfig.Type = "oneshot";
        script = ''
          flatpak update --user --noninteractive
          flatpak uninstall --user --unused --noninteractive
        '';
      };
      systemd.user.timers.flatpak-update = lib.mkIf updates {
        description = "Update the Flatpak apps and runtimes once a week";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          # spread over the week, so a household's machines don't all fetch at once
          RandomizedDelaySec = "6d";
          Persistent = true;
        };
      };

      # the installs and updates are unattended, so nobody would be there to answer OpenSnitch
      services.opensnitch.rules.flatpak-flathub = lib.mkIf withFlathub {
        name = "flatpak-flathub";
        enabled = true;
        action = "allow";
        duration = "always";
        operator = {
          type = "list";
          operand = "list";
          list = [
            {
              type = "simple";
              sensitive = false;
              operand = "process.path";
              data = "${flatpak}/bin/.flatpak-wrapped";
            }
            {
              type = "regexp";
              sensitive = false;
              operand = "dest.host";
              data = "^(dl\\.)?flathub\\.org$";
            }
          ];
        };
      };
    };
}
