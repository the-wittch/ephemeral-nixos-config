# Draws the splash from the Nix snowflake: frames/NN (truecolor, for the spin) and
# logo.txt (fastfetch $1/$2 colors, the last frame). Args: snowflake.svg out-dir
set -euo pipefail
svg=$1 out=$2
cols=40 rows=20 count=60
mkdir -p "$out/frames"

resvg -w 600 "$svg" flake.png
magick flake.png -background none -gravity center -extent 650x650 square.png

# light blue for the word, the same as the snowflake's light arms
word=(
  '█▀▀ █▀█ █ █ █▀▀ █▀▄▀█ █▀▀ █▀█ ▄▀█ █'
  '██▄ █▀▀ █▀█ ██▄ █ ▀ █ ██▄ █▀▄ █▀█ █▄▄'
)
pad=' '

cells() {
  magick square.png -background none -rotate "$1" -gravity center -extent 650x650 \
    -resize "${cols}x${rows}!" -depth 8 txt:- |
    awk -v cols="$cols" -v mode="$2" '
      NR == 1 { next }
      {
        split($1, xy, /[,:]/); x = xy[1]; y = xy[2]
        gsub(/[()]/, "", $2); split($2, c, ",")
        a = c[4] / 255
        ch = a > 0.85 ? "@" : a > 0.6 ? "#" : a > 0.35 ? "+" : a > 0.12 ? "." : " "
        # the dark arms are 82,119,195 and the light ones 126,186,228
        light = c[3] > 0 && c[2] / c[3] > 0.71
        if (ch == " ") cell = " "
        else if (mode == "ansi") cell = (light ? "\033[38;2;126;186;228m" : "\033[38;2;82;119;195m") ch
        else cell = (light ? "$2" : "$1") ch
        line[y] = line[y] cell
      }
      END { for (y = 0; y in line; y++) { s = line[y]; sub(/ +$/, "", s); print s (mode == "ansi" ? "\033[0m" : "") } }'
}

for ((i = 0; i < count; i++)); do
  # one full turn that slows to a stop on the upright flake
  angle=$(awk -v i="$i" -v n="$count" 'BEGIN { t = (i + 1) / n; printf "%.2f", 360 * (1 - (1 - t) ^ 3) }')
  {
    cells "$angle" ansi
    echo
    for w in "${word[@]}"; do printf '%s\033[38;2;126;186;228m%s\033[0m\n' "$pad" "$w"; done
  } >"$out/frames/$(printf '%02d' "$i")"
done

{
  cells 0 file
  echo
  for w in "${word[@]}"; do printf '%s$2%s\n' "$pad" "$w"; done
} >"$out/logo.txt"
