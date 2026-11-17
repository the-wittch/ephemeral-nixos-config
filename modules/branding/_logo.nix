# The snowflake logo at a size, from _logo.sh; fastfetch has it named, the installer's welcome
# screen small and on its own
{
  pkgs,
  cols,
  rows,
  named ? false,
}:
pkgs.runCommand "ephemeral-logo-${toString cols}x${toString rows}"
  {
    nativeBuildInputs = with pkgs; [
      librsvg
      imagemagick
      gawk
    ];
  }
  ''
    bash ${./_logo.sh} ${../../assets/wallpaper.svg} "$out" ${toString cols} ${toString rows} ${if named then "named" else ""}
  ''
