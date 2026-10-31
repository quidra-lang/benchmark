package main

import "strings"

type CharSet [128]bool

func letter(c byte) bool { return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' }
func digit(c byte) bool  { return c >= '0' && c <= '9' }
func swapped(c byte) byte {
	if letter(c) {
		return c ^ 32
	}
	return c
}
func standard(c byte) CharSet {
	var set CharSet
	lower := c | 32
	for i := 0; i < 128; i++ {
		x := byte(i)
		switch lower {
		case 'd':
			set[i] = digit(x)
		case 'w':
			set[i] = letter(x) || digit(x) || x == '_'
		case 's':
			set[i] = x >= 9 && x <= 13 || x == 32
		}
		if c >= 'A' && c <= 'Z' {
			set[i] = !set[i]
		}
	}
	return set
}
func charMatches(a, b byte, flags string) bool {
	return a == b || strings.Contains(flags, "i") && letter(a) && swapped(a) == b
}
func classMatches(set CharSet, negated bool, c byte, flags string) bool {
	member := set[c] || strings.Contains(flags, "i") && letter(c) && set[swapped(c)]
	return member != negated
}
func consumes(ins Instruction, text string, q int, flags string) bool {
	if q >= len(text) {
		return false
	}
	switch ins.Op {
	case "CHAR":
		return charMatches(text[q], ins.Char, flags)
	case "ANY":
		return strings.Contains(flags, "s") || text[q] != '\n'
	case "CLASS":
		return classMatches(ins.Set, ins.Negated, text[q], flags)
	}
	return false
}
func assertion(kind, text string, q int, flags string) bool {
	word := func(i int) bool {
		return i >= 0 && i < len(text) && (letter(text[i]) || digit(text[i]) || text[i] == '_')
	}
	switch kind {
	case "BOL":
		return q == 0 || strings.Contains(flags, "m") && text[q-1] == '\n'
	case "EOL":
		return q == len(text) || strings.Contains(flags, "m") && text[q] == '\n'
	case "WORD":
		return word(q-1) != word(q)
	case "NOTWORD":
		return word(q-1) == word(q)
	}
	return false
}
