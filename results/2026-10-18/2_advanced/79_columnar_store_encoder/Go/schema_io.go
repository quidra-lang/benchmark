package main

import (
	"encoding/hex"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Value struct {
	number        int64
	text          string
	null, unknown bool
}
type Column struct {
	name, kind string
	nullable   bool
}
type Options struct {
	rows, page, limit int
	methods           []int
}

var typeNames = []string{"INT", "STRING", "BOOL", "DATE"}

func number(s string) int    { v, _ := strconv.Atoi(s); return v }
func integer(s string) int64 { v, _ := strconv.ParseInt(s, 10, 64); return v }
func readLines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	if len(b) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(b),
		"\n"), "\n")
}
func dateNumber(s string) int64 {
	t, e := time.Parse("2006-01-02", s)
	if e != nil {
		panic(e)
	}
	return t.Unix() / 86400
}
func dateText(day int64) string { return time.Unix(day*86400, 0).UTC().Format("2006-01-02") }
func parseValue(s, kind string) Value {
	if s == "" {
		return Value{null: true}
	}
	switch kind {
	case "STRING":
		return Value{text: s}
	case "BOOL":
		v := int64(0)
		if s == "true" {
			v = 1
		}
		return Value{number: v}
	case "DATE":
		return Value{number: dateNumber(s)}
	default:
		return Value{number: integer(s)}
	}
}
func valueText(v Value, kind string, csv bool) string {
	if v.unknown {
		return "?"
	}
	if v.null {
		if csv {
			return ""
		}
		return "NULL"
	}
	switch kind {
	case "STRING":
		return v.text
	case "BOOL":
		if v.number == 1 {
			return "true"
		}
		return "false"
	case "DATE":
		return dateText(v.number)
	default:
		return strconv.FormatInt(v.number,
			10)
	}
}
func readSchema() []Column {
	var out []Column
	for _, line := range readLines("input/schema.txt") {
		a := strings.Fields(line)
		out = append(out,
			Column{a[0], a[1], a[2] == "NULLABLE"})
	}
	return out
}
func readTable(schema []Column) [][]Value {
	var rows [][]Value
	for _, line := range readLines("input/table.csv")[1:] {
		a := strings.Split(line,
			",")
		row := make([]Value, len(schema))
		for c, column := range schema {
			row[c] = parseValue(a[c], column.kind)
		}
		rows = append(rows,
			row)
	}
	return rows
}
func readOptions() Options {
	a := readLines("input/options.txt")
	o := Options{rows: number(strings.Fields(a[0])[1]),
		page: number(strings.Fields(a[1])[1]), limit: number(strings.Fields(a[2])[1])}
	for _, line := range a[3:] {
		name := strings.Fields(line)[2]
		method := -1
		for i, candidate := range methodNames {
			if name == candidate {
				method = i
			}
		}
		o.methods = append(o.methods, method)
	}
	return o
}
func damagedBytes() []byte {
	text := strings.Join(readLines("input/damaged.hex"), "")
	data, e := hex.DecodeString(text)
	if e != nil {
		panic(e)
	}
	return data
}
func writeLines(name string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if e := os.WriteFile("output/"+name,
		[]byte(text), 0644); e != nil {
		panic(e)
	}
}
func formatChecksum(v uint32) string { return fmt.Sprintf("%08x", v) }
