package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type ConditionalBlock struct {
	Kind                             string
	Start                            Position
	Parent, Chosen, Active, ElseSeen bool
	SkipStart                        int
}
type Inclusion struct {
	Source      *FileData
	Depth       int
	DisplayFile string
	Offset      int
	Stack       []*ConditionalBlock
	Segment     []Token
}

func (c *Inclusion) position(physical int) Position {
	return Position{c.DisplayFile, physical + c.Offset}
}
func (c *Inclusion) skipping() bool { return len(c.Stack) > 0 && !c.Stack[len(c.Stack)-1].Active }

type Header struct {
	Rendering, Name string
	Quoted          bool
}

func readHeader(tokens []Token, index int) (*Header, int, string) {
	if index >= len(tokens) {
		return nil, index, ""
	}
	t := tokens[index]
	if t.Kind == "string" || t.Kind == "header" {
		return &Header{t.Spelling, t.Spelling[1 : len(t.Spelling)-1], t.Spelling[0] == '"'}, index + 1, ""
	}
	if t.Spelling == "<" {
		end := index + 1
		for end < len(tokens) && tokens[end].Spelling != ">" {
			end++
		}
		if end == len(tokens) {
			return nil, index, "missing terminating > character"
		}
		rendering := "<" + render(tokens[index+1:end]) + ">"
		return &Header{rendering, rendering[1 : len(rendering)-1], false}, end + 1, ""
	}
	return nil, index, ""
}
func separatorNeeded(left, right string) bool {
	if left == "/" && (right[0] == '/' || right[0] == '*') {
		return true
	}
	_, _, end := readToken(left+right, 0, false)
	return end != len(left)
}
func outputRender(tokens []Token) string {
	var out strings.Builder
	for i, t := range tokens {
		if i > 0 && (t.Space || separatorNeeded(tokens[i-1].Spelling, t.Spelling)) {
			out.WriteByte(' ')
		}
		out.WriteString(t.Spelling)
	}
	return out.String()
}
func following(heading string, items []string) string {
	for _, item := range items {
		heading += " " + item
	}
	return heading
}
func decimalToken(t Token) bool {
	if t.Kind != "number" || t.Spelling == "" {
		return false
	}
	for i := range t.Spelling {
		if !digit(t.Spelling[i]) {
			return false
		}
	}
	return true
}

type Preprocessor struct {
	Macros                                                    map[string]*Macro
	EverDefined, Poisoned                                     map[string]bool
	Saved                                                     map[string][]*Macro
	Manager                                                   *IncludeManager
	Expander                                                  *Expander
	Output, History, Diagnostics, Tree, Conditionals, Regions []string
	DiagnosticCounts, ConditionCounts                         map[string]int
	Previous                                                  Position
}

func newPreprocessor() *Preprocessor {
	p := &Preprocessor{Macros: map[string]*Macro{}, EverDefined: map[string]bool{}, Poisoned: map[string]bool{}, Saved: map[string][]*Macro{}, Manager: &IncludeManager{Files: map[string]*FileData{}}, Tree: []string{"main.c"}, DiagnosticCounts: map[string]int{}, ConditionCounts: map[string]int{}}
	p.Expander = &Expander{Macros: p.Macros, Diagnostic: p.diagnostic, BuiltinCounts: map[string]int{}}
	return p
}
func (p *Preprocessor) diagnostic(pos Position, kind, message string) {
	p.Diagnostics = append(p.Diagnostics, pos.String()+": "+kind+": "+message)
	p.DiagnosticCounts[kind]++
}
func (p *Preprocessor) event(pos Position, content string) {
	p.History = append(p.History, pos.String()+": "+content)
}
func (p *Preprocessor) poisonCheck(c *Inclusion, tokens []Token) {
	for _, t := range tokens {
		if t.Kind == "identifier" && p.Poisoned[t.Spelling] {
			p.diagnostic(c.position(t.Line), "error", `attempt to use poisoned "`+t.Spelling+`"`)
		}
	}
}
func (p *Preprocessor) unusedCheck(m *Macro) {
	if m.MainFile && m.Expanded == 0 && m.Tested == 0 {
		p.diagnostic(m.Position, "warning", `macro "`+m.Name+`" is not used`)
	}
}
func (p *Preprocessor) define(tokens []Token, pos Position, main bool) {
	m, error := parseDefinition(tokens, pos, main)
	if error != "" {
		p.diagnostic(pos, "error", error)
		return
	}
	previous := p.Macros[m.Name]
	operation := "define"
	if previous == nil {
		p.Macros[m.Name] = m
		p.EverDefined[m.Name] = true
	} else if previous.identical(m) {
		operation = "identical"
	} else {
		p.unusedCheck(previous)
		p.diagnostic(pos, "warning", `"`+m.Name+`" redefined (previous definition at `+previous.Position.String()+")")
		p.Macros[m.Name] = m
		p.EverDefined[m.Name] = true
		operation = "redefine"
	}
	p.event(pos, operation+" "+m.signature())
}
func (p *Preprocessor) undefine(tokens []Token, pos Position) {
	if error := checkName(tokens, "undef"); error != "" {
		p.diagnostic(pos, "error", error)
		return
	}
	if len(tokens) > 1 {
		p.diagnostic(pos, "warning", "extra tokens at end of #undef directive")
	}
	name := tokens[0].Spelling
	if previous := p.Macros[name]; previous != nil {
		p.unusedCheck(previous)
		delete(p.Macros, name)
		p.event(pos, "undef "+name)
	} else {
		p.event(pos, "undef "+name+" (not defined)")
	}
}
func (p *Preprocessor) processDefines() {
	raw, err := os.ReadFile("input/defines.txt")
	if err != nil {
		panic(err)
	}
	for i, line := range strings.Split(string(raw), "\n") {
		if line == "" {
			continue
		}
		text := line + " 1"
		if index := strings.IndexByte(line, '='); index >= 0 {
			text = line[:index] + " " + line[index+1:]
		}
		p.define(lexDefinition(text, i+1), Position{"defines.txt", i + 1}, false)
	}
}
func (p *Preprocessor) marker(file string, line, flag int) {
	value := fmt.Sprintf("# %d %q", line, file)
	if flag != 0 {
		value += " " + strconv.Itoa(flag)
	}
	p.Output = append(p.Output, value)
	p.Previous = Position{file, line - 1}
}
func (p *Preprocessor) outputLine(c *Inclusion, physical int, text string) {
	position := c.position(physical)
	if position.File == p.Previous.File && p.Previous.Line < position.Line && position.Line <= p.Previous.Line+8 {
		for i := p.Previous.Line + 1; i < position.Line; i++ {
			p.Output = append(p.Output, "")
		}
	} else {
		p.marker(position.File, position.Line, 0)
	}
	p.Output = append(p.Output, text)
	p.Previous = position
	c.Source.OutputLines++
}
func (p *Preprocessor) flush(c *Inclusion) {
	segment := c.Segment
	c.Segment = nil
	if len(segment) == 0 {
		return
	}
	p.poisonCheck(c, segment)
	expanded := p.Expander.expand(segment, c)
	for start := 0; start < len(expanded); {
		end := start + 1
		for end < len(expanded) && expanded[end].Line == expanded[start].Line {
			end++
		}
		p.outputLine(c, expanded[start].Line, outputRender(expanded[start:end]))
		start = end
	}
}
func (p *Preprocessor) macroDefined(name string) bool {
	if m := p.Macros[name]; m != nil {
		m.Tested++
		return true
	}
	return builtins[name] || name == "__has_include"
}
func (p *Preprocessor) replaceOperators(operands []Token) ([]Token, string) {
	replaced := []Token{}
	for position := 0; position < len(operands); {
		t := operands[position]
		index := position + 1
		value := false
		if t.Kind == "identifier" && t.Spelling == "defined" {
			parenthesized := index < len(operands) && operands[index].Spelling == "("
			if parenthesized {
				index++
			}
			if index == len(operands) || operands[index].Kind != "identifier" {
				return nil, `operator "defined" requires an identifier`
			}
			name := operands[index].Spelling
			index++
			if parenthesized {
				if index == len(operands) || operands[index].Spelling != ")" {
					return nil, `missing ')' after "defined"`
				}
				index++
			}
			value = p.macroDefined(name)
		} else if t.Kind == "identifier" && t.Spelling == "__has_include" {
			if index == len(operands) || operands[index].Spelling != "(" {
				return nil, `missing '(' after "__has_include"`
			}
			header, next, error := readHeader(operands, index+1)
			if error != "" {
				return nil, error
			}
			if header == nil || header.Name == "" {
				return nil, `operator "__has_include" requires a header-name`
			}
			index = next
			if index == len(operands) || operands[index].Spelling != ")" {
				return nil, `missing ')' after "__has_include" operand`
			}
			index++
			value = p.Manager.search(header.Name, header.Quoted) != ""
		} else {
			replaced = append(replaced, t)
			position++
			continue
		}
		spelling := "0"
		if value {
			spelling = "1"
		}
		replaced = append(replaced, Token{Kind: "number", Spelling: spelling, Line: t.Line, Space: t.Space})
		position = index
	}
	return replaced, ""
}

type TestResult struct {
	Valid       bool
	Value       int64
	Expanded    []Token
	WasExpanded bool
}

func (p *Preprocessor) test(c *Inclusion, line LogicalLine, name string, operands []Token) TestResult {
	pos := c.position(line.Tokens[0].Line)
	p.poisonCheck(c, operands)
	if name != "if" && name != "elif" {
		if len(operands) == 0 {
			p.diagnostic(pos, "error", "no macro name given in #"+name+" directive")
			return TestResult{}
		}
		if operands[0].Kind != "identifier" {
			p.diagnostic(pos, "error", "macro names must be identifiers")
			return TestResult{}
		}
		if len(operands) > 1 {
			p.diagnostic(pos, "warning", "extra tokens at end of #"+name+" directive")
		}
		defined := p.macroDefined(operands[0].Spelling)
		if name == "ifndef" || name == "elifndef" {
			defined = !defined
		}
		value := int64(0)
		if defined {
			value = 1
		}
		return TestResult{Valid: true, Value: value}
	}
	replaced, error := p.replaceOperators(operands)
	if error != "" {
		p.diagnostic(pos, "error", error)
		return TestResult{}
	}
	expanded := p.Expander.expand(replaced, c)
	result := TestResult{Expanded: expanded, WasExpanded: true}
	tree, failure := parseCondition(expanded, name)
	if failure != nil {
		p.diagnostic(pos, "error", failure.Message)
		return result
	}
	value, failure := evaluateCondition(tree, func(message string) { p.diagnostic(pos, "warning", message) })
	if failure != nil {
		p.diagnostic(pos, "error", failure.Message)
		return result
	}
	result.Valid = true
	result.Value = value
	return result
}
func testDescription(name string, test TestResult) string {
	description := "not taken (error)"
	if test.Valid {
		description = "not taken"
		if test.Value != 0 {
			description = "taken"
		}
		if name == "if" || name == "elif" {
			description += fmt.Sprintf(" (value %d)", test.Value)
		}
	}
	if test.WasExpanded {
		description += " [" + outputRender(test.Expanded) + "]"
	}
	return description
}
func (p *Preprocessor) closeRegion(c *Inclusion, block *ConditionalBlock, end int) {
	start := block.SkipStart
	if start != 0 && end >= start {
		first, last := c.position(start), c.position(end)
		p.Regions = append(p.Regions, fmt.Sprintf("%s:%d-%d lines=%d", first.File, first.Line, last.Line, end-start+1))
		c.Source.SkippedLines += end - start + 1
	}
	block.SkipStart = 0
}
func (p *Preprocessor) conditionalRecord(pos Position, depth int, name string, operands []Token, description string) {
	directive := "#" + name
	if len(operands) > 0 {
		directive += " " + render(operands)
	}
	p.Conditionals = append(p.Conditionals, pos.String()+": "+strings.Repeat(" ", 2*depth)+directive+" => "+description)
	for _, pair := range [][2]string{{"taken", "taken"}, {"not taken", "not_taken"}, {"skipped", "skipped"}, {"not evaluated", "not_evaluated"}, {"closes", "endif"}} {
		if strings.HasPrefix(description, pair[0]) {
			p.ConditionCounts[pair[1]]++
			break
		}
	}
}
func (p *Preprocessor) conditional(c *Inclusion, line LogicalLine, name string, operands []Token) {
	pos := c.position(line.Tokens[0].Line)
	if wordIn("if ifdef ifndef", name) {
		parent := !c.skipping()
		block := &ConditionalBlock{Kind: name, Start: pos, Parent: parent}
		description := "skipped"
		if parent {
			test := p.test(c, line, name, operands)
			if test.Valid && test.Value != 0 {
				block.Chosen = true
				block.Active = true
			} else {
				block.SkipStart = line.End + 1
			}
			description = testDescription(name, test)
		}
		p.conditionalRecord(pos, len(c.Stack), name, operands, description)
		c.Stack = append(c.Stack, block)
		return
	}
	if len(c.Stack) == 0 {
		p.diagnostic(pos, "error", "#"+name+" without #if")
		return
	}
	block := c.Stack[len(c.Stack)-1]
	depth := len(c.Stack) - 1
	p.closeRegion(c, block, line.Start-1)
	description := ""
	if name == "endif" {
		c.Stack = c.Stack[:len(c.Stack)-1]
		if block.Parent && len(operands) > 0 {
			p.diagnostic(pos, "warning", "extra tokens at end of #endif directive")
		}
		description = fmt.Sprintf("closes #%s at line %d", block.Kind, block.Start.Line)
	} else {
		if block.ElseSeen {
			p.diagnostic(pos, "error", "#"+name+" after #else")
		}
		if name == "else" {
			if block.Parent && len(operands) > 0 {
				p.diagnostic(pos, "warning", "extra tokens at end of #else directive")
			}
			block.ElseSeen = true
			if block.Parent {
				block.Active = !block.Chosen
				block.Chosen = true
				description = "not taken"
				if block.Active {
					description = "taken"
				}
			} else {
				block.Active = false
				description = "skipped"
			}
		} else if !block.Parent {
			block.Active = false
			description = "skipped"
		} else if block.Chosen {
			block.Active = false
			description = "not evaluated"
		} else {
			test := p.test(c, line, name, operands)
			block.Active = test.Valid && test.Value != 0
			if block.Active {
				block.Chosen = true
			}
			description = testDescription(name, test)
		}
		if block.Parent && !block.Active {
			block.SkipStart = line.End + 1
		}
	}
	p.conditionalRecord(pos, depth, name, operands, description)
}
func (p *Preprocessor) include(c *Inclusion, line LogicalLine, operands []Token) {
	pos := c.position(line.Tokens[0].Line)
	sequence := operands
	header, consumed, error := readHeader(sequence, 0)
	if error != "" {
		p.diagnostic(pos, "error", error)
		return
	}
	if header == nil && len(sequence) > 0 {
		sequence = p.Expander.expand(sequence, c)
		header, consumed, error = readHeader(sequence, 0)
		if error != "" {
			p.diagnostic(pos, "error", error)
			return
		}
	}
	if header == nil {
		p.diagnostic(pos, "error", `#include expects "FILENAME" or <FILENAME>`)
		return
	}
	if consumed < len(sequence) {
		p.diagnostic(pos, "warning", "extra tokens at end of #include directive")
	}
	if header.Name == "" {
		p.diagnostic(pos, "error", "empty filename in #include")
		return
	}
	prefix := strings.Repeat(" ", 2*(c.Depth+1)) + strconv.Itoa(line.Tokens[0].Line) + ": "
	path := p.Manager.search(header.Name, header.Quoted)
	if path == "" {
		p.Tree = append(p.Tree, prefix+header.Rendering+" [not found]")
		p.diagnostic(pos, "error", "cannot find include file "+header.Rendering)
		return
	}
	previous := p.Manager.Files[path]
	if previous != nil && previous.Once {
		p.Tree = append(p.Tree, prefix+path+" [skipped: pragma once]")
		previous.Skipped++
		return
	}
	if previous != nil && previous.Guard != "" && p.Macros[previous.Guard] != nil {
		p.Tree = append(p.Tree, prefix+path+" [skipped: guard "+previous.Guard+"]")
		previous.Skipped++
		return
	}
	if c.Depth+1 > 8 {
		p.Tree = append(p.Tree, prefix+path+" [too deep]")
		p.diagnostic(pos, "error", "#include nested too deeply")
		return
	}
	p.Tree = append(p.Tree, prefix+path)
	p.marker(path, 1, 1)
	p.processFile(path, c.Depth+1)
	next := c.position(line.End + 1)
	p.marker(next.File, next.Line, 2)
}
func (p *Preprocessor) lineDirective(c *Inclusion, line LogicalLine, operands []Token) {
	pos := c.position(line.Tokens[0].Line)
	if len(operands) == 0 || !decimalToken(operands[0]) {
		operands = p.Expander.expand(operands, c)
	}
	if len(operands) < 1 || len(operands) > 2 || !decimalToken(operands[0]) || len(operands) == 2 && operands[1].Kind != "string" {
		p.diagnostic(pos, "error", "invalid #line directive")
		return
	}
	number, _ := strconv.ParseInt(operands[0].Spelling, 10, 64)
	if number < 1 || number > 2147483647 {
		p.diagnostic(pos, "error", "line number out of range")
		return
	}
	c.Offset = int(number) - (line.End + 1)
	if len(operands) == 2 {
		name := operands[1].Spelling
		c.DisplayFile = name[1 : len(name)-1]
	}
}
func (p *Preprocessor) macroPragma(pos Position, operands []Token, operation string) {
	if len(operands) != 4 || operands[1].Spelling != "(" || operands[2].Kind != "string" || operands[3].Spelling != ")" {
		p.diagnostic(pos, "error", "invalid #pragma "+operation+" directive")
		return
	}
	quoted := operands[2].Spelling
	name := quoted[1 : len(quoted)-1]
	if operation == "push_macro" {
		p.Saved[name] = append(p.Saved[name], p.Macros[name])
		p.event(pos, "push "+name)
		return
	}
	saved := p.Saved[name]
	if len(saved) == 0 {
		p.diagnostic(pos, "warning", `no matching push_macro for "`+name+`"`)
		return
	}
	m := saved[len(saved)-1]
	p.Saved[name] = saved[:len(saved)-1]
	if m == nil {
		delete(p.Macros, name)
		p.event(pos, "pop "+name+" (undefined)")
	} else {
		p.Macros[name] = m
		p.event(pos, "pop "+name)
	}
}
func (p *Preprocessor) pragma(c *Inclusion, line LogicalLine, operands []Token) {
	pos := c.position(line.Tokens[0].Line)
	name := ""
	if len(operands) > 0 && operands[0].Kind == "identifier" {
		name = operands[0].Spelling
	}
	switch {
	case name == "once":
		if len(operands) > 1 {
			p.diagnostic(pos, "warning", "extra tokens at end of #pragma once directive")
		}
		if c.Depth == 0 {
			p.diagnostic(pos, "warning", "#pragma once in main file")
		}
		c.Source.Once = true
	case len(operands) >= 2 && operands[0].Spelling == "GCC" && operands[1].Spelling == "poison":
		for _, t := range operands[2:] {
			if t.Kind != "identifier" {
				p.diagnostic(pos, "error", "invalid #pragma GCC poison directive")
				return
			}
		}
		for _, t := range operands[2:] {
			if p.Macros[t.Spelling] != nil {
				p.diagnostic(pos, "warning", `poisoning existing macro "`+t.Spelling+`"`)
			}
			p.Poisoned[t.Spelling] = true
		}
	case name == "push_macro" || name == "pop_macro":
		p.macroPragma(pos, operands, name)
	default:
		text := "#pragma"
		if len(operands) > 0 {
			text += " " + render(operands)
		}
		p.outputLine(c, line.Tokens[0].Line, text)
	}
}
func (p *Preprocessor) directive(c *Inclusion, line LogicalLine, name string, operands []Token) {
	if len(line.Tokens) == 1 {
		return
	}
	poisoning := name == "pragma" && len(operands) >= 2 && operands[0].Spelling == "GCC" && operands[1].Spelling == "poison"
	if !poisoning {
		p.poisonCheck(c, operands)
	}
	pos := c.position(line.Tokens[0].Line)
	switch name {
	case "define":
		p.define(operands, pos, c.Depth == 0)
	case "undef":
		p.undefine(operands, pos)
	case "include":
		p.include(c, line, operands)
	case "line":
		p.lineDirective(c, line, operands)
	case "error", "warning":
		text := "#" + name
		if len(operands) > 0 {
			text += " " + render(operands)
		}
		p.diagnostic(pos, name, text)
	case "pragma":
		p.pragma(c, line, operands)
	default:
		p.diagnostic(pos, "error", "invalid preprocessing directive #"+line.Tokens[1].Spelling)
	}
}
func (p *Preprocessor) processFile(path string, depth int) {
	source := p.Manager.load(path)
	source.Entered++
	c := &Inclusion{Source: source, Depth: depth, DisplayFile: path}
	for _, line := range source.Lines {
		tokens := line.Tokens
		isDirective := len(tokens) > 0 && tokens[0].Spelling == "#"
		name := directiveName(tokens)
		operands := []Token{}
		if len(tokens) > 2 {
			operands = tokens[2:]
		}
		if isDirective && wordIn("if ifdef ifndef elif elifdef elifndef else endif", name) {
			p.flush(c)
			p.conditional(c, line, name, operands)
		} else if c.skipping() {
			continue
		} else if isDirective {
			p.flush(c)
			p.directive(c, line, name, operands)
		} else {
			c.Segment = append(c.Segment, tokens...)
		}
	}
	p.flush(c)
	for _, block := range c.Stack {
		p.closeRegion(c, block, source.PhysicalLines)
	}
	for _, block := range c.Stack {
		p.diagnostic(block.Start, "error", "unterminated #"+block.Kind)
	}
}
func sortedKeys[V any](m map[string]V) []string {
	keys := []string{}
	for key := range m {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}
func (p *Preprocessor) includeReport() []string {
	out := append(append([]string{}, p.Tree...), "", "== files ==")
	for _, path := range sortedKeys(p.Manager.Files) {
		f := p.Manager.Files[path]
		guard, once := f.Guard, "no"
		if guard == "" {
			guard = "-"
		}
		if f.Once {
			once = "yes"
		}
		out = append(out, fmt.Sprintf("%s entered=%d skipped=%d lines=%d output_lines=%d skipped_lines=%d guard=%s once=%s", path, f.Entered, f.Skipped, f.PhysicalLines, f.OutputLines, f.SkippedLines, guard, once))
	}
	out = append(out, "")
	current := "main.o:"
	hasPath := false
	for _, path := range p.Manager.Order {
		if len(current)+1+len(path) > 76 && hasPath {
			out = append(out, current+` \`)
			current = " "
			hasPath = false
		}
		current += " " + path
		hasPath = true
	}
	return append(out, current)
}
func (p *Preprocessor) macroReport() []string {
	out := append([]string{"== history =="}, p.History...)
	out = append(out, "", "== table ==")
	references := map[string][]string{}
	for name, m := range p.Macros {
		parameters := map[string]bool{}
		for _, param := range m.Parameters {
			parameters[param] = true
		}
		seen := map[string]bool{}
		for _, t := range m.Replacement {
			if t.Kind == "identifier" && p.Macros[t.Spelling] != nil && !parameters[t.Spelling] {
				seen[t.Spelling] = true
			}
		}
		references[name] = sortedKeys(seen)
	}
	recursive := func(name string) bool {
		pending := append([]string{}, references[name]...)
		seen := map[string]bool{}
		for len(pending) > 0 {
			current := pending[len(pending)-1]
			pending = pending[:len(pending)-1]
			if current == name {
				return true
			}
			if !seen[current] {
				seen[current] = true
				pending = append(pending, references[current]...)
			}
		}
		return false
	}
	objects := 0
	for _, name := range sortedKeys(p.Macros) {
		m := p.Macros[name]
		definition := "#define " + m.signature()
		if len(m.Replacement) > 0 {
			definition += " " + render(m.Replacement)
		}
		recursion := "no"
		if recursive(name) {
			recursion = "yes"
		}
		out = append(out, definition, fmt.Sprintf("  at %s expanded=%d tested=%d recursive=%s", m.Position, m.Expanded, m.Tested, recursion), following("  refs:", references[name]))
		if !m.Function {
			objects++
		}
	}
	undefined := []string{}
	for _, name := range sortedKeys(p.EverDefined) {
		if p.Macros[name] == nil {
			undefined = append(undefined, name)
		}
	}
	out = append(out, "", fmt.Sprintf("macros=%d object_like=%d function_like=%d", len(p.Macros), objects, len(p.Macros)-objects), following("undefined:", undefined), fmt.Sprintf("builtins: __COUNTER__=%d __FILE__=%d __LINE__=%d", p.Expander.BuiltinCounts["__COUNTER__"], p.Expander.BuiltinCounts["__FILE__"], p.Expander.BuiltinCounts["__LINE__"]))
	return out
}
func (p *Preprocessor) conditionalReport() []string {
	out := append([]string{}, p.Conditionals...)
	out = append(out, "", "== skipped regions ==")
	out = append(out, p.Regions...)
	out = append(out, "", fmt.Sprintf("directives=%d taken=%d not_taken=%d skipped=%d not_evaluated=%d endif=%d regions=%d", len(p.Conditionals), p.ConditionCounts["taken"], p.ConditionCounts["not_taken"], p.ConditionCounts["skipped"], p.ConditionCounts["not_evaluated"], p.ConditionCounts["endif"], len(p.Regions)))
	return out
}
func writeLines(name string, lines []string) {
	for i, line := range lines {
		lines[i] = strings.TrimRight(line, " ")
	}
	if err := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		panic(err)
	}
}
func main() {
	p := newPreprocessor()
	p.processDefines()
	p.marker("main.c", 1, 0)
	p.processFile("main.c", 0)
	for _, name := range sortedKeys(p.Macros) {
		p.unusedCheck(p.Macros[name])
	}
	p.Diagnostics = append(p.Diagnostics, fmt.Sprintf("errors=%d warnings=%d", p.DiagnosticCounts["error"], p.DiagnosticCounts["warning"]))
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("preprocessed.txt", p.Output)
	writeLines("includes.txt", p.includeReport())
	writeLines("macros.txt", p.macroReport())
	writeLines("conditionals.txt", p.conditionalReport())
	writeLines("diagnostics.txt", p.Diagnostics)
}
