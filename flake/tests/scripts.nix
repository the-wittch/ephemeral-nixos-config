{ lib, ... }:
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
              openssh
              util-linux
            ];
            SCRIPTS = ../../scripts;
            # what packages.nix puts in front of every command
            PRELUDE = pkgs.writeText "prelude.sh" (import ../../modules/packages/_prelude.nix { inherit lib; });
          }
          ''
            bash ${./_scripts.sh}
            touch $out
          '';
    };
}
