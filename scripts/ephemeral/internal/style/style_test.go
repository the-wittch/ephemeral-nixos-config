package style

import (
	"math"
	"strconv"
	"strings"
	"testing"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
)

func luminance(hex string) float64 {
	hex = strings.TrimPrefix(hex, "#")
	var c [3]float64
	for i := range c {
		v, _ := strconv.ParseUint(hex[2*i:2*i+2], 16, 8)
		s := float64(v) / 255
		if s <= 0.03928 {
			c[i] = s / 12.92
		} else {
			c[i] = math.Pow((s+0.055)/1.055, 2.4)
		}
	}
	return 0.2126*c[0] + 0.7152*c[1] + 0.0722*c[2]
}

func contrast(a, b string) float64 {
	la, lb := luminance(a), luminance(b)
	return (math.Max(la, lb) + 0.05) / (math.Min(la, lb) + 0.05)
}

// text in these colours has to be readable: 4.5:1, WCAG's for ordinary text, on the site's
// background and on white; faint and unknown are for what's secondary, so 3:1
func TestEveryColourThatCarriesTextCanBeRead(t *testing.T) {
	for name, c := range map[string]lipgloss.CompleteAdaptiveColor{
		"muted": Muted, "brand-primary": BrandPrimary, "brand-secondary": BrandSecondary,
		"brand-highlight": BrandHighlight, "success": Success, "warning": Warning, "critical": Critical,
		"faint": Faint,
	} {
		need := 4.5
		if name == "faint" || name == "brand-highlight" {
			need = 3
		}
		if r := contrast(c.Dark.TrueColor, "#0e0d16"); r < need {
			t.Errorf("%s %s on the site's background: %.2f, needs %.1f", name, c.Dark.TrueColor, r, need)
		}
		if r := contrast(c.Light.TrueColor, "#ffffff"); r < need {
			t.Errorf("%s %s on white: %.2f, needs %.1f", name, c.Light.TrueColor, r, need)
		}
	}
}

func TestEveryClassHasItsOwnGlyphAndWord(t *testing.T) {
	for _, set := range []Glyphs{rich, console} {
		G = set
		seen := map[string]bool{}
		for name, c := range Classes() {
			if c.Glyph == "" || seen[c.Glyph] || c.Word != strings.ToUpper(name) {
				t.Errorf("%s: glyph %q word %q", name, c.Glyph, c.Word)
			}
			seen[c.Glyph] = true
		}
	}
	G = rich
}

func TestTheConsoleGlyphsAreInItsFont(t *testing.T) {
	// what Lat2-Terminus16 has, as the installer's console set uses
	for _, g := range []string{console.Persistent, console.Ephemeral, console.Mixed, console.Unknown,
		console.Unverified, console.Open, console.Closed, console.Cursor, console.Arrow, console.Rule} {
		for _, r := range g {
			if r > 0x7f && !strings.ContainsRune("■·•▶█░─", r) {
				t.Errorf("%q isn't in the console font", r)
			}
		}
	}
}

func TestTheHeaderFitsAndSaysWhereYouAre(t *testing.T) {
	for _, w := range []int{120, 40, 20, 5} {
		h := Header(w, "persistence", "v5.1.0")
		if len(h) != 2 {
			t.Fatalf("the header is %d lines", len(h))
		}
		for _, l := range h {
			if ansi.StringWidth(l) > w {
				t.Fatalf("at %d the header is %d wide: %q", w, ansi.StringWidth(l), ansi.Strip(l))
			}
		}
		if w >= 40 && !strings.Contains(ansi.Strip(h[0]), "EPHEMERAL NIX / PERSISTENCE") {
			t.Fatalf("at %d: %q", w, ansi.Strip(h[0]))
		}
		if w >= 120 && !strings.Contains(h[0], "v5.1.0") {
			t.Fatalf("the release isn't on the right at %d", w)
		}
	}
}

func TestKeysStopBeforeTheEdge(t *testing.T) {
	k := Keys(30, "↑↓", "move", "enter", "open", "?", "help", "q", "quit")
	if w := ansi.StringWidth(k); w > 30 || !strings.Contains(ansi.Strip(k), "↑↓ move") {
		t.Fatalf("%d wide: %q", w, ansi.Strip(k))
	}
}

func TestLightOrDarkComesFromTheEnvironmentNotAQuery(t *testing.T) {
	for _, c := range []struct {
		theme, fgbg string
		dark        bool
	}{{"", "", true}, {"", "15;0", true}, {"", "0;15", false}, {"", "0;7", false}, {"", "7;8", true},
		{"", "12;default;0", true}, {"", "nonsense", true}, {"light", "15;0", false}, {"dark", "0;15", true}} {
		if got := dark(c.theme, c.fgbg); got != c.dark {
			t.Errorf("EPHEMERAL_THEME=%q COLORFGBG=%q: dark %v, want %v", c.theme, c.fgbg, got, c.dark)
		}
	}
}
