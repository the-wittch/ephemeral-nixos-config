package main

import (
	"encoding/json"
	"fmt"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"
)

func allyPad(t *testing.T) (*pad, *[]press) {
	t.Helper()
	dev := findDevice(0x0b05, 0x1b4c, "asus")
	if dev == nil {
		t.Fatal("no table for the ROG Ally X")
	}
	var got []press
	trig := axisRange{0, 1023}
	return newPad(dev, trig, trig, func(b button, down bool) { got = append(got, press{b, down}) }), &got
}

func TestAllyButtons(t *testing.T) {
	p, got := allyPad(t)
	p.event(evKey, 304, 1)
	p.event(evKey, 304, 2)
	p.event(evKey, 304, 0)
	p.event(evKey, 311, 1)
	// the Xbox button, left out
	p.event(evKey, 314, 1)
	want := []press{{btnA, true}, {btnA, false}, {btnStart, true}}
	if !reflect.DeepEqual(*got, want) {
		t.Fatalf("got %v, want %v", *got, want)
	}
}

func TestHat(t *testing.T) {
	p, got := allyPad(t)
	p.event(evAbs, absHat0Y, -1)
	p.event(evAbs, absHat0Y, -1)
	p.event(evAbs, absHat0Y, 1)
	p.event(evAbs, absHat0Y, 0)
	p.event(evAbs, absHat0X, 1)
	p.event(evAbs, absHat0X, 0)
	want := []press{
		{btnUp, true}, {btnUp, false}, {btnDown, true}, {btnDown, false},
		{btnRight, true}, {btnRight, false},
	}
	if !reflect.DeepEqual(*got, want) {
		t.Fatalf("got %v, want %v", *got, want)
	}
}

func TestTriggerNeedsHalfWayAndLetsGoBelowAQuarter(t *testing.T) {
	p, got := allyPad(t)
	for _, v := range []int32{100, 400, 600, 300, 700, 200, 1023, 0} {
		p.event(evAbs, absZ, v)
	}
	want := []press{{btnLT, true}, {btnLT, false}, {btnLT, true}, {btnLT, false}}
	if !reflect.DeepEqual(*got, want) {
		t.Fatalf("got %v, want %v", *got, want)
	}
}

// The passphrase characters are what people's disks are locked with, so they're pinned here.
func TestPassphraseCharactersNeverChange(t *testing.T) {
	want := map[button]rune{
		btnA: 'a', btnB: 'b', btnX: 'x', btnY: 'y',
		btnUp: 'u', btnDown: 'd', btnLeft: 'l', btnRight: 'r',
		btnLB: 'q', btnRB: 'e', btnLT: 'z', btnRT: 'c', btnLS: 's', btnRS: 't',
		btnL4: '1', btnL5: '2', btnR4: '3', btnR5: '4',
	}
	acts := passphrase.actions
	for b, r := range want {
		if acts[b].char != r {
			t.Errorf("button %d types %q, want %q", b, acts[b].char, r)
		}
	}
	if acts[btnStart].key != keyEnter || acts[btnSelect].key != keyBackspace {
		t.Error("Start must be Enter and Select Backspace")
	}
	if len(acts) != len(want)+2 {
		t.Errorf("%d buttons type something, want %d", len(acts), len(want)+2)
	}
}

// French AZERTY, as the kernel reports it: a and q swapped, z on US W, digits with Shift.
func azerty(table, index uint8) (uint16, bool) {
	plain := map[uint8]uint16{16: 0xfb61, 17: 0xfb7a, 30: 0xfb71, 44: 0xfb77, 2: 0xf026, 52: 0xf03a}
	shift := map[uint8]uint16{16: 0xfb41, 2: 0xf031, 52: 0xf02f}
	if table == 0 {
		return plain[index], true
	}
	return shift[index], true
}

func TestKeymapLookup(t *testing.T) {
	cases := []struct {
		r    rune
		want stroke
	}{
		{'a', stroke{16, false, true}},
		{'q', stroke{30, false, true}},
		{'z', stroke{17, false, true}},
		{'1', stroke{2, true, false}},
		{'/', stroke{52, true, false}},
	}
	for _, c := range cases {
		got, ok := findIn(azerty, c.r)
		if !ok || got != c.want {
			t.Errorf("%q: got %v %v, want %v", c.r, got, ok, c.want)
		}
	}
	if _, ok := findIn(azerty, 'b'); ok {
		t.Error("found b, which this keymap doesn't have")
	}
}

func TestEveryCharacterHasAUSKey(t *testing.T) {
	for _, m := range []mode{passphrase, menu} {
		for b, a := range m.actions {
			if a.char == 0 {
				continue
			}
			if _, ok := (usKeymap{}).find(a.char); !ok {
				t.Errorf("button %d: no US key for %q", b, a.char)
			}
		}
	}
}

func presses(t *testing.T, dev *device, events [][3]int32) []press {
	t.Helper()
	if dev == nil {
		t.Fatal("no table")
	}
	var got []press
	trig := axisRange{0, 255}
	p := newPad(dev, trig, trig, func(b button, down bool) { got = append(got, press{b, down}) })
	for _, e := range events {
		p.event(uint16(e[0]), uint16(e[1]), e[2])
	}
	return got
}

// From drivers/input/joystick/xpad.c in 6.18: X is BTN_X and Y is BTN_Y, which the kernel
// defines as BTN_NORTH and BTN_WEST, the other way round from where they sit.
func TestXboxByDriver(t *testing.T) {
	got := presses(t, findDevice(0x045e, 0x0b12, "xpad"), [][3]int32{
		{evKey, 307, 1}, {evKey, 308, 1}, {evKey, 315, 1}, {evKey, 546, 1}, {evAbs, absRZ, 255},
	})
	want := []press{{btnX, true}, {btnY, true}, {btnStart, true}, {btnLeft, true}, {btnRT, true}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}

// From drivers/hid/hid-playstation.c in 6.18: the triggers come as buttons and as axes, and only
// the buttons count.
func TestPlayStationByDriver(t *testing.T) {
	got := presses(t, findDevice(0x054c, 0x0ce6, "playstation"), [][3]int32{
		{evKey, 307, 1}, {evKey, 308, 1}, {evKey, 312, 1}, {evAbs, absZ, 255}, {evKey, 314, 1},
	})
	want := []press{{btnY, true}, {btnX, true}, {btnLT, true}, {btnSelect, true}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}

func TestUnknownControllerIsIgnored(t *testing.T) {
	if findDevice(0x1234, 0x5678, "hid-generic") != nil {
		t.Fatal("matched a controller it has no table for")
	}
}

// The config's table, modules/handheld/_buttons.nix, is what the installer shows and checks a
// passphrase against. The Nix build passes it in; a plain go test has nothing to compare with.
func TestMatchesTheConfigTable(t *testing.T) {
	path := os.Getenv("HANDHELD_BUTTONS")
	if path == "" {
		t.Skip("HANDHELD_BUTTONS isn't set")
	}
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var rows []struct{ Button, Character string }
	if err := json.Unmarshal(b, &rows); err != nil {
		t.Fatal(err)
	}
	names := map[string]button{
		"A": btnA, "B": btnB, "X": btnX, "Y": btnY,
		"d-pad up": btnUp, "d-pad down": btnDown, "d-pad left": btnLeft, "d-pad right": btnRight,
		"LB": btnLB, "RB": btnRB, "LT": btnLT, "RT": btnRT,
		"left stick press": btnLS, "right stick press": btnRS,
		"L4": btnL4, "L5": btnL5, "R4": btnR4, "R5": btnR5,
	}
	acts := passphrase.actions
	for _, r := range rows {
		b, ok := names[r.Button]
		if !ok {
			t.Errorf("the config's table has %q, which this doesn't know", r.Button)
			continue
		}
		if string(acts[b].char) != r.Character {
			t.Errorf("%s types %q here and %q in the config's table", r.Button, acts[b].char, r.Character)
		}
	}
	if len(rows) != len(names) {
		t.Errorf("the config's table has %d buttons, this has %d", len(rows), len(names))
	}
}

// From drivers/hid/hid-steam.c in 6.18. Its ABS_HAT0 is the left trackpad, which mustn't type.
func TestDeck(t *testing.T) {
	got := presses(t, findDevice(0x28de, 0x1205, "hid-steam"), [][3]int32{
		{evAbs, absHat0X, 1}, {evKey, 544, 1}, {evKey, 307, 1}, {evKey, 548, 1}, {evKey, 551, 1},
		{evKey, 312, 1}, {evAbs, absZ, 255},
	})
	want := []press{{btnUp, true}, {btnX, true}, {btnL4, true}, {btnR5, true}, {btnLT, true}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}

// what a test keyboard was sent, as code+ or code- or code*, for a repeat
type fakeKeys struct {
	sent []string
	caps bool
}

func (f *fakeKeys) key(code uint16, down bool) error {
	f.sent = append(f.sent, fmt.Sprintf("%d%s", code, map[bool]string{true: "+", false: "-"}[down]))
	return nil
}

func (f *fakeKeys) repeat(code uint16) error {
	f.sent = append(f.sent, fmt.Sprintf("%d*", code))
	return nil
}

func (f *fakeKeys) capsLock() bool { return f.caps }

func newState(m mode) (*state, *fakeKeys) {
	kb := &fakeKeys{}
	return &state{kb: kb, km: usKeymap{}, mode: m, held: map[button]stroke{}}, kb
}

func TestCapsLockStillTypesSmallLetters(t *testing.T) {
	s, kb := newState(passphrase)
	kb.caps = true
	now := time.Now()
	s.handle(press{btnA, true}, now)
	s.handle(press{btnA, false}, now)
	s.handle(press{btnL4, true}, now)
	s.handle(press{btnL4, false}, now)
	// Shift around a, as Caps Lock is on; none around 1, which Caps Lock doesn't change
	want := "42+ 30+ 30- 42- 2+ 2-"
	if got := strings.Join(kb.sent, " "); got != want {
		t.Errorf("sent %s, want %s", got, want)
	}
}

func TestPassphraseNeverRepeats(t *testing.T) {
	s, kb := newState(passphrase)
	now := time.Now()
	s.handle(press{btnUp, true}, now)
	s.tick(now.Add(2 * time.Second))
	if got := strings.Join(kb.sent, " "); got != "22+" {
		t.Errorf("sent %s, want only u pressed", got)
	}
}

func TestMenuRepeatsTheDpad(t *testing.T) {
	s, kb := newState(menu)
	now := time.Now()
	s.handle(press{btnDown, true}, now)
	s.tick(now.Add(repeatDelay / 2))
	s.tick(now.Add(repeatDelay))
	s.tick(now.Add(repeatDelay + repeatEvery))
	s.handle(press{btnDown, false}, now)
	s.tick(now.Add(10 * time.Second))
	want := "108+ 108* 108* 108-"
	if got := strings.Join(kb.sent, " "); got != want {
		t.Errorf("sent %s, want %s", got, want)
	}
}

func TestMenuShiftTab(t *testing.T) {
	s, kb := newState(menu)
	s.handle(press{btnLB, true}, time.Now())
	s.handle(press{btnLB, false}, time.Now())
	if got, want := strings.Join(kb.sent, " "), "42+ 15+ 15- 42-"; got != want {
		t.Errorf("sent %s, want %s", got, want)
	}
}

// switching mode lets go of what's held, so no key is left down on the other side
func TestSwitchingReleasesHeldKeys(t *testing.T) {
	s, kb := newState(menu)
	s.handle(press{btnA, true}, time.Now())
	s.releaseAll()
	s.mode = passphrase
	s.handle(press{btnA, false}, time.Now())
	if got, want := strings.Join(kb.sent, " "), "28+ 28-"; got != want {
		t.Errorf("sent %s, want %s", got, want)
	}
}
