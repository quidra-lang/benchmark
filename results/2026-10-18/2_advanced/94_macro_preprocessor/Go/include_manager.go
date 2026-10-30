package main

import (
	"os"
	"strings"
)

type FileData struct {
	Path                                        string
	Lines                                       []LogicalLine
	PhysicalLines                               int
	Guard                                       string
	Entered, Skipped, OutputLines, SkippedLines int
	Once                                        bool
}
type IncludeManager struct {
	Files map[string]*FileData
	Order []string
}

func directiveName(tokens []Token) string {
	if len(tokens) >= 2 && tokens[0].Spelling == "#" && tokens[1].Kind == "identifier" {
		return tokens[1].Spelling
	}
	return ""
}
func detectGuard(logical []LogicalLine) string {
	lines := [][]Token{}
	for _, line := range logical {
		if len(line.Tokens) > 0 {
			lines = append(lines, line.Tokens)
		}
	}
	if len(lines) == 0 {
		return ""
	}
	first, last := lines[0], lines[len(lines)-1]
	if len(first) != 3 || first[0].Spelling != "#" || first[1].Spelling != "ifndef" || first[1].Kind != "identifier" || first[2].Kind != "identifier" || len(last) != 2 || last[0].Spelling != "#" || last[1].Spelling != "endif" || last[1].Kind != "identifier" {
		return ""
	}
	depth := 0
	for i, line := range lines {
		name := directiveName(line)
		if wordIn("elif elifdef elifndef else", name) && depth == 1 {
			return ""
		}
		if wordIn("if ifdef ifndef", name) {
			depth++
		} else if name == "endif" {
			depth--
		}
		if depth == 0 && i != len(lines)-1 {
			return ""
		}
	}
	if depth != 0 {
		return ""
	}
	return first[2].Spelling
}
func (m *IncludeManager) search(name string, quoted bool) string {
	paths := []string{}
	if quoted {
		paths = append(paths, name)
	}
	paths = append(paths, "include/"+name)
	for _, path := range paths {
		if info, err := os.Stat("input/" + path); err == nil && !info.IsDir() {
			return path
		}
	}
	return ""
}
func (m *IncludeManager) load(path string) *FileData {
	if file := m.Files[path]; file != nil {
		return file
	}
	raw, err := os.ReadFile("input/" + path)
	if err != nil {
		panic(err)
	}
	source := string(raw)
	logical := lexSource(source)
	file := &FileData{Path: path, Lines: logical, PhysicalLines: strings.Count(source, "\n"), Guard: detectGuard(logical)}
	m.Files[path] = file
	m.Order = append(m.Order, path)
	return file
}
