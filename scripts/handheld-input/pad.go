package main

const (
	evKey = 0x01
	evAbs = 0x03

	absZ     = 0x02
	absRZ    = 0x05
	absHat0X = 0x10
	absHat0Y = 0x11
)

type axisRange struct{ min, max int32 }

// A trigger counts as pressed past half way and released below a quarter, so a finger resting
// on it doesn't press it again and again.
type trigger struct {
	on, off int32
	down    bool
}

func newTrigger(r axisRange) trigger {
	span := r.max - r.min
	return trigger{on: r.min + span/2, off: r.min + span/4}
}

// pad turns one controller's events into button presses and releases.
type pad struct {
	dev     *device
	lt, rt  trigger
	hatX    int32
	hatY    int32
	pressed func(b button, down bool)
}

func newPad(dev *device, lt, rt axisRange, pressed func(button, bool)) *pad {
	return &pad{dev: dev, lt: newTrigger(lt), rt: newTrigger(rt), pressed: pressed}
}

func (p *pad) event(typ, code uint16, value int32) {
	switch typ {
	case evKey:
		b, ok := p.dev.buttons[code]
		// 2 is the kernel's own repeat
		if !ok || value == 2 {
			return
		}
		p.pressed(b, value == 1)
	case evAbs:
		switch code {
		case absHat0X:
			if !p.dev.hatDpad {
				return
			}
			p.hatX = p.hat(p.hatX, value, btnLeft, btnRight)
		case absHat0Y:
			if !p.dev.hatDpad {
				return
			}
			p.hatY = p.hat(p.hatY, value, btnUp, btnDown)
		case absZ:
			if p.dev.triggerAxes {
				p.trigger(&p.lt, value, btnLT)
			}
		case absRZ:
			if p.dev.triggerAxes {
				p.trigger(&p.rt, value, btnRT)
			}
		}
	}
}

func (p *pad) hat(was, now int32, neg, pos button) int32 {
	if was == now {
		return now
	}
	switch was {
	case -1:
		p.pressed(neg, false)
	case 1:
		p.pressed(pos, false)
	}
	switch now {
	case -1:
		p.pressed(neg, true)
	case 1:
		p.pressed(pos, true)
	}
	return now
}

func (p *pad) trigger(t *trigger, value int32, b button) {
	switch {
	case !t.down && value >= t.on:
		t.down = true
		p.pressed(b, true)
	case t.down && value <= t.off:
		t.down = false
		p.pressed(b, false)
	}
}
