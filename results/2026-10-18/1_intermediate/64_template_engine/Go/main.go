package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type value = any

type sourceLine struct {
	number int
	text   string
}

type failure struct {
	number int
	reason string
}

func (e failure) Error() string {
	return e.reason
}

func invalid(number int, format string, args ...any) error {
	return failure{number, fmt.Sprintf(format, args...)}
}

var identifier = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)
var subscript = regexp.MustCompile(`^(0|[1-9][0-9]*)$`)
var integer = regexp.MustCompile(`^(0|-?[1-9][0-9]*)$`)
var numberText = regexp.MustCompile(`^-?[0-9]{1,9}$`)

func trim(s string) string {
	return strings.Trim(s, " ")
}

func validName(s string) bool {
	if s == "." || s == "@index" || s == "@number" || s == "@first" || s == "@last" {
		return true
	}
	for _, p := range strings.Split(s, ".") {
		if !identifier.MatchString(p) && !subscript.MatchString(p) {
			return false
		}
	}
	return true
}

type part struct {
	name    string
	index   int
	indexed bool
	prefix  string
}

func keyParts(key string) ([]part, error) {
	parts := []part{}
	pos := 0
	for pos < len(key) {
		start := pos
		if pos > 0 && key[pos] == '[' {
			pos++
			start = pos
			for pos < len(key) && key[pos] >= '0' && key[pos] <= '9' {
				pos++
			}
			if pos == len(key) || key[pos] != ']' || !subscript.MatchString(key[start:pos]) {
				return nil, fmt.Errorf("bad key '%s'", key)
			}
			n, err := strconv.Atoi(key[start:pos])
			if err != nil {
				n = int(^uint(0) >> 1)
			}
			pos++
			parts = append(parts, part{index: n, indexed: true, prefix: key[:pos]})
		} else {
			if pos > 0 {
				if key[pos] != '.' {
					return nil, fmt.Errorf("bad key '%s'", key)
				}
				pos++
				start = pos
			}
			for pos < len(key) && (key[pos] == '_' || key[pos] >= 'A' && key[pos] <= 'Z' || key[pos] >= 'a' && key[pos] <= 'z' || key[pos] >= '0' && key[pos] <= '9') {
				pos++
			}
			if !identifier.MatchString(key[start:pos]) {
				return nil, fmt.Errorf("bad key '%s'", key)
			}
			parts = append(parts, part{name: key[start:pos], prefix: key[:pos]})
		}
	}
	if len(parts) == 0 {
		return nil, fmt.Errorf("bad key '%s'", key)
	}
	return parts, nil
}

func readScalar(s string, pos int) (value, int, bool) {
	if pos < len(s) && s[pos] == '"' {
		var b strings.Builder
		pos++
		for pos < len(s) {
			c := s[pos]
			pos++
			if c == '"' {
				return b.String(), pos, true
			}
			if c == '\\' {
				if pos == len(s) {
					break
				}
				c = s[pos]
				pos++
				switch c {
				case 'n':
					c = '\n'
				case '"', '\\':
				default:
					return nil, pos, false
				}
			}
			b.WriteByte(c)
		}
		return nil, pos, false
	}
	end := pos
	for end < len(s) && s[end] != ',' && s[end] != ']' {
		end++
	}
	word := s[pos:end]
	if word == "true" {
		return true, end, true
	}
	if word == "false" {
		return false, end, true
	}
	if integer.MatchString(word) {
		n, err := strconv.Atoi(word)
		if err == nil {
			return n, end, true
		}
	}
	return nil, end, false
}

func parseValue(s string) (value, error) {
	bad := fmt.Errorf("bad value '%s'", s)
	if s == "[]" {
		return []value{}, nil
	}
	if s == "{}" {
		return map[string]value{}, nil
	}
	if strings.HasPrefix(s, "[") {
		list := []value{}
		pos := 1
		for {
			v, end, ok := readScalar(s, pos)
			if !ok {
				return nil, bad
			}
			list = append(list, v)
			pos = end
			if s[pos:] == "]" {
				return list, nil
			}
			if !strings.HasPrefix(s[pos:], ", ") {
				return nil, bad
			}
			pos += 2
		}
	}
	v, end, ok := readScalar(s, 0)
	if !ok || end != len(s) {
		return nil, bad
	}
	return v, nil
}

func get(v value, p part) (value, bool) {
	if p.indexed {
		xs, ok := v.([]value)
		if ok && p.index >= 0 && p.index < len(xs) {
			return xs[p.index], true
		}
	} else {
		if m, ok := v.(map[string]value); ok {
			x, found := m[p.name]
			return x, found
		}
	}
	return nil, false
}

func change(v value, parts []part, at int, newValue value, remove bool, key string) (value, error) {
	p := parts[at]
	child, exists := get(v, p)
	if remove && !exists {
		return nil, fmt.Errorf("no value at '%s'", key)
	}
	if !remove && p.indexed && p.index > len(v.([]value)) {
		return nil, fmt.Errorf("index gap at '%s'", p.prefix)
	}
	if at+1 < len(parts) {
		if !remove {
			if parts[at+1].indexed {
				if !exists {
					child = []value{}
				} else if _, ok := child.([]value); !ok {
					return nil, fmt.Errorf("type conflict at '%s'", p.prefix)
				}
			} else {
				if !exists {
					child = map[string]value{}
				} else if _, ok := child.(map[string]value); !ok {
					return nil, fmt.Errorf("type conflict at '%s'", p.prefix)
				}
			}
		}
		var err error
		newValue, err = change(child, parts, at+1, newValue, remove, key)
		if err != nil {
			return nil, err
		}
	}
	if p.indexed {
		xs, ok := v.([]value)
		if !ok {
			return nil, fmt.Errorf("no value at '%s'", key)
		}
		out := append([]value{}, xs...)
		if at+1 == len(parts) && remove {
			out = append(out[:p.index], out[p.index+1:]...)
		} else if p.index == len(out) {
			out = append(out, newValue)
		} else {
			out[p.index] = newValue
		}
		return out, nil
	}
	m, ok := v.(map[string]value)
	if !ok {
		return nil, fmt.Errorf("no value at '%s'", key)
	}
	out := map[string]value{}
	for k, x := range m {
		out[k] = x
	}
	if at+1 == len(parts) && remove {
		delete(out, p.name)
	} else {
		out[p.name] = newValue
	}
	return out, nil
}

func splitQuoted(s string, sep byte) []string {
	out := []string{}
	start := 0
	quoted := false
	for i := 0; i < len(s); i++ {
		if s[i] == '\'' {
			quoted = !quoted
		} else if s[i] == sep && !quoted {
			out = append(out, s[start:i])
			start = i + 1
		}
	}
	return append(out, s[start:])
}

type filter struct {
	name string
	args []value
}

type expression struct {
	name    string
	filters []filter
}

func parseExpression(s string, line int) (expression, error) {
	pieces := splitQuoted(s, '|')
	e := expression{name: trim(pieces[0])}
	if !validName(e.name) {
		return e, invalid(line, "invalid name '%s'", e.name)
	}
	for _, piece := range pieces[1:] {
		fields := splitQuoted(trim(piece), ':')
		f := filter{name: fields[0]}
		known := strings.Contains(" upper lower title trim length first last reverse items comma sum min max default eq pad lpad truncate replace join sort pluck add sub mul div mod gt lt ", " "+f.name+" ")
		if !known {
			return e, invalid(line, "unknown filter '%s'", f.name)
		}
		valid := true
		for _, a := range fields[1:] {
			if len(a) >= 2 && a[0] == '\'' && a[len(a)-1] == '\'' && !strings.Contains(a[1:len(a)-1], "'") {
				f.args = append(f.args, a[1:len(a)-1])
			} else if numberText.MatchString(a) {
				n, _ := strconv.Atoi(a)
				f.args = append(f.args, n)
			} else {
				valid = false
			}
		}
		n := len(f.args)
		isInt := func(i int) bool {
			if i >= n {
				return false
			}
			_, ok := f.args[i].(int)
			return ok
		}
		isString := func(i int) bool {
			if i >= n {
				return false
			}
			_, ok := f.args[i].(string)
			return ok
		}
		switch f.name {
		case "default", "eq":
			valid = valid && n == 1
		case "pad", "lpad":
			valid = valid && (n == 1 || n == 2) && isInt(0)
			if valid {
				valid = f.args[0].(int) >= 0 && (n == 1 || isString(1) && len(f.args[1].(string)) == 1)
			}
		case "truncate":
			valid = valid && n == 1 && isInt(0)
			if valid {
				valid = f.args[0].(int) >= 0
			}
		case "replace":
			valid = valid && n == 2 && isString(0) && isString(1)
			if valid {
				valid = f.args[0].(string) != ""
			}
		case "join", "pluck":
			valid = valid && n == 1 && isString(0)
		case "sort":
			valid = valid && (n == 0 || n == 1 && isString(0))
		case "div", "mod":
			valid = valid && n == 1 && isInt(0)
			if valid {
				valid = f.args[0].(int) != 0
			}
		case "add", "sub", "mul", "gt", "lt":
			valid = valid && n == 1 && isInt(0)
		default:
			valid = valid && n == 0
		}
		if !valid {
			return e, invalid(line, "bad arguments for '%s'", f.name)
		}
		e.filters = append(e.filters, f)
	}
	return e, nil
}

type node struct {
	kind     byte
	text     string
	line     int
	expr     expression
	children []*node
	indent   string
}

func parseSource(lines []sourceLine) ([]*node, error) {
	root := &node{}
	targets := []*node{root}
	opens := []*node{}
	opening, closing := "{{", "}}"
	for _, line := range lines {
		tokens := []*node{}
		pos := 0
		tagCount := 0
		onlySpaces := true
		var onlyTag *node
		for {
			rel := strings.Index(line.text[pos:], opening)
			if rel < 0 {
				text := line.text[pos:]
				tokens = append(tokens, &node{text: text})
				onlySpaces = onlySpaces && trim(text) == ""
				break
			}
			start := pos + rel
			text := line.text[pos:start]
			tokens = append(tokens, &node{text: text})
			onlySpaces = onlySpaces && trim(text) == ""
			after := start + len(opening)
			triple := after < len(line.text) && line.text[after] == '{'
			close := closing
			if triple {
				after++
				close = "}" + closing
			}
			rel = strings.Index(line.text[after:], close)
			if rel < 0 {
				return nil, invalid(line.number, "unclosed tag")
			}
			end := after + rel
			content := trim(line.text[after:end])
			pos = end + len(close)
			n := &node{kind: 'v', text: content, line: line.number}
			if triple {
				n.kind = '&'
			} else if content != "" && strings.ContainsRune("#^/!>&=", rune(content[0])) {
				n.kind = content[0]
				if n.kind != '=' {
					n.text = trim(content[1:])
				}
			}
			switch n.kind {
			case '=':
				parts := []string{}
				if len(content) >= 2 && content[len(content)-1] == '=' {
					for _, p := range strings.Split(content[1:len(content)-1], " ") {
						if p != "" {
							parts = append(parts, p)
						}
					}
				}
				if len(parts) != 2 || strings.Contains(parts[0], "=") || strings.Contains(parts[1], "=") {
					return nil, invalid(line.number, "invalid delimiters")
				}
				opening, closing = parts[0], parts[1]
			case 'v', '&', '#', '^':
				var err error
				n.expr, err = parseExpression(n.text, line.number)
				if err != nil {
					return nil, err
				}
				if n.kind == '#' || n.kind == '^' {
					opens = append(opens, n)
				}
			case '/':
				if !validName(n.text) {
					return nil, invalid(line.number, "invalid name '%s'", n.text)
				}
				if len(opens) == 0 {
					return nil, invalid(line.number, "unexpected closing '%s'", n.text)
				}
				expected := opens[len(opens)-1].expr.name
				if n.text != expected {
					return nil, invalid(line.number, "mismatched closing '%s', expected '%s'", n.text, expected)
				}
				opens = opens[:len(opens)-1]
			case '>':
				if !identifier.MatchString(n.text) {
					return nil, invalid(line.number, "invalid name '%s'", n.text)
				}
			}
			tokens = append(tokens, n)
			tagCount++
			onlyTag = n
		}
		standalone := tagCount == 1 && onlySpaces && strings.ContainsRune("#^/!>=", rune(onlyTag.kind))
		if standalone {
			if onlyTag.kind == '>' {
				onlyTag.indent = tokens[0].text
			}
			tokens = []*node{onlyTag}
		} else {
			tokens = append(tokens, &node{text: "\n"})
		}
		for _, n := range tokens {
			target := targets[len(targets)-1]
			switch n.kind {
			case '#', '^':
				target.children = append(target.children, n)
				targets = append(targets, n)
			case '/':
				targets = targets[:len(targets)-1]
			case '!', '=':
			default:
				target.children = append(target.children, n)
			}
		}
	}
	if len(opens) > 0 {
		n := opens[len(opens)-1]
		return nil, invalid(n.line, "unclosed section '%s'", n.expr.name)
	}
	return root.children, nil
}

func truth(v value) bool {
	switch x := v.(type) {
	case nil:
		return false
	case bool:
		return x
	case int:
		return x != 0
	case string:
		return x != ""
	case []value:
		return len(x) > 0
	case map[string]value:
		return len(x) > 0
	}
	return false
}

func stringify(v value) (string, error) {
	switch x := v.(type) {
	case nil:
		return "", nil
	case string:
		return x, nil
	case int:
		return strconv.Itoa(x), nil
	case bool:
		return strconv.FormatBool(x), nil
	case []value:
		out := []string{}
		for _, e := range x {
			s, err := stringify(e)
			if err != nil {
				return "", err
			}
			out = append(out, s)
		}
		return strings.Join(out, ", "), nil
	}
	return "", fmt.Errorf("cannot render map")
}

func numeric(v value, name string) (int, error) {
	if v == nil {
		return 0, nil
	}
	if n, ok := v.(int); ok {
		return n, nil
	}
	if s, ok := v.(string); ok && numberText.MatchString(s) {
		n, _ := strconv.Atoi(s)
		return n, nil
	}
	return 0, fmt.Errorf("not a number for '%s'", name)
}

func rank(v value) int {
	switch v.(type) {
	case nil:
		return 0
	case int:
		return 1
	case string:
		return 2
	case bool:
		return 3
	}
	return 4
}

func less(a, b value) bool {
	ra, rb := rank(a), rank(b)
	if ra != rb {
		return ra < rb
	}
	switch x := a.(type) {
	case int:
		return x < b.(int)
	case string:
		return x < b.(string)
	case bool:
		return !x && b.(bool)
	}
	return false
}

func field(v value, key string) value {
	if m, ok := v.(map[string]value); ok {
		return m[key]
	}
	return nil
}

func apply(f filter, v value) (value, error) {
	list, isList := v.([]value)
	sArg := func(i int) string {
		return f.args[i].(string)
	}
	nArg := func() int {
		return f.args[0].(int)
	}
	switch f.name {
	case "default":
		if !truth(v) {
			return f.args[0], nil
		}
		return v, nil
	case "length":
		if isList {
			return len(list), nil
		}
		if m, ok := v.(map[string]value); ok {
			return len(m), nil
		}
	case "first", "last":
		if !isList {
			return v, nil
		}
		if len(list) == 0 {
			return nil, nil
		}
		if f.name == "first" {
			return list[0], nil
		}
		return list[len(list)-1], nil
	case "reverse":
		if isList {
			out := append([]value{}, list...)
			for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
				out[i], out[j] = out[j], out[i]
			}
			return out, nil
		}
		if s, ok := v.(string); ok {
			b := []byte(s)
			for i, j := 0, len(b)-1; i < j; i, j = i+1, j-1 {
				b[i], b[j] = b[j], b[i]
			}
			return string(b), nil
		}
		return v, nil
	case "items":
		m, ok := v.(map[string]value)
		if !ok {
			return v, nil
		}
		keys := []string{}
		for k := range m {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		out := []value{}
		for _, k := range keys {
			out = append(out, map[string]value{"key": k, "value": m[k]})
		}
		return out, nil
	case "sort", "pluck":
		if !isList {
			return v, nil
		}
		out := append([]value{}, list...)
		if f.name == "pluck" {
			for i, x := range out {
				out[i] = field(x, sArg(0))
			}
		} else {
			key := func(x value) value {
				if len(f.args) > 0 {
					return field(x, sArg(0))
				}
				return x
			}
			sort.SliceStable(out, func(i, j int) bool {
				return less(key(out[i]), key(out[j]))
			})
		}
		return out, nil
	case "sum", "min", "max":
		if !isList {
			return numeric(v, f.name)
		}
		if len(list) == 0 && f.name != "sum" {
			return nil, nil
		}
		total := 0
		for i, x := range list {
			n, err := numeric(x, f.name)
			if err != nil {
				return nil, err
			}
			if f.name == "sum" {
				total += n
			} else if i == 0 || f.name == "min" && n < total || f.name == "max" && n > total {
				total = n
			}
		}
		return total, nil
	case "comma", "add", "sub", "mul", "div", "mod", "gt", "lt":
		n, err := numeric(v, f.name)
		if err != nil {
			return nil, err
		}
		switch f.name {
		case "comma":
			s := strconv.Itoa(n)
			sign := ""
			if n < 0 {
				sign = "-"
				s = s[1:]
			}
			for i := len(s) - 3; i > 0; i -= 3 {
				s = s[:i] + "," + s[i:]
			}
			return sign + s, nil
		case "add":
			return n + nArg(), nil
		case "sub":
			return n - nArg(), nil
		case "mul":
			return n * nArg(), nil
		case "gt":
			return n > nArg(), nil
		case "lt":
			return n < nArg(), nil
		default:
			q := n / nArg()
			if n%nArg() != 0 && (n < 0) != (nArg() < 0) {
				q--
			}
			if f.name == "div" {
				return q, nil
			}
			return n - nArg()*q, nil
		}
	case "join":
		if isList {
			out := []string{}
			for _, x := range list {
				s, err := stringify(x)
				if err != nil {
					return nil, err
				}
				out = append(out, s)
			}
			return strings.Join(out, sArg(0)), nil
		}
	}
	s, err := stringify(v)
	if err != nil {
		return nil, err
	}
	switch f.name {
	case "upper":
		return strings.ToUpper(s), nil
	case "lower":
		return strings.ToLower(s), nil
	case "title":
		b := []byte(strings.ToLower(s))
		for i, c := range b {
			if (i == 0 || s[i-1] == ' ') && c >= 'a' && c <= 'z' {
				b[i] = c - 'a' + 'A'
			}
		}
		return string(b), nil
	case "trim":
		return trim(s), nil
	case "length":
		return len(s), nil
	case "eq":
		other, err := stringify(f.args[0])
		return s == other, err
	case "pad", "lpad":
		c := " "
		if len(f.args) > 1 {
			c = sArg(1)
		}
		if nArg() > len(s) {
			fill := strings.Repeat(c, nArg()-len(s))
			if f.name == "pad" {
				s += fill
			} else {
				s = fill + s
			}
		}
		return s, nil
	case "truncate":
		if len(s) > nArg() {
			s = s[:nArg()] + "..."
		}
		return s, nil
	case "replace":
		return strings.ReplaceAll(s, sArg(0), sArg(1)), nil
	case "join":
		return s, nil
	}
	return v, nil
}

var htmlEscaper = strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", "\"", "&quot;", "'", "&#39;")

type loop struct {
	index, count int
}

type renderer struct {
	contexts []value
	loops    []loop
	partials map[string][]sourceLine
	strict   bool
	out      strings.Builder
}

func (r *renderer) resolve(name string) (value, bool) {
	if name == "." {
		return r.contexts[len(r.contexts)-1], true
	}
	if strings.HasPrefix(name, "@") {
		if len(r.loops) == 0 {
			return nil, false
		}
		l := r.loops[len(r.loops)-1]
		switch name {
		case "@index":
			return l.index, true
		case "@number":
			return l.index + 1, true
		case "@first":
			return l.index == 0, true
		case "@last":
			return l.index == l.count-1, true
		}
	}
	parts := []part{}
	for _, s := range strings.Split(name, ".") {
		p := part{name: s}
		if subscript.MatchString(s) {
			p.indexed = true
			n, err := strconv.Atoi(s)
			if err != nil {
				n = -1
			}
			p.index = n
		}
		parts = append(parts, p)
	}
	for i := len(r.contexts) - 1; i >= 0; i-- {
		if _, ok := get(r.contexts[i], parts[0]); ok {
			v := r.contexts[i]
			for _, p := range parts {
				var found bool
				v, found = get(v, p)
				if !found {
					return nil, false
				}
			}
			return v, true
		}
	}
	return nil, false
}

func (r *renderer) evaluate(e expression, strict bool) (value, error) {
	v, found := r.resolve(e.name)
	if !found && strict {
		return nil, fmt.Errorf("missing '%s'", e.name)
	}
	var err error
	for _, f := range e.filters {
		v, err = apply(f, v)
		if err != nil {
			return nil, err
		}
	}
	return v, nil
}

func (r *renderer) render(nodes []*node, depth int) error {
	for _, n := range nodes {
		if n.kind == 0 {
			r.out.WriteString(n.text)
			continue
		}
		var err error
		switch n.kind {
		case 'v', '&':
			var v value
			v, err = r.evaluate(n.expr, r.strict)
			if err == nil {
				var s string
				s, err = stringify(v)
				if err == nil {
					if n.kind == 'v' {
						s = htmlEscaper.Replace(s)
					}
					r.out.WriteString(s)
				}
			}
		case '#', '^':
			var v value
			v, err = r.evaluate(n.expr, false)
			if err == nil {
				if n.kind == '^' {
					if !truth(v) {
						err = r.render(n.children, depth)
					}
				} else if list, ok := v.([]value); ok {
					for i, x := range list {
						r.contexts = append(r.contexts, x)
						r.loops = append(r.loops, loop{i, len(list)})
						err = r.render(n.children, depth)
						r.contexts = r.contexts[:len(r.contexts)-1]
						r.loops = r.loops[:len(r.loops)-1]
						if err != nil {
							break
						}
					}
				} else if truth(v) {
					r.contexts = append(r.contexts, v)
					err = r.render(n.children, depth)
					r.contexts = r.contexts[:len(r.contexts)-1]
				}
			}
		case '>':
			body, ok := r.partials[n.text]
			if !ok {
				err = fmt.Errorf("unknown partial '%s'", n.text)
			} else if depth == 8 {
				err = fmt.Errorf("partial depth exceeded at '%s'", n.text)
			} else {
				source := make([]sourceLine, len(body))
				for i, l := range body {
					source[i] = l
					if l.text != "" {
						source[i].text = n.indent + l.text
					}
				}
				var child []*node
				child, err = parseSource(source)
				if err == nil {
					err = r.render(child, depth+1)
				}
			}
		}
		if err != nil {
			if _, ok := err.(failure); ok {
				return err
			}
			return invalid(n.line, "%s", err)
		}
	}
	return nil
}

func notation(v value) string {
	switch x := v.(type) {
	case string:
		return "\"" + strings.NewReplacer("\\", "\\\\", "\"", "\\\"", "\n", "\\n").Replace(x) + "\""
	case int:
		return strconv.Itoa(x)
	case bool:
		return strconv.FormatBool(x)
	case []value:
		return "[]"
	}
	return "{}"
}

func leaves(v value, path string, out *[]string) {
	switch x := v.(type) {
	case map[string]value:
		if len(x) > 0 {
			keys := []string{}
			for k := range x {
				keys = append(keys, k)
			}
			sort.Strings(keys)
			for _, k := range keys {
				next := k
				if path != "" {
					next = path + "." + k
				}
				leaves(x[k], next, out)
			}
			return
		}
	case []value:
		if len(x) > 0 {
			for i, e := range x {
				leaves(e, fmt.Sprintf("%s[%d]", path, i), out)
			}
			return
		}
	}
	if path != "" {
		*out = append(*out, path+" = "+notation(v))
	}
}

func main() {
	data, _ := io.ReadAll(os.Stdin)
	lines := strings.Split(string(data), "\n")
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	root := map[string]value{}
	partials := map[string][]sourceLine{}
	templates := map[string][]sourceLine{}
	strict := false
	render := func(name string) {
		nodes, err := parseSource(templates[name])
		r := renderer{contexts: []value{root}, partials: partials, strict: strict}
		if err == nil {
			err = r.render(nodes, 0)
		}
		if err != nil {
			e := err.(failure)
			fmt.Fprintf(out, "TEMPLATE %s ERROR line %d: %s\n", name, e.number, e.reason)
			return
		}
		s := r.out.String()
		count := strings.Count(s, "\n")
		if s != "" && !strings.HasSuffix(s, "\n") {
			count++
		}
		fmt.Fprintf(out, "TEMPLATE %s OK lines=%d chars=%d\n", name, count, len(s))
		if s != "" {
			fmt.Fprint(out, s)
			if !strings.HasSuffix(s, "\n") {
				fmt.Fprintln(out)
			}
		}
	}
	for pos := 0; pos < len(lines); {
		line := lines[pos]
		number := pos + 1
		pos++
		if line == "END" {
			break
		}
		cmd, name, _ := strings.Cut(line, " ")
		if cmd == "DATA" || cmd == "PARTIAL" || cmd == "TEMPLATE" {
			end := "END" + cmd
			body := []sourceLine{}
			for lines[pos] != end {
				body = append(body, sourceLine{pos + 1, lines[pos]})
				pos++
			}
			pos++
			switch cmd {
			case "DATA":
				set, unset := 0, 0
				errors := []string{}
				for _, l := range body {
					if l.text == "" || strings.HasPrefix(l.text, "#") {
						continue
					}
					remove := strings.HasPrefix(l.text, "UNSET ")
					key, text, ok := strings.Cut(l.text, " = ")
					if remove {
						key = l.text[6:]
						ok = true
					}
					var err error
					var ps []part
					var v value
					if !ok {
						err = fmt.Errorf("bad line")
					} else {
						ps, err = keyParts(key)
					}
					if err == nil && !remove {
						v, err = parseValue(text)
					}
					if err == nil {
						var changed value
						changed, err = change(root, ps, 0, v, remove, key)
						if err == nil {
							root = changed.(map[string]value)
						}
					}
					if err != nil {
						errors = append(errors, fmt.Sprintf("ERROR line %d: %s", l.number, err))
					} else if remove {
						unset++
					} else {
						set++
					}
				}
				fmt.Fprintf(out, "DATA set=%d unset=%d errors=%d\n", set, unset, len(errors))
				for _, e := range errors {
					fmt.Fprintln(out, e)
				}
			case "PARTIAL":
				_, err := parseSource(body)
				if err != nil {
					e := err.(failure)
					fmt.Fprintf(out, "PARTIAL %s ERROR line %d: %s\n", name, e.number, e.reason)
				} else {
					status := "DEFINED"
					if _, ok := partials[name]; ok {
						status = "REPLACED"
					}
					partials[name] = body
					fmt.Fprintf(out, "PARTIAL %s %s lines=%d\n", name, status, len(body))
				}
			case "TEMPLATE":
				templates[name] = body
				render(name)
			}
		} else {
			switch cmd {
			case "RENDER":
				if _, ok := templates[name]; ok {
					render(name)
				} else {
					fmt.Fprintf(out, "TEMPLATE %s ERROR line %d: unknown template '%s'\n", name, number, name)
				}
			case "STRICT":
				strict = name == "ON"
				fmt.Fprintln(out, line)
			case "RESET":
				root = map[string]value{}
				partials = map[string][]sourceLine{}
				templates = map[string][]sourceLine{}
				fmt.Fprintln(out, "RESET")
			case "DUMP":
				ls := []string{}
				leaves(root, "", &ls)
				fmt.Fprintf(out, "DUMP leaves=%d\n", len(ls))
				for _, l := range ls {
					fmt.Fprintln(out, l)
				}
			}
		}
	}
}
