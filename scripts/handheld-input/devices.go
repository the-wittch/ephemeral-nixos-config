package main

type button uint8

const (
	btnA button = iota + 1
	btnB
	btnX
	btnY
	btnLB
	btnRB
	btnLT
	btnRT
	btnLS
	btnRS
	btnUp
	btnDown
	btnLeft
	btnRight
	btnStart
	btnSelect
	btnL4
	btnL5
	btnR4
	btnR5
)

// A controller this knows, by its USB IDs or by the kernel driver that runs it. The buttons are
// named by where they sit, as on an Xbox pad: A at the bottom, B on the right, X on the left, Y at
// the top, so a PlayStation pad's cross types what A does. Generic HID drivers number buttons by
// position, and the drivers made for a pad disagree about BTN_X and BTN_Y, so each table was read
// off the device or the driver's source, never assumed from the codes' names.
type device struct {
	name            string
	vendor, product uint16
	driver          string
	buttons         map[uint16]button
	// the d-pad comes as ABS_HAT0X and ABS_HAT0Y; on the Deck those are the left trackpad
	hatDpad bool
	// LT and RT report only as ABS_Z and ABS_RZ, with no button
	triggerAxes bool
}

var devices = []device{
	{
		// hid_asus, on kernel 6.18. The back buttons send nothing until Handheld Daemon has
		// set the controller up, and the Xbox button is left out on purpose.
		name:    "ROG Xbox Ally X",
		vendor:  0x0b05,
		product: 0x1b4c,
		buttons: map[uint16]button{
			304: btnA,
			305: btnB,
			306: btnX,
			307: btnY,
			308: btnLB,
			309: btnRB,
			310: btnSelect,
			311: btnStart,
			312: btnLS,
			313: btnRS,
		},
		hatDpad:     true,
		triggerAxes: true,
	},
	{
		// hid_steam in 6.18, from its source; to check on a Deck. X and Y come as BTN_X and BTN_Y,
		// as from xpad. The triggers are buttons here, and their analogue side isn't ABS_Z.
		name:    "Steam Deck",
		vendor:  0x28de,
		product: 0x1205,
		buttons: map[uint16]button{
			304: btnA,
			305: btnB,
			307: btnX,
			308: btnY,
			310: btnLB,
			311: btnRB,
			312: btnLT,
			313: btnRT,
			314: btnSelect,
			315: btnStart,
			317: btnLS,
			318: btnRS,
			544: btnUp,
			545: btnDown,
			546: btnLeft,
			547: btnRight,
			// BTN_GRIPL and BTN_GRIPR are the upper back buttons, GRIPL2 and GRIPR2 the lower
			548: btnL4,
			549: btnR4,
			550: btnL5,
			551: btnR5,
		},
	},
	{
		// wired Xbox 360, One and Series pads; X comes as BTN_X and Y as BTN_Y. A few pads
		// send the d-pad as buttons rather than a hat.
		name:   "Xbox controller",
		driver: "xpad",
		buttons: map[uint16]button{
			304: btnA,
			305: btnB,
			307: btnX,
			308: btnY,
			310: btnLB,
			311: btnRB,
			314: btnSelect,
			315: btnStart,
			317: btnLS,
			318: btnRS,
			546: btnLeft,
			547: btnRight,
			544: btnUp,
			545: btnDown,
		},
		hatDpad:     true,
		triggerAxes: true,
	},
	{
		// DualShock 4 and DualSense, wired; triangle is BTN_NORTH and square BTN_WEST. L2 and
		// R2 are buttons as well as axes, and the buttons are used, so a press isn't counted twice.
		name:    "PlayStation controller",
		driver:  "playstation",
		hatDpad: true,
		buttons: map[uint16]button{
			304: btnA,
			305: btnB,
			307: btnY,
			308: btnX,
			310: btnLB,
			311: btnRB,
			312: btnLT,
			313: btnRT,
			314: btnSelect,
			315: btnStart,
			317: btnLS,
			318: btnRS,
		},
	},
}

// The IDs first, since a known device's own table beats its driver's.
func findDevice(vendor, product uint16, driver string) *device {
	for i := range devices {
		if devices[i].vendor != 0 && devices[i].vendor == vendor && devices[i].product == product {
			return &devices[i]
		}
	}
	for i := range devices {
		if devices[i].driver != "" && devices[i].driver == driver {
			return &devices[i]
		}
	}
	return nil
}
