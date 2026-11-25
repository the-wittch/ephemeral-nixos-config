package main

import (
	"encoding/binary"
	"errors"
	"io"
	"os"
	"path/filepath"
	"syscall"
	"unsafe"
)

func ioctl(fd, req uintptr, arg unsafe.Pointer) error {
	_, _, e := syscall.Syscall(syscall.SYS_IOCTL, fd, req, uintptr(arg))
	if e != 0 {
		return e
	}
	return nil
}

func ioctlInt(fd, req, arg uintptr) error {
	_, _, e := syscall.Syscall(syscall.SYS_IOCTL, fd, req, arg)
	if e != 0 {
		return e
	}
	return nil
}

const (
	eviocgid   = 0x80084502
	eviocgrab  = 0x40044590
	eviocgabs  = 0x80184540 // + the axis
	keyBitsLen = 96
	// EVIOCGBIT(EV_KEY, keyBitsLen)
	eviocgbitKey = 0x80000000 | keyBitsLen<<16 | 0x4521

	btnSouth = 304

	uiSetEvbit   = 0x40045564
	uiSetKeybit  = 0x40045565
	uiDevSetup   = 0x405c5503
	uiDevCreate  = 0x5501
	uiDevDestroy = 0x5502

	evRep      = 0x14
	busVirtual = 0x06

	// struct input_event on 64-bit Linux, the only kind of machine this runs on
	eventSize = 24
)

type inputID struct {
	bustype, vendor, product, version uint16
}

type absInfo struct {
	value, min, max, fuzz, flat, resolution int32
}

// A controller this knows, opened and grabbed so its presses reach nothing else.
type gamepad struct {
	f   *os.File
	dev *device
	lt  axisRange
	rt  axisRange
}

// openGamepad returns nil, nil for an input device that isn't a known controller: an unknown
// one, or one of a known controller's other devices, such as the four the Ally X calls
// "Asus Keyboard" with the same IDs, of which one has gamepad buttons.
func openGamepad(path string) (*gamepad, error) {
	f, err := os.OpenFile(path, os.O_RDONLY|syscall.O_CLOEXEC, 0)
	if err != nil {
		return nil, err
	}
	var id inputID
	if err := ioctl(f.Fd(), eviocgid, unsafe.Pointer(&id)); err != nil {
		f.Close()
		return nil, err
	}
	dev := findDevice(id.vendor, id.product, driverOf(path))
	var bits [keyBitsLen]byte
	if dev == nil || ioctl(f.Fd(), eviocgbitKey, unsafe.Pointer(&bits)) != nil ||
		bits[btnSouth/8]&(1<<(btnSouth%8)) == 0 {
		f.Close()
		return nil, nil
	}
	g := &gamepad{f: f, dev: dev}
	if dev.triggerAxes {
		g.lt = axis(f, absZ)
		g.rt = axis(f, absRZ)
	}
	if err := ioctlInt(f.Fd(), eviocgrab, 1); err != nil {
		f.Close()
		return nil, err
	}
	return g, nil
}

func axis(f *os.File, code uintptr) axisRange {
	var a absInfo
	if ioctl(f.Fd(), eviocgabs+code, unsafe.Pointer(&a)) != nil || a.max <= a.min {
		// never pressed rather than always
		return axisRange{min: 0, max: 1 << 30}
	}
	return axisRange{min: a.min, max: a.max}
}

// read passes each event to p until the device goes away.
func (g *gamepad) read(p *pad) error {
	defer g.f.Close()
	buf := make([]byte, eventSize*64)
	for {
		n, err := g.f.Read(buf)
		if err != nil {
			if errors.Is(err, io.EOF) || errors.Is(err, syscall.ENODEV) {
				return nil
			}
			return err
		}
		for o := 0; o+eventSize <= n; o += eventSize {
			e := buf[o : o+eventSize]
			p.event(binary.LittleEndian.Uint16(e[16:]), binary.LittleEndian.Uint16(e[18:]),
				int32(binary.LittleEndian.Uint32(e[20:])))
		}
	}
}

// The virtual keyboard the presses come out of.
type keyboard struct{ f *os.File }

type uinputSetup struct {
	id           inputID
	name         [80]byte
	ffEffectsMax uint32
}

func newKeyboard(repeat bool) (*keyboard, error) {
	f, err := os.OpenFile("/dev/uinput", os.O_WRONLY|syscall.O_CLOEXEC, 0)
	if err != nil {
		return nil, err
	}
	fail := func(err error) (*keyboard, error) {
		f.Close()
		return nil, err
	}
	if err := ioctlInt(f.Fd(), uiSetEvbit, evKey); err != nil {
		return fail(err)
	}
	if repeat {
		if err := ioctlInt(f.Fd(), uiSetEvbit, evRep); err != nil {
			return fail(err)
		}
	}
	// every key a keymap can put a character on
	for code := uintptr(1); code < 256; code++ {
		if err := ioctlInt(f.Fd(), uiSetKeybit, code); err != nil {
			return fail(err)
		}
	}
	s := uinputSetup{id: inputID{bustype: busVirtual}}
	copy(s.name[:], "Ephemeral controller keys")
	if err := ioctl(f.Fd(), uiDevSetup, unsafe.Pointer(&s)); err != nil {
		return fail(err)
	}
	if err := ioctlInt(f.Fd(), uiDevCreate, 0); err != nil {
		return fail(err)
	}
	return &keyboard{f}, nil
}

func (k *keyboard) key(code uint16, down bool) error {
	var value uint32
	if down {
		value = 1
	}
	var b [2 * eventSize]byte
	binary.LittleEndian.PutUint16(b[16:], evKey)
	binary.LittleEndian.PutUint16(b[18:], code)
	binary.LittleEndian.PutUint32(b[20:], value)
	// the second event is EV_SYN, all zero
	_, err := k.f.Write(b[:])
	return err
}

func (k *keyboard) close() {
	ioctlInt(k.f.Fd(), uiDevDestroy, 0)
	k.f.Close()
}

// driverOf names the kernel driver behind an input device, such as xpad, from sysfs.
func driverOf(path string) string {
	link, err := os.Readlink(filepath.Join("/sys/class/input", filepath.Base(path), "device/device/driver"))
	if err != nil {
		return ""
	}
	return filepath.Base(link)
}
