// Command handheld-input lets a handheld's controller type on a virtual keyboard, for the disk
// passphrase at boot and the installer's screens, where there's no Steam to do it.
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

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: handheld-input passphrase|menu")
		os.Exit(2)
	}
	m, ok := modes[os.Args[1]]
	if !ok {
		fmt.Fprintf(os.Stderr, "handheld-input: no mode %q; it's passphrase or menu\n", os.Args[1])
		os.Exit(2)
	}

	kb, err := newKeyboard(m.repeat)
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

	held := map[button]stroke{}
	for {
		select {
		case p := <-presses:
			if err := handle(kb, km, m, held, p); err != nil {
				fmt.Fprintf(os.Stderr, "handheld-input: %v\n", err)
			}
		case <-stop:
			kb.close()
			return
		}
	}
}

func handle(kb *keyboard, km keymap, m mode, held map[button]stroke, p press) error {
	if !p.down {
		s, ok := held[p.b]
		if !ok {
			return nil
		}
		delete(held, p.b)
		if err := kb.key(s.code, false); err != nil {
			return err
		}
		if s.shift {
			return kb.key(keyLeftShift, false)
		}
		return nil
	}

	a, ok := m.actions[p.b]
	if _, already := held[p.b]; !ok || already {
		return nil
	}
	s := stroke{code: a.key}
	if a.char != 0 {
		if s, ok = km.find(a.char); !ok {
			return nil
		}
	}
	held[p.b] = s
	if s.shift {
		if err := kb.key(keyLeftShift, true); err != nil {
			return err
		}
	}
	return kb.key(s.code, true)
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
