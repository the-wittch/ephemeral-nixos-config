package explorer

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
)

// The JSON `ephemeral-doctor persistence --json` prints, version 1; docs/persistence.md
// describes it. The explorer classifies nothing itself.
type report struct {
	Version   int  `json:"version"`
	AsRoot    bool `json:"as_root"`
	Truncated bool `json:"truncated"`
	System    struct {
		ConfigRelease string `json:"config_release"`
	} `json:"system"`
	Backup backup  `json:"backup"`
	Paths  []entry `json:"paths"`
}

type backup struct {
	Configured  bool    `json:"configured"`
	LastResult  *string `json:"last_result"`
	LastSuccess *string `json:"last_success"`
}

type entry struct {
	Path              string       `json:"path"`
	Exists            string       `json:"exists"`
	Type              *string      `json:"type"`
	Owner             *string      `json:"owner"`
	Group             *string      `json:"group"`
	Mode              *string      `json:"mode"`
	Link              *string      `json:"link"`
	Classification    string       `json:"classification"`
	OwnClassification string       `json:"own_classification"`
	SurvivesReboot    *bool        `json:"survives_reboot"`
	Mechanism         string       `json:"mechanism"`
	Backing           backing      `json:"backing"`
	Declared          bool         `json:"declared"`
	Declaration       *declaration `json:"declaration"`
	DeclaredIn        []string     `json:"declared_in"`
	InsideDeclared    *string      `json:"inside_declared"`
	Verified          *bool        `json:"verified"`
	KeptInside        []string     `json:"kept_inside"`
	UnknownInside     bool         `json:"unknown_inside"`
	BackupCoverage    string       `json:"backup_coverage"`
	BackupReason      *string      `json:"backup_reason"`
	BackupVia         *string      `json:"backup_via"`
	Notes             []string     `json:"notes"`
}

type backing struct {
	Mount     *string `json:"mount"`
	FsType    *string `json:"fs_type"`
	Subvolume *string `json:"subvolume"`
}

type declaration struct {
	Kind  string `json:"kind"`
	How   string `json:"how"`
	User  string `json:"user"`
	Group string `json:"group"`
	Mode  string `json:"mode"`
}

func (e entry) isDir() bool { return e.Type != nil && *e.Type == "directory" }

func (e entry) name() string {
	if e.Path == "/" {
		return "/"
	}
	return e.Path[strings.LastIndex(e.Path, "/")+1:]
}

// loader reads a folder and what's directly in it; the first path is the folder
type loader func(dir string) (report, error)

func parseReport(out []byte) (report, error) {
	var r report
	if err := json.Unmarshal(out, &r); err != nil {
		return r, fmt.Errorf("couldn't read what ephemeral-doctor printed: %w", err)
	}
	if r.Version != 1 {
		return r, fmt.Errorf("ephemeral-doctor printed version %d of its JSON, and this reads version 1", r.Version)
	}
	return r, nil
}

func engineLoader(engine string) loader {
	return func(dir string) (report, error) {
		out, err := exec.Command(engine, "persistence", "--children", dir).Output()
		if err != nil {
			return report{}, engineError(dir, err)
		}
		return parseReport(out)
	}
}

// engineError is one line, since it's shown in the tree: a doctor from before config 5.1.0
// refuses persistence as an unknown command (exit 2), and anything else gives its first line
func engineError(dir string, err error) error {
	ee, ok := err.(*exec.ExitError)
	if !ok {
		return fmt.Errorf("couldn't run ephemeral-doctor: %v", err)
	}
	if ee.ExitCode() == 2 {
		return fmt.Errorf("this machine's ephemeral-doctor is older than config 5.1.0, which it needs; ephemeral update gets it")
	}
	for _, l := range strings.Split(string(ee.Stderr), "\n") {
		if l = strings.TrimSpace(l); l != "" {
			return fmt.Errorf("ephemeral-doctor couldn't read %s: %s", dir, l)
		}
	}
	return fmt.Errorf("ephemeral-doctor couldn't read %s: it exited %d", dir, ee.ExitCode())
}
