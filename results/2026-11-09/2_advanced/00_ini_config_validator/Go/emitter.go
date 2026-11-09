package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

const mask = "********"

func stringNotation(text string) string {
	return `"` + strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", `\n`, "\t", `\t`).Replace(text) + `"`
}

func valueNotation(value Value) string {
	switch value.Kind {
	case "string": return stringNotation(value.Text)
	case "int", "size", "duration": return strconv.FormatInt(value.Number, 10)
	case "bool": return strconv.FormatBool(value.Boolean)
	case "list":
		parts := make([]string, len(value.Items))
		for i, item := range value.Items { parts[i] = valueNotation(item) }
		return "["+strings.Join(parts, ", ")+"]"
	default: return value.Text
	}
}

func originText(origin Origin) string { return fmt.Sprintf("%s:%d", origin.Document, origin.Line) }
func shownNotation(notation string, secret bool) string { if secret { return mask }; return notation }
func checkedText(text string, secret bool) string { return shownNotation(stringNotation(text), secret) }
func shown(output *OutputKey) string { return shownNotation(output.Notation, output.Spec != nil && output.Spec.has("secret")) }

func normalizedBlock(profile *Profile) string {
	lines := []string{"profile "+profile.Name}
	previous := ""
	for _, key := range sortedKeys(profile.Outputs) {
		section, name := splitKey(key)
		if section != previous { lines = append(lines, "["+section+"]"); previous = section }
		lines = append(lines, name+" = "+shown(profile.Outputs[key]))
	}
	return strings.Join(lines, "\n")
}

func diagnosticsBlock(profile *Profile) string {
	lines := []string{fmt.Sprintf("profile %s errors %d warnings %d", profile.Name, profile.Errors, profile.Warnings)}
	for _, d := range profile.Diagnostics { lines = append(lines, originText(d.Origin)+" "+d.Code+" "+d.Message) }
	return strings.Join(lines, "\n")
}

func diffBlock(diff ProfileDiff) string {
	lines := []string{fmt.Sprintf("diff %s -> %s: %d added, %d removed, %d changed", diff.First, diff.Second, diff.Added, diff.Removed, diff.Changed)}
	for _, entry := range diff.Entries {
		switch entry.Sign {
		case "+": lines = append(lines, "+ "+entry.Key+" = "+shown(entry.After))
		case "-": lines = append(lines, "- "+entry.Key+" = "+shown(entry.Before))
		default: lines = append(lines, "~ "+entry.Key+": "+shown(entry.Before)+" -> "+shown(entry.After))
		}
	}
	return strings.Join(lines, "\n")
}

func reportBlock(profile *Profile) string {
	lines := []string{"profile "+profile.Name, "includes"}
	for _, entry := range profile.Tree { lines = append(lines, strings.Repeat(" ", 2+2*entry.Depth)+entry.Text) }
	lines = append(lines, "overridden")
	for _, key := range profile.Overridden {
		history := profile.Outputs[key].Definition.History
		origins := make([]string, len(history))
		for i, origin := range history { origins[i] = originText(origin) }
		lines = append(lines, "  "+key+": "+strings.Join(origins, " -> "))
	}
	if len(profile.Overridden) == 0 { lines = append(lines, "  (none)") }
	lines = append(lines, fmt.Sprintf("keys %d documents %d manifest %d defaults %d", len(profile.Outputs), profile.DocumentKeys, profile.ManifestKeys, profile.DefaultKeys), fmt.Sprintf("dropped %d", profile.Dropped), fmt.Sprintf("errors %d warnings %d", profile.Errors, profile.Warnings))
	return strings.Join(lines, "\n")
}

func writeOutputs(profiles []*Profile, diffs []ProfileDiff) {
	if err := os.MkdirAll("output", 0755); err != nil { panic(err) }
	files := map[string][]string{}
	for _, p := range profiles {
		files["normalized.txt"] = append(files["normalized.txt"], normalizedBlock(p))
		files["diagnostics.txt"] = append(files["diagnostics.txt"], diagnosticsBlock(p))
		files["report.txt"] = append(files["report.txt"], reportBlock(p))
	}
	for _, diff := range diffs { files["diff.txt"] = append(files["diff.txt"], diffBlock(diff)) }
	for name, blocks := range files { if err := os.WriteFile(filepath.Join("output", name), []byte(strings.Join(blocks, "\n\n")+"\n"), 0644); err != nil { panic(err) } }
}
