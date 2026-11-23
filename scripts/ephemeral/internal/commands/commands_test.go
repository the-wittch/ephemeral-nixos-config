package commands

import (
	"os"
	"path/filepath"
	"testing"
)

func TestTheLongestWordsWinAndTheRestIsLeft(t *testing.T) {
	cs := []Command{{Name: "a", Words: []string{"backup"}}, {Name: "b", Words: []string{"backup", "setup"}}}
	c, rest, ok := Find(cs, []string{"backup", "setup", "add", "x"})
	if !ok || c.Name != "b" || len(rest) != 2 || rest[0] != "add" {
		t.Fatalf("got %v %v %v", c, rest, ok)
	}
	if _, _, ok := Find(cs, []string{"back"}); ok {
		t.Fatalf("a part of a word matched")
	}
}

func TestNearestNamesWhatWasMeant(t *testing.T) {
	words := []string{"update", "doctor", "persistence", "backup"}
	for typed, want := range map[string]string{"updat": "update", "docter": "doctor", "pers": "persistence", "zzz": ""} {
		if got := Nearest(words, typed); got != want {
			t.Errorf("%s: got %q, want %q", typed, got, want)
		}
	}
}

func TestLoadReadsTheTableAndSortsIt(t *testing.T) {
	p := filepath.Join(t.TempDir(), "c.json")
	os.WriteFile(p, []byte(`[{"name": "z", "words": ["update"], "description": "d", "minimal": true},
		{"name": "y", "words": ["apps"], "description": "e", "minimal": false}]`), 0o644)
	cs, err := Load(p)
	if err != nil || len(cs) != 2 || cs[0].Name != "y" || !cs[1].Minimal {
		t.Fatalf("got %+v, %v", cs, err)
	}
	if _, err := Load(filepath.Join(t.TempDir(), "missing.json")); err == nil {
		t.Fatalf("a missing table loaded")
	}
}
