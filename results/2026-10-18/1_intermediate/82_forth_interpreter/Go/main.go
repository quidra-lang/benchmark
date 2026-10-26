package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

type forthError struct {
	word, reason string
	code         int64
	catchable    bool
}

type action struct {
	kind, raw, text string
	value           int64
	word            *word
	target          int
	slots           []int
}

type word struct {
	name, rawName, kind  string
	here, address, value int64
	token                int64
	actions              []action
	localNames           map[string]int
	localCount           int
	does                 *word
	doesStart            int
}

type control struct {
	kind         string
	index, start int
	leaves, ends []int
}

type machine struct {
	data, returns, memory []int64
	dictionary            []*word
	builtins              map[string]*word
	tokens                []*word
	tokenNumbers          map[*word]int64
	compiling             *word
	controls              []control
	line                  string
	position, depth       int
	pending               strings.Builder
	out                   *bufio.Writer
}

var compileOnly = strings.Fields("IF ELSE THEN DO ?DO LOOP +LOOP LEAVE UNLOOP I J BEGIN UNTIL WHILE REPEAT AGAIN CASE OF ENDOF ENDCASE EXIT RECURSE DOES> ; >R R> R@ ABORT\" ['] {:")
var interpretOnly = strings.Fields(": :NONAME FORGET")
var bothModes = []string{".\"", "(", "\\", "TO", "IS"}
var builtinNames = strings.Fields("+ - * / MOD /MOD */ */MOD NEGATE ABS MIN MAX 1+ 1- 2* 2/ = <> < > 0= 0<> 0< 0> WITHIN TRUE FALSE AND OR XOR INVERT DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER DEPTH PICK ROLL . .R .S ? CR EMIT SPACE SPACES BL ! @ +! , ALLOT HERE CELLS CELL+ BASE HEX DECIMAL CREATE VARIABLE CONSTANT VALUE DEFER ' EXECUTE CATCH THROW ABORT WORDS")

func has(items []string, value string) bool {
	for _, item := range items {
		if item == value {
			return true
		}
	}
	return false
}
func problem(raw, reason string, code int64) { panic(forthError{raw, reason, code, true}) }
func syntax(raw, reason string)              { panic(forthError{word: raw, reason: reason}) }
func flag(value bool) int64 {
	if value {
		return -1
	}
	return 0
}
func floorDivide(a, b int64) int64 {
	q := a / b
	if a%b != 0 && (a < 0) != (b < 0) {
		q--
	}
	return q
}

func newMachine(out *bufio.Writer) *machine {
	m := &machine{memory: []int64{10}, builtins: map[string]*word{}, tokenNumbers: map[*word]int64{}, out: out}
	for _, name := range builtinNames {
		m.builtins[name] = &word{name: name, kind: "builtin"}
	}
	return m
}
func (m *machine) read() (string, bool) {
	for m.position < len(m.line) && m.line[m.position] == ' ' {
		m.position++
	}
	start := m.position
	for m.position < len(m.line) && m.line[m.position] != ' ' {
		m.position++
	}
	return m.line[start:m.position], start != m.position
}
func (m *machine) readName(raw string) string {
	name, exists := m.read()
	if !exists {
		problem(raw, "missing name", -16)
	}
	return name
}
func (m *machine) lookup(name string) *word {
	name = strings.ToUpper(name)
	for i := len(m.dictionary) - 1; i >= 0; i-- {
		if m.dictionary[i].name == name {
			return m.dictionary[i]
		}
	}
	return m.builtins[name]
}
func (m *machine) numeric(raw string, base int64) (int64, bool) {
	if len(raw) == 3 && raw[0] == '\'' && raw[2] == '\'' {
		return int64(raw[1]), true
	}
	text := strings.ToUpper(raw)
	if len(text) > 0 {
		switch text[0] {
		case '$':
			base, text = 16, text[1:]
		case '#':
			base, text = 10, text[1:]
		case '%':
			base, text = 2, text[1:]
		default:
			if base < 2 || base > 36 {
				problem(raw, "invalid base", -40)
			}
		}
	}
	negative := false
	if strings.HasPrefix(text, "-") {
		negative, text = true, text[1:]
	}
	if text == "" {
		return 0, false
	}
	digits := make([]int64, len(text))
	for i, c := range text {
		digit := int64(-1)
		if c >= '0' && c <= '9' {
			digit = int64(c - '0')
		} else if c >= 'A' && c <= 'Z' {
			digit = int64(c - 'A' + 10)
		}
		if digit < 0 || digit >= base {
			return 0, false
		}
		digits[i] = digit
	}
	value := int64(0)
	for _, digit := range digits {
		value = value*base + digit
	}
	if negative {
		value = -value
	}
	return value, true
}
func (m *machine) checkName(raw string) {
	name := strings.ToUpper(raw)
	if has(compileOnly, name) || has(interpretOnly, name) || has(bothModes, name) {
		problem(raw, "invalid name", -19)
	}
	if _, numeric := m.numeric(raw, 10); numeric {
		problem(raw, "invalid name", -19)
	}
}
func (m *machine) take(count int, raw string) []int64 {
	if len(m.data) < count {
		problem(raw, "stack underflow", -4)
	}
	values := append([]int64(nil), m.data[len(m.data)-count:]...)
	m.data = m.data[:len(m.data)-count]
	return values
}
func (m *machine) push(value int64, raw string) {
	m.data = append(m.data, value)
	if len(m.data) > 1000 {
		problem(raw, "stack overflow", -3)
	}
}
func (m *machine) returnNeed(count int, raw string) {
	if len(m.returns) < count {
		problem(raw, "return stack underflow", -6)
	}
}
func (m *machine) returnPush(value int64, raw string) {
	m.returns = append(m.returns, value)
	if len(m.returns) > 1000 {
		problem(raw, "return stack overflow", -5)
	}
}
func (m *machine) address(address int64, raw string) int {
	if address < 0 || address%8 != 0 || address >= int64(len(m.memory))*8 {
		problem(raw, "invalid address", -9)
	}
	return int(address / 8)
}
func (m *machine) format(value int64, raw string) string {
	base := m.memory[0]
	if base < 2 || base > 36 {
		problem(raw, "invalid base", -40)
	}
	return strings.ToUpper(strconv.FormatInt(value, int(base)))
}
func (m *machine) flush() {
	fmt.Fprintln(m.out, strings.TrimRight(m.pending.String(), " "))
	m.pending.Reset()
}
func (m *machine) executionToken(w *word) int64 {
	if token, exists := m.tokenNumbers[w]; exists {
		return token
	}
	m.tokens = append(m.tokens, w)
	token := int64(len(m.tokens))
	m.tokenNumbers[w] = token
	return token
}
func (m *machine) validToken(value int64, raw string) *word {
	if value < 1 || value > int64(len(m.tokens)) {
		problem(raw, "invalid argument", -24)
	}
	return m.tokens[value-1]
}
func (m *machine) executeToken(value int64, raw string) {
	target := m.validToken(value, raw)
	m.execute(target, target.name)
}
func (m *machine) addAction(a action) int {
	index := len(m.compiling.actions)
	m.compiling.actions = append(m.compiling.actions, a)
	return index
}
func (m *machine) topControl(raw string, kinds ...string) *control {
	if len(m.controls) == 0 || !has(kinds, m.controls[len(m.controls)-1].kind) {
		syntax(raw, "control structure mismatch")
	}
	return &m.controls[len(m.controls)-1]
}
func (m *machine) compileControl(raw, name string) bool {
	switch name {
	case "IF":
		index := m.addAction(action{kind: "zero", raw: raw})
		m.controls = append(m.controls, control{kind: "IF", index: index})
	case "ELSE":
		top := m.topControl(raw, "IF")
		index := m.addAction(action{kind: "jump", raw: raw})
		m.compiling.actions[top.index].target = len(m.compiling.actions)
		top.kind, top.index = "ELSE", index
	case "THEN":
		top := m.topControl(raw, "IF", "ELSE")
		m.compiling.actions[top.index].target = len(m.compiling.actions)
		m.controls = m.controls[:len(m.controls)-1]
	case "BEGIN":
		m.controls = append(m.controls, control{kind: "BEGIN", start: len(m.compiling.actions)})
	case "UNTIL", "AGAIN":
		top := m.topControl(raw, "BEGIN")
		kind := "zero"
		if name == "AGAIN" {
			kind = "jump"
		}
		m.addAction(action{kind: kind, raw: raw, target: top.start})
		m.controls = m.controls[:len(m.controls)-1]
	case "WHILE":
		top := m.topControl(raw, "BEGIN")
		top.kind, top.index = "WHILE", m.addAction(action{kind: "zero", raw: raw})
	case "REPEAT":
		top := m.topControl(raw, "WHILE")
		m.addAction(action{kind: "jump", raw: raw, target: top.start})
		m.compiling.actions[top.index].target = len(m.compiling.actions)
		m.controls = m.controls[:len(m.controls)-1]
	case "DO", "?DO":
		index := m.addAction(action{kind: name, raw: raw})
		m.controls = append(m.controls, control{kind: name, index: index, start: index + 1})
	case "LOOP", "+LOOP":
		top := m.topControl(raw, "DO", "?DO")
		m.addAction(action{kind: name, raw: raw, target: top.start})
		finish := len(m.compiling.actions)
		m.compiling.actions[top.index].target = finish
		for _, index := range top.leaves {
			m.compiling.actions[index].target = finish
		}
		m.controls = m.controls[:len(m.controls)-1]
	case "LEAVE":
		found := -1
		for i := len(m.controls) - 1; i >= 0; i-- {
			if m.controls[i].kind == "DO" || m.controls[i].kind == "?DO" {
				found = i
				break
			}
		}
		if found < 0 {
			syntax(raw, "control structure mismatch")
		}
		index := m.addAction(action{kind: "LEAVE", raw: raw})
		m.controls[found].leaves = append(m.controls[found].leaves, index)
	case "CASE":
		m.controls = append(m.controls, control{kind: "CASE"})
	case "OF":
		m.topControl(raw, "CASE")
		index := m.addAction(action{kind: "OF", raw: raw})
		m.controls = append(m.controls, control{kind: "OF", index: index})
	case "ENDOF":
		top := m.topControl(raw, "OF")
		index := m.addAction(action{kind: "jump", raw: raw})
		m.compiling.actions[top.index].target = len(m.compiling.actions)
		m.controls = m.controls[:len(m.controls)-1]
		parent := m.topControl(raw, "CASE")
		parent.ends = append(parent.ends, index)
	case "ENDCASE":
		top := m.topControl(raw, "CASE")
		m.addAction(action{kind: "ENDCASE", raw: raw})
		for _, index := range top.ends {
			m.compiling.actions[index].target = len(m.compiling.actions)
		}
		m.controls = m.controls[:len(m.controls)-1]
	default:
		return false
	}
	return true
}
func (m *machine) readString(raw string) string {
	if m.position == len(m.line) {
		syntax(raw, "unterminated string")
	}
	start := m.position + 1
	end := strings.IndexByte(m.line[start:], '"')
	if end < 0 {
		syntax(raw, "unterminated string")
	}
	m.position = start + end + 1
	return m.line[start : start+end]
}
func (m *machine) locals(raw string) {
	names := []string{}
	ignored, closed := false, false
	for {
		name, exists := m.read()
		if !exists {
			break
		}
		if strings.ToUpper(name) == ":}" {
			closed = true
			break
		}
		if name == "--" {
			ignored = true
		}
		if !ignored {
			names = append(names, name)
		}
	}
	if !closed {
		syntax(raw, "unterminated locals")
	}
	slots := []int{}
	for _, name := range names {
		m.checkName(name)
		slot := m.compiling.localCount
		m.compiling.localCount++
		m.compiling.localNames[strings.ToUpper(name)] = slot
		slots = append(slots, slot)
	}
	m.addAction(action{kind: "locals", raw: raw, slots: slots})
}
func (m *machine) assign(raw, name string) {
	targetName := m.readName(raw)
	if name == "TO" && m.compiling != nil {
		if slot, exists := m.compiling.localNames[strings.ToUpper(targetName)]; exists {
			m.addAction(action{kind: "localSet", raw: raw, target: slot})
			return
		}
	}
	target := m.lookup(targetName)
	if target == nil {
		problem(targetName, "undefined word", -13)
	}
	required, reason := "value", "not a value"
	if name == "IS" {
		required, reason = "defer", "not deferred"
	}
	if target.kind != required {
		syntax(targetName, reason)
	}
	a := action{kind: name, raw: raw, word: target}
	if m.compiling != nil {
		m.addAction(a)
	} else {
		m.runtimeAction(a, nil)
	}
}
func (m *machine) process(raw string) {
	name := strings.ToUpper(raw)
	if name == "\\" {
		m.position = len(m.line)
		return
	}
	if name == "(" {
		end := strings.IndexByte(m.line[m.position:], ')')
		if end < 0 {
			syntax(raw, "unterminated comment")
		}
		m.position += end + 1
		return
	}
	if m.compiling == nil && has(compileOnly, name) {
		syntax(raw, "compile only")
	}
	if m.compiling != nil && has(interpretOnly, name) {
		syntax(raw, "interpret only")
	}
	if name == ".\"" || name == "ABORT\"" {
		text := m.readString(raw)
		if m.compiling == nil {
			m.pending.WriteString(text)
		} else {
			m.addAction(action{kind: name, raw: raw, text: text})
		}
		return
	}
	if name == "TO" || name == "IS" {
		m.assign(raw, name)
		return
	}
	if name == ":" || name == ":NONAME" {
		rawName := raw
		if name == ":" {
			rawName = m.readName(raw)
			m.checkName(rawName)
		}
		m.compiling = &word{name: strings.ToUpper(rawName), rawName: rawName, kind: "colon", here: int64(len(m.memory)) * 8, localNames: map[string]int{}}
		if name == ":NONAME" {
			m.compiling.name = ":NONAME"
		}
		m.controls = nil
		return
	}
	if name == "FORGET" {
		targetName := m.readName(raw)
		index := -1
		for i := len(m.dictionary) - 1; i >= 0; i-- {
			if m.dictionary[i].name == strings.ToUpper(targetName) {
				index = i
				break
			}
		}
		if index < 0 {
			problem(targetName, "undefined word", -13)
		}
		m.memory = m.memory[:m.dictionary[index].here/8]
		m.dictionary = m.dictionary[:index]
		return
	}
	if m.compiling != nil {
		if m.compileControl(raw, name) {
			return
		}
		switch name {
		case ";":
			if len(m.controls) > 0 {
				kind := m.controls[len(m.controls)-1].kind
				if kind == "ELSE" {
					kind = "IF"
				}
				if kind == "WHILE" {
					kind = "BEGIN"
				}
				syntax(raw, "unclosed "+kind)
			}
			finished := m.compiling
			m.compiling = nil
			if finished.name == ":NONAME" {
				m.push(m.executionToken(finished), raw)
			} else {
				m.dictionary = append(m.dictionary, finished)
			}
			return
		case "DOES>":
			if len(m.controls) != 0 {
				syntax(raw, "control structure mismatch")
			}
			m.addAction(action{kind: "DOES>", raw: raw, word: m.compiling})
			return
		case "EXIT":
			m.addAction(action{kind: "EXIT", raw: raw})
			return
		case "RECURSE":
			m.addAction(action{kind: "call", raw: raw, word: m.compiling})
			return
		case "[']":
			targetName := m.readName(raw)
			target := m.lookup(targetName)
			if target == nil {
				problem(targetName, "undefined word", -13)
			}
			m.addAction(action{kind: "push", raw: raw, value: m.executionToken(target)})
			return
		case "{:":
			m.locals(raw)
			return
		}
		if has([]string{">R", "R>", "R@", "I", "J", "UNLOOP"}, name) {
			m.addAction(action{kind: name, raw: raw})
			return
		}
		if slot, exists := m.compiling.localNames[name]; exists {
			m.addAction(action{kind: "localGet", raw: raw, target: slot})
			return
		}
		if target := m.lookup(raw); target != nil {
			m.addAction(action{kind: "call", raw: raw, word: target})
			return
		}
		if value, valid := m.numeric(raw, m.memory[0]); valid {
			m.addAction(action{kind: "push", raw: raw, value: value})
			return
		}
		problem(raw, "undefined word", -13)
	}
	if target := m.lookup(raw); target != nil {
		m.execute(target, raw)
		return
	}
	if value, valid := m.numeric(raw, m.memory[0]); valid {
		m.push(value, raw)
		return
	}
	problem(raw, "undefined word", -13)
}
func (m *machine) runtimeAction(a action, locals []int64) {
	switch a.kind {
	case "push":
		m.push(a.value, a.raw)
	case "call":
		m.execute(a.word, a.raw)
	case ".\"":
		m.pending.WriteString(a.text)
	case "ABORT\"":
		if m.take(1, a.raw)[0] != 0 {
			problem(a.raw, a.text, -2)
		}
	case "localGet":
		m.push(locals[a.target], a.raw)
	case "localSet":
		locals[a.target] = m.take(1, a.raw)[0]
	case "locals":
		values := m.take(len(a.slots), a.raw)
		for i, slot := range a.slots {
			locals[slot] = values[i]
		}
	case "TO":
		m.memory[a.word.address/8] = m.take(1, a.raw)[0]
	case "IS":
		value := m.take(1, a.raw)[0]
		m.validToken(value, a.raw)
		a.word.token = value
	case ">R":
		m.returnPush(m.take(1, a.raw)[0], a.raw)
	case "R>":
		m.returnNeed(1, a.raw)
		value := m.returns[len(m.returns)-1]
		m.returns = m.returns[:len(m.returns)-1]
		m.push(value, a.raw)
	case "R@", "I", "J":
		count := 1
		if a.kind == "J" {
			count = 3
		}
		m.returnNeed(count, a.raw)
		m.push(m.returns[len(m.returns)-count], a.raw)
	case "UNLOOP":
		m.returnNeed(2, a.raw)
		m.returns = m.returns[:len(m.returns)-2]
	}
}
func (m *machine) definition(w *word, start int, raw string) {
	if m.depth == 100 {
		problem(raw, "nesting too deep", -7)
	}
	m.depth++
	saved := len(m.returns)
	locals := make([]int64, w.localCount)
	for pc := start; pc < len(w.actions); {
		a := w.actions[pc]
		pc++
		switch a.kind {
		case "EXIT":
			pc = len(w.actions)
		case "DOES>":
			if len(m.dictionary) == 0 || m.dictionary[len(m.dictionary)-1].kind != "create" {
				problem(a.raw, "no CREATE word", -31)
			}
			newest := m.dictionary[len(m.dictionary)-1]
			newest.does, newest.doesStart = a.word, pc
			pc = len(w.actions)
		case "jump":
			pc = a.target
		case "zero":
			if m.take(1, a.raw)[0] == 0 {
				pc = a.target
			}
		case "DO", "?DO":
			values := m.take(2, a.raw)
			if a.kind == "?DO" && values[0] == values[1] {
				pc = a.target
			} else {
				m.returnPush(values[0], a.raw)
				m.returnPush(values[1], a.raw)
			}
		case "LOOP", "+LOOP":
			step := int64(1)
			if a.kind == "+LOOP" {
				step = m.take(1, a.raw)[0]
			}
			m.returnNeed(2, a.raw)
			index, limit := m.returns[len(m.returns)-1], m.returns[len(m.returns)-2]
			next := index + step
			if (index-limit < 0) != (next-limit < 0) {
				m.returns = m.returns[:len(m.returns)-2]
			} else {
				m.returns[len(m.returns)-1] = next
				pc = a.target
			}
		case "LEAVE":
			m.returnNeed(2, a.raw)
			m.returns = m.returns[:len(m.returns)-2]
			pc = a.target
		case "OF":
			values := m.take(2, a.raw)
			if values[0] != values[1] {
				m.push(values[0], a.raw)
				pc = a.target
			}
		case "ENDCASE":
			m.take(1, a.raw)
		default:
			m.runtimeAction(a, locals)
		}
	}
	if len(m.returns) > saved {
		m.returns = m.returns[:saved]
	}
	m.depth--
}
func (m *machine) execute(w *word, raw string) {
	for w.kind == "defer" {
		if w.token == 0 {
			problem(raw, "deferred word not set", -21)
		}
		w = m.validToken(w.token, raw)
		raw = w.name
	}
	switch w.kind {
	case "colon":
		m.definition(w, 0, raw)
	case "create":
		m.push(w.address, raw)
		if w.does != nil {
			m.definition(w.does, w.doesStart, raw)
		}
	case "variable":
		m.push(w.address, raw)
	case "constant":
		m.push(w.value, raw)
	case "value":
		m.push(m.memory[w.address/8], raw)
	default:
		m.builtin(w.name, raw)
	}
}
func (m *machine) builtin(name, raw string) {
	if has([]string{"CREATE", "VARIABLE", "CONSTANT", "VALUE", "DEFER"}, name) {
		rawName := m.readName(raw)
		m.checkName(rawName)
		value := int64(0)
		if name == "CONSTANT" || name == "VALUE" {
			value = m.take(1, raw)[0]
		}
		w := &word{name: strings.ToUpper(rawName), rawName: rawName, kind: strings.ToLower(name), here: int64(len(m.memory)) * 8, address: int64(len(m.memory)) * 8, value: value}
		m.dictionary = append(m.dictionary, w)
		if name == "VARIABLE" || name == "VALUE" {
			m.memory = append(m.memory, value)
		}
		return
	}
	if name == "'" {
		targetName := m.readName(raw)
		target := m.lookup(targetName)
		if target == nil {
			problem(targetName, "undefined word", -13)
		}
		m.push(m.executionToken(target), raw)
		return
	}
	if name == "EXECUTE" {
		m.executeToken(m.take(1, raw)[0], raw)
		return
	}
	if name == "CATCH" {
		token := m.take(1, raw)[0]
		target := m.validToken(token, raw)
		saved := append([]int64(nil), m.data...)
		returnSize, depth := len(m.returns), m.depth
		code := int64(0)
		func() {
			defer func() {
				if caught := recover(); caught != nil {
					e, valid := caught.(forthError)
					if !valid || !e.catchable {
						panic(caught)
					}
					m.data = saved
					if len(m.returns) > returnSize {
						m.returns = m.returns[:returnSize]
					}
					m.depth, code = depth, e.code
				}
			}()
			m.execute(target, target.name)
		}()
		m.push(code, raw)
		return
	}
	if name == "THROW" {
		code := m.take(1, raw)[0]
		if code != 0 {
			problem(raw, fmt.Sprintf("exception %d", code), code)
		}
		return
	}
	if name == "ABORT" {
		problem(raw, "aborted", -1)
	}
	if name == "WORDS" {
		for i := len(m.dictionary) - 1; i >= 0; i-- {
			m.pending.WriteString(m.dictionary[i].name + " ")
		}
		return
	}
	if name == "CR" {
		m.flush()
		return
	}
	if name == "SPACE" {
		m.pending.WriteByte(' ')
		return
	}
	if name == ".S" {
		count := m.format(int64(len(m.data)), raw)
		values := []string{}
		for _, value := range m.data {
			values = append(values, m.format(value, raw))
		}
		m.pending.WriteString("<" + count + "> ")
		for _, value := range values {
			m.pending.WriteString(value + " ")
		}
		return
	}
	switch name {
	case "TRUE":
		m.push(-1, raw)
		return
	case "FALSE":
		m.push(0, raw)
		return
	case "BL":
		m.push(32, raw)
		return
	case "BASE":
		m.push(0, raw)
		return
	case "HERE":
		m.push(int64(len(m.memory))*8, raw)
		return
	case "DEPTH":
		m.push(int64(len(m.data)), raw)
		return
	case "HEX":
		m.memory[0] = 16
		return
	case "DECIMAL":
		m.memory[0] = 10
		return
	}
	effects := map[string]int{"+": 2, "-": 2, "*": 2, "/": 2, "MOD": 2, "/MOD": 2, "*/": 3, "*/MOD": 3, "MIN": 2, "MAX": 2, "=": 2, "<>": 2, "<": 2, ">": 2, "WITHIN": 3, "AND": 2, "OR": 2, "XOR": 2, "SWAP": 2, "OVER": 2, "ROT": 3, "-ROT": 3, "NIP": 2, "TUCK": 2, "2DUP": 2, "2DROP": 2, "2SWAP": 4, "2OVER": 4, ".R": 2, "!": 2, "+!": 2}
	count := 1
	if n, exists := effects[name]; exists {
		count = n
	}
	v := m.take(count, raw)
	a := v[0]
	b := int64(0)
	if len(v) > 1 {
		b = v[1]
	}
	push := func(values ...int64) {
		for _, value := range values {
			m.push(value, raw)
		}
	}
	switch name {
	case "+":
		push(a + b)
	case "-":
		push(a - b)
	case "*":
		push(a * b)
	case "/", "MOD", "/MOD", "*/", "*/MOD":
		dividend, divisor := a, b
		if len(v) == 3 {
			dividend, divisor = a*b, v[2]
		}
		if divisor == 0 {
			problem(raw, "division by zero", -10)
		}
		q := floorDivide(dividend, divisor)
		r := dividend - divisor*q
		if name == "MOD" {
			push(r)
		} else if name == "/MOD" || name == "*/MOD" {
			push(r, q)
		} else {
			push(q)
		}
	case "NEGATE":
		push(-a)
	case "ABS":
		if a < 0 {
			a = -a
		}
		push(a)
	case "MIN":
		if b < a {
			a = b
		}
		push(a)
	case "MAX":
		if b > a {
			a = b
		}
		push(a)
	case "1+":
		push(a + 1)
	case "1-":
		push(a - 1)
	case "2*":
		push(2 * a)
	case "2/":
		push(floorDivide(a, 2))
	case "=":
		push(flag(a == b))
	case "<>":
		push(flag(a != b))
	case "<":
		push(flag(a < b))
	case ">":
		push(flag(a > b))
	case "0=":
		push(flag(a == 0))
	case "0<>":
		push(flag(a != 0))
	case "0<":
		push(flag(a < 0))
	case "0>":
		push(flag(a > 0))
	case "WITHIN":
		push(flag(b <= a && a < v[2]))
	case "AND":
		push(a & b)
	case "OR":
		push(a | b)
	case "XOR":
		push(a ^ b)
	case "INVERT":
		push(^a)
	case "DUP":
		push(a, a)
	case "?DUP":
		push(a)
		if a != 0 {
			push(a)
		}
	case "DROP", "2DROP":
	case "SWAP":
		push(b, a)
	case "OVER":
		push(a, b, a)
	case "ROT":
		push(b, v[2], a)
	case "-ROT":
		push(v[2], a, b)
	case "NIP":
		push(b)
	case "TUCK":
		push(b, a, b)
	case "2DUP":
		push(a, b, a, b)
	case "2SWAP":
		push(v[2], v[3], a, b)
	case "2OVER":
		push(a, b, v[2], v[3], a, b)
	case "PICK", "ROLL":
		if a < 0 {
			problem(raw, "invalid argument", -24)
		}
		if a >= int64(len(m.data)) {
			problem(raw, "stack underflow", -4)
		}
		index := len(m.data) - 1 - int(a)
		value := m.data[index]
		if name == "ROLL" {
			m.data = append(m.data[:index], m.data[index+1:]...)
		}
		push(value)
	case ".":
		m.pending.WriteString(m.format(a, raw) + " ")
	case ".R":
		text := m.format(a, raw)
		if b > int64(len(text)) {
			m.pending.WriteString(strings.Repeat(" ", int(b)-len(text)))
		}
		m.pending.WriteString(text)
	case "?":
		address := m.address(a, raw)
		m.pending.WriteString(m.format(m.memory[address], raw) + " ")
	case "EMIT":
		if a < 32 || a > 126 {
			problem(raw, "invalid argument", -24)
		}
		m.pending.WriteByte(byte(a))
	case "SPACES":
		if a > 0 {
			m.pending.WriteString(strings.Repeat(" ", int(a)))
		}
	case "!":
		m.memory[m.address(b, raw)] = a
	case "@":
		push(m.memory[m.address(a, raw)])
	case "+!":
		address := m.address(b, raw)
		m.memory[address] += a
	case ",":
		m.memory = append(m.memory, a)
	case "ALLOT":
		if a < 0 || a%8 != 0 {
			problem(raw, "invalid argument", -24)
		}
		m.memory = append(m.memory, make([]int64, a/8)...)
	case "CELLS":
		push(8 * a)
	case "CELL+":
		push(a + 8)
	}
}
func (m *machine) processLine(line string) {
	m.line, m.position = line, 0
	defer func() {
		if caught := recover(); caught != nil {
			e, valid := caught.(forthError)
			if !valid {
				panic(caught)
			}
			if m.pending.Len() > 0 {
				m.flush()
			}
			fmt.Fprintf(m.out, "ERROR %s: %s\n", e.word, e.reason)
			m.data, m.returns, m.compiling, m.controls, m.depth = nil, nil, nil, nil, 0
		}
	}()
	for {
		raw, exists := m.read()
		if !exists {
			break
		}
		m.process(raw)
	}
	if m.pending.Len() > 0 {
		m.flush()
	}
}
func main() {
	scanner := bufio.NewScanner(os.Stdin)
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	m := newMachine(out)
	for scanner.Scan() {
		line := scanner.Text()
		if line == "BYE" {
			if m.compiling != nil {
				fmt.Fprintf(out, "ERROR %s: unterminated definition\n", m.compiling.rawName)
			}
			break
		}
		m.processLine(line)
	}
}
