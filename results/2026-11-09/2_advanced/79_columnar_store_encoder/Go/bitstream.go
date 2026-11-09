package main

type Reader struct {
	data     []byte
	position int
}

func (r *Reader) byte() byte { v := r.data[r.position]; r.position++; return v }
func (r *Reader) take(n int) []byte {
	v := r.data[r.position : r.position+n]
	r.position += n
	return v
}
func (r *Reader) uleb() int64 {
	value := int64(0)
	shift := uint(0)
	for {
		b := r.byte()
		value |= int64(b&127) << shift
		if b < 128 {
			return value
		}
		shift += 7
	}
}
func (r *Reader) zigzag() int64 {
	v := r.uleb()
	if v%2 == 0 {
		return v / 2
	}
	return -(v + 1) / 2
}
func (r *Reader) u32() uint32 {
	a := r.take(4)
	return uint32(a[0]) | uint32(a[1])<<8 | uint32(a[2])<<16 | uint32(a[3])<<24
}
func appendULEB(out []byte, n int64) []byte {
	for n >= 128 {
		out = append(out, byte(n%128)+128)
		n /= 128
	}
	return append(out, byte(n))
}
func appendZigzag(out []byte, x int64) []byte {
	if x >= 0 {
		return appendULEB(out, 2*x)
	}
	return appendULEB(out, -2*x-1)
}
func appendU32(out []byte, n uint32) []byte {
	return append(out, byte(n), byte(n>>8), byte(n>>16), byte(n>>24))
}
func pack(a []int64, w int) []byte {
	out := make([]byte, len(a)*w/8)
	for i, value := range a {
		for j := 0; j < w; j++ {
			if value>>j&1 != 0 {
				k := i*w + j
				out[k/8] |= 1 << uint(k%8)
			}
		}
	}
	return out
}
func unpack(r *Reader, count, w int) []int64 {
	data := r.take(count * w / 8)
	out := make([]int64, count)
	for i := range out {
		for j := 0; j < w; j++ {
			k := i*w + j
			out[i] |= int64(data[k/8]>>uint(k%8)&1) << j
		}
	}
	return out
}
func adler(data []byte) uint32 {
	a, b := uint32(1), uint32(0)
	for _, v := range data {
		a = (a + uint32(v)) % 65521
		b = (b + a) % 65521
	}
	return b*65536 + a
}
func encodeHybrid(a []int64, w int) []byte {
	var out []byte
	run := func(i int) int {
		j := i + 1
		for j < len(a) && a[j] == a[i] {
			j++
		}
		return j - i
	}
	for i := 0; i < len(a); {
		length := run(i)
		if length >= 8 {
			out = appendULEB(out,
				int64(2*length))
			for j := 0; j < (w+7)/8; j++ {
				out = append(out, byte(a[i]>>uint(8*j)))
			}
			i += length
		} else {
			j,
				g := i, 0
			for {
				j += 8
				g++
				if j >= len(a) || g == 63 || run(j) >= 8 {
					break
				}
			}
			out = appendULEB(out, int64(2*g+1))
			values := make([]int64,
				8*g)
			copy(values, a[i:min(j, len(a))])
			out = append(out, pack(values, w)...)
			i = j
		}
	}
	return out
}
func decodeHybrid(r *Reader, count, w int) []int64 {
	var out []int64
	for len(out) < count {
		header := int(r.uleb())
		if header%2 == 0 {
			value := int64(0)
			for j := 0; j < (w+7)/8; j++ {
				value |= int64(r.byte()) << uint(8*j)
			}
			for j := 0; j < header/2; j++ {
				out = append(out,
					value)
			}
		} else {
			out = append(out, unpack(r, 8*((header-1)/2), w)...)
		}
	}
	return out[:count]
}
