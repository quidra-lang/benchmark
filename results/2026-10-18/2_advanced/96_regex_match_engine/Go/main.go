package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Node struct {
	Kind, Value, Mode, Name      string
	Char                         byte
	Set                          CharSet
	Negated, Positive            bool
	Number, Column, Lower, Upper int
	Child                        *Node
	Children                     []*Node
}
type PatternError struct {
	Message string
	Column  int
}
type PatternParser struct {
	Text          string
	Index, Groups int
	Names         map[string]int
	References    []*Node
}

func (p *PatternParser) peek(offset int) byte {
	if p.Index+offset >= len(p.Text) {
		return 0
	}
	return p.Text[p.Index+offset]
}
func (p *PatternParser) fail(message string, column int) { panic(PatternError{message, column}) }
func (p *PatternParser) digits() string {
	start := p.Index
	for digit(p.peek(0)) {
		p.Index++
	}
	return p.Text[start:p.Index]
}
func integer(text string) int {
	n, err := strconv.Atoi(text)
	if err != nil {
		panic(err)
	}
	return n
}
func (p *PatternParser) name() string {
	start := p.Index
	if letter(p.peek(0)) || p.peek(0) == '_' {
		p.Index++
		for letter(p.peek(0)) || digit(p.peek(0)) || p.peek(0) == '_' {
			p.Index++
		}
	}
	if start == p.Index || p.peek(0) != '>' {
		p.fail("invalid group name", p.Index+1)
	}
	name := p.Text[start:p.Index]
	p.Index++
	return name
}
func quantifier(c byte) bool { return c != 0 && strings.ContainsRune("*+?{", rune(c)) }
func (p *PatternParser) parse() *Node {
	root := p.alternation()
	if p.Index != len(p.Text) {
		p.fail("unmatched )", p.Index+1)
	}
	for _, ref := range p.References {
		if ref.Name != "" {
			n, ok := p.Names[ref.Name]
			if !ok {
				p.fail("unknown group name", ref.Column)
			}
			ref.Number = n
		} else if ref.Number > p.Groups {
			p.fail("invalid group reference", ref.Column)
		}
	}
	return root
}
func (p *PatternParser) alternation() *Node {
	children := []*Node{p.concatenation()}
	for p.peek(0) == '|' {
		p.Index++
		children = append(children, p.concatenation())
	}
	if len(children) == 1 {
		return children[0]
	}
	return &Node{Kind: "alternation", Children: children}
}
func (p *PatternParser) concatenation() *Node {
	children := []*Node{}
	for p.peek(0) != 0 && p.peek(0) != '|' && p.peek(0) != ')' {
		children = append(children, p.quantified())
	}
	if len(children) == 1 {
		return children[0]
	}
	return &Node{Kind: "concat", Children: children}
}
func (p *PatternParser) quantified() *Node {
	if quantifier(p.peek(0)) {
		p.fail("nothing to repeat", p.Index+1)
	}
	child := p.element()
	if !quantifier(p.peek(0)) {
		return child
	}
	if child.Kind == "assert" || child.Kind == "look" {
		p.fail("nothing to repeat", p.Index+1)
	}
	lower, upper := 0, -1
	switch p.peek(0) {
	case '*':
		p.Index++
	case '+':
		lower = 1
		p.Index++
	case '?':
		upper = 1
		p.Index++
	case '{':
		column := p.Index + 1
		p.Index++
		first := p.digits()
		if first == "" {
			p.fail("invalid quantifier", column)
		}
		lower = integer(first)
		if p.peek(0) == '}' {
			upper = lower
		} else if p.peek(0) == ',' {
			p.Index++
			if p.peek(0) != '}' {
				last := p.digits()
				if last == "" {
					p.fail("invalid quantifier", column)
				}
				upper = integer(last)
			}
		} else {
			p.fail("invalid quantifier", column)
		}
		if p.peek(0) != '}' {
			p.fail("invalid quantifier", column)
		}
		p.Index++
		if lower > 100 || upper > 100 {
			p.fail("quantifier too large", column)
		}
		if upper >= 0 && lower > upper {
			p.fail("quantifier range out of order", column)
		}
	}
	mode := "greedy"
	if p.peek(0) == '?' {
		mode = "lazy"
		p.Index++
	} else if p.peek(0) == '+' {
		mode = "possessive"
		p.Index++
	}
	if quantifier(p.peek(0)) {
		p.fail("nested quantifier", p.Index+1)
	}
	return &Node{Kind: "repeat", Child: child, Lower: lower, Upper: upper, Mode: mode}
}
func (p *PatternParser) element() *Node {
	c := p.peek(0)
	switch c {
	case '(':
		return p.group()
	case '[':
		return p.characterClass()
	case '\\':
		return p.escape()
	case '.':
		p.Index++
		return &Node{Kind: "any"}
	case '^':
		p.Index++
		return &Node{Kind: "assert", Value: "BOL"}
	case '$':
		p.Index++
		return &Node{Kind: "assert", Value: "EOL"}
	}
	p.Index++
	return &Node{Kind: "literal", Char: c}
}
func (p *PatternParser) group() *Node {
	column := p.Index + 1
	p.Index++
	kind := byte('c')
	name := ""
	if p.peek(0) == '?' {
		p.Index++
		kind = p.peek(0)
		if kind != ':' && kind != '=' && kind != '!' && kind != '<' {
			p.fail("invalid group", column)
		}
		p.Index++
		if kind == '<' {
			nameColumn := p.Index + 1
			name = p.name()
			if _, exists := p.Names[name]; exists {
				p.fail("duplicate group name", nameColumn)
			}
		}
	}
	number := 0
	if kind == 'c' || kind == '<' {
		p.Groups++
		number = p.Groups
		if name != "" {
			p.Names[name] = number
		}
	}
	content := p.alternation()
	if p.peek(0) != ')' {
		p.fail("missing )", column)
	}
	p.Index++
	if kind == ':' {
		return content
	}
	if kind == '=' || kind == '!' {
		return &Node{Kind: "look", Positive: kind == '=', Child: content}
	}
	return &Node{Kind: "group", Number: number, Child: content}
}
func (p *PatternParser) classItem() (CharSet, int, bool) {
	c := p.peek(0)
	p.Index++
	if c == '\\' {
		column := p.Index
		c = p.peek(0)
		if c == 0 {
			p.fail("trailing backslash", column)
		}
		p.Index++
		if strings.ContainsRune("dDwWsS", rune(c)) {
			return standard(c), 0, true
		}
		if c == 'n' {
			c = '\n'
		} else if c == 't' {
			c = '\t'
		} else if letter(c) || digit(c) {
			p.fail("invalid escape", column)
		}
	}
	var set CharSet
	set[c] = true
	return set, int(c), false
}
func (p *PatternParser) characterClass() *Node {
	column := p.Index + 1
	p.Index++
	negated := false
	if p.peek(0) == '^' {
		negated = true
		p.Index++
	}
	if p.peek(0) == ']' {
		p.fail("empty class", p.Index+1)
	}
	var set CharSet
	for {
		if p.peek(0) == 0 {
			p.fail("missing ]", column)
		}
		if p.peek(0) == ']' {
			p.Index++
			break
		}
		item, first, isSet := p.classItem()
		if p.peek(0) == '-' && p.peek(1) != 0 && p.peek(1) != ']' {
			dash := p.Index + 1
			p.Index++
			if isSet {
				p.fail("invalid range", dash)
			}
			_, last, lastSet := p.classItem()
			if lastSet || first > last {
				p.fail("invalid range", dash)
			}
			for c := first; c <= last; c++ {
				set[c] = true
			}
		} else {
			for c, present := range item {
				set[c] = set[c] || present
			}
		}
	}
	return &Node{Kind: "class", Set: set, Negated: negated}
}
func (p *PatternParser) escape() *Node {
	column := p.Index + 1
	p.Index++
	c := p.peek(0)
	if c == 0 {
		p.fail("trailing backslash", column)
	}
	p.Index++
	if strings.ContainsRune("dDwWsS", rune(c)) {
		return &Node{Kind: "class", Set: standard(c | 32), Negated: c >= 'A' && c <= 'Z'}
	}
	if c == 'b' || c == 'B' {
		kind := "WORD"
		if c == 'B' {
			kind = "NOTWORD"
		}
		return &Node{Kind: "assert", Value: kind}
	}
	if c == 'n' {
		return &Node{Kind: "literal", Char: '\n'}
	}
	if c == 't' {
		return &Node{Kind: "literal", Char: '\t'}
	}
	ref := &Node{Kind: "backref", Column: column}
	if c >= '1' && c <= '9' {
		ref.Number = integer(string(c) + p.digits())
	} else if c == 'k' {
		if p.peek(0) != '<' {
			p.fail("invalid escape", column)
		}
		p.Index++
		ref.Name = p.name()
	} else {
		if letter(c) || digit(c) {
			p.fail("invalid escape", column)
		}
		return &Node{Kind: "literal", Char: c}
	}
	p.References = append(p.References, ref)
	return ref
}

type Instruction struct {
	Op, Kind     string
	Char         byte
	Set          CharSet
	Negated      bool
	X, Y, Number int
}
type Compiler struct{ Program []Instruction }

func (c *Compiler) emit(ins Instruction) int {
	pc := len(c.Program)
	c.Program = append(c.Program, ins)
	return pc
}
func (c *Compiler) split(pc, continuation, end int, lazy bool) {
	if lazy {
		c.Program[pc].X, c.Program[pc].Y = end, continuation
	} else {
		c.Program[pc].X, c.Program[pc].Y = continuation, end
	}
}
func (c *Compiler) compile(n *Node) {
	switch n.Kind {
	case "literal":
		c.emit(Instruction{Op: "CHAR", Char: n.Char})
	case "any":
		c.emit(Instruction{Op: "ANY"})
	case "class":
		c.emit(Instruction{Op: "CLASS", Set: n.Set, Negated: n.Negated})
	case "assert":
		c.emit(Instruction{Op: "ASSERT", Kind: n.Value})
	case "backref":
		c.emit(Instruction{Op: "BACKREF", Number: n.Number})
	case "group":
		c.emit(Instruction{Op: "SAVE", Number: 2 * n.Number})
		c.compile(n.Child)
		c.emit(Instruction{Op: "SAVE", Number: 2*n.Number + 1})
	case "look":
		kind := "NOT"
		if n.Positive {
			kind = "AHEAD"
		}
		pc := c.emit(Instruction{Op: "LOOK", Kind: kind})
		c.compile(n.Child)
		c.emit(Instruction{Op: "MATCH"})
		c.Program[pc].X = len(c.Program)
	case "concat":
		for _, child := range n.Children {
			c.compile(child)
		}
	case "alternation":
		jumps := []int{}
		for _, child := range n.Children[:len(n.Children)-1] {
			pc := c.emit(Instruction{Op: "SPLIT"})
			c.Program[pc].X = pc + 1
			c.compile(child)
			jump := c.emit(Instruction{Op: "JMP"})
			c.Program[pc].Y = len(c.Program)
			jumps = append(jumps, jump)
		}
		c.compile(n.Children[len(n.Children)-1])
		for _, jump := range jumps {
			c.Program[jump].X = len(c.Program)
		}
	case "repeat":
		if n.Mode == "possessive" {
			pc := c.emit(Instruction{Op: "LOOK", Kind: "ATOMIC"})
			clone := *n
			clone.Mode = "greedy"
			c.compile(&clone)
			c.emit(Instruction{Op: "MATCH"})
			c.Program[pc].X = len(c.Program)
			return
		}
		lazy := n.Mode == "lazy"
		if n.Upper < 0 && n.Lower == 0 {
			pc := c.emit(Instruction{Op: "SPLIT"})
			continuation := len(c.Program)
			c.compile(n.Child)
			c.emit(Instruction{Op: "JMP", X: pc})
			c.split(pc, continuation, len(c.Program), lazy)
			return
		}
		if n.Upper < 0 {
			for i := 0; i < n.Lower-1; i++ {
				c.compile(n.Child)
			}
			first := len(c.Program)
			c.compile(n.Child)
			pc := c.emit(Instruction{Op: "SPLIT"})
			c.split(pc, first, len(c.Program), lazy)
			return
		}
		for i := 0; i < n.Lower; i++ {
			c.compile(n.Child)
		}
		optional := [][2]int{}
		for i := n.Lower; i < n.Upper; i++ {
			pc := c.emit(Instruction{Op: "SPLIT"})
			continuation := len(c.Program)
			c.compile(n.Child)
			optional = append(optional, [2]int{pc, continuation})
		}
		for _, pair := range optional {
			c.split(pair[0], pair[1], len(c.Program), lazy)
		}
	}
}
func lengthRange(n *Node) (int, int) {
	switch n.Kind {
	case "literal", "any", "class":
		return 1, 1
	case "assert", "look":
		return 0, 0
	case "backref":
		return 0, -1
	case "group":
		return lengthRange(n.Child)
	case "repeat":
		a, b := lengthRange(n.Child)
		upper := -1
		if b == 0 {
			upper = 0
		} else if b >= 0 && n.Upper >= 0 {
			upper = b * n.Upper
		}
		return a * n.Lower, upper
	case "concat", "alternation":
		lower, upper := 0, 0
		for i, child := range n.Children {
			a, b := lengthRange(child)
			if n.Kind == "concat" {
				lower += a
				if upper < 0 || b < 0 {
					upper = -1
				} else {
					upper += b
				}
			} else {
				if i == 0 || a < lower {
					lower = a
				}
				if upper < 0 || b < 0 {
					upper = -1
				} else {
					upper = max(upper, b)
				}
			}
		}
		return lower, upper
	}
	panic("unknown node")
}
func firstCharacters(n *Node, flags string) (CharSet, bool) {
	var set CharSet
	switch n.Kind {
	case "literal":
		set[n.Char] = true
		if strings.Contains(flags, "i") && letter(n.Char) {
			set[swapped(n.Char)] = true
		}
		return set, false
	case "any":
		for i := range set {
			set[i] = strings.Contains(flags, "s") || i != 10
		}
		return set, false
	case "class":
		for i := range set {
			set[i] = classMatches(n.Set, n.Negated, byte(i), flags)
		}
		return set, false
	case "assert", "look":
		return set, true
	case "backref":
		for i := range set {
			set[i] = true
		}
		return set, true
	case "group":
		return firstCharacters(n.Child, flags)
	case "repeat":
		if n.Upper == 0 {
			return set, true
		}
		chars, nullable := firstCharacters(n.Child, flags)
		return chars, nullable || n.Lower == 0
	case "concat", "alternation":
		nullable := n.Kind == "concat"
		for _, child := range n.Children {
			chars, empty := firstCharacters(child, flags)
			for i := range set {
				set[i] = set[i] || chars[i]
			}
			if n.Kind == "concat" {
				if !empty {
					return set, false
				}
			} else {
				nullable = nullable || empty
			}
		}
		return set, nullable
	}
	panic("unknown node")
}

type Pattern struct {
	Name, FlagsText, Flags, Text string
	Root                         *Node
	Program                      []Instruction
	Groups                       int
	Names                        map[string]int
	Pike                         bool
	Error                        *PatternError
}

func parsePattern(name, flags, text string) (result *Pattern) {
	result = &Pattern{Name: name, FlagsText: flags, Flags: strings.ReplaceAll(flags, "-", ""), Text: text}
	defer func() {
		if failure := recover(); failure != nil {
			if err, ok := failure.(PatternError); ok {
				result.Error = &err
			} else {
				panic(failure)
			}
		}
	}()
	parser := &PatternParser{Text: text, Names: map[string]int{}}
	result.Root = parser.parse()
	result.Groups = parser.Groups
	result.Names = parser.Names
	compiler := &Compiler{}
	compiler.emit(Instruction{Op: "SAVE", Number: 0})
	compiler.compile(result.Root)
	compiler.emit(Instruction{Op: "SAVE", Number: 1})
	compiler.emit(Instruction{Op: "MATCH"})
	result.Program = compiler.Program
	result.Pike = true
	for _, ins := range result.Program {
		if ins.Op == "BACKREF" || ins.Op == "LOOK" {
			result.Pike = false
		}
	}
	return result
}
func readLines(path string) []string {
	file, err := os.Open(path)
	if err != nil {
		panic(err)
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 4096), 1024*1024)
	out := []string{}
	for scanner.Scan() {
		out = append(out, scanner.Text())
	}
	if err := scanner.Err(); err != nil {
		panic(err)
	}
	return out
}
func decodeQuoted(text string) string {
	out := []byte{}
	for i := 1; i < len(text)-1; i++ {
		c := text[i]
		if c == '\\' {
			i++
			c = text[i]
			if c == 'n' {
				c = '\n'
			} else if c == 't' {
				c = '\t'
			}
		}
		out = append(out, c)
	}
	return string(out)
}

type Command struct {
	Number                                       int
	Line, Kind, Mode, Pattern, Subject, Template string
}

func readCommand(line string, number int) Command {
	c := Command{Number: number, Line: line}
	a := strings.SplitN(line, " ", 5)
	c.Kind = a[0]
	if c.Kind == "REPLACE" {
		c.Mode, c.Pattern, c.Subject, c.Template = a[1], a[2], a[3], decodeQuoted(a[4])
	} else {
		c.Pattern = a[1]
		if c.Kind != "LIST" {
			c.Subject = a[2]
		}
	}
	return c
}

type TemplatePart struct {
	Text  string
	Group int
}

func parseTemplate(text string, pattern *Pattern) ([]TemplatePart, bool) {
	parts := []TemplatePart{}
	for i := 0; i < len(text); {
		if text[i] != '$' {
			parts = append(parts, TemplatePart{Text: text[i : i+1], Group: -1})
			i++
			continue
		}
		i++
		if i == len(text) {
			return nil, false
		}
		if text[i] == '$' {
			parts = append(parts, TemplatePart{Text: "$", Group: -1})
			i++
			continue
		}
		group := -1
		if digit(text[i]) {
			group = int(text[i] - '0')
			i++
		} else if text[i] == '{' {
			end := strings.IndexByte(text[i+1:], '}')
			if end < 0 {
				return nil, false
			}
			end += i + 1
			name := text[i+1 : end]
			numeric := name != ""
			for j := 0; j < len(name); j++ {
				numeric = numeric && digit(name[j])
			}
			if numeric {
				group = integer(name)
			} else if n, ok := pattern.Names[name]; ok {
				group = n
			}
			i = end + 1
		} else {
			return nil, false
		}
		if group < 0 || group > pattern.Groups {
			return nil, false
		}
		parts = append(parts, TemplatePart{Group: group})
	}
	return parts, true
}
func expandTemplate(parts []TemplatePart, c []int, text string) string {
	var out strings.Builder
	for _, part := range parts {
		if part.Group < 0 {
			out.WriteString(part.Text)
		} else {
			a, b := c[2*part.Group], c[2*part.Group+1]
			if a >= 0 && b >= 0 {
				out.WriteString(text[a:b])
			}
		}
	}
	return out.String()
}
func scans(search func(int) []int, text string, single bool, aborted func() bool) [][]int {
	matches := [][]int{}
	for start := 0; start <= len(text); {
		c := search(start)
		if aborted() || c == nil {
			break
		}
		matches = append(matches, c)
		if single {
			break
		}
		start = c[1]
		if c[0] == c[1] {
			start++
		}
	}
	return matches
}
func sameMatches(a, b [][]int) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		for j := range a[i] {
			if a[i][j] != b[i][j] {
				return false
			}
		}
	}
	return true
}

type Step struct {
	Engine string
	Count  int
}
type Evaluation struct {
	Status, Engine, Text string
	Matches              [][]int
	Parts                []TemplatePart
	Steps                []Step
}

func evaluate(c Command, pattern *Pattern, subjects map[string]string) Evaluation {
	out := Evaluation{}
	if pattern.Error != nil {
		out.Status = "invalid pattern"
		return out
	}
	if c.Kind == "LIST" {
		out.Status = "list"
		return out
	}
	if c.Kind == "REPLACE" {
		var valid bool
		out.Parts, valid = parseTemplate(c.Template, pattern)
		if !valid {
			out.Status = "invalid template"
			return out
		}
	}
	out.Text = subjects[c.Subject]
	single := c.Kind == "MATCH" || c.Kind == "SEARCH" || c.Kind == "REPLACE" && c.Mode == "FIRST"
	bt := &BacktrackVM{Program: pattern.Program, Flags: pattern.Flags, Groups: pattern.Groups, Text: out.Text, Full: c.Kind == "MATCH"}
	matches := scans(bt.search, out.Text, single, func() bool { return bt.Aborted })
	out.Steps = append(out.Steps, Step{"backtrack", bt.Steps})
	if pattern.Pike {
		vm := &PikeVM{Program: pattern.Program, Flags: pattern.Flags, Groups: pattern.Groups, Text: out.Text, Full: c.Kind == "MATCH"}
		pike := scans(vm.search, out.Text, single, func() bool { return false })
		out.Steps = append(out.Steps, Step{"pike", vm.Steps})
		if bt.Aborted {
			out.Engine = "pike (backtrack: TOO_MANY_STEPS)"
		} else if !sameMatches(matches, pike) {
			out.Status = "MISMATCH"
			return out
		} else {
			out.Engine = "both"
		}
		out.Matches = pike
	} else {
		if bt.Aborted {
			out.Status = "TOO_MANY_STEPS"
			return out
		}
		out.Engine = "backtrack"
		out.Matches = matches
	}
	out.Status = "ok"
	return out
}
func matchLines(c []int, pattern *Pattern, text string) []string {
	out := []string{fmt.Sprintf("match %d-%d %s", c[0], c[1], quoted(text[c[0]:c[1]]))}
	for k := 1; k <= pattern.Groups; k++ {
		a, b := c[2*k], c[2*k+1]
		if a < 0 || b < 0 {
			out = append(out, fmt.Sprintf("group %d -", k))
		} else {
			out = append(out, fmt.Sprintf("group %d %d-%d %s", k, a, b, quoted(text[a:b])))
		}
	}
	return out
}
func renderResult(c Command, pattern *Pattern, e Evaluation) []string {
	out := []string{fmt.Sprintf("#%d %s", c.Number, c.Line)}
	if e.Status == "list" {
		return append(out, fmt.Sprintf("instructions %d", len(pattern.Program)))
	}
	if e.Status != "ok" {
		return append(out, e.Status)
	}
	out = append(out, "engine "+e.Engine)
	switch c.Kind {
	case "MATCH", "SEARCH":
		if len(e.Matches) == 0 {
			out = append(out, "no match")
		} else {
			out = append(out, matchLines(e.Matches[0], pattern, e.Text)...)
		}
	case "FINDALL":
		out = append(out, fmt.Sprintf("matches %d", len(e.Matches)))
		for _, m := range e.Matches {
			out = append(out, matchLines(m, pattern, e.Text)...)
		}
	case "REPLACE":
		var value strings.Builder
		previous := 0
		for _, m := range e.Matches {
			value.WriteString(e.Text[previous:m[0]])
			value.WriteString(expandTemplate(e.Parts, m, e.Text))
			previous = m[1]
		}
		value.WriteString(e.Text[previous:])
		out = append(out, fmt.Sprintf("replacements %d", len(e.Matches)), "result "+quoted(value.String()))
	case "SPLIT":
		pieces := []string{}
		previous := 0
		for _, m := range e.Matches {
			pieces = append(pieces, e.Text[previous:m[0]])
			previous = m[1]
		}
		pieces = append(pieces, e.Text[previous:])
		out = append(out, fmt.Sprintf("pieces %d", len(pieces)), "piece "+quoted(pieces[0]))
		for i, m := range e.Matches {
			for k := 1; k <= pattern.Groups; k++ {
				a, b := m[2*k], m[2*k+1]
				value := "-"
				if a >= 0 && b >= 0 {
					value = quoted(e.Text[a:b])
				}
				out = append(out, fmt.Sprintf("group %d %s", k, value))
			}
			out = append(out, "piece "+quoted(pieces[i+1]))
		}
	}
	return out
}
func programListing(p *Pattern) []string {
	lower, upper := lengthRange(p.Root)
	maximum := "inf"
	if upper >= 0 {
		maximum = strconv.Itoa(upper)
	}
	first, _ := firstCharacters(p.Root, p.Flags)
	hasFirst := false
	for _, v := range first {
		hasFirst = hasFirst || v
	}
	firstText := "-"
	if hasFirst {
		firstText = setNotation(first, false)
	}
	nameParts := []string{}
	for k := 1; k <= p.Groups; k++ {
		for name, n := range p.Names {
			if n == k {
				nameParts = append(nameParts, fmt.Sprintf("%s:%d", name, n))
			}
		}
	}
	nameText := "-"
	if len(nameParts) > 0 {
		nameText = strings.Join(nameParts, ",")
	}
	pike := "no"
	if p.Pike {
		pike = "yes"
	}
	out := []string{"=== " + p.Name, fmt.Sprintf("flags=%s groups=%d names=%s length=%d..%s first=%s pike=%s size=%d", p.FlagsText, p.Groups, nameText, lower, maximum, firstText, pike, len(p.Program))}
	for pc, ins := range p.Program {
		out = append(out, fmt.Sprintf("%d %s", pc, instructionNotation(ins)))
	}
	return out
}
func save(name string, lines []string) {
	value := ""
	if len(lines) > 0 {
		value = strings.Join(lines, "\n") + "\n"
	}
	if err := os.WriteFile("output/"+name, []byte(value), 0644); err != nil {
		panic(err)
	}
}
func main() {
	patterns := map[string]*Pattern{}
	ordered := []*Pattern{}
	for _, line := range readLines("input/patterns.txt") {
		a := strings.SplitN(line, " ", 3)
		p := parsePattern(a[0], a[1], a[2])
		patterns[p.Name] = p
		ordered = append(ordered, p)
	}
	subjects := map[string]string{}
	for _, line := range readLines("input/subjects.txt") {
		a := strings.SplitN(line, " ", 2)
		subjects[a[0]] = decodeQuoted(a[1])
	}
	results, programs := []string{}, []string{}
	steps := []string{"command,engine,steps"}
	for i, line := range readLines("input/commands.txt") {
		c := readCommand(line, i+1)
		p := patterns[c.Pattern]
		e := evaluate(c, p, subjects)
		results = append(results, renderResult(c, p, e)...)
		if c.Kind == "LIST" && p.Error == nil {
			programs = append(programs, programListing(p)...)
		}
		for _, s := range e.Steps {
			steps = append(steps, fmt.Sprintf("%d,%s,%d", c.Number, s.Engine, s.Count))
		}
	}
	errors := []string{}
	for _, p := range ordered {
		if p.Error != nil {
			errors = append(errors, fmt.Sprintf("%s: %s at column %d", p.Name, p.Error.Message, p.Error.Column), "  "+p.Text, "  "+strings.Repeat(" ", p.Error.Column-1)+"^")
		}
	}
	if len(errors) == 0 {
		errors = append(errors, "no errors")
	}
	if len(programs) == 0 {
		programs = append(programs, "no programs")
	}
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	save("results.txt", results)
	save("programs.txt", programs)
	save("steps.csv", steps)
	save("errors.txt", errors)
}
