package main

var relocationTypes = []string{"ABS32", "REL32", "ABS16", "HI16", "LO16", "GPREL16", "CALL24"}

func width(kind string) int {
	switch kind {
	case "ABS32", "REL32":
		return 4
	case "CALL24":
		return 3
	}
	return 2
}
func modulo(a, b int64) int64 {
	r := a % b
	if r < 0 {
		r += b
	}
	return r
}
func floorDivide(a, b int64) int64 {
	q := a / b
	if a < 0 && a%b != 0 {
		q--
	}
	return q
}
func relocationField(kind string, s, a, p, gp int64) (int64, int64, bool) {
	v := s + a
	switch kind {
	case "REL32", "CALL24":
		v -= p
	case "GPREL16":
		v -= gp
	}
	field := int64(0)
	valid := true
	switch kind {
	case "ABS32", "HI16":
		valid = v >= -(1<<31) && v < 1<<32
	case "REL32":
		valid = v >= -(1<<31) && v < 1<<31
	case "ABS16":
		valid = v >= -(1<<15) && v < 1<<16
	case "GPREL16":
		valid = v >= -(1<<15) && v < 1<<15
	case "CALL24":
		valid = v >= -(1<<25) && v < 1<<25
	}
	switch kind {
	case "ABS32", "REL32":
		field = modulo(v, 1<<32)
	case "HI16":
		field = modulo((modulo(v, 1<<32)+32768)/65536, 65536)
	case "CALL24":
		field = modulo(floorDivide(v, 4), 1<<24)
	default:
		field = modulo(v, 1<<16)
	}
	return v, field, valid
}
func unpaired(relocations []*Relocation, index int) bool {
	r := relocations[index]
	if r.Type != "HI16" {
		return false
	}
	if index+1 == len(relocations) {
		return true
	}
	next := relocations[index+1]
	return next.Type != "LO16" || next.Symbol != r.Symbol || next.Addend != r.Addend
}
func littleEndian(data []byte, offset int, value int64, n int) {
	for i := 0; i < n; i++ {
		data[offset+i] = byte(value >> uint(8*i) & 255)
	}
}
