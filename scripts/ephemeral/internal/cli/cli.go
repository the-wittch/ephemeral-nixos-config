// Package cli is what `ephemeral` does with its arguments: it runs the helper command they name,
// in its own place, or one of its own interactive parts.
package cli

import (
	"fmt"
	"io"
	"strings"

	"ephemeral/internal/commands"
	"ephemeral/internal/style"
)

// Env is everything Run needs from the machine, so the tests can stand in for it.
type Env struct {
	Commands []commands.Command
	Version  string
	LookPath func(name string) (string, error)
	// Exec runs argv in place of this process; it only returns when that fails
	Exec    func(path string, argv []string) error
	IsTTY   func() bool
	Explore func(engine string) error
	Center  func() error
	Stdout  io.Writer
	Stderr  io.Writer
}

// Exit codes: what the command ran returns its own; these are for what happens before it.
const (
	ok       = 0
	failed   = 1
	usage    = 2
	cantRun  = 126
	notThere = 127
)

const doctor = "ephemeral-doctor"

// the persistence group's own words, each the ephemeral-doctor persistence options it stands for
var persistence = []struct{ word, args, help string }{
	{"", "", "explore what survives a reboot, in a terminal; elsewhere, the summary"},
	{"inspect", "PATH...", "what happens to each PATH at a reboot, and whether it's backed up; --json too"},
	{"audit", "", "what isn't kept as the config says; exits 1 on anything CRITICAL; --json too"},
	{"export", "[PATH...]", "all of it as JSON, for scripts (docs/persistence.md has the fields)"},
	{"summary", "", "what's declared and set up, as a tree"},
}

func Run(args []string, e Env) int {
	if len(args) == 0 {
		help(e, e.Stdout)
		return ok
	}
	switch args[0] {
	case "-h", "--help", "help":
		if len(args) > 1 {
			if g := commands.Group(e.Commands, args[1]); len(g) > 0 {
				groupHelp(e.Stdout, args[1], g)
				return ok
			}
			if args[1] == "persistence" {
				persistenceHelp(e.Stdout)
				return ok
			}
		}
		help(e, e.Stdout)
		return ok
	case "--version":
		fmt.Fprintln(e.Stdout, "ephemeral", e.Version)
		return ok
	case "tui":
		if len(args) > 1 {
			return refuse(e, "tui takes no arguments")
		}
		if !e.IsTTY() {
			fmt.Fprintln(e.Stderr, "ephemeral tui needs a terminal; ephemeral --help lists the commands it opens")
			return failed
		}
		if err := e.Center(); err != nil {
			fmt.Fprintln(e.Stderr, "ephemeral:", err)
			return failed
		}
		return ok
	case "persistence":
		return persistenceRun(args[1:], e)
	}
	if strings.HasPrefix(args[0], "-") {
		return refuse(e, "unknown option "+args[0])
	}
	c, rest, found := commands.Find(e.Commands, args)
	if !found {
		if g := commands.Group(e.Commands, args[0]); len(g) > 0 {
			groupHelp(e.Stderr, args[0], g)
			return usage
		}
		words := []string{"persistence", "tui"}
		for _, c := range e.Commands {
			words = append(words, c.Words[0])
		}
		msg := fmt.Sprintf("there's no command %q", args[0])
		if near := commands.Nearest(words, args[0]); near != "" {
			msg += fmt.Sprintf("; did you mean %s?", near)
		}
		return refuse(e, msg)
	}
	return run(e, c.Name, c.Minimal, rest)
}

func refuse(e Env, msg string) int {
	fmt.Fprintf(e.Stderr, "ephemeral: %s\nephemeral --help lists the commands.\n", msg)
	return usage
}

// run hands over to the command, with the arguments as they were, never through a shell
func run(e Env, name string, minimal bool, args []string) int {
	path, err := e.LookPath(name)
	if err != nil {
		if !minimal {
			fmt.Fprintf(e.Stderr, "ephemeral: %s isn't on the small install; ephemeral setup switches to the full system, which has it\n", name)
		} else {
			fmt.Fprintf(e.Stderr, "ephemeral: can't find %s on PATH\n", name)
		}
		return notThere
	}
	err = e.Exec(path, append([]string{name}, args...))
	fmt.Fprintf(e.Stderr, "ephemeral: couldn't run %s: %v\n", name, err)
	return cantRun
}

func persistenceRun(args []string, e Env) int {
	if len(args) == 0 {
		if !e.IsTTY() {
			return run(e, doctor, true, []string{"persistence", "--summary"})
		}
		if err := e.Explore(doctor); err != nil {
			fmt.Fprintln(e.Stderr, "ephemeral:", err)
			return failed
		}
		return ok
	}
	sub, rest := args[0], args[1:]
	flags, paths := []string{}, []string{}
	for _, a := range rest {
		switch {
		case a == "--json":
			flags = append(flags, a)
		case strings.HasPrefix(a, "-"):
			return refuse(e, fmt.Sprintf("persistence %s doesn't take %s", sub, a))
		default:
			paths = append(paths, a)
		}
	}
	withPaths := func(out []string) []string {
		for _, p := range paths {
			out = append(out, "--path", p)
		}
		return out
	}
	switch sub {
	case "-h", "--help", "help":
		persistenceHelp(e.Stdout)
		return ok
	case "--engine":
		// how ephemeral-doctor persistence opens the explorer, naming itself
		if len(rest) != 1 {
			return refuse(e, "--engine takes the path to ephemeral-doctor")
		}
		if err := e.Explore(rest[0]); err != nil {
			fmt.Fprintln(e.Stderr, "ephemeral:", err)
			return failed
		}
		return ok
	case "inspect":
		if len(paths) == 0 {
			return refuse(e, "persistence inspect needs a path")
		}
		return run(e, doctor, true, withPaths(append([]string{"persistence"}, flags...)))
	case "audit":
		if len(paths) > 0 {
			return refuse(e, "persistence audit looks at the whole machine, and takes no path")
		}
		return run(e, doctor, true, append([]string{"persistence", "--audit"}, flags...))
	case "export":
		return run(e, doctor, true, withPaths([]string{"persistence", "--json"}))
	case "summary":
		if len(paths) > 0 || len(flags) > 0 {
			return refuse(e, "persistence summary takes no arguments")
		}
		return run(e, doctor, true, []string{"persistence", "--summary"})
	}
	words := make([]string, 0, len(persistence))
	for _, p := range persistence[1:] {
		words = append(words, p.word)
	}
	msg := fmt.Sprintf("persistence has no %q", sub)
	if near := commands.Nearest(words, sub); near != "" {
		msg += fmt.Sprintf("; did you mean %s?", near)
	}
	return refuse(e, msg)
}

type line struct{ usage, help string }

func lines(e Env) []line {
	out := []line{}
	for _, c := range e.Commands {
		out = append(out, line{c.Usage(), c.Description})
	}
	out = append(out,
		line{"ephemeral persistence", "what survives a reboot and what's backed up: inspect, audit, export"},
		line{"ephemeral tui", "a menu of all of these"},
	)
	return out
}

func table(w io.Writer, ls []line) {
	width := 0
	for _, l := range ls {
		width = max(width, len(l.usage))
	}
	for _, l := range ls {
		fmt.Fprintf(w, "  %-*s  %s\n", width, l.usage, l.help)
	}
}

func help(e Env, w io.Writer) {
	if e.IsTTY() {
		fmt.Fprintln(w, style.Wordmark()+style.MutedS.Render(" / ")+style.Label("commands"))
		fmt.Fprintln(w)
	}
	fmt.Fprintln(w, "ephemeral [command] [its options]\n\nLook after this Ephemeral Nix machine:")
	fmt.Fprintln(w)
	table(w, lines(e))
	fmt.Fprintln(w, `
--help on any of them shows its options, as in ephemeral update --help. The commands that
change the machine ask first; the ones that only look don't need sudo. Each also has its own
name, such as ephemeral-update, which works as before.`)
}

func groupHelp(w io.Writer, word string, g []commands.Command) {
	fmt.Fprintf(w, "ephemeral %s needs one of:\n\n", word)
	var ls []line
	for _, c := range g {
		ls = append(ls, line{c.Usage(), c.Description})
	}
	table(w, ls)
}

func persistenceHelp(w io.Writer) {
	fmt.Fprintln(w, "ephemeral persistence [command]\n\nWhat survives a reboot, and whether it's backed up. It only reads; sudo lets it see\ninto folders only root can read.")
	fmt.Fprintln(w)
	var ls []line
	for _, p := range persistence {
		u := strings.TrimSpace("ephemeral persistence " + p.word + " " + p.args)
		ls = append(ls, line{u, p.help})
	}
	table(w, ls)
}
