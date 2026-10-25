package main

import (
	"bufio"
	"cmp"
	"errors"
	"fmt"
	"maps"
	"os"
	"slices"
	"strconv"
	"strings"
)

type atom struct {
	character byte
	matched   bool
}

type replacement struct {
	atoms []atom
}

func (r *replacement) text() string {
	var result strings.Builder
	for _, a := range r.atoms {
		result.WriteByte(a.character)
	}
	return result.String()
}

func delimited(s string, position int, delimiter byte) (*replacement, int, error) {
	value := &replacement{}
	for position < len(s) {
		character := s[position]
		position++
		if character == delimiter {
			return value, position, nil
		}
		escaped := character == '\\'
		if escaped {
			if position == len(s) {
				return nil, position, errors.New("missing delimiter")
			}
			character = s[position]
			position++
		}
		value.atoms = append(value.atoms, atom{character, character == '&' && !escaped})
	}
	return nil, position, errors.New("missing delimiter")
}

type token struct {
	kind   byte
	number int
	name   byte
	search string
}

func digit(c byte) bool { return c >= '0' && c <= '9' }
func lower(c byte) bool { return c >= 'a' && c <= 'z' }
func upper(c byte) bool { return c >= 'A' && c <= 'Z' }
func contains(set string, c byte) bool { return strings.IndexByte(set, c) >= 0 }

func digits(s string) bool {
	if s == "" {
		return false
	}
	for i := range len(s) {
		if !digit(s[i]) {
			return false
		}
	}
	return true
}

func number(s string, position *int) int {
	value := 0
	for *position < len(s) && digit(s[*position]) {
		value = value*10 + int(s[*position]-'0')
		*position += 1
	}
	return value
}

func lexAddresses(s string) ([]token, int, error) {
	var tokens []token
	position := 0
	for position < len(s) {
		c := s[position]
		value := token{}
		switch {
		case digit(c):
			value.kind, value.number = 'N', number(s, &position)
		case c == '+' || c == '-':
			position++
			value.kind, value.number = 'O', 1
			if position < len(s) && digit(s[position]) {
				value.number = number(s, &position)
			}
			if c == '-' {
				value.number = -value.number
			}
		case contains(".$,;%", c):
			value.kind = c
			position++
		case c == '\'':
			value.kind = c
			position++
			if position < len(s) {
				value.name = s[position]
				position++
			}
		case c == '/' || c == '?':
			text, end, err := delimited(s, position+1, c)
			if err != nil {
				return nil, 0, err
			}
			position = end
			value.kind, value.search = c, text.text()
		default:
			return tokens, position, nil
		}
		tokens = append(tokens, value)
	}
	return tokens, position, nil
}

func withText(line string) bool {
	_, end, err := lexAddresses(line)
	if err != nil {
		return false
	}
	part := line[end:]
	if part == "a" || part == "i" || part == "c" {
		return true
	}
	if len(part) >= 2 && contains("gv", part[0]) && !contains(" \\", part[1]) {
		_, end, err := delimited(part, 2, part[1])
		if err == nil {
			rest := part[end:]
			return rest == "a" || rest == "i" || rest == "c"
		}
	}
	return false
}

func validAddress(tokens []token) bool {
	for i, t := range tokens {
		if t.kind != 'O' && (i != 0 || !contains("N.$'/?", t.kind)) {
			return false
		}
	}
	return true
}

type addresses struct {
	count       int
	left, right []token
	semicolon   bool
}

func parseAddresses(tokens []token) (addresses, error) {
	value := addresses{}
	if len(tokens) == 0 {
		return value, nil
	}
	if len(tokens) == 1 && tokens[0].kind == '%' {
		return addresses{count: 2, left: []token{{kind: 'N', number: 1}}, right: []token{{kind: '$'}}}, nil
	}
	separator := -1
	for i, t := range tokens {
		if contains(",;", t.kind) {
			if separator >= 0 {
				return value, errors.New("bad address")
			}
			separator = i
		}
	}
	if separator < 0 {
		value.count, value.left = 1, tokens
	} else {
		value.count, value.left, value.right = 2, tokens[:separator], tokens[separator+1:]
		value.semicolon = tokens[separator].kind == ';'
	}
	if !validAddress(value.left) || !validAddress(value.right) {
		return value, errors.New("bad address")
	}
	return value, nil
}

type kind int

const (
	cmdEmpty kind = iota
	cmdAppend
	cmdInsert
	cmdChange
	cmdPrint
	cmdNumber
	cmdList
	cmdEquals
	cmdCount
	cmdYank
	cmdMarks
	cmdHistory
	cmdFiles
	cmdDelete
	cmdPut
	cmdJoin
	cmdJoinSpace
	cmdPage
	cmdIndent
	cmdUnindent
	cmdUndo
	cmdRedo
	cmdCase
	cmdRead
	cmdWrite
	cmdWriteAppend
	cmdEdit
	cmdWritePrint
	cmdMark
	cmdMove
	cmdCopy
	cmdSubstitute
	cmdGlobal
	cmdInverse
	cmdSort
)

type sortOptions struct {
	reverse, unique, insensitive, numeric bool
}

type command struct {
	kind        kind
	number      int
	suffix      byte
	option      byte
	name        string
	search      string
	destination []token
	replacement *replacement
	all         bool
	sort        sortOptions
	sub         *command
}

func printSuffix(s string) (byte, error) {
	if s == "" {
		return 0, nil
	}
	if len(s) != 1 || !contains("pnl", s[0]) {
		return 0, errors.New("invalid suffix")
	}
	return s[0], nil
}

func positive(s string) (int, error) {
	if s == "" {
		return 0, nil
	}
	if !digits(s) {
		return 0, errors.New("invalid suffix")
	}
	value, _ := strconv.Atoi(s)
	if value == 0 {
		return 0, errors.New("invalid suffix")
	}
	return value, nil
}

func filename(s string) (string, error) {
	if len(s) < 2 || len(s) > 9 || s[0] != ' ' {
		return "", errors.New("invalid file name")
	}
	for i := 1; i < len(s); i++ {
		if !lower(s[i]) && !digit(s[i]) {
			return "", errors.New("invalid file name")
		}
	}
	return s[1:], nil
}

func sortForm(s string) bool { return s == "sort" || strings.HasPrefix(s, "sort ") }

func parseCommand(part string) (command, error) {
	c := command{}
	if sortForm(part) {
		c.kind = cmdSort
		if part == "sort " {
			return c, errors.New("invalid suffix")
		}
		if len(part) > 4 {
			for _, option := range part[5:] {
				var flag *bool
				switch option {
				case 'r':
					flag = &c.sort.reverse
				case 'u':
					flag = &c.sort.unique
				case 'i':
					flag = &c.sort.insensitive
				case 'n':
					flag = &c.sort.numeric
				default:
					return c, errors.New("invalid suffix")
				}
				if *flag {
					return c, errors.New("invalid suffix")
				}
				*flag = true
			}
		}
		if c.sort.insensitive && c.sort.numeric {
			return c, errors.New("invalid suffix")
		}
		return c, nil
	}
	if part == "" {
		return c, nil
	}
	first, arg := part[0], part[1:]
	simple := "aicpnl=#yKhf"
	kinds := [...]kind{cmdAppend, cmdInsert, cmdChange, cmdPrint, cmdNumber, cmdList,
		cmdEquals, cmdCount, cmdYank, cmdMarks, cmdHistory, cmdFiles}
	if index := strings.IndexByte(simple, first); index >= 0 {
		c.kind = kinds[index]
		if arg != "" {
			return c, errors.New("invalid suffix")
		}
		return c, nil
	}
	var err error
	switch first {
	case 'd', 'x', 'j', 'J':
		c.kind = map[byte]kind{'d': cmdDelete, 'x': cmdPut, 'j': cmdJoin, 'J': cmdJoinSpace}[first]
		c.suffix, err = printSuffix(arg)
	case 'z', '>', '<', 'u':
		c.kind = map[byte]kind{'z': cmdPage, '>': cmdIndent, '<': cmdUnindent, 'u': cmdUndo}[first]
		c.number, err = positive(arg)
	case '~':
		c.kind = cmdCase
		if arg != "" {
			if len(arg) != 1 || !contains("ul", arg[0]) {
				return c, errors.New("invalid suffix")
			}
			c.option = arg[0]
		}
	case 'r':
		if arg == "" || digits(arg) {
			c.kind, c.number = cmdRedo, 0
			c.number, err = positive(arg)
		} else {
			c.kind = cmdRead
			c.name, err = filename(arg)
		}
	case 'w', 'W', 'e':
		if first == 'w' && arg == "" {
			c.kind = cmdWritePrint
		} else {
			c.kind = map[byte]kind{'w': cmdWrite, 'W': cmdWriteAppend, 'e': cmdEdit}[first]
			c.name, err = filename(arg)
		}
	case 'k':
		c.kind = cmdMark
		if len(arg) != 1 || !lower(arg[0]) {
			return c, errors.New("invalid mark")
		}
		c.option = arg[0]
	case 'm', 't':
		c.kind = cmdMove
		if first == 't' {
			c.kind = cmdCopy
		}
		var end int
		c.destination, end, err = lexAddresses(arg)
		if err != nil {
			return c, err
		}
		if len(c.destination) == 0 || !validAddress(c.destination) {
			return c, errors.New("invalid destination")
		}
		c.suffix, err = printSuffix(arg[end:])
	case 's':
		c.kind, c.number = cmdSubstitute, 1
		repeated := true
		for i := range len(arg) {
			if !contains("gpnl", arg[i]) && !digit(arg[i]) {
				repeated = false
			}
		}
		position := 0
		if !repeated {
			delimiter := arg[0]
			if contains(" \\", delimiter) {
				return c, errors.New("missing delimiter")
			}
			search, start, err := delimited(arg, 1, delimiter)
			if err != nil {
				return c, err
			}
			value, end, err := delimited(arg, start, delimiter)
			if err != nil {
				return c, err
			}
			c.search = search.text()
			if arg[start:end-1] != "%" {
				c.replacement = value
			}
			position = end
		}
		counted := false
		for position < len(arg) {
			flag := arg[position]
			position++
			switch {
			case flag == 'g':
				if c.all {
					return c, errors.New("invalid suffix")
				}
				c.all = true
			case contains("pnl", flag):
				if c.suffix != 0 {
					return c, errors.New("invalid suffix")
				}
				c.suffix = flag
			case digit(flag):
				if counted {
					return c, errors.New("invalid suffix")
				}
				counted = true
				position--
				c.number = number(arg, &position)
				if c.number == 0 {
					return c, errors.New("invalid suffix")
				}
			default:
				return c, errors.New("invalid suffix")
			}
		}
	case 'g', 'v':
		c.kind = cmdGlobal
		if first == 'v' {
			c.kind = cmdInverse
		}
		if arg == "" || contains(" \\", arg[0]) {
			return c, errors.New("missing delimiter")
		}
		search, end, err := delimited(arg, 1, arg[0])
		if err != nil {
			return c, err
		}
		c.search = search.text()
		body := arg[end:]
		if body == "" {
			body = "p"
		}
		if !contains("pnldmtjJs><~aicx", body[0]) || sortForm(body) {
			return c, errors.New("invalid global command")
		}
		sub, err := parseCommand(body)
		if err != nil {
			return c, err
		}
		c.sub = &sub
	default:
		return c, errors.New("unknown command")
	}
	return c, err
}

func (c command) addressKind() int {
	switch c.kind {
	case cmdUndo, cmdRedo, cmdHistory, cmdMarks, cmdFiles, cmdEdit:
		return 0
	case cmdAppend, cmdInsert, cmdPut, cmdEquals, cmdRead, cmdMark, cmdPage:
		return 1
	default:
		return 2
	}
}

func (c command) modifying() bool {
	switch c.kind {
	case cmdAppend, cmdInsert, cmdChange, cmdDelete, cmdPut, cmdJoin, cmdJoinSpace,
		cmdMove, cmdCopy, cmdSubstitute, cmdIndent, cmdUnindent, cmdCase, cmdSort, cmdRead, cmdEdit:
		return true
	case cmdGlobal, cmdInverse:
		return c.sub.modifying()
	default:
		return false
	}
}

type line struct {
	id   uint64
	text string
}

type snapshot struct {
	buffer  []line
	current int
}

type record struct {
	command string
	state   snapshot
}

type editor struct {
	buffer           []line
	current, display int
	marks            [26]uint64
	cut              []string
	pattern          string
	hasPattern       bool
	replacement      *replacement
	undo, redo       []*record
	files            map[string][]string
	nextID           uint64
}

func newEditor() editor {
	return editor{display: 5, files: make(map[string][]string), nextID: 1}
}

func (e *editor) clone() editor {
	copy := *e
	copy.buffer = slices.Clone(e.buffer)
	copy.undo = slices.Clone(e.undo)
	copy.redo = slices.Clone(e.redo)
	copy.files = maps.Clone(e.files)
	return copy
}

func (e *editor) snapshot() snapshot { return snapshot{e.buffer, e.current} }

func (e *editor) locate(id uint64) int {
	for i, line := range e.buffer {
		if line.id == id {
			return i + 1
		}
	}
	return 0
}

func (e *editor) resolvePattern(search string) (string, error) {
	if search != "" {
		e.pattern, e.hasPattern = search, true
	}
	if !e.hasPattern {
		return "", errors.New("no previous pattern")
	}
	return e.pattern, nil
}

func (e *editor) address(tokens []token) (int, error) {
	value := e.current
	for _, t := range tokens {
		switch t.kind {
		case 'O':
			value += t.number
		case 'N':
			value = t.number
		case '.':
			value = e.current
		case '$':
			value = len(e.buffer)
		case '\'':
			if !lower(t.name) {
				return 0, errors.New("invalid mark")
			}
			value = e.locate(e.marks[t.name-'a'])
			if value == 0 {
				return 0, errors.New("mark not set")
			}
		case '/', '?':
			pattern, err := e.resolvePattern(t.search)
			if err != nil {
				return 0, err
			}
			size, start := len(e.buffer), e.current
			if t.kind == '?' && start == 0 {
				start = size + 1
			}
			value = 0
			for step := 1; step <= size; step++ {
				index := (start + step - 1) % size
				if t.kind == '?' {
					index = (start - step - 1 + size) % size
				}
				if strings.Contains(e.buffer[index].text, pattern) {
					value = index + 1
					break
				}
			}
			if value == 0 {
				return 0, errors.New("no match")
			}
		}
	}
	return value, nil
}

type lineRange struct {
	first, last int
}

func (e *editor) evaluate(a addresses) (lineRange, error) {
	values := lineRange{}
	if a.count == 0 {
		return values, nil
	}
	var err error
	if len(a.left) != 0 {
		values.first, err = e.address(a.left)
		if err != nil {
			return values, err
		}
	} else if a.semicolon {
		values.first = e.current
	} else {
		values.first = 1
	}
	if a.count == 2 {
		if a.semicolon {
			if values.first < 0 || values.first > len(e.buffer) {
				return values, errors.New("address out of range")
			}
			e.current = values.first
		}
		values.last = len(e.buffer)
		if len(a.right) != 0 {
			values.last, err = e.address(a.right)
		}
	}
	return values, err
}

func (e *editor) checkedRange(c command, count int, values lineRange) (lineRange, error) {
	size := len(e.buffer)
	switch c.addressKind() {
	case 0:
		return lineRange{}, nil
	case 1:
		a := values.first
		if count == 0 {
			switch c.kind {
			case cmdEquals, cmdRead:
				a = size
			case cmdPage:
				a = e.current + 1
			default:
				a = e.current
			}
		}
		minimum := 0
		if c.kind == cmdMark || c.kind == cmdPage {
			minimum = 1
		}
		if a < minimum || a > size {
			return values, errors.New("address out of range")
		}
		return lineRange{a, a}, nil
	}
	if count == 0 {
		switch c.kind {
		case cmdWrite, cmdWriteAppend, cmdWritePrint, cmdCount:
			return lineRange{1, size}, nil
		case cmdGlobal, cmdInverse, cmdSort:
			values = lineRange{1, size}
		case cmdJoin, cmdJoinSpace:
			values = lineRange{e.current, e.current + 1}
		default:
			values = lineRange{e.current, e.current}
		}
	} else if count == 1 {
		values.last = values.first
	}
	if values.first < 1 || values.first > size || values.last < 1 || values.last > size {
		return values, errors.New("address out of range")
	}
	if values.first > values.last || values.first == values.last && (c.kind == cmdJoin || c.kind == cmdJoinSpace) {
		return values, errors.New("invalid range")
	}
	return values, nil
}

func (e *editor) printLine(number int, form byte, output *strings.Builder) {
	text := e.buffer[number-1].text
	switch form {
	case 'n':
		fmt.Fprintf(output, "%3d %s\n", number, text)
	case 'l':
		remaining := strings.ReplaceAll(text, "\\", "\\\\") + "$"
		for len(remaining) > 40 {
			fmt.Fprintf(output, "%s\\\n", remaining[:39])
			remaining = remaining[39:]
		}
		fmt.Fprintln(output, remaining)
	default:
		fmt.Fprintln(output, text)
	}
}

func (e *editor) contents(r lineRange) []string {
	text := make([]string, 0, r.last-r.first+1)
	for _, line := range e.buffer[r.first-1:r.last] {
		text = append(text, line.text)
	}
	return text
}

func (e *editor) insert(after int, text []string) {
	lines := make([]line, len(text))
	for i, value := range text {
		lines[i] = line{e.nextID, value}
		e.nextID++
	}
	e.buffer = slices.Insert(e.buffer, after, lines...)
}

func (e *editor) substitute(c command, r lineRange, output *strings.Builder, inGlobal bool) (bool, error) {
	pattern, err := e.resolvePattern(c.search)
	if err != nil {
		return false, err
	}
	replacement := c.replacement
	if replacement == nil {
		replacement = e.replacement
	}
	if replacement == nil {
		return false, errors.New("no previous substitution")
	}
	e.replacement = replacement
	var expanded strings.Builder
	for _, atom := range replacement.atoms {
		if atom.matched {
			expanded.WriteString(pattern)
		} else {
			expanded.WriteByte(atom.character)
		}
	}
	last := 0
	for i := r.first; i <= r.last; i++ {
		old := e.buffer[i-1].text
		var result strings.Builder
		position, occurrence := 0, 0
		changed := false
		for {
			offset := strings.Index(old[position:], pattern)
			if offset < 0 {
				break
			}
			start := position + offset
			result.WriteString(old[position:start])
			occurrence++
			if occurrence == c.number || c.all && occurrence > c.number {
				result.WriteString(expanded.String())
				changed = true
			} else {
				result.WriteString(pattern)
			}
			position = start + len(pattern)
		}
		result.WriteString(old[position:])
		if changed {
			value := result.String()
			if len(value) > 80 {
				return false, errors.New("line too long")
			}
			if value == "" || strings.HasSuffix(value, " ") {
				return false, errors.New("bad line")
			}
			e.buffer[i-1].text = value
			last = i
		}
	}
	if last == 0 && !inGlobal {
		return false, errors.New("no match")
	}
	if last != 0 {
		e.current = last
		if c.suffix != 0 {
			e.printLine(last, c.suffix, output)
		}
	}
	return last != 0, nil
}

func leadingInteger(text string) int64 {
	negative := strings.HasPrefix(text, "-")
	if negative {
		text = text[1:]
	}
	var value int64
	for i := 0; i < len(text) && digit(text[i]); i++ {
		value = value*10 + int64(text[i]-'0')
	}
	if negative {
		return -value
	}
	return value
}

func compareLines(a, b line, options sortOptions) int {
	if options.numeric {
		return cmp.Compare(leadingInteger(a.text), leadingInteger(b.text))
	}
	left, right := a.text, b.text
	if options.insensitive {
		left, right = strings.ToLower(left), strings.ToLower(right)
	}
	return strings.Compare(left, right)
}

func (e *editor) sortLines(r lineRange, options sortOptions) {
	lines := slices.Clone(e.buffer[r.first-1:r.last])
	slices.SortStableFunc(lines, func(a, b line) int {
		order := compareLines(a, b, options)
		if options.reverse {
			return -order
		}
		return order
	})
	if options.unique {
		lines = slices.CompactFunc(lines, func(a, b line) bool { return compareLines(a, b, options) == 0 })
	}
	e.current = r.first + len(lines) - 1
	e.buffer = slices.Replace(e.buffer, r.first-1, r.last, lines...)
}

func fileBytes(lines []string) int {
	bytes := 0
	for _, line := range lines {
		bytes += len(line) + 1
	}
	return bytes
}

func (e *editor) fileCommand(c command, r lineRange, output *strings.Builder) error {
	file, exists := e.files[c.name]
	if c.kind == cmdWrite || c.kind == cmdWriteAppend {
		var saved []string
		if c.kind == cmdWriteAppend {
			saved = slices.Clone(file)
		}
		file = append(saved, e.contents(r)...)
		e.files[c.name] = file
	} else {
		if !exists {
			return errors.New("no such file")
		}
		after := r.first
		if c.kind == cmdEdit {
			e.buffer = nil
			after = 0
		}
		e.insert(after, file)
		e.current = after + len(file)
	}
	fmt.Fprintf(output, "file %s lines=%d bytes=%d\n", c.name, len(file), fileBytes(file))
	return nil
}

func (e *editor) transferHistory(redo bool, count int) error {
	from, to := &e.undo, &e.redo
	if redo {
		from, to = to, from
	}
	if len(*from) < count {
		if redo {
			return errors.New("nothing to redo")
		}
		return errors.New("nothing to undo")
	}
	for range count {
		last := (*from)[len(*from)-1]
		*from = (*from)[:len(*from)-1]
		*to = append(*to, &record{last.command, e.snapshot()})
		e.buffer, e.current = last.state.buffer, last.state.current
	}
	return nil
}

func (e *editor) execute(c command, r lineRange, text []string, output *strings.Builder, inGlobal bool) (bool, error) {
	a, b := r.first, r.last
	switch c.kind {
	case cmdEmpty:
		e.printLine(b, 'p', output)
		e.current = b
	case cmdPrint, cmdNumber, cmdList:
		form := map[kind]byte{cmdPrint: 'p', cmdNumber: 'n', cmdList: 'l'}[c.kind]
		for i := a; i <= b; i++ {
			e.printLine(i, form, output)
		}
		e.current = b
	case cmdPage:
		if c.number != 0 {
			e.display = c.number
		}
		last := min(a+e.display-1, len(e.buffer))
		for i := a; i <= last; i++ {
			e.printLine(i, 'p', output)
		}
		e.current = last
	case cmdEquals:
		fmt.Fprintln(output, a)
	case cmdCount, cmdWritePrint:
		words, chars := 0, 0
		for i := a; i <= b; i++ {
			text := e.buffer[i-1].text
			chars += len(text)
			for j := range len(text) {
				if text[j] != ' ' && (j == 0 || text[j-1] == ' ') {
					words++
				}
			}
			if c.kind == cmdWritePrint {
				e.printLine(i, 'p', output)
			}
		}
		count := b - a + 1
		if c.kind == cmdCount {
			fmt.Fprintf(output, "count lines=%d words=%d chars=%d\n", count, words, chars)
		} else {
			fmt.Fprintf(output, "lines=%d bytes=%d\n", count, chars+count)
		}
	case cmdAppend, cmdInsert:
		after := a
		if c.kind == cmdInsert {
			after = max(a, 1) - 1
		}
		e.insert(after, text)
		e.current = after + len(text)
	case cmdChange, cmdDelete:
		e.cut = e.contents(r)
		e.buffer = slices.Delete(e.buffer, a-1, b)
		if c.kind == cmdChange {
			e.insert(a-1, text)
		}
		e.current = min(a, len(e.buffer))
		if c.kind == cmdChange && len(text) != 0 {
			e.current = a + len(text) - 1
		}
	case cmdYank:
		e.cut = e.contents(r)
	case cmdPut:
		if len(e.cut) == 0 {
			return false, errors.New("nothing to put")
		}
		e.insert(a, e.cut)
		e.current = a + len(e.cut)
	case cmdMove, cmdCopy:
		destination, err := e.address(c.destination)
		if err != nil {
			return false, err
		}
		if destination < 0 || destination > len(e.buffer) {
			return false, errors.New("address out of range")
		}
		if c.kind == cmdMove && a <= destination && destination < b {
			return false, errors.New("invalid destination")
		}
		moved := slices.Clone(e.buffer[a-1:b])
		if c.kind == cmdMove {
			e.buffer = slices.Delete(e.buffer, a-1, b)
			if destination >= b {
				destination -= len(moved)
			}
		} else {
			for i := range moved {
				moved[i].id = e.nextID
				e.nextID++
			}
		}
		e.buffer = slices.Insert(e.buffer, destination, moved...)
		e.current = destination + len(moved)
	case cmdJoin, cmdJoinSpace:
		var joined strings.Builder
		for i := a; i <= b; i++ {
			part := e.buffer[i-1].text
			if c.kind == cmdJoinSpace && i > a {
				joined.WriteByte(' ')
				part = strings.TrimLeft(part, " ")
			}
			joined.WriteString(part)
		}
		if joined.Len() > 80 {
			return false, errors.New("line too long")
		}
		e.buffer[a-1].text = joined.String()
		e.buffer = slices.Delete(e.buffer, a, b)
		e.current = a
	case cmdIndent, cmdUnindent, cmdCase:
		width := c.number
		if width == 0 {
			width = 4
		}
		for i := a; i <= b; i++ {
			old := e.buffer[i-1].text
			switch c.kind {
			case cmdIndent:
				if len(old)+width > 80 {
					return false, errors.New("line too long")
				}
				e.buffer[i-1].text = strings.Repeat(" ", width) + old
			case cmdUnindent:
				removed := 0
				for removed < width && removed < len(old) && old[removed] == ' ' {
					removed++
				}
				e.buffer[i-1].text = old[removed:]
			case cmdCase:
				converted := []byte(old)
				for j, character := range converted {
					if lower(character) && c.option != 'l' {
						converted[j] = character - 'a' + 'A'
					} else if upper(character) && c.option != 'u' {
						converted[j] = character - 'A' + 'a'
					}
				}
				e.buffer[i-1].text = string(converted)
			}
		}
		e.current = b
	case cmdSort:
		e.sortLines(r, c.sort)
	case cmdSubstitute:
		return e.substitute(c, r, output, inGlobal)
	case cmdMark:
		e.marks[c.option-'a'] = e.buffer[a-1].id
	case cmdMarks:
		output.WriteString("marks")
		any := false
		for name, id := range e.marks {
			if position := e.locate(id); position != 0 {
				fmt.Fprintf(output, " %c=%d", 'a'+name, position)
				any = true
			}
		}
		if !any {
			output.WriteString(" none")
		}
		output.WriteByte('\n')
	case cmdUndo, cmdRedo:
		count := c.number
		if count == 0 {
			count = 1
		}
		if err := e.transferHistory(c.kind == cmdRedo, count); err != nil {
			return false, err
		}
	case cmdHistory:
		fmt.Fprintf(output, "history undo=%d redo=%d\n", len(e.undo), len(e.redo))
		for side, records := range [][]*record{e.undo, e.redo} {
			name := "undo"
			if side == 1 {
				name = "redo"
			}
			for i := len(records) - 1; i >= 0; i-- {
				fmt.Fprintf(output, "%s %d: %s\n", name, len(records)-i, records[i].command)
			}
		}
	case cmdRead, cmdWrite, cmdWriteAppend, cmdEdit:
		if err := e.fileCommand(c, r, output); err != nil {
			return false, err
		}
	case cmdFiles:
		output.WriteString("files")
		for _, name := range slices.Sorted(maps.Keys(e.files)) {
			fmt.Fprintf(output, " %s=%d", name, len(e.files[name]))
		}
		if len(e.files) == 0 {
			output.WriteString(" none")
		}
		output.WriteByte('\n')
	case cmdGlobal, cmdInverse:
		pattern, err := e.resolvePattern(c.search)
		if err != nil {
			return false, err
		}
		var selected []uint64
		for _, line := range e.buffer[a-1:b] {
			if strings.Contains(line.text, pattern) == (c.kind == cmdGlobal) {
				selected = append(selected, line.id)
			}
		}
		if len(selected) == 0 {
			return false, errors.New("no match")
		}
		substituted := false
		for _, id := range selected {
			if position := e.locate(id); position != 0 {
				e.current = position
				r, err := e.checkedRange(*c.sub, 0, lineRange{})
				if err != nil {
					return false, err
				}
				changed, err := e.execute(*c.sub, r, text, output, true)
				if err != nil {
					return false, err
				}
				substituted = substituted || changed
			}
		}
		if c.sub.kind == cmdSubstitute && !substituted {
			return false, errors.New("no match")
		}
	}
	if c.suffix != 0 && e.current >= 1 {
		e.printLine(e.current, c.suffix, output)
	}
	return false, nil
}

func (e *editor) apply(line string, text []string) (string, error) {
	tokens, end, err := lexAddresses(line)
	if err != nil {
		return "", err
	}
	addresses, err := parseAddresses(tokens)
	if err != nil {
		return "", err
	}
	command, err := parseCommand(line[end:])
	if err != nil {
		return "", err
	}
	if command.addressKind() == 0 && addresses.count > 0 {
		return "", errors.New("unexpected address")
	}
	if command.addressKind() == 1 && addresses.count == 2 {
		return "", errors.New("too many addresses")
	}
	trial := e.clone()
	values, err := trial.evaluate(addresses)
	if err != nil {
		return "", err
	}
	r, err := trial.checkedRange(command, addresses.count, values)
	if err != nil {
		return "", err
	}
	var output strings.Builder
	if _, err = trial.execute(command, r, text, &output, false); err != nil {
		return "", err
	}
	if len(trial.buffer) > 200 {
		return "", errors.New("buffer full")
	}
	if command.modifying() {
		trial.undo = append(trial.undo, &record{line, e.snapshot()})
		trial.redo = nil
	}
	*e = trial
	return output.String(), nil
}

func main() {
	input := bufio.NewScanner(os.Stdin)
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	editor := newEditor()
	for input.Scan() {
		line := input.Text()
		if line == "Q" {
			break
		}
		var text []string
		if withText(line) {
			for input.Scan() {
				entered := input.Text()
				if entered == "." {
					break
				}
				text = append(text, entered)
			}
		}
		response, err := editor.apply(line, text)
		if err != nil {
			fmt.Fprintf(output, "? %s\n", err)
		} else {
			fmt.Fprint(output, response)
		}
	}
	if err := input.Err(); err != nil {
		panic(err)
	}
}
