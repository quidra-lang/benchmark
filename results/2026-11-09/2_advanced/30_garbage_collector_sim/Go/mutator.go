package main

import (
	"os"
	"strconv"
	"strings"
)

var commandNames = []string{"ALLOC", "PUSH", "LOAD", "POP", "SET", "OVERWRITE", "CHECKPOINT"}

type CollectorEntry struct {
	Name, Type string
	Young, Age int
}
type Config struct {
	HeapSize, Width int
	Collectors      []CollectorEntry
	Maps            map[string]bool
	Windows         []int
}
type Command struct {
	Line                                       int
	Name                                       string
	Pointers, Data, Slot, Field, Source, Count int
	Label                                      string
}
type ParsedLine struct {
	Command Command
	Reason  string
}

func integer(s string) int {
	n, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return n
}
func readLines(path string) []string {
	content, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(content), "\n"), "\n")
}
func readConfig() Config {
	c := Config{Maps: map[string]bool{}}
	for _, l := range readLines("input/config.txt") {
		t := strings.Split(l, " ")
		switch t[0] {
		case "HEAP":
			c.HeapSize = integer(t[1])
		case "WIDTH":
			c.Width = integer(t[1])
		case "COLLECTOR":
			entry := CollectorEntry{Name: t[1], Type: t[2]}
			if len(t) > 3 {
				entry.Young, entry.Age = integer(t[3]), integer(t[4])
			}
			c.Collectors = append(c.Collectors, entry)
		case "MAPS":
			for _, s := range t[1:] {
				c.Maps[s] = true
			}
		case "MMU":
			for _, s := range t[1:] {
				c.Windows = append(c.Windows, integer(s))
			}
		}
	}
	return c
}
func isNumber(token string) bool {
	if len(token) < 1 || len(token) > 4 || len(token) > 1 && token[0] == '0' {
		return false
	}
	for _, r := range token {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}
func isLabel(token string) bool {
	if len(token) < 1 || len(token) > 16 {
		return false
	}
	for _, r := range token {
		if !(r >= 'a' && r <= 'z' || r >= '0' && r <= '9' || r == '_') {
			return false
		}
	}
	return true
}
func parseLine(number int, text string) ParsedLine {
	tokens := strings.Split(text, " ")
	forms := map[string]string{"ALLOC": "nn", "PUSH": "r", "LOAD": "nn", "POP": "n", "SET": "nnr", "OVERWRITE": "nr", "CHECKPOINT": "l"}
	form, exists := forms[tokens[0]]
	if !exists || len(tokens) != len(form)+1 {
		return ParsedLine{Reason: "syntax"}
	}
	for i, kind := range form {
		t := tokens[i+1]
		if kind == 'n' && !isNumber(t) || kind == 'r' && t != "-" && !isNumber(t) || kind == 'l' && !isLabel(t) {
			return ParsedLine{Reason: "syntax"}
		}
	}
	c := Command{Line: number, Name: tokens[0], Source: -1}
	source := func(s string) int {
		if s == "-" {
			return -1
		}
		return integer(s)
	}
	switch c.Name {
	case "ALLOC":
		c.Pointers, c.Data = integer(tokens[1]), integer(tokens[2])
	case "PUSH":
		c.Source = source(tokens[1])
	case "LOAD":
		c.Slot, c.Field = integer(tokens[1]), integer(tokens[2])
	case "POP":
		c.Count = integer(tokens[1])
	case "SET":
		c.Slot, c.Field, c.Source = integer(tokens[1]), integer(tokens[2]), source(tokens[3])
	case "OVERWRITE":
		c.Slot, c.Source = integer(tokens[1]), source(tokens[2])
	case "CHECKPOINT":
		c.Label = tokens[1]
	}
	if c.Name == "ALLOC" && (c.Pointers > 6 || c.Data > 24) || c.Name == "POP" && c.Count == 0 {
		return ParsedLine{Reason: "range"}
	}
	return ParsedLine{Command: c}
}
