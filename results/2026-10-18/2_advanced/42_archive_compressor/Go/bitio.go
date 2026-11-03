package main

import "fmt"

type DecodeError struct {
	Kind     string
	Position int
}

func (e *DecodeError) Error() string { return fmt.Sprintf("%s at %d", e.Kind, e.Position) }

type BitWriter struct {
	Data                 []byte
	Partial, Used, Count int
}

func (w *BitWriter) write(value, width int) {
	for shift := width - 1; shift >= 0; shift-- {
		w.Partial = w.Partial<<1 | ((value >> shift) & 1)
		w.Used++
		if w.Used == 8 {
			w.Data = append(w.Data, byte(w.Partial))
			w.Partial = 0
			w.Used = 0
		}
	}
	w.Count += width
}
func (w *BitWriter) finish() []byte {
	out := append([]byte{}, w.Data...)
	if w.Used > 0 {
		out = append(out, byte(w.Partial<<(8-w.Used)))
	}
	return out
}

type BitReader struct {
	Payload  []byte
	Position int
	ZeroFill bool
}

func (r *BitReader) read(width, position int) (int, *DecodeError) {
	if !r.ZeroFill && r.Position+width > 8*len(r.Payload) {
		return 0, &DecodeError{"end_of_data", position}
	}
	value := 0
	for i := 0; i < width; i++ {
		value <<= 1
		if r.Position < 8*len(r.Payload) {
			value |= int((r.Payload[r.Position/8] >> uint(7-r.Position%8)) & 1)
		}
		r.Position++
	}
	return value, nil
}
