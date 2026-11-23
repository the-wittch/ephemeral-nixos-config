package explorer

import (
	"path"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

type node struct {
	entry    entry
	parent   *node
	children []*node
	loaded   bool
	loading  bool
	expanded bool
	partial  bool // more in it than the engine listed
	err      string
}

type loadedMsg struct {
	n   *node
	r   report
	err error
}

type inputMode int

const (
	browsing inputMode = iota
	searching
	goingTo
)

var filters = []string{"", "persistent", "ephemeral", "mixed", "unknown", "unverified"}

type model struct {
	load    loader
	root    *node
	cursor  int
	top     int
	width   int
	height  int
	filter  int
	mode    inputMode
	query   string // what search keeps, once typed
	typed   string // what's being typed now
	target  string // a path g was given, opened one folder at a time
	help    bool
	details bool // narrow windows show the tree or the details, not both
	status  string
	asRoot  bool
	release string
	backups bool
}

func newModel(load loader) model {
	root := &node{entry: entry{Path: "/", Type: strp("directory"), Classification: "unknown"}, expanded: true, loading: true}
	return model{load: load, root: root, width: 80, height: 24}
}

func strp(s string) *string { return &s }

func (m model) fetch(n *node) tea.Cmd {
	load, dir := m.load, n.entry.Path
	return func() tea.Msg {
		r, err := load(dir)
		return loadedMsg{n: n, r: r, err: err}
	}
}

func (m model) Init() tea.Cmd { return m.fetch(m.root) }

// matches says whether a node passes the filter and the search
func (m model) matches(n *node) bool {
	if f := filters[m.filter]; f != "" && n.entry.Classification != f {
		return false
	}
	return m.query == "" || strings.Contains(strings.ToLower(n.entry.name()), strings.ToLower(m.query))
}

type row struct {
	n     *node
	depth int
}

// rows is the tree as shown: open folders' children, and with a filter or a search only what
// matches and the folders that lead to it
func (m model) rows() []row {
	var out []row
	var walk func(n *node, depth int) bool
	walk = func(n *node, depth int) bool {
		at := len(out)
		out = append(out, row{n, depth})
		keep := n == m.root || m.matches(n)
		if n.expanded {
			for _, c := range n.children {
				if walk(c, depth+1) {
					keep = true
				}
			}
		}
		if !keep {
			out = out[:at]
		}
		return keep
	}
	walk(m.root, 0)
	return out
}

func (m model) selected() *node {
	rs := m.rows()
	if len(rs) == 0 {
		return m.root
	}
	if m.cursor >= len(rs) {
		return rs[len(rs)-1].n
	}
	return rs[m.cursor].n
}

func (m *model) selectNode(n *node) {
	for i, r := range m.rows() {
		if r.n == n {
			m.cursor = i
			return
		}
	}
}

func (m *model) clamp() {
	n := len(m.rows())
	if m.cursor >= n {
		m.cursor = n - 1
	}
	if m.cursor < 0 {
		m.cursor = 0
	}
}

// expand opens a folder, reading it the first time
func (m *model) expand(n *node) tea.Cmd {
	if !n.entry.isDir() {
		return nil
	}
	n.expanded = true
	if n.loaded || n.loading {
		return nil
	}
	n.loading = true
	return m.fetch(n)
}

func childNamed(n *node, p string) *node {
	for _, c := range n.children {
		if c.entry.Path == p {
			return c
		}
	}
	return nil
}

// goStep opens the next folder on the way to m.target, or selects it once it's there
func (m *model) goStep() tea.Cmd {
	n := m.root
	for n.entry.Path != m.target {
		if !n.loaded {
			m.selectNode(n)
			return m.expand(n)
		}
		n.expanded = true
		next := childNamed(n, nextOnWay(n.entry.Path, m.target))
		if next == nil {
			m.status = m.target + " isn't there, or " + n.entry.Path + " lists too much to show it"
			m.target = ""
			m.selectNode(n)
			return nil
		}
		n = next
	}
	m.target = ""
	m.query = ""
	m.filter = 0
	m.selectNode(n)
	return m.expand(n)
}

// nextOnWay is the child of dir that leads to target
func nextOnWay(dir, target string) string {
	rest := strings.TrimPrefix(target, strings.TrimSuffix(dir, "/")+"/")
	first := strings.SplitN(rest, "/", 2)[0]
	return path.Join(dir, first)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		return m, nil
	case loadedMsg:
		n := msg.n
		n.loading = false
		if msg.err != nil {
			n.err = msg.err.Error()
			m.target = ""
			return m, nil
		}
		n.loaded, n.err = true, ""
		m.asRoot, m.backups, m.release = msg.r.AsRoot, msg.r.Backup.Configured, msg.r.System.ConfigRelease
		if len(msg.r.Paths) > 0 {
			n.entry = msg.r.Paths[0]
		}
		n.children = nil
		for _, e := range msg.r.Paths[min(1, len(msg.r.Paths)):] {
			n.children = append(n.children, &node{entry: e, parent: n})
		}
		n.partial = msg.r.Truncated
		m.clamp()
		if m.target != "" {
			return m, m.goStep()
		}
		return m, nil
	case tea.KeyMsg:
		return m.key(msg)
	}
	return m, nil
}

func (m model) key(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	if m.mode != browsing {
		switch k.Type {
		case tea.KeyEsc:
			if m.mode == searching {
				m.query = ""
			}
			m.mode, m.typed = browsing, ""
		case tea.KeyEnter:
			mode, typed := m.mode, strings.TrimSpace(m.typed)
			m.mode, m.typed = browsing, ""
			if mode == searching {
				m.query = typed
				m.clamp()
				return m, nil
			}
			if typed != "" {
				m.target = path.Clean("/" + typed)
				return m, m.goStep()
			}
		case tea.KeyBackspace:
			if r := []rune(m.typed); len(r) > 0 {
				m.typed = string(r[:len(r)-1])
			}
		case tea.KeyRunes:
			m.typed += string(k.Runes)
		case tea.KeySpace:
			m.typed += " "
		case tea.KeyCtrlC:
			return m, tea.Quit
		}
		if m.mode == searching {
			m.query = m.typed
			m.clamp()
		}
		return m, nil
	}
	if m.help {
		m.help = false
		if k.String() == "q" || k.Type == tea.KeyCtrlC {
			return m, tea.Quit
		}
		return m, nil
	}
	m.status = ""
	rs := m.rows()
	n := m.selected()
	switch k.String() {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "?":
		m.help = true
	case "up", "k":
		m.cursor--
	case "down", "j":
		m.cursor++
	case "pgup":
		m.cursor -= m.treeHeight()
	case "pgdown":
		m.cursor += m.treeHeight()
	case "home":
		m.cursor = 0
	case "end":
		m.cursor = len(rs) - 1
	case "right", "l", "enter":
		if n.expanded && n.loaded && len(n.children) > 0 && k.String() != "enter" {
			m.cursor++
		} else if cmd := m.expand(n); cmd != nil {
			return m, cmd
		}
	case "left", "h":
		if n.expanded && n != m.root {
			n.expanded = false
		} else if n.parent != nil {
			m.selectNode(n.parent)
		}
	case " ":
		if n.expanded && n != m.root {
			n.expanded = false
		} else if cmd := m.expand(n); cmd != nil {
			return m, cmd
		}
	case "r":
		if n.entry.isDir() {
			n.loaded = false
			return m, m.expand(n)
		}
	case "f":
		m.filter = (m.filter + 1) % len(filters)
	case "/":
		m.mode, m.typed = searching, m.query
	case "g":
		m.mode, m.typed = goingTo, n.entry.Path
	case "tab":
		m.details = !m.details
	}
	m.clamp()
	return m, nil
}
