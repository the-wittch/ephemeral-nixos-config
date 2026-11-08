{
  flake.modules.homeManager.extras =
    { lib, pkgs, ... }:
    let
      logo =
        pkgs.runCommand "ephemeral-fastfetch-logo"
          {
            nativeBuildInputs = with pkgs; [
              librsvg
              imagemagick
              gawk
            ];
          }
          ''
            bash ${./_logo.sh} ${../../../assets/wallpaper.svg} "$out"
          '';

      # each section is a box: the key draws the left edge and label, jumps to the right
      # edge for the border, then jumps back so the value prints after the label
      width = 64;
      labelWidth = 10;
      keyWidth = labelWidth + 5;
      esc = builtins.fromJSON ''"\u001b"'';
      rule = n: lib.strings.replicate n "─";
      section =
        {
          title,
          color,
          rows,
        }:
        [
          {
            type = "custom";
            format = "┌─ ${title} ${rule (width - 5 - lib.stringLength title)}┐";
            outputColor = color;
          }
        ]
        ++ map (
          row:
          removeAttrs row [ "label" ]
          // {
            key = "│ ${row.label}${
              lib.strings.replicate (labelWidth - lib.stringLength row.label) " "
            } │ ${esc}[${toString (width - 1 - keyWidth)}C│${esc}[${toString (width - keyWidth)}D";
            keyColor = color;
          }
        ) rows
        ++ [
          {
            type = "custom";
            format = "└${rule (width - 2)}┘";
            outputColor = color;
          }
        ];
    in
    {
      programs.fastfetch.settings = {
        logo = {
          # already colored, so it's printed as it is; fastfetch can't measure it
          type = "file-raw";
          source = "${logo}";
          width = 72;
          height = 25;
          padding.right = 3;
        };
        display = {
          separator = "";
          # a value too long for its box is cut at the window edge instead of wrapping under the logo
          disableLinewrap = true;
        };
        modules = [
          "title"
          "break"
        ]
        ++ section {
          title = "System";
          color = "blue";
          rows = [
            {
              type = "os";
              label = "OS";
            }
            {
              type = "kernel";
              label = "Kernel";
            }
            {
              type = "uptime";
              label = "Uptime";
            }
            {
              type = "packages";
              label = "Packages";
              format = "{all}";
            }
          ];
        }
        ++ section {
          title = "Hardware";
          color = "cyan";
          rows = [
            {
              type = "cpu";
              label = "CPU";
              format = "{name}";
            }
            {
              type = "gpu";
              label = "GPU";
              format = "{name}";
            }
            {
              type = "memory";
              label = "Memory";
            }
            {
              type = "swap";
              label = "Swap";
            }
            {
              type = "disk";
              label = "Disk";
              folders = "/persist";
            }
            {
              type = "battery";
              label = "Battery";
            }
          ];
        }
        ++ section {
          title = "Desktop";
          color = "magenta";
          rows = [
            {
              type = "de";
              label = "Desktop";
            }
            {
              type = "wm";
              label = "Session";
            }
            {
              type = "display";
              label = "Display";
            }
          ];
        }
        ++ section {
          title = "Terminal";
          color = "yellow";
          rows = [
            {
              type = "shell";
              label = "Shell";
            }
            {
              type = "terminal";
              label = "Terminal";
            }
            {
              type = "terminalfont";
              label = "Font";
            }
          ];
        };
      };

      # the logo and the boxes side by side need about 140 columns
      programs.ghostty.settings = {
        window-width = 151;
        window-height = 43;
      };

      # once per Ghostty window; shells started from it (nix develop, direnv) skip it
      programs.zsh.initContent = lib.mkOrder 1500 ''
        if [[ $TERM_PROGRAM == ghostty && -z $EPHEMERAL_FASTFETCH ]]; then
          export EPHEMERAL_FASTFETCH=1
          fastfetch
        fi
      '';
    };
}
