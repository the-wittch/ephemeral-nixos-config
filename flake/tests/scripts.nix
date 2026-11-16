# nix build path:.#checks.x86_64-linux.scripts-behaviour -L
{
  perSystem =
    { pkgs, ... }:
    {
      checks.scripts-behaviour =
        pkgs.runCommand "scripts-behaviour"
          {
            nativeBuildInputs = with pkgs; [
              bash
              coreutils
              findutils
              gawk
              gnugrep
              gnused
              jq
              mkpasswd
              util-linux
            ];
            SCRIPTS = ../../scripts;
            # packages.nix puts it in front of every command
            CONTROLD_ID_RE = (import ../../modules/settings/_rules.nix).controldResolver;
          }
          ''
            bash ${./_scripts.sh}
            touch $out
          '';
    };
}
