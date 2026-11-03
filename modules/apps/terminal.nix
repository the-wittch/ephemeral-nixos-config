let
  app = label: description: package: {
    inherit label description package;
    category = "Terminal";
  };
in
{
  ephemeral.apps = {
    lazygit = app "lazygit" "git in the terminal" "lazygit";
    tig = app "tig" "browse git history" "tig";
    k9s = app "k9s" "Kubernetes clusters" "k9s";
    harlequin = app "Harlequin" "SQL client for SQLite and Postgres" "harlequin";
    posting = app "Posting" "HTTP API client" "posting";

    tmux = app "tmux" "split and keep terminal sessions" "tmux";
    zellij = app "Zellij" "terminal workspace that's easier than tmux" "zellij";
    helix = app "Helix" "modal editor that works out of the box" "helix";

    mc = app "Midnight Commander" "two-pane file manager" "mc";
    nnn = app "nnn" "tiny and fast file manager" "nnn";
    broot = app "broot" "find your way around big folders" "broot";
    ncdu = app "ncdu" "what's using the disk" "ncdu";

    bottom = app "bottom" "system monitor with graphs" "bottom";
    glances = app "Glances" "everything about the system on one screen" "glances";
    nvtop = app "nvtop" "GPU usage on any vendor" "nvtopPackages.full";
    systemctl-tui = app "systemctl-tui" "browse and restart systemd services" "systemctl-tui";
    lnav = app "lnav" "log viewer" "lnav";
    nix-tree = app "nix-tree" "what a Nix package pulls in" "nix-tree";

    gping = app "gping" "ping with a graph" "gping";
    bluetuith = app "bluetuith" "Bluetooth devices" "bluetuith";

    neomutt = app "NeoMutt" "email" "neomutt";
    aerc = app "aerc" "email that's easy to set up" "aerc";
    newsboat = app "Newsboat" "RSS and Atom feeds" "newsboat";
    weechat = app "WeeChat" "IRC and Matrix chat" "weechat";
    irssi = app "Irssi" "IRC chat" "irssi";
    browsh = app "Browsh" "the web in the terminal through Firefox" "browsh";
    w3m = app "w3m" "text web browser" "w3m";
    wiki-tui = app "wiki-tui" "read Wikipedia" "wiki-tui";

    cmus = app "cmus" "music player for your own files" "cmus";
    ncspot = app "ncspot" "Spotify (needs Premium)" "ncspot";

    calcurse = app "calcurse" "calendar and to-do list" "calcurse";
    visidata = app "VisiData" "explore CSV and spreadsheets" "visidata";
    sc-im = app "sc-im" "spreadsheet" "sc-im";
    glow = app "Glow" "read Markdown in the terminal" "glow";

    taskwarrior-tui = {
      label = "Taskwarrior";
      category = "Terminal";
      description = "task list with a TUI";
      nixos =
        { pkgs, ... }:
        {
          environment.systemPackages = [
            pkgs.taskwarrior3
            pkgs.taskwarrior-tui
          ];
        };
    };
    trippy = {
      label = "Trippy";
      category = "Terminal";
      description = "traceroute and ping together";
      nixos.programs.trippy.enable = true;
    };
    lazydocker = {
      label = "lazydocker";
      category = "Terminal";
      description = "containers in the terminal (Podman or Docker)";
      nixos =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          # without Docker, talk to the rootless Podman socket
          environment.systemPackages = [
            (pkgs.writeShellApplication {
              name = "lazydocker";
              text = ''
                if [[ -z ''${DOCKER_HOST:-} && ! -S /run/docker.sock ]]; then
                  export DOCKER_HOST="unix://''${XDG_RUNTIME_DIR:-/run/user/$UID}/podman/podman.sock"
                fi
                exec ${lib.getExe pkgs.lazydocker} "$@"
              '';
            })
          ];
          systemd.user.sockets.podman.wantedBy = lib.mkIf (!config.virtualisation.docker.enable) [
            "sockets.target"
          ];
        };
    };
  };
}
