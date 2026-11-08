{
  flake.modules.homeManager.extras =
    { lib, pkgs, ... }:
    let
      art =
        pkgs.runCommand "ephemeral-splash-art"
          {
            nativeBuildInputs = with pkgs; [
              resvg
              imagemagick
              gawk
            ];
          }
          ''
            bash ${./_frames.sh} ${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg "$out"
          '';

      splash = pkgs.writeShellApplication {
        name = "ephemeral-splash";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          # prints the key that stopped the spin, if any, so the shell can put it on the prompt
          frames=(${art}/frames/*)
          lines=$(wc -l <"''${frames[0]}")
          read -r rows _ < <(stty size </dev/tty)
          ((rows > lines + 1)) || exit 0

          exec 3>/dev/tty
          trap 'printf "\e[?25h" >&3' EXIT
          printf '\e[?25l' >&3
          # make room first, so drawing a frame never scrolls the window
          printf '\n%.0s' $(seq "$lines") >&3
          printf '\e[%dA\e7' "$lines" >&3

          key=""
          for f in "''${frames[@]}"; do
            printf '\e8' >&3
            cat "$f" >&3
            if IFS= read -rsn1 -t 0.03 key; then break; fi
          done
          printf '\e8\e[J' >&3
          printf '%s' "$key"
        '';
      };
    in
    {
      home.packages = [ splash ];

      programs.fastfetch.settings = {
        logo = {
          type = "file";
          source = "${art}/logo.txt";
          color = {
            "1" = "38;2;82;119;195";
            "2" = "38;2;126;186;228";
          };
          padding.right = 2;
        };
        # long lines are cut at the window edge instead of wrapping under the logo
        display.disableLinewrap = true;
        modules = [
          "title"
          "separator"
          "os"
          "host"
          "kernel"
          "uptime"
          {
            type = "packages";
            format = "{all}";
          }
          "shell"
          {
            type = "de";
            key = "DE";
          }
          {
            type = "wm";
            key = "WM";
          }
          "terminal"
          {
            type = "cpu";
            format = "{name}";
          }
          {
            type = "gpu";
            format = "{name}";
          }
          "memory"
          "swap"
          "disk"
          {
            type = "battery";
            key = "Battery";
          }
          "break"
          "colors"
        ];
      };

      # once per Ghostty window; shells started from it (nix develop, direnv) skip it
      programs.zsh.initContent = lib.mkOrder 1500 ''
        if [[ $TERM_PROGRAM == ghostty && -z $EPHEMERAL_SPLASH ]] && (( $+commands[ephemeral-splash] )); then
          export EPHEMERAL_SPLASH=1
          () {
            local key=$(ephemeral-splash)
            fastfetch
            if [[ $key == [[:print:]] ]]; then print -z -- "$key"; fi
          }
        fi
      '';
    };
}
