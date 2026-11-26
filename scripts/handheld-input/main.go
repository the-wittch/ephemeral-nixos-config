// Command handheld-input lets a handheld's controller type, on a virtual keyboard, where there's
// no Steam to do it: the disk passphrase at boot, and the installer's screens.
//
// With no argument it types the passphrase; with menu it starts in the installer's keys.
// SIGUSR1 switches to the passphrase and SIGUSR2 back to menu, which the installer sends around
// its passphrase fields, so the passphrase is pressed there as it will be at boot.
//
// It prints nothing about what's pressed: in passphrase mode the presses are the passphrase.
package main

import (
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"sync"
	"syscall"
	"time"
)

type press struct {
	b    button
	down bool
}

// how long a d-pad press waits before repeating, and how often it repeats after
const (
	repeatDelay = 400 * time.Millisecond
	repeatEvery = 80 * time.Millisecond
)

// what the virtual keyboard does, so the presses can be tested without one
type keySender interface {
	key(code uint16, down bool) error
	repeat(code uint16) error
	capsLock() bool
}

type state struct {
	kb   keySender
	km   keymap
	mode mode
	held map[button]stroke
	// the repeating button and when it next repeats
	rep     button
	repNext time.Time
}

func main() {
	start := passphrase
	switch {
	case len(os.Args) == 2 && os.Args[1] == "menu":
		start = menu
	case len(os.Args) != 1:
		fmt.Fprintln(os.Stderr, "usage: handheld-input [menu]")
		os.Exit(2)
	}

	kb, err := newKeyboard()
	if err != nil {
		fmt.Fprintf(os.Stderr, "handheld-input: can't make the virtual keyboard: %v\n", err)
		os.Exit(1)
	}
	var km keymap = layered{}
	if vt, err := openVTKeymap(); err == nil {
		km = layered{first: vt}
	}

	presses := make(chan press, 64)
	go watch(presses)

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	switchTo := make(chan os.Signal, 1)
	signal.Notify(switchTo, syscall.SIGUSR1, syscall.SIGUSR2)
	tick := time.NewTicker(20 * time.Millisecond)

	s := &state{kb: kb, km: km, mode: start, held: map[button]stroke{}}
	for {
		var err error
		select {
		case p := <-presses:
			err = s.handle(p, time.Now())
		case <-tick.C:
			err = s.tick(time.Now())
		case sig := <-switchTo:
			err = s.releaseAll()
			s.mode = menu
			if sig == syscall.SIGUSR1 {
				s.mode = passphrase
			}
		case <-stop:
			s.releaseAll()
			kb.close()
			return
		}
		if err != nil {
			fmt.Fprintf(os.Stderr, "handheld-input: %v\n", err)
		}
	}
}

func (s *state) handle(p press, now time.Time) error {
	if !p.down {
		return s.release(p.b)
	}
	a, ok := s.mode.actions[p.b]
	if _, already := s.held[p.b]; !ok || already {
		return nil
	}
	st := stroke{code: a.key, shift: a.shift}
	if a.char != 0 {
		if st, ok = s.km.find(a.char); !ok {
			return nil
		}
		// with Caps Lock on, Shift is what gives the small letter
		if st.letter && s.kb.capsLock() {
			st.shift = !st.shift
		}
	}
	s.held[p.b] = st
	if s.mode.repeat[p.b] {
		s.rep, s.repNext = p.b, now.Add(repeatDelay)
	}
	if st.shift {
		if err := s.kb.key(keyLeftShift, true); err != nil {
			return err
		}
	}
	return s.kb.key(st.code, true)
}

func (s *state) release(b button) error {
	st, ok := s.held[b]
	if !ok {
		return nil
	}
	delete(s.held, b)
	if s.rep == b {
		s.rep = 0
	}
	if err := s.kb.key(st.code, false); err != nil {
		return err
	}
	if st.shift {
		return s.kb.key(keyLeftShift, false)
	}
	return nil
}

func (s *state) releaseAll() error {
	var first error
	for b := range s.held {
		if err := s.release(b); err != nil && first == nil {
			first = err
		}
	}
	return first
}

func (s *state) tick(now time.Time) error {
	if s.rep == 0 || now.Before(s.repNext) {
		return nil
	}
	s.repNext = now.Add(repeatEvery)
	return s.kb.repeat(s.held[s.rep].code)
}

// watch opens each controller it knows as it appears, and passes on its presses.
func watch(out chan<- press) {
	var mu sync.Mutex
	// open is every device being read; other holds the ones that aren't controllers, so they
	// aren't opened again until they go away
	open := map[string]bool{}
	other := map[string]bool{}
	for {
		paths, _ := filepath.Glob("/dev/input/event*")
		present := map[string]bool{}
		mu.Lock()
		for _, path := range paths {
			present[path] = true
			if open[path] || other[path] {
				continue
			}
			g, err := openGamepad(path)
			if err != nil || g == nil {
				// one that failed to open is tried again, as udev may not have set it up yet
				if err == nil {
					other[path] = true
				}
				continue
			}
			open[path] = true
			go func() {
				p := newPad(g.dev, g.lt, g.rt, func(b button, down bool) { out <- press{b, down} })
				if err := g.read(p); err != nil {
					fmt.Fprintf(os.Stderr, "handheld-input: reading the %s: %v\n", g.dev.name, err)
				}
				mu.Lock()
				delete(open, path)
				mu.Unlock()
			}()
		}
		for path := range other {
			if !present[path] {
				delete(other, path)
			}
		}
		mu.Unlock()
		time.Sleep(250 * time.Millisecond)
	}
}
