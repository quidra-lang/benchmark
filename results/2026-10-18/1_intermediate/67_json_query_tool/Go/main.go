package main

import (
    "bufio"
    "fmt"
    "io"
    "os"
    "sort"
    "strconv"
    "strings"
)

type value struct {
    kind string
    text string
    number int64
    boolean bool
    keys []string
    items []*value
}

func (v *value) find(key string) int {
    for i, k := range v.keys {
        if k == key {
            return i
        }
    }
    return -1
}

func (v *value) copy() *value {
    result := *v
    result.keys = append([]string{}, v.keys...)
    result.items = make([]*value, len(v.items))
    for i, item := range v.items {
        result.items[i] = item.copy()
    }
    return &result
}

func (v *value) size() (int, int) {
    count, depth := 1, 1
    for _, item := range v.items {
        n, d := item.size()
        count += n
        if d + 1 > depth {
            depth = d + 1
        }
    }
    return count, depth
}

func letter(c byte) bool {
    return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'
}
func digit(c byte) bool {
    return c >= '0' && c <= '9'
}
func identifier(s string) bool {
    if s == "" || !letter(s[0]) && s[0] != '_' {
        return false
    }
    for i := range s {
        if !letter(s[i]) && !digit(s[i]) && s[i] != '_' {
            return false
        }
    }
    return true
}

func integerNotation(s string) bool {
    if s == "0" {
        return true
    }
    if strings.HasPrefix(s, "-") {
        s = s[1:]
    }
    if len(s) < 1 || len(s) > 9 || s[0] == '0' {
        return false
    }
    for i := range s {
        if !digit(s[i]) {
            return false
        }
    }
    return true
}

func quote(s string, mark byte) string {
    var out strings.Builder
    out.WriteByte(mark)
    for i := range s {
        c := s[i]
        switch {
        case c == mark || c == '\\':
            out.WriteByte('\\')
            out.WriteByte(c)
        case c == 8:
            out.WriteString("\\b")
        case c == 12:
            out.WriteString("\\f")
        case c == 10:
            out.WriteString("\\n")
        case c == 13:
            out.WriteString("\\r")
        case c == 9:
            out.WriteString("\\t")
        case c < 32 || c == 127:
            fmt.Fprintf(&out, "\\u%04x", c)
        default:
            out.WriteByte(c)
        }
    }
    out.WriteByte(mark)
    return out.String()
}

func compact(v *value) string {
    switch v.kind {
    case "null":
        return "null"
    case "boolean":
        return strconv.FormatBool(v.boolean)
    case "number":
        return strconv.FormatInt(v.number, 10)
    case "string":
        return quote(v.text, '"')
    }
    parts := make([]string, len(v.items))
    for i, item := range v.items {
        parts[i] = compact(item)
        if v.kind == "object" {
            parts[i] = quote(v.keys[i], '"') + ":" + parts[i]
        }
    }
    if v.kind == "array" {
        return "[" + strings.Join(parts, ",") + "]"
    }
    return "{" + strings.Join(parts, ",") + "}"
}

func pretty(v *value, indent string) string {
    if len(v.items) == 0 {
        return compact(v)
    }
    inner := indent + "  "
    parts := make([]string, len(v.items))
    for i, item := range v.items {
        label := ""
        if v.kind == "object" {
            label = quote(v.keys[i], '"') + ": "
        }
        parts[i] = inner + label + pretty(item, inner)
    }
    open, close := "[", "]"
    if v.kind == "object" {
        open, close = "{", "}"
    }
    return open + "\n" + strings.Join(parts, ",\n") + "\n" + indent + close
}

func same(a, b *value) bool {
    if a.kind != b.kind {
        return false
    }
    switch a.kind {
    case "null":
        return true
    case "boolean":
        return a.boolean == b.boolean
    case "number":
        return a.number == b.number
    case "string":
        return a.text == b.text
    }
    if len(a.items) != len(b.items) {
        return false
    }
    for i, item := range a.items {
        j := i
        if a.kind == "object" {
            j = b.find(a.keys[i])
        }
        if j < 0 || !same(item, b.items[j]) {
            return false
        }
    }
    return true
}

type jsonError struct {
    position int
    reason string
}
func (e jsonError) Error() string {
    return e.reason
}
type reader struct {
    text string
    pos int
}
func (p *reader) peek() byte {
    if p.pos >= len(p.text) {
        return 0
    }
    return p.text[p.pos]
}
func (p *reader) fail(reason string) error {
    return jsonError{p.pos, reason}
}
func (p *reader) skip() {
    for p.peek() == ' ' || p.peek() == '\n' {
        p.pos++
    }
}
func (p *reader) require(c byte, reason string) error {
    if p.pos == len(p.text) {
        return p.fail("unexpected end of input")
    }
    if p.peek() != c {
        return p.fail(reason)
    }
    return nil
}
func (p *reader) string(mark byte) (string, error) {
    p.pos++
    var out strings.Builder
    escapes := map[byte]byte{'\\':'\\', '/':'/', 'b':8, 'f':12, 'n':10, 'r':13, 't':9, mark:mark}
    for {
        c := p.peek()
        if c == 0 || c == '\n' {
            return "", p.fail("unterminated string")
        }
        if c == mark {
            p.pos++
            return out.String(), nil
        }
        if c != '\\' {
            out.WriteByte(c)
            p.pos++
            continue
        }
        start := p.pos
        p.pos++
        e := p.peek()
        if e == 0 || e == '\n' {
            return "", p.fail("unterminated string")
        }
        if e == 'u' {
            if start + 6 > len(p.text) {
                return "", jsonError{start, "bad unicode escape"}
            }
            notation := p.text[start + 2:start + 6]
            for i := range notation {
                if !strings.ContainsRune("0123456789abcdefABCDEF", rune(notation[i])) {
                    return "", jsonError{start, "bad unicode escape"}
                }
            }
            n, _ := strconv.ParseInt(notation, 16, 32)
            if n > 127 {
                return "", jsonError{start, "non-ascii escape"}
            }
            out.WriteByte(byte(n))
            p.pos = start + 6
        } else if decoded, ok := escapes[e]; ok {
            out.WriteByte(decoded)
            p.pos++
        } else {
            return "", jsonError{start, fmt.Sprintf("invalid escape '\\%c'", e)}
        }
    }
}
func (p *reader) containerEnd(close byte, reason string) (bool, error) {
    p.skip()
    if p.peek() == close {
        p.pos++
        return true, nil
    }
    if err := p.require(',', reason); err != nil {
        return false, err
    }
    p.pos++
    p.skip()
    if p.peek() == close {
        return false, p.fail("trailing comma")
    }
    return false, nil
}
func (p *reader) value() (*value, error) {
    p.skip()
    c := p.peek()
    if c == 0 {
        return nil, p.fail("unexpected end of input")
    }
    if c == '"' {
        s, err := p.string('"')
        return &value{kind:"string", text:s}, err
    }
    if c == '{' || c == '[' {
        kind, close, reason := "array", byte(']'), "expected ',' or ']'"
        if c == '{' {
            kind, close, reason = "object", '}', "expected ',' or '}'"
        }
        v := &value{kind:kind}
        p.pos++
        p.skip()
        if p.peek() == close {
            p.pos++
            return v, nil
        }
        for {
            if kind == "object" {
                p.skip()
                if err := p.require('"', "expected key"); err != nil {
                    return nil, err
                }
                start := p.pos
                key, err := p.string('"')
                if err != nil {
                    return nil, err
                }
                if v.find(key) >= 0 {
                    return nil, jsonError{start, "duplicate key " + quote(key, '"')}
                }
                p.skip()
                if err := p.require(':', "expected ':'"); err != nil {
                    return nil, err
                }
                p.pos++
                v.keys = append(v.keys, key)
            }
            item, err := p.value()
            if err != nil {
                return nil, err
            }
            v.items = append(v.items, item)
            done, err := p.containerEnd(close, reason)
            if err != nil {
                return nil, err
            }
            if done {
                return v, nil
            }
        }
    }
    if c == '-' || digit(c) {
        start := p.pos
        negative := c == '-'
        if negative {
            p.pos++
        }
        digitsStart := p.pos
        for digit(p.peek()) {
            p.pos++
        }
        ds := p.text[digitsStart:p.pos]
        if ds == "" {
            return nil, jsonError{start, "invalid number"}
        }
        if len(ds) > 1 && ds[0] == '0' {
            return nil, jsonError{digitsStart, "leading zero"}
        }
        if p.peek() == '.' {
            return nil, p.fail("fraction not allowed")
        }
        if p.peek() == 'e' || p.peek() == 'E' {
            return nil, p.fail("exponent not allowed")
        }
        if len(ds) >= 10 {
            return nil, jsonError{start, "number out of range"}
        }
        n, _ := strconv.ParseInt(ds, 10, 64)
        if negative {
            n = -n
        }
        return &value{kind:"number", number:n}, nil
    }
    if letter(c) {
        start := p.pos
        for letter(p.peek()) {
            p.pos++
        }
        word := p.text[start:p.pos]
        if word == "null" {
            return &value{kind:"null"}, nil
        }
        if word == "true" || word == "false" {
            return &value{kind:"boolean", boolean:word == "true"}, nil
        }
        return nil, jsonError{start, "invalid literal '" + word + "'"}
    }
    return nil, p.fail(fmt.Sprintf("unexpected character '%c'", c))
}
func parseJSON(text string) (*value, error) {
    p := reader{text:text}
    v, err := p.value()
    if err != nil {
        return nil, err
    }
    p.skip()
    if p.pos < len(text) {
        return nil, p.fail("trailing characters")
    }
    return v, nil
}

type selector struct {
    kind, key string
    index int64
    start, end *int64
    descendant bool
}
type pathReader struct {
    reader
    reason string
}
func (p *pathReader) invalid() error {
    return fmt.Errorf("%s", p.reason)
}
func (p *pathReader) identifier() (string, error) {
    start := p.pos
    if !letter(p.peek()) && p.peek() != '_' {
        return "", p.invalid()
    }
    for letter(p.peek()) || digit(p.peek()) || p.peek() == '_' {
        p.pos++
    }
    return p.text[start:p.pos], nil
}
func (p *pathReader) selection() (selector, error) {
    if p.peek() == '\'' {
        key, err := p.string('\'')
        if err != nil || p.peek() != ']' {
            return selector{}, p.invalid()
        }
        p.pos++
        return selector{kind:"key", key:key}, nil
    }
    end := strings.IndexByte(p.text[p.pos:], ']')
    if end < 0 {
        return selector{}, p.invalid()
    }
    text := p.text[p.pos:p.pos + end]
    p.pos += end + 1
    if text == "*" {
        return selector{kind:"all"}, nil
    }
    if integerNotation(text) {
        n, _ := strconv.ParseInt(text, 10, 64)
        return selector{kind:"index", index:n}, nil
    }
    a, b, colon := strings.Cut(text, ":")
    if !colon || a != "" && !integerNotation(a) || b != "" && !integerNotation(b) {
        return selector{}, p.invalid()
    }
    s := selector{kind:"slice"}
    if a != "" {
        n, _ := strconv.ParseInt(a, 10, 64)
        s.start = &n
    }
    if b != "" {
        n, _ := strconv.ParseInt(b, 10, 64)
        s.end = &n
    }
    return s, nil
}
func parsePath(text string, field bool) ([]selector, error) {
    reason, mark := "bad path", byte('$')
    if field {
        reason, mark = "bad field", '@'
    }
    p := pathReader{reader:reader{text:text}, reason:reason}
    if p.peek() != mark {
        return nil, p.invalid()
    }
    p.pos++
    out := []selector{}
    for p.pos < len(text) {
        s := selector{}
        var err error
        if p.peek() == '[' {
            p.pos++
            s, err = p.selection()
        } else {
            if p.peek() != '.' {
                return nil, p.invalid()
            }
            p.pos++
            if !field && p.peek() == '.' {
                s.descendant = true
                p.pos++
            }
            descendant := s.descendant
            if !field && p.peek() == '*' {
                p.pos++
                s.kind = "all"
            } else if descendant && p.peek() == '[' {
                p.pos++
                s, err = p.selection()
            } else {
                s.kind = "key"
                s.key, err = p.identifier()
            }
            s.descendant = descendant
        }
        if err != nil {
            return nil, err
        }
        if field && s.kind != "key" && s.kind != "index" {
            return nil, p.invalid()
        }
        out = append(out, s)
    }
    return out, nil
}
func parseKey(text string) (string, error) {
    p := pathReader{reader:reader{text:text}, reason:"bad key"}
    var key string
    var err error
    if p.peek() == '\'' {
        key, err = p.string('\'')
    } else {
        key, err = p.identifier()
    }
    if err != nil || p.pos != len(text) {
        return "", p.invalid()
    }
    return key, nil
}

type step struct {
    key string
    position int
    indexed bool
}
type match struct {
    node *value
    steps []step
}
func (m match) child(i int) match {
    s := step{position:i, indexed:m.node.kind == "array"}
    if !s.indexed {
        s.key = m.node.keys[i]
    }
    steps := append(append([]step{}, m.steps...), s)
    return match{m.node.items[i], steps}
}
func (m match) location() string {
    var out strings.Builder
    out.WriteByte('$')
    for _, s := range m.steps {
        if s.indexed {
            fmt.Fprintf(&out, "[%d]", s.position)
        } else if identifier(s.key) {
            out.WriteByte('.')
            out.WriteString(s.key)
        } else {
            out.WriteByte('[')
            out.WriteString(quote(s.key, '\''))
            out.WriteByte(']')
        }
    }
    return out.String()
}
func position(v *value, s selector) int {
    if s.kind == "key" {
        if v.kind == "object" {
            return v.find(s.key)
        }
        return -1
    }
    if v.kind != "array" {
        return -1
    }
    i := s.index
    if i < 0 {
        i += int64(len(v.items))
    }
    if i < 0 || i >= int64(len(v.items)) {
        return -1
    }
    return int(i)
}
func selectValue(m match, s selector, out *[]match) {
    if s.kind == "all" {
        for i := range m.node.items {
            *out = append(*out, m.child(i))
        }
    } else if s.kind == "slice" {
        if m.node.kind != "array" {
            return
        }
        n := int64(len(m.node.items))
        clamp := func(x int64) int64 {
            if x < 0 {
                x += n
            }
            if x < 0 {
                return 0
            }
            if x > n {
                return n
            }
            return x
        }
        a, b := int64(0), n
        if s.start != nil {
            a = clamp(*s.start)
        }
        if s.end != nil {
            b = clamp(*s.end)
        }
        for i := a; i < b; i++ {
            *out = append(*out, m.child(int(i)))
        }
    } else if i := position(m.node, s); i >= 0 {
        *out = append(*out, m.child(i))
    }
}
func preorder(m match, visit func(match)) {
    visit(m)
    for i := range m.node.items {
        preorder(m.child(i), visit)
    }
}
func applySegment(matches []match, s selector) []match {
    out := []match{}
    for _, m := range matches {
        if s.descendant {
            preorder(m, func(v match) {
                selectValue(v, s, &out)
            })
        } else {
            selectValue(m, s, &out)
        }
    }
    return out
}
func evaluate(root *value, path []selector) []match {
    result := []match{{node:root}}
    for _, s := range path {
        result = applySegment(result, s)
    }
    return result
}
func fieldValue(v *value, path []selector) *value {
    for _, s := range path {
        i := position(v, s)
        if i < 0 {
            return nil
        }
        v = v.items[i]
    }
    return v
}
func compare(a, b *value) int {
    rank := func(v *value) int {
        if v == nil {
            return 3
        }
        switch v.kind {
        case "null":
            return 0
        case "number":
            return 1
        case "string":
            return 2
        }
        return 3
    }
    x, y := rank(a), rank(b)
    if x < y {
        return -1
    }
    if x > y {
        return 1
    }
    if x == 1 {
        if a.number < b.number {
            return -1
        }
        if a.number > b.number {
            return 1
        }
    }
    if x == 2 {
        return strings.Compare(a.text, b.text)
    }
    return 0
}
func holds(operator string, v, reference *value) bool {
    if operator == "EXISTS" {
        return v != nil
    }
    if operator == "==" || operator == "!=" {
        equal := v != nil && same(v, reference)
        if operator == "!=" {
            return !equal
        }
        return equal
    }
    if v == nil || v.kind != reference.kind || v.kind != "number" && v.kind != "string" {
        return false
    }
    c := compare(v, reference)
    switch operator {
    case "<":
        return c < 0
    case "<=":
        return c <= 0
    case ">":
        return c > 0
    default:
        return c >= 0
    }
}
func targetOrder(a, b match) int {
    n := len(a.steps)
    if len(b.steps) < n {
        n = len(b.steps)
    }
    for i := 0; i < n; i++ {
        if a.steps[i].position < b.steps[i].position {
            return -1
        }
        if a.steps[i].position > b.steps[i].position {
            return 1
        }
    }
    if len(a.steps) < len(b.steps) {
        return -1
    }
    if len(a.steps) > len(b.steps) {
        return 1
    }
    return 0
}
func targets(matches []match) []match {
    result := append([]match{}, matches...)
    sort.Slice(result, func(i, j int) bool {
        return targetOrder(result[i], result[j]) > 0
    })
    unique := []match{}
    for _, m := range result {
        if len(unique) == 0 || targetOrder(unique[len(unique) - 1], m) != 0 {
            unique = append(unique, m)
        }
    }
    return unique
}
func resolve(root *value, steps []step) *value {
    for _, s := range steps {
        root = root.items[s.position]
    }
    return root
}
func merge(target, patch *value) {
    for i, key := range patch.keys {
        j := target.find(key)
        if j < 0 {
            target.keys = append(target.keys, key)
            target.items = append(target.items, patch.items[i].copy())
        } else if target.items[j].kind == "object" && patch.items[i].kind == "object" {
            merge(target.items[j], patch.items[i])
        } else {
            target.items[j] = patch.items[i].copy()
        }
    }
}

type tool struct {
    document *value
    history []*value
    out *bufio.Writer
}
func (t *tool) commit(v *value) {
    t.history = append(t.history, t.document)
    t.document = v
}
func (t *tool) load(lines []string) {
    text := strings.Join(lines, "\n")
    v, err := parseJSON(text)
    if err != nil {
        e := err.(jsonError)
        before := text[:e.position]
        line := strings.Count(before, "\n") + 1
        column := e.position - strings.LastIndex(before, "\n")
        fmt.Fprintf(t.out, "PARSE ERROR line %d col %d: %s\n", line, column, e.reason)
        return
    }
    t.commit(v)
    n, d := v.size()
    fmt.Fprintf(t.out, "LOADED nodes=%d depth=%d\n", n, d)
}
func requireKind(matches []match, kind, message string) error {
    for _, m := range matches {
        if m.node.kind != kind {
            return fmt.Errorf("%s at %s", message, m.location())
        }
    }
    return nil
}
func (t *tool) execute(line string) error {
    command, argument, hasArgument := strings.Cut(line, " ")
    known := " LOAD GET COMPACT PRETTY TYPE LENGTH KEYS FLATTEN COUNT SUM MIN MAX AVG FILTER SET DELETE INSERT MERGE SORT RENAME UNDO "
    if !strings.Contains(known, " " + command + " ") {
        return fmt.Errorf("unknown command '%s'", command)
    }
    parts := []string{}
    if hasArgument {
        parts = strings.Split(argument, " ")
    }
    shape := func(minimum, maximum int) error {
        if len(parts) < minimum || len(parts) > maximum {
            return fmt.Errorf("bad arguments")
        }
        return nil
    }
    if command == "UNDO" {
        if err := shape(0, 0); err != nil {
            return err
        }
        if len(t.history) == 0 {
            return fmt.Errorf("nothing to undo")
        }
        t.document = t.history[len(t.history) - 1]
        t.history = t.history[:len(t.history) - 1]
        fmt.Fprintf(t.out, "UNDO %d\n", len(t.history))
        return nil
    }
    if command == "SET" || command == "MERGE" || command == "INSERT" {
        n := 2
        if command == "INSERT" {
            n = 3
        }
        parts = strings.SplitN(argument, " ", n)
        if !hasArgument || len(parts) != n {
            return fmt.Errorf("bad arguments")
        }
    } else if command == "FILTER" {
        parts = strings.SplitN(argument, " ", 4)
        if !hasArgument || len(parts) < 3 || parts[2] == "EXISTS" && len(parts) == 4 || parts[2] != "EXISTS" && len(parts) == 3 {
            return fmt.Errorf("bad arguments")
        }
    } else if command == "SORT" {
        if err := shape(1, 3); err != nil {
            return err
        }
        if len(parts) == 3 && (parts[1] == "DESC" || parts[2] != "DESC") {
            return fmt.Errorf("bad arguments")
        }
    } else {
        minimum, maximum := 1, 1
        if command == "COMPACT" || command == "PRETTY" || command == "FLATTEN" {
            minimum = 0
        }
        if command == "RENAME" {
            minimum, maximum = 2, 2
        }
        if err := shape(minimum, maximum); err != nil {
            return err
        }
    }
    pathText := "$"
    if len(parts) > 0 {
        pathText = parts[0]
    }
    path, err := parsePath(pathText, false)
    if err != nil {
        return err
    }
    var field []selector
    var patch *value
    var index int64
    newKey, operator := "", ""
    descending := false
    if command == "FILTER" {
        field, err = parsePath(parts[1], true)
        if err != nil {
            return err
        }
        operator = parts[2]
        if operator != "==" && operator != "!=" && operator != "<" && operator != "<=" && operator != ">" && operator != ">=" && operator != "EXISTS" {
            return fmt.Errorf("bad operator")
        }
        if operator != "EXISTS" {
            patch, err = parseJSON(parts[3])
        }
    } else if command == "SET" || command == "MERGE" {
        patch, err = parseJSON(parts[1])
    } else if command == "INSERT" {
        if !integerNotation(parts[1]) {
            return fmt.Errorf("bad index")
        }
        index, _ = strconv.ParseInt(parts[1], 10, 64)
        patch, err = parseJSON(parts[2])
    } else if command == "SORT" {
        fieldText := "@"
        if len(parts) > 1 {
            if parts[len(parts) - 1] == "DESC" {
                descending = true
            }
            if parts[1] != "DESC" {
                fieldText = parts[1]
            }
        }
        field, err = parsePath(fieldText, true)
    } else if command == "RENAME" {
        newKey, err = parseKey(parts[1])
    }
    if err != nil {
        return err
    }
    if command == "DELETE" && len(path) == 0 {
        return fmt.Errorf("cannot delete root")
    }
    if command == "MERGE" && patch.kind != "object" {
        return fmt.Errorf("merge value is not an object")
    }
    matches := evaluate(t.document, path)
    if command == "LENGTH" {
        for _, m := range matches {
            if m.node.kind != "object" && m.node.kind != "array" && m.node.kind != "string" {
                return fmt.Errorf("no length at %s", m.location())
            }
        }
    }
    required, reason := "", ""
    switch command {
    case "KEYS", "MERGE":
        required, reason = "object", "not an object"
    case "FILTER", "INSERT", "SORT":
        required, reason = "array", "not an array"
    }
    if required != "" {
        if err := requireKind(matches, required, reason); err != nil {
            return err
        }
    }
    if command == "INSERT" {
        for _, m := range matches {
            n := int64(len(m.node.items))
            if index < -n - 1 || index > n {
                return fmt.Errorf("index out of range at %s", m.location())
            }
        }
    }
    if command == "RENAME" {
        for _, m := range matches {
            if len(m.steps) == 0 || m.steps[len(m.steps) - 1].indexed {
                return fmt.Errorf("not a member at %s", m.location())
            }
        }
    }
    if command == "COUNT" {
        fmt.Fprintf(t.out, "COUNT %d\n", len(matches))
        return nil
    }
    if command == "SUM" || command == "MIN" || command == "MAX" || command == "AVG" {
        var sum, minimum, maximum int64
        count := int64(0)
        for _, m := range matches {
            if m.node.kind == "number" {
                n := m.node.number
                sum += n
                if count == 0 || n < minimum {
                    minimum = n
                }
                if count == 0 || n > maximum {
                    maximum = n
                }
                count++
            }
        }
        text := "null"
        switch command {
        case "SUM":
            text = strconv.FormatInt(sum, 10)
        case "MIN":
            if count > 0 {
                text = strconv.FormatInt(minimum, 10)
            }
        case "MAX":
            if count > 0 {
                text = strconv.FormatInt(maximum, 10)
            }
        case "AVG":
            if count > 0 {
                magnitude := sum
                if magnitude < 0 {
                    magnitude = -magnitude
                }
                q := (magnitude * 200 + count) / (2 * count)
                sign := ""
                if sum < 0 && q >= 1 {
                    sign = "-"
                }
                text = fmt.Sprintf("%s%d.%02d", sign, q / 100, q % 100)
            }
        }
        fmt.Fprintf(t.out, "%s %s\n", command, text)
        return nil
    }
    modifying := command == "SET" || command == "DELETE" || command == "INSERT" || command == "MERGE" || command == "SORT" || command == "RENAME"
    if modifying {
        if command == "SET" && len(path) == 0 {
            t.commit(patch.copy())
            fmt.Fprintln(t.out, "SET 1")
            return nil
        }
        if command == "SET" {
            matches = nil
            last := path[len(path) - 1]
            for _, parent := range evaluate(t.document, path[:len(path) - 1]) {
                if last.kind == "key" && !last.descendant && parent.node.kind == "object" {
                    i := parent.node.find(last.key)
                    if i < 0 {
                        i = len(parent.node.items)
                    }
                    steps := append(append([]step{}, parent.steps...), step{key:last.key, position:i})
                    matches = append(matches, match{steps:steps})
                } else {
                    matches = append(matches, applySegment([]match{parent}, last)... )
                }
            }
        }
        selected := targets(matches)
        document := t.document.copy()
        for _, target := range selected {
            if command == "SET" || command == "DELETE" || command == "RENAME" {
                parent := resolve(document, target.steps[:len(target.steps) - 1])
                i := target.steps[len(target.steps) - 1].position
                if command == "SET" {
                    if i == len(parent.items) {
                        parent.keys = append(parent.keys, target.steps[len(target.steps) - 1].key)
                        parent.items = append(parent.items, patch.copy())
                    } else {
                        parent.items[i] = patch.copy()
                    }
                } else if command == "DELETE" {
                    parent.items = append(parent.items[:i], parent.items[i + 1:]...)
                    if parent.kind == "object" {
                        parent.keys = append(parent.keys[:i], parent.keys[i + 1:]...)
                    }
                } else {
                    if parent.keys[i] != newKey && parent.find(newKey) >= 0 {
                        return fmt.Errorf("key exists at %s", target.location())
                    }
                    parent.keys[i] = newKey
                }
            } else {
                v := resolve(document, target.steps)
                switch command {
                case "INSERT":
                    j := index
                    if j < 0 {
                        j += int64(len(v.items)) + 1
                    }
                    i := int(j)
                    v.items = append(v.items, nil)
                    copy(v.items[i + 1:], v.items[i:])
                    v.items[i] = patch.copy()
                case "MERGE":
                    merge(v, patch)
                case "SORT":
                    sort.SliceStable(v.items, func(i, j int) bool {
                        c := compare(fieldValue(v.items[i], field), fieldValue(v.items[j], field))
                        if descending {
                            return c > 0
                        }
                        return c < 0
                    })
                }
            }
        }
        t.commit(document)
        fmt.Fprintf(t.out, "%s %d\n", command, len(selected))
        return nil
    }
    emitted := false
    for _, m := range matches {
        switch command {
        case "GET":
            fmt.Fprintf(t.out, "%s = %s\n", m.location(), compact(m.node))
        case "COMPACT":
            fmt.Fprintln(t.out, compact(m.node))
        case "PRETTY":
            fmt.Fprintln(t.out, pretty(m.node, ""))
        case "TYPE":
            fmt.Fprintf(t.out, "%s %s\n", m.location(), m.node.kind)
        case "LENGTH":
            n := len(m.node.items)
            if m.node.kind == "string" {
                n = len(m.node.text)
            }
            fmt.Fprintf(t.out, "%s %d\n", m.location(), n)
        case "KEYS":
            items := make([]string, len(m.node.keys))
            for i, k := range m.node.keys {
                items[i] = quote(k, '"')
            }
            fmt.Fprintf(t.out, "%s [%s]\n", m.location(), strings.Join(items, ","))
        case "FLATTEN":
            preorder(m, func(leaf match) {
                if len(leaf.node.items) == 0 {
                    fmt.Fprintf(t.out, "%s = %s\n", leaf.location(), compact(leaf.node))
                }
            })
        case "FILTER":
            for i := range m.node.items {
                element := m.child(i)
                if holds(operator, fieldValue(element.node, field), patch) {
                    fmt.Fprintf(t.out, "%s = %s\n", element.location(), compact(element.node))
                    emitted = true
                }
            }
            continue
        }
        emitted = true
    }
    if !emitted {
        fmt.Fprintln(t.out, "no match")
    }
    return nil
}

func main() {
    input, _ := io.ReadAll(os.Stdin)
    lines := strings.Split(string(input), "\n")
    out := bufio.NewWriter(os.Stdout)
    defer out.Flush()
    t := tool{document:&value{kind:"null"}, out:out}
    position := 0
    load := func() {
        start := position
        for lines[position] != "%%" {
            position++
        }
        t.load(lines[start:position])
        position++
    }
    load()
    for lines[position] != "END" {
        line := lines[position]
        position++
        if line == "LOAD" {
            load()
            continue
        }
        if err := t.execute(line); err != nil {
            if e, ok := err.(jsonError); ok {
                fmt.Fprintf(out, "PARSE ERROR col %d: %s\n", e.position + 1, e.reason)
            } else {
                fmt.Fprintf(out, "ERROR %s\n", err)
            }
        }
    }
}
