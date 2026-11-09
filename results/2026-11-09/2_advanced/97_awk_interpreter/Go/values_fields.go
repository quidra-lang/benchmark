package main

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
)

type Value struct {
	Kind   string
	Number int64
	Text   string
}

func numeric(n int64) Value      { return Value{Kind: "number", Number: n} }
func stringValue(s string) Value { return Value{Kind: "string", Text: s} }
func whitespace(c byte) bool     { return c == ' ' || c == '\t' || c == '\n' }
func numericPrefix(text string) (int64, int, bool) {
	i := 0
	for i < len(text) && whitespace(text[i]) {
		i++
	}
	sign := int64(1)
	if i < len(text) && (text[i] == '+' || text[i] == '-') {
		if text[i] == '-' {
			sign = -1
		}
		i++
	}
	start := i
	for i < len(text) && digit(text[i]) {
		i++
	}
	if start == i {
		return 0, i, false
	}
	return sign * decimal(text[start:i]), i, true
}
func inputValue(text string) Value {
	n, end, ok := numericPrefix(text)
	for end < len(text) && whitespace(text[end]) {
		end++
	}
	if ok && end == len(text) {
		return Value{Kind: "strnum", Number: n, Text: text}
	}
	return stringValue(text)
}
func (v Value) number() int64 {
	if v.Kind == "number" || v.Kind == "strnum" {
		return v.Number
	}
	n, _, _ := numericPrefix(v.Text)
	return n
}
func (v Value) text() string {
	if v.Kind == "number" {
		return strconv.FormatInt(v.Number, 10)
	}
	return v.Text
}
func (v Value) truth() bool {
	if v.Kind == "number" || v.Kind == "strnum" {
		return v.Number != 0
	}
	return v.Kind == "string" && v.Text != ""
}
func compare(a, b Value) int {
	if a.Kind != "string" && b.Kind != "string" {
		x, y := a.number(), b.number()
		if x < y {
			return -1
		}
		if x > y {
			return 1
		}
		return 0
	}
	return strings.Compare(a.text(), b.text())
}
func integerForm(text string) bool {
	if text == "0" {
		return true
	}
	i := 0
	if strings.HasPrefix(text, "-") {
		i++
	}
	if i == len(text) || text[i] < '1' || text[i] > '9' {
		return false
	}
	for i++; i < len(text); i++ {
		if !digit(text[i]) {
			return false
		}
	}
	return true
}
func orderedSubscripts(array map[string]Value) []string {
	keys := []string{}
	for key := range array {
		keys = append(keys, key)
	}
	sort.Slice(keys, func(i, j int) bool {
		a, b := integerForm(keys[i]), integerForm(keys[j])
		if a != b {
			return a
		}
		if a {
			return decimal(keys[i]) < decimal(keys[j])
		}
		return keys[i] < keys[j]
	})
	return keys
}
func splitPieces(text, separator string) []string {
	if text == "" {
		return []string{}
	}
	if separator == " " {
		out := []string{}
		for i := 0; i < len(text); {
			for i < len(text) && whitespace(text[i]) {
				i++
			}
			start := i
			for i < len(text) && !whitespace(text[i]) {
				i++
			}
			if i > start {
				out = append(out, text[start:i])
			}
		}
		return out
	}
	if separator == "" {
		out := []string{}
		for i := 0; i < len(text); i++ {
			out = append(out, text[i:i+1])
		}
		return out
	}
	return strings.Split(text, separator)
}

type Record struct {
	Zero   Value
	Fields []Value
	Global func(string) Value
}

func (r *Record) set(text string) {
	r.Zero = inputValue(text)
	r.Fields = nil
	for _, piece := range splitPieces(text, r.Global("FS").text()) {
		r.Fields = append(r.Fields, inputValue(piece))
	}
}
func (r *Record) read(index int) Value {
	if index == 0 {
		return r.Zero
	}
	if index > len(r.Fields) {
		return Value{}
	}
	return r.Fields[index-1]
}
func (r *Record) rebuild() {
	parts := []string{}
	for _, v := range r.Fields {
		parts = append(parts, v.text())
	}
	r.Zero = inputValue(strings.Join(parts, r.Global("OFS").text()))
}
func (r *Record) resize(n int) {
	if n < len(r.Fields) {
		r.Fields = r.Fields[:n]
	}
	for len(r.Fields) < n {
		r.Fields = append(r.Fields, stringValue(""))
	}
	r.rebuild()
}
func (r *Record) write(index int, value Value) {
	if index == 0 {
		r.set(value.text())
		return
	}
	for len(r.Fields) < index {
		r.Fields = append(r.Fields, stringValue(""))
	}
	r.Fields[index-1] = value
	r.rebuild()
}
func escapedString(text string) string {
	var out strings.Builder
	out.WriteByte('"')
	for i := 0; i < len(text); i++ {
		c := text[i]
		switch c {
		case '\\':
			out.WriteString("\\\\")
		case '"':
			out.WriteString("\\\"")
		case '\n':
			out.WriteString("\\n")
		case '\t':
			out.WriteString("\\t")
		default:
			if c >= 32 && c <= 126 {
				out.WriteByte(c)
			} else {
				out.WriteString(fmt.Sprintf("\\%03o", c))
			}
		}
	}
	out.WriteByte('"')
	return out.String()
}
func describe(v Value) string {
	switch v.Kind {
	case "number":
		return v.text()
	case "string":
		return escapedString(v.Text)
	case "strnum":
		return escapedString(v.Text) + " (strnum)"
	}
	return "(uninitialized)"
}
