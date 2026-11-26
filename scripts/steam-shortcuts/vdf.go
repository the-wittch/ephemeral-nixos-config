package main

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
)

// Steam's binary KeyValues, as shortcuts.vdf has them: a type byte, a NUL-ended name, then the
// value. Every type Steam writes there is kept byte for byte, so a file read and written back is
// the same file; one with a type this doesn't know is refused rather than rewritten.
const (
	typeMap    = 0x00
	typeString = 0x01
	typeInt32  = 0x02
	typeFloat  = 0x03
	typeUint64 = 0x07
	typeEnd    = 0x08
	typeInt64  = 0x0a
)

type node struct {
	typ  byte
	name string
	// the string without its NUL, or the number's bytes as they were
	value []byte
	kids  []node
}

func (n *node) get(name string) *node {
	for i := range n.kids {
		if n.kids[i].name == name {
			return &n.kids[i]
		}
	}
	return nil
}

func parseVDF(data []byte) ([]node, error) {
	r := bufio.NewReader(bytes.NewReader(data))
	nodes, err := readNodes(r, 0)
	if err != nil {
		return nil, err
	}
	if _, err := r.ReadByte(); err != io.EOF {
		return nil, errors.New("data after the end")
	}
	return nodes, nil
}

// readNodes reads until the end of this map, or, at the top, the end of the file.
func readNodes(r *bufio.Reader, depth int) ([]node, error) {
	if depth > 16 {
		return nil, errors.New("nested too deep")
	}
	var out []node
	for {
		t, err := r.ReadByte()
		if err == io.EOF && depth == 0 {
			return out, nil
		}
		if err != nil {
			return nil, err
		}
		if t == typeEnd {
			return out, nil
		}
		name, err := readString(r)
		if err != nil {
			return nil, err
		}
		n := node{typ: t, name: name}
		switch t {
		case typeMap:
			if n.kids, err = readNodes(r, depth+1); err != nil {
				return nil, err
			}
		case typeString:
			s, err := readString(r)
			if err != nil {
				return nil, err
			}
			n.value = []byte(s)
		case typeInt32, typeFloat:
			n.value = make([]byte, 4)
			_, err = io.ReadFull(r, n.value)
		case typeUint64, typeInt64:
			n.value = make([]byte, 8)
			_, err = io.ReadFull(r, n.value)
		default:
			return nil, fmt.Errorf("unknown type 0x%02x for %q", t, name)
		}
		if err != nil {
			return nil, err
		}
		out = append(out, n)
	}
}

func readString(r *bufio.Reader) (string, error) {
	s, err := r.ReadString(0)
	if err != nil {
		return "", err
	}
	return s[:len(s)-1], nil
}

func writeVDF(nodes []node) []byte {
	var b bytes.Buffer
	writeNodes(&b, nodes)
	b.WriteByte(typeEnd)
	return b.Bytes()
}

func writeNodes(b *bytes.Buffer, nodes []node) {
	for _, n := range nodes {
		b.WriteByte(n.typ)
		b.WriteString(n.name)
		b.WriteByte(0)
		switch n.typ {
		case typeMap:
			writeNodes(b, n.kids)
			b.WriteByte(typeEnd)
		case typeString:
			b.Write(n.value)
			b.WriteByte(0)
		default:
			b.Write(n.value)
		}
	}
}

func str(name, value string) node { return node{typ: typeString, name: name, value: []byte(value)} }

func i32(name string, v uint32) node {
	b := make([]byte, 4)
	binary.LittleEndian.PutUint32(b, v)
	return node{typ: typeInt32, name: name, value: b}
}
