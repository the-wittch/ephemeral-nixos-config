package cli

import (
	"bytes"
	"errors"
	"strings"
	"testing"

	"ephemeral/internal/commands"
)

// the tools table as packages.nix writes it, in part
var tools = []commands.Command{
	{Name: "ephemeral-update", Words: []string{"update"}, Description: "rebuild", Minimal: true},
	{Name: "ephemeral-doctor", Words: []string{"doctor"}, Description: "check the machine", Minimal: true},
	{Name: "ephemeral-backup", Words: []string{"backup", "save"}, Description: "save secrets", Minimal: true},
	{Name: "backup-setup", Words: []string{"backup", "setup"}, Description: "scheduled backups", Minimal: true},
	{Name: "luks-header-backup", Words: []string{"backup", "header"}, Description: "copy the header", Minimal: true},
	{Name: "ephemeral-apps", Words: []string{"apps"}, Description: "pick apps"},
	{Name: "ephemeral-restore", Words: []string{"snapshot", "restore"}, Description: "from a snapshot"},
}

type ran struct {
	path string
	argv []string
}

func env(t *testing.T, installed ...string) (Env, *bytes.Buffer, *bytes.Buffer, *[]ran, *[]string) {
	out, errOut := &bytes.Buffer{}, &bytes.Buffer{}
	calls, explored := &[]ran{}, &[]string{}
	have := map[string]bool{}
	for _, n := range installed {
		have[n] = true
	}
	return Env{
		Commands: tools,
		Version:  "v5.1.0",
		LookPath: func(n string) (string, error) {
			if have[n] {
				return "/run/current-system/sw/bin/" + n, nil
			}
			return "", errors.New("not found")
		},
		Exec: func(path string, argv []string) error {
			*calls = append(*calls, ran{path, argv})
			return errors.New("exec stood in for by the test")
		},
		IsTTY:   func() bool { return false },
		Explore: func(e string) error { *explored = append(*explored, e); return nil },
		Center:  func() error { return nil },
		Stdout:  out,
		Stderr:  errOut,
	}, out, errOut, calls, explored
}

var all = []string{"ephemeral-update", "ephemeral-doctor", "ephemeral-backup", "backup-setup", "luks-header-backup", "ephemeral-apps", "ephemeral-restore"}

func TestEveryWordReachesItsCommandWithTheArgumentsAsTheyAre(t *testing.T) {
	for _, c := range tools {
		e, _, _, calls, _ := env(t, all...)
		args := append(append([]string{}, c.Words...), "--flag", "a value with spaces", `it's "quoted"`, "$(not run)")
		Run(args, e)
		if len(*calls) != 1 {
			t.Fatalf("%v ran %d commands", c.Words, len(*calls))
		}
		got := (*calls)[0]
		want := []string{c.Name, "--flag", "a value with spaces", `it's "quoted"`, "$(not run)"}
		if got.path != "/run/current-system/sw/bin/"+c.Name || strings.Join(got.argv, "\x00") != strings.Join(want, "\x00") {
			t.Fatalf("%v ran %s %q, want %q", c.Words, got.path, got.argv, want)
		}
	}
}

func TestExitCodes(t *testing.T) {
	cases := []struct {
		args []string
		code int
		says string
	}{
		{nil, 0, "Look after this Ephemeral Nix machine"},
		{[]string{"--help"}, 0, "ephemeral backup save"},
		{[]string{"help", "backup"}, 0, "ephemeral backup header"},
		{[]string{"--version"}, 0, "ephemeral v5.1.0"},
		{[]string{"updte"}, 2, "did you mean update?"},
		{[]string{"--bogus"}, 2, "unknown option --bogus"},
		{[]string{"backup"}, 2, "ephemeral backup needs one of"},
		{[]string{"backup", "nope"}, 2, "ephemeral backup needs one of"},
		{[]string{"tui", "x"}, 2, "takes no arguments"},
		{[]string{"tui"}, 1, "needs a terminal"},
		{[]string{"update"}, 126, "couldn't run ephemeral-update"},
	}
	for _, c := range cases {
		e, out, errOut, _, _ := env(t, all...)
		if code := Run(c.args, e); code != c.code {
			t.Errorf("%v exited %d, want %d", c.args, code, c.code)
		}
		if said := out.String() + errOut.String(); !strings.Contains(said, c.says) {
			t.Errorf("%v said %q, want %q in it", c.args, said, c.says)
		}
	}
}

func TestHelpGoesToStdoutAndMistakesToStderr(t *testing.T) {
	e, out, errOut, _, _ := env(t, all...)
	Run([]string{"--help"}, e)
	if errOut.Len() != 0 || !strings.Contains(out.String(), "ephemeral tui") {
		t.Fatalf("help: out %q, err %q", out, errOut)
	}
	e, out, errOut, _, _ = env(t, all...)
	Run([]string{"nonsense"}, e)
	if out.Len() != 0 || errOut.Len() == 0 {
		t.Fatalf("a mistake: out %q, err %q", out, errOut)
	}
}

func TestACommandTheSmallInstallDoesntHaveSaysWhatAddsIt(t *testing.T) {
	e, _, errOut, calls, _ := env(t, "ephemeral-update")
	if code := Run([]string{"apps"}, e); code != 127 || len(*calls) != 0 {
		t.Fatalf("apps without ephemeral-apps exited %d and ran %v", code, *calls)
	}
	if !strings.Contains(errOut.String(), "isn't on the small install; ephemeral setup") {
		t.Fatalf("it said %q", errOut)
	}
	e, _, errOut, _, _ = env(t)
	Run([]string{"update"}, e)
	if !strings.Contains(errOut.String(), "can't find ephemeral-update") {
		t.Fatalf("a missing command the small install should have: %q", errOut)
	}
}

func TestPersistenceGoesToTheDoctorWithTheRightOptions(t *testing.T) {
	cases := []struct {
		args []string
		want string
	}{
		{[]string{"inspect", "/home/a b", "/etc"}, "persistence --path /home/a b --path /etc"},
		{[]string{"inspect", "--json", "/etc"}, "persistence --json --path /etc"},
		{[]string{"audit"}, "persistence --audit"},
		{[]string{"audit", "--json"}, "persistence --audit --json"},
		{[]string{"export"}, "persistence --json"},
		{[]string{"export", "/var"}, "persistence --json --path /var"},
		{[]string{"summary"}, "persistence --summary"},
		{nil, "persistence --summary"}, // without a terminal
	}
	for _, c := range cases {
		e, _, errOut, calls, _ := env(t, all...)
		Run(append([]string{"persistence"}, c.args...), e)
		if len(*calls) != 1 || strings.Join((*calls)[0].argv[1:], " ") != c.want || (*calls)[0].argv[0] != "ephemeral-doctor" {
			t.Errorf("persistence %v ran %v, want ephemeral-doctor %s (%s)", c.args, *calls, c.want, errOut)
		}
	}
	for _, bad := range [][]string{{"inspect"}, {"audit", "/etc"}, {"summary", "x"}, {"inspect", "--force", "/"}, {"explor"}} {
		e, _, errOut, calls, _ := env(t, all...)
		if code := Run(append([]string{"persistence"}, bad...), e); code != 2 || len(*calls) != 0 {
			t.Errorf("persistence %v exited %d and ran %v: %s", bad, code, *calls, errOut)
		}
	}
}

func TestTheExplorerOpensInATerminal(t *testing.T) {
	e, _, _, calls, explored := env(t, all...)
	e.IsTTY = func() bool { return true }
	Run([]string{"persistence"}, e)
	Run([]string{"persistence", "--engine", "/nix/store/x-ephemeral-doctor/bin/ephemeral-doctor"}, e)
	if len(*calls) != 0 || strings.Join(*explored, ",") != "ephemeral-doctor,/nix/store/x-ephemeral-doctor/bin/ephemeral-doctor" {
		t.Fatalf("explored %v, ran %v", *explored, *calls)
	}
}

func TestHelpListsEveryCommandOnce(t *testing.T) {
	e, out, _, _, _ := env(t, all...)
	Run([]string{"--help"}, e)
	for _, c := range tools {
		n := 0
		for _, l := range strings.Split(out.String(), "\n") {
			if strings.HasPrefix(l, "  "+c.Usage()+" ") {
				n++
			}
		}
		if n != 1 {
			t.Errorf("%s is in the help %d times", c.Usage(), n)
		}
	}
}

func TestHelpOnlyHasTheHeadingInATerminal(t *testing.T) {
	e, out, _, _, _ := env(t, all...)
	Run([]string{"--help"}, e)
	if strings.Contains(out.String(), "EPHEMERAL NIX") || strings.Contains(out.String(), "\x1b[") {
		t.Fatalf("piped help has the heading or escape codes:\n%s", out)
	}
	e.IsTTY = func() bool { return true }
	out.Reset()
	Run([]string{"--help"}, e)
	if !strings.Contains(out.String(), "COMMANDS") {
		t.Fatalf("terminal help has no heading:\n%s", out)
	}
}
