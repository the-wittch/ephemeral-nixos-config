{
  flake.modules.nixos.base =
    { pkgs, ... }:
    let
      wallpaper = ../../assets/wallpaper.svg;
      theme =
        pkgs.runCommand "ephemeral-plymouth"
          {
            nativeBuildInputs = [
              pkgs.librsvg
              (pkgs.python3.withPackages (p: [
                p.numpy
                p.pillow
              ]))
            ];
          }
          ''
            dir=$out/share/plymouth/themes/ephemeral
            mkdir -p "$dir"

            # the wallpaper's snowflake on its own, with its gradient and glow; the glow
            # filter's box is widened, as the snowflake has no room around it here
            {
              echo '<svg xmlns="http://www.w3.org/2000/svg" width="510" height="510" viewBox="-310 -310 620 620"><defs>'
              sed -n '/<linearGradient id="neon"/,/<\/linearGradient>/p' ${wallpaper}
              sed -n '/<filter id="glow"/,/<\/filter>/p' ${wallpaper} |
                sed 's/x="-20%" y="-20%" width="140%" height="140%"/x="-40%" y="-40%" width="180%" height="180%"/'
              echo '</defs><g transform="translate(-407.3 715.8)">'
              grep -A8 '<g transform="translate(1920 900)' ${wallpaper} | grep '<path'
              echo '</g></svg>'
            } >flake.svg
            if [[ $(grep -c '<path' flake.svg) != 6 ]]; then
              echo "couldn't find the snowflake's six paths in assets/wallpaper.svg" >&2
              exit 1
            fi
            rsvg-convert flake.svg -o flake.png

            python3 ${./_render.py} flake.png ${pkgs.jetbrains-mono}/share/fonts/truetype "$dir"
            cat "$dir/shed.script" ${./_ephemeral.script} >"$dir/ephemeral.script"
            rm "$dir/shed.script"

            cat >"$dir/ephemeral.plymouth" <<EOF
            [Plymouth Theme]
            Name=Ephemeral Nix
            Description=The wallpaper's snowflake, breaking up into pixels
            ModuleName=script

            [script]
            ImageDir=$dir
            ScriptFile=$dir/ephemeral.script
            EOF
          '';
    in
    {
      boot.plymouth = {
        theme = "ephemeral";
        themePackages = [ theme ];
      };
    };
}
