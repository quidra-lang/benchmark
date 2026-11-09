package main

import (
	"slices"
	"strings"
)

type Expander struct {
	Configuration map[string]*Definition
	Results map[string]*string
	Stack []string
	CycleKeys map[string]bool
	Report func(Origin, string, string)
}

func expandAll(configuration map[string]*Definition, report func(Origin, string, string)) map[string]*string {
	e := &Expander{Configuration: configuration, Results: map[string]*string{}, CycleKeys: map[string]bool{}, Report: report}
	for _, key := range sortedKeys(configuration) { e.expand(key) }
	return e.Results
}

func (e *Expander) expand(key string) *string {
	if result, ok := e.Results[key]; ok { return result }
	e.Stack = append(e.Stack, key)
	result := e.evaluate(key)
	e.Stack = e.Stack[:len(e.Stack)-1]
	e.Results[key] = result
	return result
}

func (e *Expander) evaluate(key string) *string {
	definition := e.Configuration[key]
	text := definition.Value
	section, _ := splitKey(key)
	var out strings.Builder
	for i := 0; i < len(text); {
		if !strings.HasPrefix(text[i:], "${") {
			if text[i] == literalDollar { out.WriteByte('$') } else { out.WriteByte(text[i]) }
			i++
			continue
		}
		end := strings.IndexByte(text[i+2:], '}')
		if end < 0 { e.Report(definition.Origin, "E_BAD_REF", key+": invalid reference"); return nil }
		end += i+2
		reference := text[i+2:end]
		if !sectionPattern.MatchString(reference) { e.Report(definition.Origin, "E_BAD_REF", key+": invalid reference"); return nil }
		target := reference
		if !strings.Contains(target, ".") { target = section+"."+target }
		if e.Configuration[target] == nil { e.Report(definition.Origin, "E_UNDEFINED", key+": undefined reference "+target); return nil }
		var result *string
		if index := slices.Index(e.Stack, target); index >= 0 {
			path := append(append([]string(nil), e.Stack[index:]...), target)
			e.Report(e.Configuration[target].Origin, "E_CYCLE", "interpolation cycle "+strings.Join(path, " -> "))
			for _, member := range path { e.CycleKeys[member] = true }
		} else { result = e.expand(target) }
		if result == nil {
			if !e.CycleKeys[key] { e.Report(definition.Origin, "E_DEPENDENCY", key+": depends on failed key "+target) }
			return nil
		}
		out.WriteString(*result)
		i = end+1
	}
	result := out.String()
	return &result
}
