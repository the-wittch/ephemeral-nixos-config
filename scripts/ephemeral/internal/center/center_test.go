package center

import (
	"errors"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"

	"ephemeral/internal/commands"
)

var table = []commands.Command{
	{Name: "ephemeral-doctor", Words: []string{"doctor"}, Description: "check the machine", Minimal: true},
	{Name: "ephemeral-update", Words: []string{"update"}, Description: "rebuild", Minimal: true},
	{Name: "ephemeral-backup", Words: []string{"backup", "save"}, Description: "save secrets", Minimal: true},
	{Name: "backup-setup", Words: []string{"backup", "setup"}, Description: "scheduled backups", Minimal: true},
	{Name: "ephemeral-apps", Words: []string{"apps"}, Description: "pick apps"},
	{Name: "ephemeral-report", Words: []string{"report"}, Description: "for a bug report", Minimal: true},
}

type recorder struct {
	ran, captured [][]string
}

func start(t *testing.T, w, h int, installed ...string) (Model, *recorder) {
	rec := &recorder{}
	have := map[string]bool{}
	for _, n := range installed {
		have[n] = true
	}
	look := func(n string) (string, error) {
		if have[n] {
			return n, nil
		}
		return "", errors.New("no")
	}
	run := func(argv []string, done func(error) tea.Msg) tea.Cmd {
		rec.ran = append(rec.ran, argv)
		return func() tea.Msg { return done(nil) }
	}
	capture := func(argv []string) (string, error) {
		rec.captured = append(rec.captured, argv)
		return strings.Repeat("✓ a line\n", 50) + "✗ the last line", errors.New("it exited 1")
	}
	m := New(table, "/bin/ephemeral", "v5.1.0", look, run, capture)
	next, _ := m.Update(tea.WindowSizeMsg{Width: w, Height: h})
	return next.(Model), rec
}

func press(m Model, keys ...string) Model {
	for _, k := range keys {
		var msg tea.KeyMsg
		switch k {
		case "up", "down", "enter", "esc", "end", "home":
			msg = tea.KeyMsg{Type: map[string]tea.KeyType{"up": tea.KeyUp, "down": tea.KeyDown, "enter": tea.KeyEnter,
				"esc": tea.KeyEsc, "end": tea.KeyEnd, "home": tea.KeyHome}[k]}
		default:
			msg = tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(k)}
		}
		next, cmd := m.Update(msg)
		m = next.(Model)
		for cmd != nil {
			next, cmd = m.Update(cmd())
			m = next.(Model)
		}
	}
	return m
}

func titlesOf(m Model) []string {
	var out []string
	for _, r := range m.rows {
		if r.it != nil {
			out = append(out, r.it.title)
		} else {
			out = append(out, "["+r.header+"]")
		}
	}
	return out
}

var all = []string{"ephemeral-doctor", "ephemeral-update", "ephemeral-backup", "backup-setup", "ephemeral-apps", "ephemeral-report"}

func TestListsWhatsInstalledInItsSection(t *testing.T) {
	m, _ := start(t, 100, 30, all...)
	got := strings.Join(titlesOf(m), " | ")
	want := "[SYSTEM] | Check this machine | Update | Apps | [DATA] | What survives a reboot | Save settings and secrets for a reinstall | Scheduled backups | [MACHINE] | Details for a bug report | Quit"
	if got != want {
		t.Fatalf("menu\n got %s\nwant %s", got, want)
	}
}

func TestTheSmallInstallLeavesOutWhatItHasnt(t *testing.T) {
	m, _ := start(t, 100, 30, "ephemeral-doctor", "ephemeral-update")
	got := strings.Join(titlesOf(m), " | ")
	if got != "[SYSTEM] | Check this machine | Update | [DATA] | What survives a reboot | Quit" {
		t.Fatalf("small install menu: %s", got)
	}
	if !strings.Contains(m.View(), "4 more come with the full system") {
		t.Fatalf("it doesn't say what's missing:\n%s", ansi.Strip(m.View()))
	}
}

func TestMovingSkipsTheHeadingsAndRunsTheChosenCommand(t *testing.T) {
	m, rec := start(t, 100, 30, all...)
	m = press(m, "down", "down", "down") // past Apps, over [DATA]
	if m.rows[m.cursor].it.title != "What survives a reboot" {
		t.Fatalf("at %q", m.rows[m.cursor].it.title)
	}
	m = press(m, "enter")
	if len(rec.ran) != 1 || strings.Join(rec.ran[0], " ") != "/bin/ephemeral persistence" {
		t.Fatalf("ran %v", rec.ran)
	}
	if !strings.Contains(m.View(), "What survives a reboot: done") {
		t.Fatalf("no word that it finished:\n%s", ansi.Strip(m.View()))
	}
	m = press(m, "up", "up", "up", "up", "up")
	if m.rows[m.cursor].it.title != "Check this machine" {
		t.Fatalf("up from the top left the first entry: %q", m.rows[m.cursor].it.title)
	}
}

func TestAnEntryThatNeedsAFolderAsksFirst(t *testing.T) {
	m, rec := start(t, 100, 30, all...)
	m = press(m, "down", "down", "down", "down", "enter")
	if m.asking == nil || len(rec.ran) != 0 {
		t.Fatalf("it ran before asking: %v", rec.ran)
	}
	m = press(m, "esc")
	if m.asking != nil || len(rec.ran) != 0 {
		t.Fatalf("esc didn't cancel")
	}
	m = press(m, "enter", "/run/media/me/stick", "enter")
	if len(rec.ran) != 1 || strings.Join(rec.ran[0], "|") != "ephemeral-backup|/run/media/me/stick" {
		t.Fatalf("ran %q", rec.ran)
	}
}

func TestTheDoctorsReportIsShownAndScrolls(t *testing.T) {
	m, rec := start(t, 100, 20, all...)
	m = press(m, "enter")
	if len(rec.captured) != 1 || rec.captured[0][0] != "ephemeral-doctor" || len(rec.ran) != 0 {
		t.Fatalf("captured %v, ran %v", rec.captured, rec.ran)
	}
	if !strings.Contains(m.View(), "1–17 of 53") {
		t.Fatalf("the report view:\n%s", ansi.Strip(m.View()))
	}
	m = press(m, "end")
	for i := 0; i < 60; i++ {
		m = press(m, "j")
	}
	if !strings.Contains(m.View(), "✗ the last line") || !strings.Contains(m.View(), "it exited 1") {
		t.Fatalf("scrolling didn't reach the end:\n%s", ansi.Strip(m.View()))
	}
	m = press(m, "q")
	if m.output != nil {
		t.Fatalf("q didn't go back to the menu")
	}
}

func TestEveryLineFitsAtAnySize(t *testing.T) {
	for _, s := range [][2]int{{120, 40}, {60, 12}, {30, 6}, {20, 4}} {
		m, _ := start(t, s[0], s[1], all...)
		for _, v := range []string{m.View(), press(m, "?").View(), press(m, "enter").View(), press(m, "end", "enter").View()} {
			lines := strings.Split(v, "\n")
			if len(lines) > s[1] {
				t.Fatalf("at %dx%d it's %d lines high", s[0], s[1], len(lines))
			}
			for _, l := range lines {
				if w := ansi.StringWidth(l); w > s[0] {
					t.Fatalf("at %dx%d a line is %d wide: %q", s[0], s[1], w, ansi.Strip(l))
				}
			}
		}
	}
}

func TestTheSelectionStaysInViewInAShortWindow(t *testing.T) {
	m, _ := start(t, 80, 8, all...)
	m = press(m, "end")
	if !strings.Contains(ansi.Strip(m.View()), "› Quit") {
		t.Fatalf("the last entry isn't in view:\n%s", ansi.Strip(m.View()))
	}
}

func TestTheSelectionShowsWithoutColour(t *testing.T) {
	m, _ := start(t, 100, 30, all...)
	m = press(m, "down")
	var marked []string
	for _, l := range strings.Split(ansi.Strip(m.View()), "\n") {
		if strings.HasPrefix(strings.TrimSpace(l), "›") {
			marked = append(marked, strings.TrimSpace(l))
		}
	}
	if len(marked) != 1 || marked[0] != "› Update" {
		t.Fatalf("marked rows %q", marked)
	}
	if !strings.HasPrefix(ansi.Strip(m.View()), "EPHEMERAL NIX / MENU") {
		t.Fatalf("header: %q", strings.Split(ansi.Strip(m.View()), "\n")[0])
	}
}

func TestQuitIsAnEntryToo(t *testing.T) {
	m, rec := start(t, 100, 30, all...)
	m = press(m, "end")
	if m.rows[m.cursor].it.title != "Quit" {
		t.Fatalf("the last entry is %q", m.rows[m.cursor].it.title)
	}
	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	if cmd == nil {
		t.Fatalf("Quit did nothing")
	}
	if _, ok := cmd().(tea.QuitMsg); !ok || len(rec.ran) != 0 {
		t.Fatalf("Quit didn't quit, or ran %v", rec.ran)
	}
}
