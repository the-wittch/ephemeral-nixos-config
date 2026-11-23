// Package center is `ephemeral tui`: a menu of what's on this machine. Each entry runs the
// command as it is, with the terminal, and the doctor's and the report's output are shown here.
package center

import (
	"fmt"
	"os/exec"
	"sort"
	"strings"

	"ephemeral/internal/commands"
	"ephemeral/internal/style"
	tea "github.com/charmbracelet/bubbletea"
)

type item struct {
	title, help string
	argv        []string // what runs; the first is the command's name
	ask         string   // set when it needs one argument first, and what to call it
	show        bool     // its output is shown here rather than given the terminal
	quit        bool     // leaves the menu, as q does
}

type section struct {
	name  string
	words []string
}

// where each command goes; a command's own description comes from the tools table
var sections = []section{
	{"SYSTEM", []string{"doctor", "update", "setup", "apps"}},
	{"DATA", []string{"persistence", "backup", "snapshot"}},
	{"MACHINE", []string{"password", "shares", "dns", "pass", "report"}},
}

var titles = map[string]string{
	"doctor": "Check this machine", "update": "Update", "setup": "Profile and options", "apps": "Apps",
	"persistence": "What survives a reboot", "backup save": "Save settings and secrets for a reinstall",
	"backup setup": "Scheduled backups", "backup header": "Copy the LUKS header",
	"snapshot restore": "Restore from a snapshot", "password": "Change the login password",
	"shares": "SMB shares", "dns": "Control D", "pass settings": "Settings from Proton Pass",
	"pass ssh-keys": "SSH keys from Proton Pass", "report": "Details for a bug report",
}

var asks = map[string]string{
	"backup save": "folder on another disk to save it to", "backup header": "file on another disk",
	"snapshot restore": "path to bring back",
}

type row struct {
	header string
	it     *item
}

// Runner gives a command the terminal, and says when it's done.
type Runner func(argv []string, done func(error) tea.Msg) tea.Cmd

// Capture runs a command and returns what it printed.
type Capture func(argv []string) (string, error)

type Model struct {
	rows     []row
	missing  int
	cursor   int
	width    int
	height   int
	run      Runner
	capture  Capture
	asking   *item
	typed    string
	output   []string // what a shown command printed
	outTitle string
	scroll   int
	status   string
	help     bool
	release  string
}

type doneMsg struct {
	title string
	err   error
}

type shownMsg struct {
	title, out string
	err        error
}

// New builds the menu from the commands found by lookPath; self is how to run ephemeral itself.
func New(cs []commands.Command, self, release string, lookPath func(string) (string, error), run Runner, capture Capture) Model {
	m := Model{width: 80, height: 24, run: run, capture: capture, release: release}
	have := map[string]commands.Command{}
	for _, c := range cs {
		if _, err := lookPath(c.Name); err == nil {
			have[strings.Join(c.Words, " ")] = c
		} else {
			m.missing++
		}
	}
	keys := make([]string, 0, len(have))
	for k := range have {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, s := range sections {
		var items []*item
		for _, w := range s.words {
			if w == "persistence" {
				if _, ok := have["doctor"]; ok {
					items = append(items, &item{title: titles[w], help: "explore each folder: kept, reset, mixed or unknown, and backed up or not",
						argv: []string{self, "persistence"}})
				}
				continue
			}
			for _, key := range keys {
				if key != w && !strings.HasPrefix(key, w+" ") {
					continue
				}
				c := have[key]
				it := &item{title: titles[key], help: c.Description, argv: []string{c.Name}, ask: asks[key],
					show: key == "doctor" || key == "report"}
				if it.title == "" {
					it.title = c.Usage()
				}
				items = append(items, it)
			}
		}
		if len(items) == 0 {
			continue
		}
		m.rows = append(m.rows, row{header: s.name})
		for _, it := range items {
			m.rows = append(m.rows, row{it: it})
		}
	}
	// the way out, as an entry too, below the rest
	m.rows = append(m.rows, row{it: &item{title: "Quit", help: "leave the menu; q does the same", quit: true}})
	m.cursor = m.next(0, 1)
	return m
}

// next is the first selectable row from i, going in direction d
func (m Model) next(i, d int) int {
	for ; i >= 0 && i < len(m.rows); i += d {
		if m.rows[i].it != nil {
			return i
		}
	}
	return m.cursor
}

func (m Model) Init() tea.Cmd { return nil }

func (m Model) start(it *item, arg string) tea.Cmd {
	argv := append([]string{}, it.argv...)
	if arg != "" {
		argv = append(argv, arg)
	}
	if it.show {
		capture, title := m.capture, it.title
		return func() tea.Msg {
			out, err := capture(argv)
			return shownMsg{title: title, out: out, err: err}
		}
	}
	title := it.title
	return m.run(argv, func(err error) tea.Msg { return doneMsg{title: title, err: err} })
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
	case doneMsg:
		m.status = msg.title + ": done"
		if msg.err != nil {
			m.status = msg.title + ": " + msg.err.Error()
		}
	case shownMsg:
		m.outTitle, m.scroll = msg.title, 0
		m.output = strings.Split(strings.TrimRight(msg.out, "\n"), "\n")
		if msg.err != nil {
			m.output = append(m.output, "", "("+msg.err.Error()+")")
		}
	case tea.KeyMsg:
		return m.key(msg)
	}
	return m, nil
}

func (m Model) key(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	if k.Type == tea.KeyCtrlC {
		return m, tea.Quit
	}
	if m.asking != nil {
		switch k.Type {
		case tea.KeyEsc:
			m.asking, m.typed = nil, ""
		case tea.KeyEnter:
			it, arg := m.asking, strings.TrimSpace(m.typed)
			m.asking, m.typed = nil, ""
			if arg != "" {
				return m, m.start(it, arg)
			}
		case tea.KeyBackspace:
			if r := []rune(m.typed); len(r) > 0 {
				m.typed = string(r[:len(r)-1])
			}
		case tea.KeySpace:
			m.typed += " "
		case tea.KeyRunes:
			m.typed += string(k.Runes)
		}
		return m, nil
	}
	if m.output != nil {
		switch k.String() {
		case "q", "esc", "left", "h":
			m.output = nil
		case "up", "k":
			m.scroll = max(0, m.scroll-1)
		case "down", "j":
			m.scroll = min(max(0, len(m.output)-m.bodyHeight()), m.scroll+1)
		case "pgup":
			m.scroll = max(0, m.scroll-m.bodyHeight())
		case "pgdown", " ":
			m.scroll = min(max(0, len(m.output)-m.bodyHeight()), m.scroll+m.bodyHeight())
		}
		return m, nil
	}
	if m.help {
		m.help = false
		return m, nil
	}
	m.status = ""
	switch k.String() {
	case "q":
		return m, tea.Quit
	case "?":
		m.help = true
	case "up", "k":
		m.cursor = m.next(m.cursor-1, -1)
	case "down", "j":
		m.cursor = m.next(m.cursor+1, 1)
	case "home":
		m.cursor = m.next(0, 1)
	case "end":
		m.cursor = m.next(len(m.rows)-1, -1)
	case "enter", "right", "l":
		if len(m.rows) == 0 {
			return m, nil
		}
		it := m.rows[m.cursor].it
		if it.quit {
			return m, tea.Quit
		}
		if it.ask != "" {
			m.asking = it
			return m, nil
		}
		return m, m.start(it, "")
	}
	return m, nil
}

var (
	sBold = style.Bold
	sDim  = style.MutedS
)

func fit(s string, w int) string { return style.Fit(s, w) }

// the header takes two lines and the footer one
func (m Model) bodyHeight() int { return max(m.height-3, 1) }

func (m Model) View() string {
	var body []string
	screen := "menu"
	footer := style.Keys(m.width, "↑↓", "move", "enter", "open", "?", "help", "q", "quit")
	switch {
	case m.help:
		screen = "menu · help"
		body = []string{
			"",
			"Each entry runs the command it names, as it would on its own: it asks before it changes",
			"anything, and when it's done you're back here. The ones with a report show it here.",
			"Only what's on this machine is listed.", "",
			"  " + style.Keys(m.width-2, "↑ ↓", "move", "enter", "open", "q", "quit"),
			"  " + style.Keys(m.width-2, "in a report: ↑ ↓ pgup pgdn", "scroll", "q", "back"), "",
			style.FaintS.Render("Every entry is also a command; ephemeral --help lists them."),
		}
		footer = sDim.Render("any key goes back")
	case m.output != nil:
		screen = m.outTitle
		end := min(len(m.output), m.scroll+m.bodyHeight())
		body = append(body, m.output[m.scroll:end]...)
		footer = style.Keys(m.width, fmt.Sprintf("%d–%d of %d", m.scroll+1, end, len(m.output)), "", "↑↓", "scroll", "q", "back")
	default:
		cursorLine := 0
		for i, r := range m.rows {
			if r.header != "" {
				if i > 0 {
					body = append(body, "")
				}
				body = append(body, "  "+style.Label(r.header))
				continue
			}
			if r.it.quit {
				body = append(body, "")
			}
			line := "    " + r.it.title
			if i == m.cursor {
				cursorLine = len(body)
				// the mark carries the selection without colour
				line = "  " + style.Selected.Render(style.KeyS.Render(style.G.Cursor)+" "+r.it.title)
			}
			body = append(body, line)
		}
		if len(m.rows) > 0 {
			body = append(body, "", "  "+sDim.Render(m.rows[m.cursor].it.help))
		}
		if m.missing > 0 {
			body = append(body, "  "+style.FaintS.Render(fmt.Sprintf("%d more come with the full system; Profile and options switches to it", m.missing)))
		}
		if h := m.bodyHeight(); len(body) > h {
			// a short window keeps the selection in view, with its description below when it fits
			top := min(max(0, cursorLine-h+1), len(body)-h)
			body = body[top : top+h]
		}
		if m.asking != nil {
			footer = m.asking.ask + ": " + m.typed + "▏ " + style.Keys(m.width, "enter", "run it", "esc", "cancel")
		} else if m.status != "" {
			footer = m.status
		}
	}
	if h := m.bodyHeight(); len(body) > h {
		body = body[:h]
	}
	out := style.Header(m.width, screen, m.release)
	out = append(out, body...)
	out = append(out, footer)
	for i := range out {
		out[i] = fit(out[i], m.width)
	}
	return strings.Join(out, "\n")
}

// ExecRunner gives the terminal to the command with Bubble Tea's ExecProcess.
func ExecRunner(argv []string, done func(error) tea.Msg) tea.Cmd {
	return tea.ExecProcess(exec.Command(argv[0], argv[1:]...), done)
}

// ExecCapture runs the command without a terminal and returns its output.
func ExecCapture(argv []string) (string, error) {
	out, err := exec.Command(argv[0], argv[1:]...).CombinedOutput()
	if ee, ok := err.(*exec.ExitError); ok {
		return string(out), fmt.Errorf("it exited %d", ee.ExitCode())
	}
	return string(out), err
}

func Run(cs []commands.Command, self, release string, lookPath func(string) (string, error)) error {
	_, err := tea.NewProgram(New(cs, self, release, lookPath, ExecRunner, ExecCapture), tea.WithAltScreen()).Run()
	return err
}
