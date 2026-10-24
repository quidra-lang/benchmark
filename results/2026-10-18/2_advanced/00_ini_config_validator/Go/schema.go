package main

import (
	"sort"
	"strings"
)

type Spec struct {
	Line int
	Pattern, Key, Kind string
	Parts []string
	Wildcard bool
	Attributes map[string]string
}

func (s *Spec) has(attribute string) bool { _, ok := s.Attributes[attribute]; return ok }
func (s *Spec) item() string { if s.has("item") { return s.Attributes["item"] }; return "string" }
func (s *Spec) matches(section string) bool {
	parts := strings.Split(section, ".")
	if len(parts) != len(s.Parts) { return false }
	for i, p := range parts { if s.Parts[i] != "*" && s.Parts[i] != p { return false } }
	return true
}

type Schema struct { Specs []*Spec; Exact map[string]*Spec }

func loadSchema(path string) *Schema {
	schema := &Schema{Exact: map[string]*Spec{}}
	for i, line := range readLines(path) {
		if strings.Trim(line, " ") == "" || strings.HasPrefix(line, "#") { continue }
		words := strings.Split(line, " ")
		section, key := splitKey(words[0])
		spec := &Spec{Line: i+1, Pattern: words[0], Key: key, Kind: words[1], Parts: strings.Split(section, "."), Attributes: map[string]string{}}
		for _, part := range spec.Parts { spec.Wildcard = spec.Wildcard || part == "*" }
		for _, word := range words[2:] { attribute, value, _ := strings.Cut(word, "="); spec.Attributes[attribute] = value }
		schema.Specs = append(schema.Specs, spec)
		if !spec.Wildcard { schema.Exact[spec.Pattern] = spec }
	}
	return schema
}

func (s *Schema) find(key string) *Spec {
	if spec := s.Exact[key]; spec != nil { return spec }
	section, name := splitKey(key)
	for _, spec := range s.Specs { if spec.Wildcard && spec.Key == name && spec.matches(section) { return spec } }
	return nil
}

func (s *Schema) targets(spec *Spec, sections map[string]bool) []string {
	if !spec.Wildcard { return []string{spec.Pattern} }
	var keys []string
	for section := range sections {
		key := section+"."+spec.Key
		if spec.matches(section) && s.find(key) == spec { keys = append(keys, key) }
	}
	sort.Slice(keys, func(i, j int) bool { return keyLess(keys[i], keys[j]) })
	return keys
}
