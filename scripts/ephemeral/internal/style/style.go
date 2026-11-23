// Package style is how everything in ephemeral looks: the site's colours as terminal colours,
// the glyphs, and the pieces each screen is built from. No screen sets a colour of its own.
// The design and where each value comes from: designs/terminal-design.md in the maintainer repo.
package style

import (
	"os"
	"strconv"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
)

// a token: the site's value in true colour, the installer's 256- and 16-colour slots for the
// same hue, and a darker one for light terminals
func token(dark, light, c256, c16 string) lipgloss.CompleteAdaptiveColor {
	return lipgloss.CompleteAdaptiveColor{
		Dark:  lipgloss.CompleteColor{TrueColor: dark, ANSI256: c256, ANSI: c16},
		Light: lipgloss.CompleteColor{TrueColor: light, ANSI256: c256, ANSI: c16},
	}
}

var (
	Muted           = token("#9a97b3", "#625e7a", "103", "8")
	Faint           = token("#817e9e", "#76738c", "60", "8")
	Line            = token("#363349", "#d4d1e2", "237", "8")
	SurfaceSelected = token("#24213a", "#e9e5f7", "236", "0")
	BrandPrimary    = token("#c4a0fb", "#6f4bc0", "183", "5")
	BrandSecondary  = token("#8cc8f2", "#2f6f9e", "117", "4")
	BrandHighlight  = token("#7a7cf0", "#4d50c4", "105", "4")
	Success         = token("#a6e3a1", "#2e7d32", "151", "2")
	Warning         = token("#f0c27a", "#8a5d0f", "222", "3")
	Critical        = token("#f0919b", "#b4323f", "210", "1")
	Unknown         = Faint
)

// the wallpaper's gradient, for the wordmark
var gradient = []string{"#c084fc", "#a855f7", "#8b5cf6", "#6366f1", "#3b82f6", "#38bdf8"}

var (
	Bold     = lipgloss.NewStyle().Bold(true)
	MutedS   = lipgloss.NewStyle().Foreground(Muted)
	FaintS   = lipgloss.NewStyle().Foreground(Faint)
	LineS    = lipgloss.NewStyle().Foreground(Line)
	KeyS     = lipgloss.NewStyle().Foreground(BrandPrimary)
	Selected = lipgloss.NewStyle().Background(SurfaceSelected).Bold(true)
	ErrorS   = lipgloss.NewStyle().Foreground(Critical)
	WarnS    = lipgloss.NewStyle().Foreground(Warning)
	OKS      = lipgloss.NewStyle().Foreground(Success)
)

// Glyphs: the Linux console's fonts lack most of the rich set, as the installer found
type Glyphs struct {
	Persistent, Ephemeral, Mixed, Unknown, Unverified string
	Open, Closed, Cursor, Arrow, Rule                 string
}

var rich = Glyphs{"●", "○", "◐", "?", "!", "▾ ", "▸ ", "›", "→", "─"}
var console = Glyphs{"■", "·", "+", "?", "!", "v ", "> ", ">", "->", "-"}

func pick() Glyphs {
	if os.Getenv("TERM") == "linux" || os.Getenv("EPHEMERAL_CONSOLE_GLYPHS") == "1" {
		return console
	}
	return rich
}

// G is the glyph set for this terminal.
var G = pick()

type Class struct {
	Glyph, Word string
	Style       lipgloss.Style
}

// Classes are the persistence classes, each with its glyph, its word and its colour.
func Classes() map[string]Class {
	return map[string]Class{
		"persistent": {G.Persistent, "PERSISTENT", lipgloss.NewStyle().Foreground(BrandPrimary)},
		"ephemeral":  {G.Ephemeral, "EPHEMERAL", lipgloss.NewStyle().Foreground(Muted)},
		"mixed":      {G.Mixed, "MIXED", lipgloss.NewStyle().Foreground(BrandSecondary)},
		"unknown":    {G.Unknown, "UNKNOWN", lipgloss.NewStyle().Foreground(Unknown)},
		"unverified": {G.Unverified, "UNVERIFIED", lipgloss.NewStyle().Foreground(Critical)},
	}
}

// Fit cuts a line, styled or not, to a width.
func Fit(s string, w int) string { return ansi.Truncate(s, max(w, 0), "…") }

// Label is the site's .label: uppercase and muted.
func Label(s string) string { return MutedS.Render(strings.ToUpper(s)) }

// Wordmark is EPHEMERAL NIX in the wallpaper's gradient, letter by letter.
func Wordmark() string {
	const word = "EPHEMERAL NIX"
	var b strings.Builder
	n := len(word) - 1
	for i, r := range word {
		c := gradient[i*(len(gradient)-1)/n]
		b.WriteString(lipgloss.NewStyle().Bold(true).Foreground(lipgloss.CompleteColor{TrueColor: c, ANSI256: "183", ANSI: "5"}).Render(string(r)))
	}
	return b.String()
}

// Header is the wordmark, the screen, and something on the right such as the release, with a
// rule under it: two lines.
func Header(width int, screen, right string) []string {
	left := Wordmark() + MutedS.Render(" / ") + Label(screen)
	gap := width - ansi.StringWidth(left) - ansi.StringWidth(right)
	line := left
	if right != "" && gap >= 2 {
		line += strings.Repeat(" ", gap) + FaintS.Render(right)
	}
	return []string{Fit(line, width), LineS.Render(strings.Repeat(G.Rule, max(width, 0)))}
}

// Keys is the footer: each key in the brand colour, what it does muted, as many as fit.
func Keys(width int, pairs ...string) string {
	var parts []string
	used := 0
	for i := 0; i+1 < len(pairs); i += 2 {
		part := KeyS.Render(pairs[i]) + " " + MutedS.Render(pairs[i+1])
		w := ansi.StringWidth(part) + 2
		if used+w > width+2 {
			break
		}
		parts = append(parts, part)
		used += w
	}
	return strings.Join(parts, "  ")
}

// Field is one row of details: the name padded and muted, then the value.
func Field(name string, width int) string {
	return MutedS.Render(strings.ToUpper(name) + strings.Repeat(" ", max(1, width-len(name))))
}

// dark says whether the background is dark, from EPHEMERAL_THEME, or COLORFGBG as many terminals
// set it ("15;0": colour 15 on 0), or dark like the site when neither says
func dark(theme, colorfgbg string) bool {
	switch theme {
	case "light":
		return false
	case "dark":
		return true
	}
	parts := strings.Split(colorfgbg, ";")
	if n, err := strconv.Atoi(parts[len(parts)-1]); err == nil && colorfgbg != "" {
		// 0 to 6 and 8 are the dark ones of the 16
		return n < 7 || n == 8
	}
	return true
}

// Light or dark is decided here, without asking the terminal: asking (OSC 11) waits five seconds
// on one that doesn't answer, as the Linux console doesn't. Bubble Tea v1 asks in its own init
// unless it's already decided, and this init runs first: since Go 1.21 packages initialise in
// import path order once their imports have, "ephemeral/..." sorts before "github.com/...", and
// what this imports, Bubble Tea imports too. The module path is "ephemeral" for that reason.
func init() {
	lipgloss.SetHasDarkBackground(dark(os.Getenv("EPHEMERAL_THEME"), os.Getenv("COLORFGBG")))
}
