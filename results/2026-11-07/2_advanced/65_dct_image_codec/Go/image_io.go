package main

import (
	"encoding/hex"
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Image struct {
	W, H int
	RGB  []int
}
type Parameters struct {
	Qualities, Truncate          []int
	Sampling, Mode               string
	Restart, Target, Generations int
}
type InputTables struct {
	C        [64]int
	Base     [2][64]int
	Standard [4]Huffman
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}
func readText(path string) string { b, e := os.ReadFile(path); must(e); return string(b) }
func integer(s string) int        { n, e := strconv.Atoi(s); must(e); return n }
func ints(s string) []int {
	fields := strings.Fields(s)
	a := make([]int, len(fields))
	for i, s := range fields {
		a[i] = integer(s)
	}
	return a
}
func joined(a []int) string {
	s := make([]string, len(a))
	for i, v := range a {
		s[i] = strconv.Itoa(v)
	}
	return strings.Join(s, " ")
}
func readImage(path string) Image {
	f := strings.Fields(readText(path))
	w, h := integer(f[1]), integer(f[2])
	a := make([]int,
		3*w*h)
	for i := range a {
		a[i] = integer(f[i+4])
	}
	return Image{w, h, a}
}
func writeImage(path string, im Image) {
	var s strings.Builder
	fmt.Fprintf(&s, "P3\n%d %d\n255\n", im.W,
		im.H)
	for y := 0; y < im.H; y++ {
		s.WriteString(joined(im.RGB[y*3*im.W : (y+1)*3*im.W]))
		s.WriteByte('\n')
	}
	must(os.WriteFile(path,
		[]byte(s.String()), 0644))
}
func readParameters() Parameters {
	l := strings.Split(strings.TrimSpace(readText("input/params.txt")),
		"\n")
	return Parameters{ints(strings.TrimPrefix(l[0], "qualities ")), ints(strings.TrimPrefix(l[6],
		"truncate ")), strings.Fields(l[1])[1], strings.Fields(l[3])[1], integer(strings.Fields(l[2])[1]),
		integer(strings.Fields(l[4])[1]), integer(strings.Fields(l[5])[1])}
}
func readTables() InputTables {
	l := strings.Split(strings.TrimSpace(readText("input/tables.txt")),
		"\n")
	var t InputTables
	for y := 0; y < 8; y++ {
		copy(t.C[y*8:], ints(l[y+1]))
		for k := 0; k < 2; k++ {
			copy(t.Base[k][y*8:],
				ints(l[10+9*k+y]))
		}
	}
	for k := 0; k < 4; k++ {
		v := ints(l[28+3*k])
		copy(t.Standard[k].Bits[1:], v)
		t.Standard[k].Values = ints(l[29+3*k])
		t.Standard[k].Assign()
	}
	return t
}
func readHex(path string) []byte {
	b, e := hex.DecodeString(strings.Join(strings.Fields(readText(path)), ""))
	must(e)
	return b
}
func writeHex(path string, b []byte) {
	var s strings.Builder
	for i := 0; i < len(b); i += 32 {
		s.WriteString(hex.EncodeToString(b[i:min(i+32,
			len(b))]))
		s.WriteByte('\n')
	}
	must(os.WriteFile(path, []byte(s.String()), 0644))
}
func writeText(path, s string) { must(os.WriteFile(path, []byte(s), 0644)) }
