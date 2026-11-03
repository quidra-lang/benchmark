package main

import "math/bits"

var methodNames = []string{"PLAIN", "DICTIONARY", "RLE", "DELTA_BINARY_PACKED", "DELTA_LENGTH_BYTE_ARRAY"}

func candidates(kind string) []int {
	switch kind {
	case "BOOL":
		return []int{0, 2}
	case "STRING":
		return []int{0, 1, 4}
	default:
		return []int{0, 1, 3}
	}
}
func encodeDelta(a []int64) []byte {
	var out []byte
	out = appendULEB(out, 128)
	out = appendULEB(out, 4)
	out = appendULEB(out,
		int64(len(a)))
	first := int64(0)
	if len(a) > 0 {
		first = a[0]
	}
	out = appendZigzag(out, first)
	for start := 1; start < len(a); start += 128 {
		end := min(start+128,
			len(a))
		deltas := make([]int64, end-start)
		minimum := a[start] - a[start-1]
		for i := start; i < end; i++ {
			deltas[i-start] = a[i] - a[i-1]
			minimum = min(minimum,
				deltas[i-start])
		}
		out = appendZigzag(out, minimum)
		widths := make([]int, 4)
		for t := 0; t < 4; t++ {
			maximum := int64(0)
			for i := t * 32; i < min((t+1)*32,
				len(deltas)); i++ {
				maximum = max(maximum, deltas[i]-minimum)
			}
			widths[t] = bits.Len64(uint64(maximum))
			out = append(out,
				byte(widths[t]))
		}
		for t := 0; t < 4 && t*32 < len(deltas); t++ {
			values := make([]int64, 32)
			for i := t * 32; i < min((t+1)*32,
				len(deltas)); i++ {
				values[i-t*32] = deltas[i] - minimum
			}
			out = append(out, pack(values, widths[t])...)
		}
	}
	return out
}
func decodeDelta(r *Reader) []int64 {
	r.uleb()
	r.uleb()
	n := int(r.uleb())
	first := r.zigzag()
	if n == 0 {
		return nil
	}
	out := []int64{first}
	for len(out) < n {
		minimum := r.zigzag()
		widths := r.take(4)
		for t := 0; t < 4 && len(out) < n; t++ {
			values := unpack(r,
				32, int(widths[t]))
			for _, v := range values[:min(32, n-len(out))] {
				out = append(out, out[len(out)-1]+minimum+v)
			}
		}
	}
	return out
}
func dictionaryKey(v Value, kind string) string {
	if kind == "STRING" {
		return v.text
	}
	return valueText(v, "INT", false)
}
func encodeValues(a []Value, kind string, method int, dictionary []Value) []byte {
	var out []byte
	switch method {
	case 0:
		if kind == "BOOL" {
			values := make([]int64,
				(len(a)+7)/8*8)
			for i, v := range a {
				values[i] = v.number
			}
			return pack(values, 1)
		}
		for _, v := range a {
			if kind == "STRING" {
				out = appendU32(out,
					uint32(len(v.text)))
				out = append(out, []byte(v.text)...)
			} else {
				out = appendU32(out, uint32(v.number))
			}
		}
	case 1:
		w := bits.Len(uint(max(0,
			len(dictionary)-1)))
		out = append(out, byte(w))
		indices := map[string]int64{}
		for i, v := range dictionary {
			indices[dictionaryKey(v,
				kind)] = int64(i)
		}
		values := make([]int64, len(a))
		for i, v := range a {
			values[i] = indices[dictionaryKey(v,
				kind)]
		}
		out = append(out, encodeHybrid(values, w)...)
	case 2:
		values := make([]int64, len(a))
		for i, v := range a {
			values[i] = v.number
		}
		data := encodeHybrid(values,
			1)
		out = appendU32(out, uint32(len(data)))
		out = append(out, data...)
	case 3:
		values := make([]int64, len(a))
		for i, v := range a {
			values[i] = v.number
		}
		out = encodeDelta(values)
	case 4:
		lengths := make([]int64, len(a))
		for i, v := range a {
			lengths[i] = int64(len(v.text))
		}
		out = encodeDelta(lengths)
		for _, v := range a {
			out = append(out,
				[]byte(v.text)...)
		}
	}
	return out
}
func decodeValues(r *Reader, count int, kind string, method int, dictionary []Value) []Value {
	out := make([]Value,
		count)
	switch method {
	case 0:
		if kind == "BOOL" {
			values := unpack(r, (count+7)/8*8, 1)
			for i := range out {
				out[i].number = values[i]
			}
			return out
		}
		for i := range out {
			if kind == "STRING" {
				out[i].text = string(r.take(int(r.u32())))
			} else {
				out[i].number = int64(int32(r.u32()))
			}
		}
	case 1:
		w := int(r.byte())
		indices := decodeHybrid(r,
			count, w)
		for i, index := range indices {
			out[i] = dictionary[int(index)]
		}
	case 2:
		size := int(r.u32())
		body := Reader{data: r.take(size)}
		values := decodeHybrid(&body,
			count, 1)
		for i, v := range values {
			out[i].number = v
		}
	case 3:
		values := decodeDelta(r)
		for i, v := range values {
			out[i].number = v
		}
	case 4:
		lengths := decodeDelta(r)
		for i, length := range lengths {
			out[i].text = string(r.take(int(length)))
		}
	}
	return out
}
func writeStatValue(out []byte, v Value, kind string) []byte {
	switch kind {
	case "STRING":
		out = appendULEB(out,
			int64(len(v.text)))
		return append(out, []byte(v.text)...)
	case "BOOL":
		return append(out, byte(v.number))
	default:
		return appendZigzag(out,
			v.number)
	}
}
func readStatValue(r *Reader, kind string) Value {
	switch kind {
	case "STRING":
		return Value{text: string(r.take(int(r.uleb())))}
	case "BOOL":
		return Value{number: int64(r.byte())}
	default:
		return Value{number: r.zigzag()}
	}
}
