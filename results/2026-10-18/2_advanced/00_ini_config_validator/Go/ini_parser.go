package main

import (
	"fmt"
	"regexp"
	"strings"
)

var namePattern = regexp.MustCompile(`^[a-z][a-z0-9_]*$`)
var sectionPattern = regexp.MustCompile(`^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$`)

type Statement struct { Kind string; Line int; Target, Value string }
type Document struct { Statements []Statement; Diagnostics []Diagnostic }

func trimSegments(source []string) []string {
	segments := append([]string(nil), source...)
	segments[0] = strings.TrimLeft(segments[0], " ")
	last := len(segments)-1
	segments[last] = strings.TrimRight(segments[last], " ")
	return segments
}

func parseDocument(name string, physical []string) *Document {
	document := &Document{}
	section, base := "", ""
	assigned := map[string]int{}
	for _, line := range logicalLines(physical) {
		report := func(code, message string) { document.Diagnostics = append(document.Diagnostics, Diagnostic{Origin{name, line.Number}, code, message}) }
		add := func(kind, target, value string) { document.Statements = append(document.Statements, Statement{kind, line.Number, target, value}) }
		if line.Code != "" { report(line.Code, line.Message); continue }
		s := trimSegments(line.Segments)
		text := s[0]
		if len(s) == 1 && text == "" { continue }
		if strings.HasPrefix(text, "[") {
			valid := len(s) == 1 && strings.HasSuffix(text, "]")
			n, parent, colon := "", "", false
			if len(text) >= 2 { n, parent, colon = strings.Cut(text[1:len(text)-1], ":") }
			n, parent = strings.Trim(n, " "), strings.Trim(parent, " ")
			relative := strings.HasPrefix(n, ".") && sectionPattern.MatchString(n[1:])
			if !valid || (colon && !sectionPattern.MatchString(parent)) || (!relative && !sectionPattern.MatchString(n)) {
				report("E_SECTION", "invalid section header"); section = ""
			} else if relative && base == "" {
				report("E_SECTION", "relative section without base"); section = ""
			} else {
				if relative { section = base+n } else { section, base = n, n }
				if colon { add("inherit", section, parent) }
			}
			continue
		}
		if strings.HasPrefix(text, "@") {
			words := strings.Fields(text)
			if len(s) != 1 || len(words) != 2 || (words[0] != "@include" && words[0] != "@unset") || !namePattern.MatchString(words[1]) {
				report("E_SYNTAX", "invalid directive")
			} else if words[0] == "@include" { add("include", words[1], "")
			} else if section == "" { report("E_NO_SECTION", "no current section")
			} else { add("unset", section+"."+words[1], "") }
			continue
		}
		hasEquals := false
		for i := 0; i < len(s); i += 2 { hasEquals = hasEquals || strings.Contains(s[i], "=") }
		if !hasEquals { report("E_SYNTAX", "invalid line"); continue }
		key, rest, found := strings.Cut(text, "=")
		if !found { report("E_SYNTAX", "invalid key"); continue }
		key = strings.Trim(key, " ")
		appending := strings.HasSuffix(key, "+")
		if appending { key = strings.TrimRight(strings.TrimSuffix(key, "+"), " ") }
		if !namePattern.MatchString(key) { report("E_SYNTAX", "invalid key"); continue }
		s[0] = rest
		s = trimSegments(s)
		value := s[0]
		if len(s) == 3 && s[0] == "" && s[2] == "" { value = s[1]
		} else if len(s) != 1 { report("E_SYNTAX", "invalid value"); continue }
		if section == "" { report("E_NO_SECTION", "no current section"); continue }
		fullKey := section+"."+key
		kind := "assign"
		if appending { kind = "append" } else {
			if previous, ok := assigned[fullKey]; ok { report("W_DUPLICATE", fmt.Sprintf("%s already set at line %d", fullKey, previous)) }
			assigned[fullKey] = line.Number
		}
		add(kind, fullKey, value)
	}
	return document
}
