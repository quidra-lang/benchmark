package main

type BitWriter struct {
	Bytes                          []byte
	Value, Count, Padding, Stuffed int
}

func (w *BitWriter) Write(value, n int) {
	for i := n - 1; i >= 0; i-- {
		w.Value = w.Value*2 + (value >> i & 1)
		w.Count++
		if w.Count == 8 {
			w.Bytes = append(w.Bytes,
				byte(w.Value))
			if w.Value == 255 {
				w.Bytes = append(w.Bytes, 0)
				w.Stuffed++
			}
			w.Value, w.Count = 0, 0
		}
	}
}
func (w *BitWriter) Pad() {
	if w.Count > 0 {
		n := 8 - w.Count
		w.Padding += n
		w.Write((1<<n)-1, n)
	}
}
func (w *BitWriter) Marker(m int) { w.Pad(); w.Bytes = append(w.Bytes, 255, byte(m)) }

type BitReader struct {
	Bytes            []byte
	Pos, Value, Left int
}

func (r *BitReader) Read(n int) (int, string) {
	a := 0
	for i := 0; i < n; i++ {
		if r.Left == 0 {
			if r.Pos >= len(r.Bytes) {
				return 0,
					"marker"
			}
			v := int(r.Bytes[r.Pos])
			if v == 255 {
				if r.Pos+1 >= len(r.Bytes) || r.Bytes[r.Pos+1] != 0 {
					return 0,
						"marker"
				}
				r.Pos += 2
			} else {
				r.Pos++
			}
			r.Value, r.Left = v, 8
		}
		r.Left--
		a = a*2 + (r.Value >> r.Left & 1)
	}
	return a,
		""
}
func (r *BitReader) Symbol(t Huffman) (int, string) {
	code := 0
	for l := 1; l <= 16; l++ {
		b, e := r.Read(1)
		if e != "" {
			return 0,
				e
		}
		code = 2*code + b
		for _, v := range t.Values {
			if t.Length[v] == l && t.Code[v] == code {
				return v, ""
			}
		}
	}
	return 0,
		"code"
}
func resync(b []byte, p int) int {
	for p+1 < len(b) {
		if b[p] == 255 && (b[p+1] >= 208 && b[p+1] <= 215 || b[p+1] == 217) {
			return p
		}
		p++
	}
	return len(b) - 2
}
