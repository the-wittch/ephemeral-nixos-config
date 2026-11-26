// Command steam-shortcuts adds the launchers picked in the app catalog to Steam as non-Steam
// games, so they're in Game Mode's library. It runs before Steam starts, as Steam writes its own
// copy of shortcuts.vdf back when it exits.
//
// It only adds. A shortcut it added once isn't added again, so one deleted in Steam stays
// deleted, and nothing a person added or changed is touched.
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"hash/crc32"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
)

type shortcut struct {
	Name string `json:"name"`
	Exe  string `json:"exe"`
	Args string `json:"args"`
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: steam-shortcuts shortcuts.json")
		os.Exit(2)
	}
	if err := run(os.Args[1], os.Getenv("HOME"), stateFile()); err != nil {
		fmt.Fprintf(os.Stderr, "steam-shortcuts: %v\n", err)
		os.Exit(1)
	}
}

func stateFile() string {
	dir := os.Getenv("XDG_STATE_HOME")
	if dir == "" {
		dir = filepath.Join(os.Getenv("HOME"), ".local/state")
	}
	return filepath.Join(dir, "ephemeral/steam-shortcuts")
}

func run(listPath, home, statePath string) error {
	data, err := os.ReadFile(listPath)
	if err != nil {
		return err
	}
	var want []shortcut
	if err := json.Unmarshal(data, &want); err != nil {
		return fmt.Errorf("%s: %w", listPath, err)
	}
	// one Steam account per folder, named by its account id; 0 is the logged-out one
	users, _ := filepath.Glob(filepath.Join(home, ".local/share/Steam/userdata/[1-9]*"))
	if len(users) == 0 {
		return nil
	}
	added, err := readState(statePath)
	if err != nil {
		return err
	}
	for _, dir := range users {
		id := filepath.Base(dir)
		if _, err := strconv.ParseUint(id, 10, 32); err != nil {
			continue
		}
		var todo []shortcut
		for _, s := range want {
			if !slices.Contains(added, id+" "+s.Name) {
				todo = append(todo, s)
			}
		}
		if len(todo) == 0 {
			continue
		}
		if err := addTo(filepath.Join(dir, "config/shortcuts.vdf"), todo, home); err != nil {
			fmt.Fprintf(os.Stderr, "steam-shortcuts: account %s: %v\n", id, err)
			continue
		}
		for _, s := range todo {
			added = append(added, id+" "+s.Name)
		}
	}
	return writeState(statePath, added)
}

func addTo(path string, todo []shortcut, home string) error {
	mode := os.FileMode(0o600)
	nodes := []node{{typ: typeMap, name: "shortcuts"}}
	data, err := os.ReadFile(path)
	switch {
	case err == nil:
		if nodes, err = parseVDF(data); err != nil {
			return fmt.Errorf("%s isn't a shortcuts file this can read, so it's left alone: %w", path, err)
		}
		if st, err := os.Stat(path); err == nil {
			mode = st.Mode().Perm()
		}
	case !errors.Is(err, os.ErrNotExist):
		return err
	}
	root := &nodes[0]
	if len(nodes) != 1 || root.typ != typeMap || root.name != "shortcuts" {
		return fmt.Errorf("%s doesn't start with shortcuts, so it's left alone", path)
	}
	next := 0
	for _, k := range root.kids {
		if i, err := strconv.Atoi(k.name); err == nil && i >= next {
			next = i + 1
		}
	}
	for _, s := range todo {
		// one already there by name, made by hand or before this kept track, isn't doubled
		if hasName(root, s.Name) {
			continue
		}
		root.kids = append(root.kids, entry(strconv.Itoa(next), s, home))
		next++
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp := path + ".ephemeral"
	if err := os.WriteFile(tmp, writeVDF(nodes), mode); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func hasName(root *node, name string) bool {
	for i := range root.kids {
		if n := root.kids[i].get("AppName"); n != nil && string(n.value) == name {
			return true
		}
		// older files spell it appname
		if n := root.kids[i].get("appname"); n != nil && string(n.value) == name {
			return true
		}
	}
	return false
}

// The fields Steam itself writes for a non-Steam game. Its id is the one Steam would work out
// from the program and the name, so artwork and controller layouts people set stay with it.
func entry(index string, s shortcut, home string) node {
	exe := `"` + s.Exe + `"`
	return node{typ: typeMap, name: index, kids: []node{
		i32("appid", crc32.ChecksumIEEE([]byte(exe+s.Name))|0x80000000),
		str("AppName", s.Name),
		str("Exe", exe),
		str("StartDir", `"`+home+`"`),
		str("icon", ""),
		str("ShortcutPath", ""),
		str("LaunchOptions", s.Args),
		i32("IsHidden", 0),
		i32("AllowDesktopConfig", 1),
		i32("AllowOverlay", 1),
		i32("OpenVR", 0),
		i32("Devkit", 0),
		str("DevkitGameID", ""),
		i32("DevkitOverrideAppID", 0),
		i32("LastPlayTime", 0),
		str("FlatpakAppID", ""),
		{typ: typeMap, name: "tags"},
	}}
}

func readState(path string) ([]string, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var out []string
	for _, l := range strings.Split(string(data), "\n") {
		if l != "" {
			out = append(out, l)
		}
	}
	return out, nil
}

func writeState(path string, lines []string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644)
}
