package main

import (
	"fmt"
	"strings"
)

const alphanumeric = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"

var modes = []string{"NUMERIC", "ALPHANUMERIC", "BYTE"}

type Bits struct {
	values   []int
	position int
}

func (b *Bits) append(value, width int) {
	for i := width - 1; i >= 0; i-- {
		b.values = append(b.values, value>>i&1)
	}
}
func (b *Bits) read(width int) int {
	value := 0
	for i := 0; i < width; i++ {
		value = value*2 + b.values[b.position]
		b.position++
	}
	return value
}
func bitsFromWords(words []int) []int {
	b := Bits{}
	for _, w := range words {
		b.append(w, 8)
	}
	return b.values
}
func wordsFromBits(bits []int) []int {
	b := Bits{values: bits}
	var words []int
	for b.position < len(bits) {
		words = append(words, b.read(8))
	}
	return words
}
func binary(value, width int) string { return fmt.Sprintf("%0*b", width, value) }
func hexadecimal(words []int) string {
	var out strings.Builder
	for _, w := range words {
		fmt.Fprintf(&out, "%02x", w)
	}
	return out.String()
}
