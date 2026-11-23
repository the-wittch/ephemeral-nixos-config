package explorer

import (
	"errors"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
)

func dir(p, class string) entry {
	return entry{Path: p, Exists: "yes", Type: strp("directory"), Classification: class, OwnClassification: class,
		Mechanism: "how " + p, BackupCoverage: "not-configured"}
}

func file(p, class string) entry {
	e := dir(p, class)
	e.Type = strp("file")
	return e
}

// a machine with a kept /home and /var/lib/bluetooth, and a /var/lib/libvirt that isn't set up
var tree = map[string][]entry{
	"/":        {dir("/", "mixed"), dir("/home", "persistent"), dir("/tmp", "ephemeral"), dir("/var", "mixed"), file("/odd\nname", "ephemeral")},
	"/var":     {dir("/var", "mixed"), dir("/var/lib", "mixed")},
	"/var/lib": {dir("/var/lib", "mixed"), dir("/var/lib/bluetooth", "persistent"), dir("/var/lib/libvirt", "unverified"), dir("/var/lib/lastlog", "ephemeral")},
	"/home":    {dir("/home", "persistent")},
	"/tmp":     {dir("/tmp", "ephemeral")},
}

func fakeLoader(t *testing.T, asked *[]string) loader {
	return func(d string) (report, error) {
		*asked = append(*asked, d)
		es, ok := tree[d]
		if !ok {
			return report{}, errors.New("no such folder " + d)
		}
		return report{Version: 1, Paths: es}, nil
	}
}

// run feeds keys to the model, carrying out the reads it asks for along the way
func run(t *testing.T, m model, cmd tea.Cmd, keys ...string) model {
	t.Helper()
	settle := func() {
		for cmd != nil {
			msg := cmd()
			var next tea.Model
			next, cmd = m.Update(msg)
			m = next.(model)
		}
	}
	settle()
	for _, k := range keys {
		var msg tea.KeyMsg
		switch k {
		case "up", "down", "left", "right", "enter", "esc", "tab", "backspace", " ":
			msg = tea.KeyMsg{Type: map[string]tea.KeyType{"up": tea.KeyUp, "down": tea.KeyDown, "left": tea.KeyLeft,
				"right": tea.KeyRight, "enter": tea.KeyEnter, "esc": tea.KeyEsc, "tab": tea.KeyTab,
				"backspace": tea.KeyBackspace, " ": tea.KeySpace}[k]}
		default:
			msg = tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(k)}
		}
		var next tea.Model
		next, cmd = m.Update(msg)
		m = next.(model)
		settle()
	}
	return m
}

func start(t *testing.T, w, h int) (model, *[]string) {
	asked := &[]string{}
	m := newModel(fakeLoader(t, asked))
	next, _ := m.Update(tea.WindowSizeMsg{Width: w, Height: h})
	m = next.(model)
	return run(t, m, m.Init()), asked
}

func names(m model) []string {
	var out []string
	for _, r := range m.rows() {
		out = append(out, r.n.entry.Path)
	}
	return out
}

func TestOpensTheRootAndShowsWhatsInIt(t *testing.T) {
	m, asked := start(t, 120, 30)
	if got := strings.Join(*asked, ","); got != "/" {
		t.Fatalf("asked for %s, want only /", got)
	}
	if got := strings.Join(names(m), ","); got != "/,/home,/tmp,/var,/odd\nname" {
		t.Fatalf("rows %q", got)
	}
	if m.root.entry.Classification != "mixed" {
		t.Fatalf("the root's entry wasn't taken from the engine: %s", m.root.entry.Classification)
	}
}

func TestExpandingReadsAFolderOnceAndCollapsing(t *testing.T) {
	m, asked := start(t, 120, 30)
	m = run(t, m, nil, "down", "down", "down", "right") // /var
	if !strings.Contains(strings.Join(names(m), ","), "/var/lib") {
		t.Fatalf("/var didn't open: %v", names(m))
	}
	m = run(t, m, nil, "left", "right")
	if n := strings.Count(strings.Join(*asked, ","), "/var"); n != 1 {
		t.Fatalf("/var was read %d times, want once: %v", n, *asked)
	}
	m = run(t, m, nil, "right", "right") // into /var/lib, which opens
	if !strings.Contains(strings.Join(names(m), ","), "/var/lib/bluetooth") {
		t.Fatalf("/var/lib didn't open: %v", names(m))
	}
	m = run(t, m, nil, "left", "left")
	if m.selected().entry.Path != "/var" {
		t.Fatalf("left from a closed folder should go to its parent, at %s", m.selected().entry.Path)
	}
}

func TestFilterKeepsTheFoldersThatLeadToAMatch(t *testing.T) {
	m, _ := start(t, 120, 30)
	m = run(t, m, nil, "g", "backspace", "/var/lib", "enter")
	for m.filter != 5 { // unverified
		m = run(t, m, nil, "f")
	}
	if got := strings.Join(names(m), ","); got != "/,/var,/var/lib,/var/lib/libvirt" {
		t.Fatalf("filtered rows %q", got)
	}
	if !strings.Contains(m.View(), "only") {
		t.Fatalf("the header doesn't say a filter is on")
	}
}

func TestSearchMatchesNamesAndEscClearsIt(t *testing.T) {
	m, _ := start(t, 120, 30)
	m = run(t, m, nil, "/", "ho")
	if got := strings.Join(names(m), ","); got != "/,/home" {
		t.Fatalf("searching ho gave %q", got)
	}
	m = run(t, m, nil, "esc")
	if m.query != "" || len(names(m)) != 5 {
		t.Fatalf("esc didn't clear the search: %q %v", m.query, names(m))
	}
}

func TestGoToOpensEachFolderOnTheWay(t *testing.T) {
	m, asked := start(t, 120, 30)
	m = run(t, m, nil, "g")
	for range m.typed {
		m = run(t, m, nil, "backspace")
	}
	m = run(t, m, nil, "/var/lib/bluetooth", "enter")
	if got := m.selected().entry.Path; got != "/var/lib/bluetooth" {
		t.Fatalf("go to ended at %s; read %v", got, *asked)
	}
	m = run(t, m, nil, "g", "backspace", "x", "enter")
	if !strings.Contains(m.status, "isn't there") {
		t.Fatalf("going to a path that isn't there says nothing: %q", m.status)
	}
}

func TestAFolderThatCantBeReadSaysWhy(t *testing.T) {
	m, _ := start(t, 120, 30)
	m.root.children = append(m.root.children, &node{entry: dir("/gone", "unknown"), parent: m.root})
	m = run(t, m, nil, "end", "right")
	if !strings.Contains(m.View(), "no such folder /gone") {
		t.Fatalf("the error isn't shown:\n%s", m.View())
	}
}

func TestEveryLineFitsWideNarrowAndTiny(t *testing.T) {
	for _, size := range [][2]int{{140, 40}, {96, 24}, {60, 20}, {30, 8}} {
		m, _ := start(t, size[0], size[1])
		m = run(t, m, nil, "down", "down", "down", "right")
		for _, view := range []string{m.View(), run(t, m, nil, "tab").View(), run(t, m, nil, "?").View()} {
			lines := strings.Split(view, "\n")
			for _, l := range lines {
				if w := ansi.StringWidth(l); w > size[0] {
					t.Fatalf("at %dx%d a line is %d wide: %q", size[0], size[1], w, ansi.Strip(l))
				}
			}
		}
		if size[0] >= wideAt && !strings.Contains(m.View(), "AFTER A REBOOT") {
			t.Fatalf("at %d wide the details aren't beside the tree", size[0])
		}
	}
}

func TestResizingKeepsTheSelection(t *testing.T) {
	m, _ := start(t, 140, 40)
	m = run(t, m, nil, "down")
	next, _ := m.Update(tea.WindowSizeMsg{Width: 50, Height: 12})
	m = next.(model)
	if m.selected().entry.Path != "/home" || m.wide() {
		t.Fatalf("after shrinking: %s, wide %v", m.selected().entry.Path, m.wide())
	}
	if !strings.Contains(m.View(), "PERSISTENT") {
		t.Fatalf("the narrow view lost the selected path's class:\n%s", ansi.Strip(m.View()))
	}
}

func TestOddNamesCantMoveTheCursor(t *testing.T) {
	m, _ := start(t, 120, 30)
	if strings.Contains(m.View(), "odd\nname") || !strings.Contains(m.View(), "odd?name") {
		t.Fatalf("a newline in a name reached the screen")
	}
}

func TestHelpExplainsEveryClassAndClosesOnAnyKey(t *testing.T) {
	m, _ := start(t, 120, 40)
	m = run(t, m, nil, "?")
	v := m.View()
	for _, w := range []string{"PERSISTENT", "EPHEMERAL", "MIXED", "UNKNOWN", "UNVERIFIED", "quit"} {
		if !strings.Contains(v, w) {
			t.Fatalf("help leaves out %s", w)
		}
	}
	m = run(t, m, nil, "x")
	if m.help {
		t.Fatalf("help didn't close")
	}
}

func TestParsesTheEnginesJSONWithItsNulls(t *testing.T) {
	r, err := parseReport([]byte(`{"version": 1, "as_root": false, "truncated": true,
		"backup": {"configured": false, "last_result": null, "last_success": null},
		"paths": [{"path": "/x", "exists": "unknown", "type": null, "owner": null, "group": null, "mode": null,
		"link": null, "classification": "unknown", "own_classification": "unknown", "survives_reboot": null,
		"mechanism": "m", "backing": {"mount": null, "fs_type": null, "source": null, "subvolume": null},
		"declared": false, "declaration": null, "declared_in": [], "inside_declared": null, "verified": null,
		"kept_inside": [], "unknown_inside": false, "backup_coverage": "not-configured", "backup_reason": "r",
		"backup_via": "/x", "notes": ["n"]}]}`))
	if err != nil || !r.Truncated || len(r.Paths) != 1 || r.Paths[0].SurvivesReboot != nil {
		t.Fatalf("parsed %+v, %v", r, err)
	}
	if _, err := parseReport([]byte(`{"version": 2}`)); err == nil {
		t.Fatalf("a newer version was taken as version 1")
	}
}

func TestTheCursorShowsWithoutColour(t *testing.T) {
	m, _ := start(t, 120, 30)
	m = run(t, m, nil, "down")
	var marked []string
	for _, l := range strings.Split(ansi.Strip(m.View()), "\n") {
		if strings.HasPrefix(strings.TrimSpace(l), "›") {
			marked = append(marked, l)
		}
	}
	if len(marked) != 1 || !strings.Contains(marked[0], "home/") {
		t.Fatalf("the rows with the cursor's mark: %q", marked)
	}
}

func TestTheHeaderNamesTheScreenAndTheRelease(t *testing.T) {
	asked := &[]string{}
	load := func(d string) (report, error) {
		r, err := fakeLoader(t, asked)(d)
		r.AsRoot = true
		r.System.ConfigRelease = "v5.1.0"
		return r, err
	}
	m := newModel(load)
	next, _ := m.Update(tea.WindowSizeMsg{Width: 120, Height: 30})
	m = run(t, next.(model), next.(model).Init())
	head := strings.Split(ansi.Strip(m.View()), "\n")[0]
	if !strings.HasPrefix(head, "EPHEMERAL NIX / PERSISTENCE") || !strings.HasSuffix(head, "v5.1.0") {
		t.Fatalf("header %q", head)
	}
}
