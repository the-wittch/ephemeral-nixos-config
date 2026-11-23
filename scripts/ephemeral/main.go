// ephemeral is the one command for looking after an Ephemeral Nix machine. It runs the helper
// commands, which stay as they are, and holds the interactive parts: the persistence explorer
// and the menu.
package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"syscall"

	"github.com/charmbracelet/x/term"

	"ephemeral/internal/center"
	"ephemeral/internal/cli"
	"ephemeral/internal/commands"
	"ephemeral/internal/explorer"
)

// set by the build: the tools table as JSON
var manifest = "commands.json"

// the config release this system was built from, as modules/release.nix writes it
func version() string {
	b, err := os.ReadFile("/etc/ephemeral/release")
	if err != nil {
		return "(release unknown)"
	}
	return strings.TrimSpace(string(b))
}

func main() {
	cs, err := commands.Load(manifest)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ephemeral:", err)
		os.Exit(1)
	}
	self, err := os.Executable()
	if err != nil {
		self = "ephemeral"
	}
	os.Exit(cli.Run(os.Args[1:], cli.Env{
		Commands: cs,
		Version:  version(),
		LookPath: exec.LookPath,
		Exec: func(path string, argv []string) error {
			return syscall.Exec(path, argv, os.Environ())
		},
		IsTTY: func() bool {
			return term.IsTerminal(os.Stdin.Fd()) && term.IsTerminal(os.Stdout.Fd())
		},
		Explore: explorer.Run,
		Center:  func() error { return center.Run(cs, self, version(), exec.LookPath) },
		Stdout:  os.Stdout,
		Stderr:  os.Stderr,
	}))
}
