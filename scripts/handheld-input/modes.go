package main

const (
	keyEsc       = 1
	keyBackspace = 14
	keyTab       = 15
	keyEnter     = 28
	keyLeftShift = 42
	keySpace     = 57
	keyF2        = 60
	keyUp        = 103
	keyLeft      = 105
	keyRight     = 106
	keyDown      = 108
)

// What a button does: type a character, which the keymap turns into a key, or press a key that
// means the same on every layout.
type action struct {
	char  rune
	key   uint16
	shift bool
}

type mode struct {
	actions map[button]action
	// held, these repeat, for moving through a list
	repeat map[button]bool
}

// The characters are the disk passphrase's; they must never change, or a passphrase set with
// them stops working. Nothing repeats while held.
var passphrase = mode{actions: map[button]action{
	btnA:      {char: 'a'},
	btnB:      {char: 'b'},
	btnX:      {char: 'x'},
	btnY:      {char: 'y'},
	btnUp:     {char: 'u'},
	btnDown:   {char: 'd'},
	btnLeft:   {char: 'l'},
	btnRight:  {char: 'r'},
	btnLB:     {char: 'q'},
	btnRB:     {char: 'e'},
	btnLT:     {char: 'z'},
	btnRT:     {char: 'c'},
	btnLS:     {char: 's'},
	btnRS:     {char: 't'},
	btnL4:     {char: '1'},
	btnL5:     {char: '2'},
	btnR4:     {char: '3'},
	btnR5:     {char: '4'},
	btnStart:  {key: keyEnter},
	btnSelect: {key: keyBackspace},
}}

// The installer's screens: X ticks a box, as space does there, and Y opens their on-screen
// keyboard, which F2 does.
var menu = mode{
	actions: map[button]action{
		btnUp:     {key: keyUp},
		btnDown:   {key: keyDown},
		btnLeft:   {key: keyLeft},
		btnRight:  {key: keyRight},
		btnA:      {key: keyEnter},
		btnStart:  {key: keyEnter},
		btnB:      {key: keyEsc},
		btnX:      {key: keySpace},
		btnY:      {key: keyF2},
		btnSelect: {key: keyBackspace},
		btnLB:     {key: keyTab, shift: true},
		btnRB:     {key: keyTab},
	},
	repeat: map[button]bool{btnUp: true, btnDown: true, btnLeft: true, btnRight: true},
}
