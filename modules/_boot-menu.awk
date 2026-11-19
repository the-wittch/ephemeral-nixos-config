# The boot menu's picture, from assets/wallpaper.svg: the halo, the snowflake and the glitches
# near it on a flat colour, in the square the halo fills, so it meets Limine's backdrop without an
# edge. Limine draws it unscaled in the middle of any screen. Whatever spans the whole wallpaper,
# the gradient, grid, circuit lines, scan lines and vignette, is left out, and so are the words.
BEGIN { x0 = 1020; y0 = 0; size = 1800 }
/^<svg / {
  sub(/width="3840" height="2160" viewBox="0 0 3840 2160"/,
    "width=\"" size "\" height=\"" size "\" viewBox=\"" x0 " " y0 " " size " " size "\"")
  print; next
}
/^<\/defs>/ { print; print "<rect x=\"" x0 "\" y=\"" y0 "\" width=\"" size "\" height=\"" size "\" fill=\"#" bg "\"/>"; next }
/^<rect width="3840"/ || /^<text / || /^<path d="M / { next }
/^<circle / && !/url\(#halo\)/ { next }
# a glitch cut off by the square's edge would end in a hard line on the flat colour
/^<rect x=/ {
  split($0, f, "\"")
  if (f[2] < x0 + 20 || f[2] + f[6] > x0 + size - 20 || f[4] < y0 + 20 || f[4] + f[8] > y0 + size - 20) next
}
{ print }
