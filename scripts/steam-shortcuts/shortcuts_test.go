package main

import (
	"bytes"
	"encoding/binary"
	"os"
	"path/filepath"
	"testing"
)

// A shortcuts.vdf as Steam writes one, with a game added by hand, a float and a 64-bit field.
func steamFile() []byte {
	var b bytes.Buffer
	b.WriteString("\x00shortcuts\x00")
	b.WriteString("\x000\x00")
	b.WriteString("\x02appid\x00\x01\x02\x03\x84")
	b.WriteString("\x01AppName\x00My Game\x00")
	b.WriteString("\x01Exe\x00\"/home/me/game\"\x00")
	b.WriteString("\x03scale\x00\x00\x00\x80\x3f")
	b.WriteString("\x07played\x00\x01\x00\x00\x00\x00\x00\x00\x00")
	b.WriteString("\x00tags\x00\x010\x00Favourites\x00\x08")
	b.WriteString("\x08")
	b.WriteString("\x08\x08")
	return b.Bytes()
}

func TestReadAndWriteBackIsTheSameFile(t *testing.T) {
	nodes, err := parseVDF(steamFile())
	if err != nil {
		t.Fatal(err)
	}
	if got := writeVDF(nodes); !bytes.Equal(got, steamFile()) {
		t.Errorf("wrote back\n%q\nwant\n%q", got, steamFile())
	}
}

func TestUnknownTypeIsRefused(t *testing.T) {
	if _, err := parseVDF([]byte("\x00shortcuts\x00\x05odd\x00\x08\x08")); err == nil {
		t.Error("read a type it doesn't know")
	}
	if _, err := parseVDF([]byte("\x00shortcuts\x00\x01AppName\x00cut off")); err == nil {
		t.Error("read a file that stops half way")
	}
}

func setup(t *testing.T, list string) (home, listPath, state, vdf string) {
	t.Helper()
	home = t.TempDir()
	vdf = filepath.Join(home, ".local/share/Steam/userdata/12345/config/shortcuts.vdf")
	if err := os.MkdirAll(filepath.Dir(vdf), 0o755); err != nil {
		t.Fatal(err)
	}
	listPath = filepath.Join(home, "list.json")
	if err := os.WriteFile(listPath, []byte(list), 0o644); err != nil {
		t.Fatal(err)
	}
	return home, listPath, filepath.Join(home, "state"), vdf
}

const heroic = `[{"name":"Heroic","exe":"/run/current-system/sw/bin/flatpak","args":"run com.heroicgameslauncher.hgl"}]`

func names(t *testing.T, vdf string) []string {
	t.Helper()
	data, err := os.ReadFile(vdf)
	if err != nil {
		t.Fatal(err)
	}
	nodes, err := parseVDF(data)
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, k := range nodes[0].kids {
		out = append(out, string(k.get("AppName").value))
	}
	return out
}

func TestAddsNextToWhatsThere(t *testing.T) {
	home, list, state, vdf := setup(t, heroic)
	if err := os.WriteFile(vdf, steamFile(), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := run(list, home, state); err != nil {
		t.Fatal(err)
	}
	got := names(t, vdf)
	if len(got) != 2 || got[0] != "My Game" || got[1] != "Heroic" {
		t.Errorf("got %v, want My Game then Heroic", got)
	}
	data, _ := os.ReadFile(vdf)
	nodes, _ := parseVDF(data)
	h := nodes[0].kids[1]
	if h.name != "1" || string(h.get("Exe").value) != `"/run/current-system/sw/bin/flatpak"` {
		t.Errorf("Heroic is entry %q with Exe %q", h.name, h.get("Exe").value)
	}
	if id := binary.LittleEndian.Uint32(h.get("appid").value); id&0x80000000 == 0 {
		t.Errorf("appid %x hasn't got Steam's top bit for a non-Steam game", id)
	}
	orig, _ := parseVDF(steamFile())
	if !bytes.Equal(writeVDF(nodes[0].kids[:1]), writeVDF(orig[0].kids)) {
		t.Error("the game added by hand changed")
	}
	if st, _ := os.Stat(vdf); st.Mode().Perm() != 0o600 {
		t.Errorf("mode is %v, want the file's own 0600", st.Mode().Perm())
	}
}

func TestADeletedShortcutStaysDeleted(t *testing.T) {
	home, list, state, vdf := setup(t, heroic)
	if err := run(list, home, state); err != nil {
		t.Fatal(err)
	}
	if got := names(t, vdf); len(got) != 1 {
		t.Fatalf("got %v, want Heroic", got)
	}
	// deleted in Steam
	if err := os.WriteFile(vdf, []byte("\x00shortcuts\x00\x08\x08"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := run(list, home, state); err != nil {
		t.Fatal(err)
	}
	if got := names(t, vdf); len(got) != 0 {
		t.Errorf("added %v again after it was deleted", got)
	}
}

func TestOneWithTheSameNameIsntDoubled(t *testing.T) {
	home, list, state, vdf := setup(t, `[{"name":"My Game","exe":"/x","args":""}]`)
	if err := os.WriteFile(vdf, steamFile(), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := run(list, home, state); err != nil {
		t.Fatal(err)
	}
	if got := names(t, vdf); len(got) != 1 {
		t.Errorf("got %v, want My Game once", got)
	}
}

func TestAFileItCantReadIsLeftAlone(t *testing.T) {
	home, list, state, vdf := setup(t, heroic)
	odd := []byte("\x00shortcuts\x00\x05odd\x00\x08\x08")
	if err := os.WriteFile(vdf, odd, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := run(list, home, state); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(vdf); !bytes.Equal(data, odd) {
		t.Error("rewrote a file it couldn't read")
	}
	if s, _ := readState(state); len(s) != 0 {
		t.Errorf("recorded %v as added", s)
	}
}

func TestNoSteamAccountYet(t *testing.T) {
	home := t.TempDir()
	list := filepath.Join(home, "list.json")
	os.WriteFile(list, []byte(heroic), 0o644)
	if err := run(list, home, filepath.Join(home, "state")); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(home, "state")); err == nil {
		t.Error("recorded something with no Steam account to add it to")
	}
}
