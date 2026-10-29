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
    in
    {
      warnings = map (id: "apps.json: ${id} isn't in the app catalog, so it's skipped") unknown;

      environment.systemPackages = lib.concatMap (
        app: lib.optional (app.package != null) (lib.getAttrFromPath (lib.splitString "." app.package) pkgs)
      ) apps;
      ephemeral.unfreePackages = lib.concatMap (app: app.unfree) apps;
      home-manager.sharedModules = map (app: app.homeManager) apps;

      systemd.user.services.ephemeral-flatpaks = {
        description = "Install the Flatpaks picked with ephemeral-apps";
        wantedBy = [ "default.target" ];
        unitConfig.ConditionUser = "!@system";
        path = [ pkgs.flatpak ];
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
    };
}
