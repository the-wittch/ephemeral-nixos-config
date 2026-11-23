package explorer

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"

	"ephemeral/internal/style"
)

var (
	sBold  = style.Bold
	sDim   = style.MutedS
	sFaint = style.FaintS
	sError = style.ErrorS
)

// badge and word: each class has its own glyph as well as a colour, so it reads without colour
func badge(class string) string {
	c, ok := style.Classes()[class]
	if !ok {
		return "?"
	}
	return c.Style.Render(c.Glyph)
}

func word(class string) string {
	c, ok := style.Classes()[class]
	if !ok {
		return strings.ToUpper(class)
	}
	return c.Style.Bold(true).Render(c.Word)
}

// shown keeps control characters in a file name from moving the cursor around
func shown(s string) string {
	return strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7f {
			return '?'
		}
		return r
	}, s)
}

func fit(s string, w int) string {
	if w <= 0 {
		return ""
	}
	return ansi.Truncate(s, w, "…")
}

const wideAt = 96

func (m model) wide() bool { return m.width >= wideAt }

// lines for the body: the header takes two and the footer one, and a narrow window keeps room
// for a short summary of the selected path below the tree
func (m model) bodyHeight() int { return max(m.height-3, 1) }

func (m model) treeHeight() int {
	h := m.bodyHeight()
	if !m.wide() && !m.details {
		h -= 4
	}
	return max(h, 3)
}

func (m model) View() string {
	if m.help {
		return m.helpView()
	}
	var notes []string
	if f := filters[m.filter]; f != "" {
		notes = append(notes, "only "+style.Classes()[f].Word)
	}
	if m.query != "" {
		notes = append(notes, "names with "+shown(m.query))
	}
	if !m.asRoot {
		notes = append(notes, "without sudo")
	}
	right := m.release
	if len(notes) > 0 {
		right = strings.Join(notes, " · ")
	}
	out := style.Header(m.width, "persistence", right)
	var body []string
	switch {
	case m.wide():
		left := m.width * 2 / 5
		tree := m.treeView(left, m.bodyHeight())
		info := m.detailView(m.width-left-3, m.bodyHeight())
		for i := 0; i < m.bodyHeight(); i++ {
			t, d := "", ""
			if i < len(tree) {
				t = fit(tree[i], left)
			}
			if i < len(info) {
				d = info[i]
			}
			body = append(body, t+strings.Repeat(" ", max(0, left-ansi.StringWidth(t)))+style.LineS.Render(" │ ")+fit(d, m.width-left-3))
		}
	case m.details:
		body = m.detailView(m.width, m.bodyHeight())
	default:
		body = m.treeView(m.width, m.treeHeight())
		body = append(body, style.LineS.Render(strings.Repeat(style.G.Rule, max(m.width, 0))))
		body = append(body, m.shortView(m.width)...)
	}
	out = append(out, body...)
	out = append(out, m.footer())
	for i := range out {
		out[i] = fit(out[i], m.width)
	}
	return strings.Join(out, "\n")
}

func (m model) footer() string {
	switch m.mode {
	case searching:
		return "search names: " + shown(m.typed) + "▏ " + style.Keys(m.width, "enter", "keep it", "esc", "clear it")
	case goingTo:
		return "go to: " + shown(m.typed) + "▏ " + style.Keys(m.width, "enter", "go", "esc", "cancel")
	}
	if m.status != "" {
		return sError.Render(m.status)
	}
	if !m.wide() {
		return style.Keys(m.width, "↑↓", "move", "→", "open", "←", "close", "tab", "details", "/", "search",
			"f", "filter", "g", "go to", "?", "help", "q", "quit")
	}
	return style.Keys(m.width, "↑↓", "move", "→", "open", "←", "close", "/", "search", "f", "filter",
		"g", "go to", "?", "help", "q", "quit")
}

func (m model) treeView(w, h int) []string {
	rs := m.rows()
	top := 0
	if m.cursor >= h {
		top = m.cursor - h + 1
	}
	var out []string
	for i := top; i < len(rs) && len(out) < h; i++ {
		n, depth := rs[i].n, rs[i].depth
		mark := "  "
		if n.entry.isDir() {
			mark = style.G.Closed
			if n.expanded {
				mark = style.G.Open
			}
		}
		name := shown(n.entry.name())
		if n.entry.isDir() && n != m.root {
			name += "/"
		}
		if n.entry.Link != nil {
			name += sFaint.Render(" " + style.G.Arrow + " " + shown(*n.entry.Link))
		}
		// the cursor has a mark of its own, so it shows without colour too
		gutter := "  "
		if i == m.cursor {
			gutter = style.KeyS.Render(style.G.Cursor) + " "
		}
		line := gutter + strings.Repeat("  ", depth) + mark + badge(n.entry.Classification) + " " + name
		if i == m.cursor {
			line = style.Selected.Render(fit(line, w))
		}
		out = append(out, line)
		if n.expanded {
			pad := "  " + strings.Repeat("  ", depth+1) + "  "
			switch {
			case n.loading && len(n.children) == 0:
				out = append(out, pad+sFaint.Render("reading…"))
			case n.err != "":
				out = append(out, pad+sError.Render(n.err))
			case n.loaded && len(n.children) == 0 && n.entry.Exists == "yes" && n.entry.Classification != "unknown":
				out = append(out, pad+sFaint.Render("empty, or nothing it can read"))
			case n.partial:
				out = append(out, pad+sFaint.Render("more than it lists; g goes to a path in it"))
			}
		}
	}
	return out
}

func yesNo(b *bool, yes, no, unknown string) string {
	if b == nil {
		return unknown
	}
	if *b {
		return yes
	}
	return no
}

func or(s *string, d string) string {
	if s == nil || *s == "" {
		return d
	}
	return *s
}

var coverage = map[string]string{
	"included":       "backed up",
	"partial":        "partly backed up",
	"excluded":       "not backed up",
	"unknown":        "can't tell",
	"not-configured": "no scheduled backups",
}

func (m model) shortView(w int) []string {
	e := m.selected().entry
	return []string{
		badge(e.Classification) + " " + sBold.Render(shown(e.Path)) + "  " + word(e.Classification),
		style.Field("after a reboot", 15) + reboot(e) + sDim.Render(" · ") + style.Field("backups", 8) + coverage[e.BackupCoverage],
		sDim.Render(fit(e.Mechanism, w)),
	}
}

func reboot(e entry) string {
	if e.Classification == "mixed" {
		return "some of it is still there"
	}
	return yesNo(e.SurvivesReboot, "still there", "gone", "can't tell")
}

const fieldWidth = 15

func (m model) detailView(w, h int) []string {
	n := m.selected()
	e := n.entry
	field := func(k, v string) []string {
		lines := strings.Split(lipgloss.NewStyle().Width(max(10, w-fieldWidth-1)).Render(v), "\n")
		out := []string{style.Field(k, fieldWidth+1) + lines[0]}
		for _, l := range lines[1:] {
			out = append(out, strings.Repeat(" ", fieldWidth+1)+l)
		}
		return out
	}
	var out []string
	add := func(k, v string) { out = append(out, field(k, v)...) }
	out = append(out, badge(e.Classification)+" "+sBold.Render(shown(e.Path)), "")
	class := word(e.Classification)
	if (e.Classification == "mixed" || e.Classification == "unverified") && e.OwnClassification != "" {
		class += sDim.Render(" · what holds it now is " + strings.ToLower(style.Classes()[e.OwnClassification].Word))
	}
	add("class", class)
	add("after a reboot", reboot(e))
	add("how", e.Mechanism)
	on := or(e.Backing.Mount, "?") + " (" + or(e.Backing.FsType, "?")
	if e.Backing.Subvolume != nil {
		on += ", subvolume " + *e.Backing.Subvolume
	}
	add("on", on+")")
	switch e.Exists {
	case "yes":
		add("exists", "yes, "+or(e.Type, "?"))
		add("owner, mode", or(e.Owner, "?")+":"+or(e.Group, "?")+" "+or(e.Mode, "?"))
	case "no":
		add("exists", "no")
	default:
		add("exists", "can't tell; it needs sudo to read")
	}
	switch {
	case e.Declaration != nil:
		from := "the config"
		if len(e.DeclaredIn) > 0 {
			from = strings.Join(e.DeclaredIn, ", ")
		}
		d := e.Declaration
		how := map[string]string{"bindmount": "bind mount", "symlink": "link"}[d.How]
		if how == "" {
			how = d.How
		}
		add("kept by", fmt.Sprintf("%s, as a %s (%s:%s %s)", from, how, d.User, d.Group, d.Mode))
		add("set up now", yesNo(e.Verified, "yes", "no", "can't tell"))
	case e.InsideDeclared != nil:
		v := "part of " + shown(*e.InsideDeclared)
		if len(e.DeclaredIn) > 0 {
			v += ", from " + strings.Join(e.DeclaredIn, ", ")
		}
		add("kept as", v)
	default:
		add("declared", "no")
	}
	b := coverage[e.BackupCoverage]
	if e.BackupReason != nil {
		b += ": " + shown(*e.BackupReason)
	}
	if e.BackupVia != nil && *e.BackupVia != e.Path {
		b += " (read as " + shown(*e.BackupVia) + ")"
	}
	add("backups", b)
	if len(e.KeptInside) > 0 {
		names := e.KeptInside
		more := ""
		if len(names) > 5 {
			names, more = names[:5], fmt.Sprintf(" and %d more", len(e.KeptInside)-5)
		}
		add("kept inside", strings.Join(names, ", ")+more)
	}
	if e.UnknownInside {
		add("also inside", "mounts it can't classify")
	}
	if n.loaded && len(n.children) > 0 {
		counts := map[string]int{}
		for _, c := range n.children {
			counts[c.entry.Classification]++
		}
		var parts []string
		for _, k := range []string{"persistent", "ephemeral", "mixed", "unknown", "unverified"} {
			if counts[k] > 0 {
				parts = append(parts, fmt.Sprintf("%s %d", badge(k), counts[k]))
			}
		}
		listed := strings.Join(parts, "  ")
		if n.partial {
			listed += sFaint.Render("  (not all of it)")
		}
		add("directly in it", listed)
	}
	for _, note := range e.Notes {
		add("note", shown(note))
	}
	if len(out) > h {
		out = out[:h]
	}
	return out
}

func (m model) helpView() string {
	lines := style.Header(m.width, "persistence · help", "")
	lines = append(lines,
		"",
		"/ is reset at every boot. What's kept is on /persist, mounted or linked into place",
		"as the config says. Each path is classified from that list and the mounts as they are now:",
		"",
	)
	for _, k := range []string{"persistent", "ephemeral", "mixed", "unknown", "unverified"} {
		c := style.Classes()[k]
		lines = append(lines, "  "+badge(k)+" "+word(k)+strings.Repeat(" ", 11-len(c.Word))+map[string]string{
			"persistent": "kept: on /persist, mounted or linked from it, or on /nix, /var/log or /boot",
			"ephemeral":  "gone at the next boot: on the part of the disk that's reset, or in memory",
			"mixed":      "a folder that holds both",
			"unknown":    "another disk, a network share, firmware storage, or nothing it can tell",
			"unverified": "the config keeps it, but it isn't set up that way now",
		}[k])
	}
	lines = append(lines,
		"",
		"Kept and backed up aren't the same: the details say what the scheduled backups read.",
		"",
		style.Label("keys"),
		"  "+style.Keys(m.width-2, "↑ ↓", "move", "→ enter", "open a folder", "←", "close it, or go up"),
		"  "+style.Keys(m.width-2, "space", "open or close", "pgup pgdn home end", "page", "r", "read the folder again"),
		"  "+style.Keys(m.width-2, "/", "search the names shown", "f", "show only one class", "g", "go to a path"),
		"  "+style.Keys(m.width-2, "tab", "tree or details, in a narrow window", "?", "this help", "q", "quit"),
		"",
		sFaint.Render("It only reads. Any key goes back."),
	)
	for i := range lines {
		lines[i] = fit(lines[i], m.width)
	}
	return strings.Join(lines, "\n")
}
