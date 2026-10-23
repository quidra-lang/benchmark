package main

import (
	"fmt"
	"os"
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"
)

type Origin struct { Document string; Line int }
type Diagnostic struct { Origin Origin; Code, Message string }
type Definition struct { Value string; Origin Origin; Number int64; History []Origin }
type Value struct { Kind, Text string; Number int64; Boolean bool; Items []Value }
type OutputKey struct { Definition *Definition; Spec *Spec; Value Value; Notation string }
type Parent struct { Section string; Origin Origin }
type TreeEntry struct { Depth int; Text string }
type CheckError struct { Code, Message string }

func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil { panic(err) }
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}

func splitKey(key string) (string, string) { i := strings.LastIndexByte(key, '.'); return key[:i], key[i+1:] }
func keyLess(a, b string) bool {
	as, ak := splitKey(a); bs, bk := splitKey(b)
	if as != bs { return as < bs }; return ak < bk
}
func sortedKeys[V any](values map[string]V) []string {
	keys := make([]string, 0, len(values))
	for key := range values { keys = append(keys, key) }
	sort.Slice(keys, func(i, j int) bool { return keyLess(keys[i], keys[j]) })
	return keys
}
func decimal(text string) int64 { n, _ := strconv.ParseInt(text, 10, 64); return n }

var integerPattern = regexp.MustCompile(`^([+-]?)(0[xX]([0-9a-fA-F]{1,10})|([0-9](_?[0-9])*))$`)
var sizePattern = regexp.MustCompile(`^([0-9]{1,6})(\.([0-9]{1,3}))?([A-Za-z]*)$`)
var secondsPattern = regexp.MustCompile(`^[0-9]{1,6}$`)
var durationPattern = regexp.MustCompile(`^(([0-9]{1,6})h)?(([0-9]{1,6})m)?(([0-9]{1,6})s)?$`)
var ipv4Characters = regexp.MustCompile(`^[0-9.]*$`)
var ipv4Part = regexp.MustCompile(`^(0|[1-9][0-9]{0,2})$`)
var hostLabel = regexp.MustCompile(`^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$`)
var schemePattern = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9+.-]*$`)
var portPattern = regexp.MustCompile(`^[1-9][0-9]{0,4}$`)
var datePattern = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}$`)

func parseScalar(kind, text string, values []string) (Value, bool) {
	v := Value{Kind: kind, Text: text}
	switch kind {
	case "string": return v, true
	case "int":
		m := integerPattern.FindStringSubmatch(text)
		if m == nil { return v, false }
		if m[3] != "" { v.Number, _ = strconv.ParseInt(m[3], 16, 64) } else {
			digits := strings.ReplaceAll(m[4], "_", "")
			if len(digits) > 12 { return v, false }
			v.Number = decimal(digits)
		}
		if m[1] == "-" { v.Number = -v.Number }
	case "bool":
		switch strings.ToLower(text) {
		case "true", "yes", "on", "1": v.Boolean = true
		case "false", "no", "off", "0": v.Boolean = false
		default: return v, false
		}
	case "enum":
		found := false
		for _, entry := range values { if strings.EqualFold(text, entry) { v.Text = entry; found = true; break } }
		if !found { return v, false }
	case "size":
		m := sizePattern.FindStringSubmatch(text)
		if m == nil { return v, false }
		factor, ok := map[string]int64{"":1, "b":1, "kb":1024, "mb":1048576, "gb":1073741824}[strings.ToLower(m[4])]
		if !ok { return v, false }
		v.Number = decimal(m[1])*factor
		if m[3] != "" {
			divisor := int64(1)
			for range m[3] { divisor *= 10 }
			numerator := decimal(m[3])*factor
			if numerator%divisor != 0 { return v, false }
			v.Number += numerator/divisor
		}
	case "duration":
		if secondsPattern.MatchString(text) { v.Number = decimal(text); break }
		m := durationPattern.FindStringSubmatch(text)
		if m == nil || text == "" { return v, false }
		v.Number = decimal(m[2])*3600+decimal(m[4])*60+decimal(m[6])
	case "host":
		parts := strings.Split(text, ".")
		if ipv4Characters.MatchString(text) {
			if len(parts) != 4 { return v, false }
			for _, p := range parts { if !ipv4Part.MatchString(p) || decimal(p) > 255 { return v, false } }
		} else {
			if len(text) > 253 { return v, false }
			for _, p := range parts { if !hostLabel.MatchString(p) { return v, false } }
			v.Text = strings.ToLower(text)
		}
	case "path":
		if text == "" || strings.ContainsAny(text, " \n\t") { return v, false }
		absolute := strings.HasPrefix(text, "/")
		var parts []string
		for _, part := range strings.Split(text, "/") {
			if part == "" || part == "." { continue }
			if part != ".." { parts = append(parts, part)
			} else if len(parts)>0 && parts[len(parts)-1] != ".." { parts = parts[:len(parts)-1]
			} else if absolute { return v, false
			} else { parts = append(parts, part) }
		}
		v.Text = strings.Join(parts, "/")
		if absolute { v.Text = "/"+v.Text } else if v.Text == "" { v.Text = "." }
	case "url":
		scheme, rest, found := strings.Cut(text, "://")
		if !found || !schemePattern.MatchString(scheme) || strings.ContainsAny(rest, "?#") { return v, false }
		authority, path, _ := strings.Cut(rest, "/")
		host, port, colon := strings.Cut(authority, ":")
		hostValue, hostOK := parseScalar("host", host, nil)
		pathValue, pathOK := parseScalar("path", "/"+path, nil)
		if !hostOK || !pathOK { return v, false }
		scheme = strings.ToLower(scheme)
		v.Text = scheme+"://"+hostValue.Text
		if colon {
			if !portPattern.MatchString(port) || decimal(port) > 65535 { return v, false }
			defaultPort := int64(-1)
			if scheme == "http" { defaultPort = 80 } else if scheme == "https" { defaultPort = 443 }
			if decimal(port) != defaultPort { v.Text += ":"+port }
		}
		v.Text += pathValue.Text
	case "date":
		if !datePattern.MatchString(text) { return v, false }
		year, month, day := decimal(text[:4]), decimal(text[5:7]), decimal(text[8:])
		if year < 1 || month < 1 || month > 12 { return v, false }
		days := []int64{31,28,31,30,31,30,31,31,30,31,30,31}
		if year%4 == 0 && (year%100 != 0 || year%400 == 0) { days[1] = 29 }
		if day < 1 || day > days[month-1] { return v, false }
	default: return v, false
	}
	return v, true
}

func typeError(key, kind, text string, spec *Spec, item bool) *CheckError {
	display := checkedText(text, spec.has("secret"))
	if item { display = "item "+display }
	if kind == "enum" { return &CheckError{"E_ENUM", key+": "+display+" is not one of "+spec.Attributes["values"]} }
	return &CheckError{"E_TYPE", key+": "+display+" is not a valid "+kind}
}

type Profile struct {
	Name, Root string
	Configuration map[string]*Definition
	Parents map[string]Parent
	Tree []TreeEntry
	Reported map[Diagnostic]bool
	Outputs map[string]*OutputKey
	DefinitionCount int64
	Diagnostics []Diagnostic
	Overridden []string
	Errors, Warnings, DocumentKeys, ManifestKeys, DefaultKeys, Dropped int
}

func newProfile(name, root string) *Profile {
	return &Profile{Name: name, Root: root, Configuration: map[string]*Definition{}, Parents: map[string]Parent{}, Reported: map[Diagnostic]bool{}, Outputs: map[string]*OutputKey{}}
}
func (p *Profile) report(origin Origin, code, message string) { p.Reported[Diagnostic{origin, code, message}] = true }
func (p *Profile) define(key, value string, origin Origin) {
	p.DefinitionCount++
	var history []Origin
	if previous := p.Configuration[key]; previous != nil { history = append(history, previous.History...) }
	if len(history) == 0 || history[len(history)-1] != origin { history = append(history, origin) }
	p.Configuration[key] = &Definition{value, origin, p.DefinitionCount, history}
}

type DocumentLibrary struct { Cache map[string]*Document }
func (l *DocumentLibrary) find(name string) *Document {
	if document, ok := l.Cache[name]; ok { return document }
	path := "input/conf/"+name+".ini"
	if _, err := os.Stat(path); os.IsNotExist(err) { l.Cache[name] = nil; return nil }
	document := parseDocument(name, readLines(path))
	l.Cache[name] = document
	return document
}

func (p *Profile) apply(library *DocumentLibrary, name string, chain []string) {
	document := library.find(name)
	p.Tree = append(p.Tree, TreeEntry{len(chain)-1, name})
	for _, d := range document.Diagnostics { p.Reported[d] = true }
	for _, statement := range document.Statements {
		origin := Origin{name, statement.Line}
		key, value := statement.Target, statement.Value
		switch statement.Kind {
		case "assign": p.define(key, value, origin)
		case "append":
			if previous := p.Configuration[key]; previous != nil && previous.Value != "" { value = previous.Value+","+value }
			p.define(key, value, origin)
		case "unset":
			if p.Configuration[key] == nil { p.report(origin, "W_UNSET", key+" is not set") } else { delete(p.Configuration, key) }
		case "inherit": p.Parents[key] = Parent{value, origin}
		case "include":
			if index := slices.Index(chain, key); index >= 0 {
				path := append(append([]string(nil), chain[index:]...), key)
				p.report(origin, "E_INCLUDE_CYCLE", "include cycle "+strings.Join(path, " -> "))
				p.Tree = append(p.Tree, TreeEntry{len(chain), key+" (cycle)"})
			} else if library.find(key) == nil {
				p.report(origin, "E_INCLUDE_MISSING", "missing document "+key)
				p.Tree = append(p.Tree, TreeEntry{len(chain), key+" (missing)"})
			} else { p.apply(library, key, append(append([]string(nil), chain...), key)) }
		}
	}
}

func (p *Profile) inheritSections() {
	own := map[string]map[string]*Definition{}
	for key, definition := range p.Configuration {
		section, name := splitKey(key)
		if own[section] == nil { own[section] = map[string]*Definition{} }
		own[section][name] = definition
	}
	for section, declaration := range p.Parents {
		chain := []string{section}
		for {
			parent, exists := p.Parents[chain[len(chain)-1]]
			if !exists || slices.Contains(chain, parent.Section) { break }
			chain = append(chain, parent.Section)
		}
		if parent, exists := p.Parents[chain[len(chain)-1]]; exists {
			p.report(declaration.Origin, "E_INHERIT_CYCLE", "inheritance cycle "+strings.Join(append(chain, parent.Section), " -> "))
			continue
		}
		if _, recorded := p.Parents[declaration.Section]; !recorded && len(own[declaration.Section]) == 0 {
			p.report(declaration.Origin, "W_PARENT_EMPTY", "section "+section+" inherits from empty section "+declaration.Section)
		}
		for _, ancestor := range chain[1:] { for name, definition := range own[ancestor] {
			key := section+"."+name
			if p.Configuration[key] == nil { p.Configuration[key] = definition }
		} }
	}
}

func (p *Profile) resolveAliases(schema *Schema) {
	for _, spec := range schema.Specs {
		if !spec.has("alias") { continue }
		aliases := strings.Split(spec.Attributes["alias"], ",")
		var candidates []string
		if p.Configuration[spec.Pattern] != nil { candidates = append(candidates, spec.Pattern) }
		hasAlias := false
		for _, alias := range aliases { if p.Configuration[alias] != nil { candidates = append(candidates, alias); hasAlias = true } }
		if !hasAlias { continue }
		winner := candidates[0]
		for _, key := range candidates[1:] { if p.Configuration[key].Number > p.Configuration[winner].Number { winner = key } }
		chosen := p.Configuration[winner]
		for _, key := range candidates {
			origin := p.Configuration[key].Origin
			if key != spec.Pattern { p.report(origin, "W_DEPRECATED", key+" is deprecated, use "+spec.Pattern) }
			if key != winner { p.report(origin, "W_SHADOWED", key+" is superseded by "+winner+" at "+originText(chosen.Origin)) }
		}
		p.Configuration[spec.Pattern] = chosen
		for _, alias := range aliases { delete(p.Configuration, alias) }
	}
}

func (p *Profile) fillDefaults(schema *Schema) map[string]bool {
	sections := map[string]bool{}
	for key := range p.Configuration { section, _ := splitKey(key); sections[section] = true }
	for _, spec := range schema.Specs { if spec.has("default") { for _, key := range schema.targets(spec, sections) {
		if p.Configuration[key] == nil { p.define(key, spec.Attributes["default"], Origin{"schema", spec.Line}) }
	} } }
	return sections
}

func (p *Profile) normalize(key, text string, spec *Spec, origin Origin) (Value, *CheckError) {
	values := strings.Split(spec.Attributes["values"], ",")
	var value Value
	if spec.Kind == "list" {
		value.Kind = "list"
		if strings.Trim(text, " ") != "" {
			items := strings.Split(text, ",")
			for i := range items { items[i] = strings.Trim(items[i], " ") }
			if slices.Contains(items, "") { p.report(origin, "W_EMPTY_ITEM", key+": empty list item ignored") }
			for _, item := range items {
				if item == "" { continue }
				normalized, ok := parseScalar(spec.item(), item, values)
				if !ok { return value, typeError(key, spec.item(), item, spec, true) }
				value.Items = append(value.Items, normalized)
			}
		}
		if spec.has("unique") {
			seen := map[string]bool{}
			unique := make([]Value, 0, len(value.Items))
			for _, item := range value.Items { notation := valueNotation(item); if !seen[notation] { seen[notation] = true; unique = append(unique, item) } }
			if len(unique) < len(value.Items) { p.report(origin, "W_DUPLICATE_ITEM", key+": duplicate items removed") }
			value.Items = unique
		}
	} else {
		var ok bool
		value, ok = parseScalar(spec.Kind, text, values)
		if !ok { return value, typeError(key, spec.Kind, text, spec, false) }
	}
	if spec.has("range") {
		lower, upper, _ := strings.Cut(spec.Attributes["range"], "..")
		measure := value.Number
		display := shownNotation(valueNotation(value), spec.has("secret"))
		count := spec.Kind == "string" || spec.Kind == "list"
		if count {
			label := "length"
			measure = int64(len(value.Text))
			if spec.Kind == "list" { measure = int64(len(value.Items)); label = "count" }
			display = fmt.Sprintf("%s %d", label, measure)
		}
		outside := false
		bounds := []string{lower, upper}
		for i, bound := range bounds {
			if bound == "" { continue }
			if spec.Kind == "date" {
				outside = outside || (i == 0 && value.Text < bound) || (i == 1 && value.Text > bound)
			} else {
				number := decimal(bound)
				if !count { parsed, _ := parseScalar(spec.Kind, bound, nil); number = parsed.Number }
				outside = outside || (i == 0 && measure < number) || (i == 1 && measure > number)
				bounds[i] = strconv.FormatInt(number, 10)
			}
		}
		if outside { return value, &CheckError{"E_RANGE", key+": "+display+" is out of range "+strings.Join(bounds, "..")} }
	}
	return value, nil
}

func (p *Profile) validate(schema *Schema) {
	expanded := expandAll(p.Configuration, p.report)
	for _, key := range sortedKeys(p.Configuration) {
		text := expanded[key]
		if text == nil { continue }
		definition, spec := p.Configuration[key], schema.find(key)
		value := Value{Kind:"string", Text:*text}
		if spec == nil { p.report(definition.Origin, "W_UNKNOWN", key+" is not in the schema") } else {
			var failure *CheckError
			value, failure = p.normalize(key, *text, spec, definition.Origin)
			if failure != nil { p.report(definition.Origin, failure.Code, failure.Message); continue }
		}
		p.Outputs[key] = &OutputKey{definition, spec, value, valueNotation(value)}
	}
}

func (p *Profile) checkOrder() {
	var removed []string
	for _, key := range sortedKeys(p.Outputs) {
		output := p.Outputs[key]
		if output.Spec == nil || !output.Spec.has("le") { continue }
		section, _ := splitKey(key)
		limitKey := section+"."+output.Spec.Attributes["le"]
		limit := p.Outputs[limitKey]
		if limit != nil && (limit.Value.Kind == "int" || limit.Value.Kind == "size" || limit.Value.Kind == "duration") && output.Value.Number > limit.Value.Number {
			p.report(output.Definition.Origin, "E_ORDER", key+": "+shown(output)+" is greater than "+limitKey+" ("+shown(limit)+")")
			removed = append(removed, key)
		}
	}
	for _, key := range removed { delete(p.Outputs, key) }
}

func (p *Profile) checkRequired(schema *Schema, sections map[string]bool) {
	for _, spec := range schema.Specs { if spec.has("required") { for _, key := range schema.targets(spec, sections) {
		if p.Configuration[key] != nil { continue }
		message := key+" is required"
		if spec.has("when") {
			section, _ := splitKey(key)
			conditionKey := section+"."+spec.Attributes["when"]
			condition := p.Outputs[conditionKey]
			if condition == nil || condition.Value.Kind != "bool" || !condition.Value.Boolean { continue }
			message += " when "+conditionKey+" is true"
		}
		p.report(Origin{p.Root, 0}, "E_REQUIRED", message)
	} } }
}

func (p *Profile) checkFixed(earlier []*Profile) {
	for _, key := range sortedKeys(p.Outputs) {
		output := p.Outputs[key]
		if output.Spec == nil || !output.Spec.has("fixed") { continue }
		for _, reference := range earlier {
			before := reference.Outputs[key]
			if before == nil { continue }
			if before.Notation != output.Notation {
				p.report(output.Definition.Origin, "E_FIXED", key+": value differs from profile "+reference.Name)
				delete(p.Outputs, key)
			}
			break
		}
	}
}

func (p *Profile) finish() {
	for diagnostic := range p.Reported { p.Diagnostics = append(p.Diagnostics, diagnostic) }
	sort.Slice(p.Diagnostics, func(i, j int) bool {
		a, b := p.Diagnostics[i], p.Diagnostics[j]
		if a.Origin.Document != b.Origin.Document { return a.Origin.Document < b.Origin.Document }
		if a.Origin.Line != b.Origin.Line { return a.Origin.Line < b.Origin.Line }
		if a.Code != b.Code { return a.Code < b.Code }; return a.Message < b.Message
	})
	for _, d := range p.Diagnostics { if strings.HasPrefix(d.Code, "E_") { p.Errors++ } else { p.Warnings++ } }
	for _, key := range sortedKeys(p.Outputs) {
		definition := p.Outputs[key].Definition
		if len(definition.History) >= 2 { p.Overridden = append(p.Overridden, key) }
		switch definition.Origin.Document {
		case "manifest": p.ManifestKeys++
		case "schema": p.DefaultKeys++
		default: p.DocumentKeys++
		}
	}
	p.Dropped = len(p.Configuration)-len(p.Outputs)
}

type DiffEntry struct { Sign, Key string; Before, After *OutputKey }
type ProfileDiff struct { First, Second string; Added, Removed, Changed int; Entries []DiffEntry }
func differences(first, second *Profile) ProfileDiff {
	diff := ProfileDiff{First:first.Name, Second:second.Name}
	keys := map[string]bool{}
	for key := range first.Outputs { keys[key] = true }; for key := range second.Outputs { keys[key] = true }
	for _, key := range sortedKeys(keys) {
		before, after := first.Outputs[key], second.Outputs[key]
		sign := ""
		if before == nil { sign = "+"; diff.Added++ } else if after == nil { sign = "-"; diff.Removed++ } else if before.Notation != after.Notation { sign = "~"; diff.Changed++ }
		if sign != "" { diff.Entries = append(diff.Entries, DiffEntry{sign, key, before, after}) }
	}
	return diff
}

func main() {
	schema := loadSchema("input/schema.txt")
	library := &DocumentLibrary{Cache: map[string]*Document{}}
	var profiles []*Profile
	for number, line := range readLines("input/manifest.txt") {
		words := strings.Split(line, " ")
		profile := newProfile(words[0], words[1])
		profile.apply(library, profile.Root, []string{profile.Root})
		for _, override := range words[2:] { key, value, _ := strings.Cut(override, "="); profile.define(key, value, Origin{"manifest", number+1}) }
		profile.inheritSections()
		profile.resolveAliases(schema)
		sections := profile.fillDefaults(schema)
		profile.validate(schema)
		profile.checkOrder()
		profile.checkRequired(schema, sections)
		profile.checkFixed(profiles)
		profile.finish()
		profiles = append(profiles, profile)
	}
	var diffs []ProfileDiff
	for i := 1; i < len(profiles); i++ { diffs = append(diffs, differences(profiles[i-1], profiles[i])) }
	writeOutputs(profiles, diffs)
}
