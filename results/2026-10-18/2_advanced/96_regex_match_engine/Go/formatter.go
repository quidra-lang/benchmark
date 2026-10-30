package main

import (
	"fmt"
	"strings"
)

func display(c byte) string {
	if c >= 33 && c <= 126 && !strings.ContainsRune("\\]^-", rune(c)) {
		return string(c)
	}
	return fmt.Sprintf("\\x%02X", c)
}
func setNotation(set CharSet, negated bool) string {
	out := "["
	if negated {
		out += "^"
	}
	for a := 0; a < 128; {
		if !set[a] {
			a++
			continue
		}
		b := a
		for b+1 < 128 && set[b+1] {
			b++
		}
		out += display(byte(a))
		if b == a+1 {
			out += display(byte(b))
		} else if b > a+1 {
			out += "-" + display(byte(b))
		}
		a = b + 1
	}
	return out + "]"
}
func instructionNotation(ins Instruction) string {
	switch ins.Op {
	case "CHAR":
		return "CHAR " + display(ins.Char)
	case "CLASS":
		return "CLASS " + setNotation(ins.Set, ins.Negated)
	case "SPLIT":
		return fmt.Sprintf("SPLIT %d, %d", ins.X, ins.Y)
	case "JMP":
		return fmt.Sprintf("JMP %d", ins.X)
	case "SAVE", "BACKREF":
		return fmt.Sprintf("%s %d", ins.Op, ins.Number)
	case "ASSERT":
		return "ASSERT " + ins.Kind
	case "LOOK":
		return fmt.Sprintf("LOOK %s %d", ins.Kind, ins.X)
	}
	return ins.Op
}
func quoted(text string) string {
	var out strings.Builder
	out.WriteByte('"')
	for i := 0; i < len(text); i++ {
		switch text[i] {
		case '\\':
			out.WriteString("\\\\")
		case '"':
			out.WriteString("\\\"")
		case '\n':
			out.WriteString("\\n")
		case '\t':
			out.WriteString("\\t")
		default:
			out.WriteByte(text[i])
		}
	}
	out.WriteByte('"')
	return out.String()
}
