package main

import (
	"os"
	"syscall"
	"unsafe"
)

// A key, with Shift or without.
type stroke struct {
	code  uint16
	shift bool
}

// The console's layout decides which key types which character: on AZERTY the key US keyboards
// call Q types a. The passphrase prompt reads characters, so each one is looked up in the
// keymap loaded now, not assumed.
type keymap interface {
	find(r rune) (stroke, bool)
}

const kdgkbent = 0x4b46

type kbentry struct {
	table uint8
	index uint8
	value uint16
}

type entryFunc func(table, index uint8) (uint16, bool)

// The console's own keymap, read with KDGKBENT.
type vtKeymap struct{ f *os.File }

func openVTKeymap() (*vtKeymap, error) {
	f, err := os.OpenFile("/dev/tty0", os.O_RDONLY|syscall.O_NOCTTY, 0)
	if err != nil {
		return nil, err
	}
	return &vtKeymap{f}, nil
}

func (k *vtKeymap) entry(table, index uint8) (uint16, bool) {
	e := kbentry{table: table, index: index}
	if ioctl(k.f.Fd(), kdgkbent, unsafe.Pointer(&e)) != nil {
		return 0, false
	}
	return e.value, true
}

func (k *vtKeymap) find(r rune) (stroke, bool) {
	return findIn(k.entry, r)
}

// Plain keys first, then with Shift; the lowest key code wins.
func findIn(entry entryFunc, r rune) (stroke, bool) {
	for _, t := range []struct {
		table uint8
		shift bool
	}{{0, false}, {1, true}} {
		for i := 1; i < 256; i++ {
			v, ok := entry(t.table, uint8(i))
			if !ok {
				return stroke{}, false
			}
			if keysymIs(v, r) {
				return stroke{code: uint16(i), shift: t.shift}, true
			}
		}
	}
	return stroke{}, false
}

// A keysym's high byte is its type: 0x00 a plain character, 0x0b a letter that Caps Lock
// affects, and the same with 0xf0 on top in a Unicode keymap.
func keysymIs(v uint16, r rune) bool {
	if r > 0x7f {
		return false
	}
	switch v >> 8 {
	case 0x00, 0x0b, 0xf0, 0xfb:
		return byte(v) == byte(r)
	}
	return false
}

// US positions, for when there's no console to ask, as in a terminal over SSH.
type usKeymap struct{}

var usKeys = map[rune]uint16{
	'a': 30, 'b': 48, 'c': 46, 'd': 32, 'e': 18, 'l': 38, 'q': 16, 'r': 19,
	's': 31, 't': 20, 'u': 22, 'x': 45, 'y': 21, 'z': 44,
	'1': 2, '2': 3, '3': 4, '4': 5, '/': 53,
}

func (usKeymap) find(r rune) (stroke, bool) {
	c, ok := usKeys[r]
	return stroke{code: c}, ok
}

// The console's keymap, falling back to US positions for a character it doesn't have.
type layered struct {
	first keymap
}

func (l layered) find(r rune) (stroke, bool) {
	if l.first != nil {
		if s, ok := l.first.find(r); ok {
			return s, true
		}
	}
	return usKeymap{}.find(r)
}
