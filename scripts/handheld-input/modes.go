package main

const (
	keyBackspace = 14
	keyEnter     = 28
	keyLeftShift = 42
)

// What a button does: type a character, which the keymap turns into a key, or press a key that
// means the same on every layout.
type action struct {
	char rune
	key  uint16
}

// The characters are the disk passphrase's; they must never change, or a passphrase set with
// them stops working. Nothing repeats while held.
var passphrase = map[button]action{
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
}
