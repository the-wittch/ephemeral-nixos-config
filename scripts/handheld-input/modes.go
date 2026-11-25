package main

const (
	keyEsc       = 1
	keyBackspace = 14
	keyTab       = 15
	keyEnter     = 28
	keyLeftShift = 42
	keyUp        = 103
	keyPageUp    = 104
	keyLeft      = 105
	keyRight     = 106
	keyDown      = 108
	keyPageDown  = 109
)

// What a button does: type a character, which the keymap turns into a key, or press a key that
// means the same on every layout.
type action struct {
	char rune
	key  uint16
}

type mode struct {
	actions map[button]action
	// held keys repeat, for scrolling through a list
	repeat bool
}

var modes = map[string]mode{
	// The characters are the disk passphrase's; they must never change, or a passphrase set
	// with them stops working.
	"passphrase": {
		actions: map[button]action{
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
		},
	},
	"menu": {
		actions: map[button]action{
			btnUp:     {key: keyUp},
			btnDown:   {key: keyDown},
			btnLeft:   {key: keyLeft},
			btnRight:  {key: keyRight},
			btnA:      {key: keyEnter},
			btnB:      {key: keyEsc},
			btnX:      {key: keyBackspace},
			btnY:      {char: '/'},
			btnLB:     {key: keyPageUp},
			btnRB:     {key: keyPageDown},
			btnStart:  {key: keyEnter},
			btnSelect: {key: keyTab},
		},
		repeat: true,
	},
}
