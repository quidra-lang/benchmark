package main

import (
    "bufio"
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

type expression struct {
    op string
    name string
    value int64
    left, right *expression
}

type expressionParser struct {
    tokens []string
    position int
}

func parseExpression(text string) *expression {
    tokens := []string{}
    for i := 0; i < len(text); {
        c := text[i]
        if c == ' ' {
            i++
            continue
        }
        start := i
        if c >= '0' && c <= '9' {
            for i < len(text) && text[i] >= '0' && text[i] <= '9' { i++ }
        } else if c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '_' {
            for i < len(text) && (text[i] >= 'a' && text[i] <= 'z' || text[i] >= 'A' && text[i] <= 'Z' || text[i] >= '0' && text[i] <= '9' || text[i] == '_') { i++ }
        } else {
            i++
            if i < len(text) && (text[start:i+1] == "||" || text[start:i+1] == "&&" || text[start:i+1] == "==" || text[start:i+1] == "!=" || text[start:i+1] == "<=" || text[start:i+1] == ">=") { i++ }
        }
        tokens = append(tokens, text[start:i])
    }
    parser := expressionParser{tokens: tokens}
    return parser.binary(0)
}

var operators = [][]string{{"||"}, {"&&"}, {"==", "!=", "<", "<=", ">", ">="}, {"+", "-"}, {"*", "/", "%"}}

func contains(items []string, value string) bool {
    for _, item := range items { if item == value { return true } }
    return false
}

func (p *expressionParser) binary(level int) *expression {
    if level == len(operators) { return p.unary() }
    result := p.binary(level+1)
    for p.position < len(p.tokens) && contains(operators[level], p.tokens[p.position]) {
        op := p.tokens[p.position]
        p.position++
        result = &expression{op: op, left: result, right: p.binary(level+1)}
    }
    return result
}

func (p *expressionParser) unary() *expression {
    token := p.tokens[p.position]
    p.position++
    if token == "!" || token == "-" { return &expression{op: "unary"+token, left: p.unary()} }
    if token == "(" {
        result := p.binary(0)
        p.position++
        return result
    }
    if token == "in" {
        p.position++
        name := p.tokens[p.position]
        p.position += 2
        return &expression{op: "in", name: name}
    }
    if token[0] >= '0' && token[0] <= '9' {
        value, _ := strconv.ParseInt(token, 10, 64)
        return &expression{op: "number", value: value}
    }
    return &expression{op: "variable", name: token}
}

type action struct {
    kind, name, text string
    delay int64
    value *expression
}

func parseActions(text string) []action {
    if text == "" { return nil }
    result := []action{}
    for _, item := range strings.Split(text, "; ") {
        var a action
        switch {
        case strings.HasPrefix(item, "raise "):
            parts := strings.SplitN(item, " ", 3)
            a.kind, a.name = "raise", parts[1]
            if len(parts) == 3 { a.value = parseExpression(parts[2]) }
        case strings.HasPrefix(item, "send "):
            parts := strings.SplitN(item, " ", 4)
            a.kind, a.name = "send", parts[1]
            a.delay, _ = strconv.ParseInt(parts[2], 10, 64)
            if len(parts) == 4 { a.value = parseExpression(parts[3]) }
        case strings.HasPrefix(item, "cancel "):
            a.kind, a.name = "cancel", item[7:]
        case strings.HasPrefix(item, "log "):
            a.kind = "log"
            tail := item[4:]
            if tail[0] == '"' {
                end := strings.IndexByte(tail[1:], '"')+1
                a.text = tail[1:end]
                if end+1 < len(tail) { a.value = parseExpression(tail[end+2:]) }
            } else { a.value = parseExpression(tail) }
        default:
            parts := strings.SplitN(item, " = ", 2)
            a.kind, a.name, a.value = "assign", parts[0], parseExpression(parts[1])
        }
        result = append(result, a)
    }
    return result
}

type state struct {
    name, kind, initialName, defaultName string
    parent, depth, initial, defaultTarget int
    deep bool
    children, childStates []int
    entries, exits [][]action
    transitions []*transition
    entered, taken, dwell, entryTime int64
}

type transition struct {
    id, source, target int
    kind, mode string
    descriptors []string
    delay int64
    guard *expression
    actions []action
}

type definition struct {
    text, kind string
    line, state int
    error string
}

type event struct { name string; value int64 }
type reservation struct { due, order int64; timer *transition; event event }
type trigger struct { kind string; timer *transition; event event }
type selected struct { transition *transition; scope int; exits []bool }

type chart struct {
    out *bufio.Writer
    states []*state
    names map[string]int
    variables map[string]int64
    variableNames []string
    transitions []*transition
    document []int
    active []bool
    history map[int][]int
    queue []event
    queueHead int
    reservations []reservation
    time, creation, data, macrosteps, microsteps int64
    trace, halted bool
}

func newChart(out *bufio.Writer) *chart {
    return &chart{out: out, states: []*state{{kind: "root"}}, names: map[string]int{}, variables: map[string]int64{}, history: map[int][]int{}}
}

func (c *chart) reference(e *expression) string {
    if e == nil { return "" }
    if e.op == "variable" && e.name != "_data" {
        if _, exists := c.variables[e.name]; !exists { return "unknown variable "+e.name }
    }
    if e.op == "in" {
        if _, exists := c.names[e.name]; !exists { return "unknown state "+e.name }
    }
    if result := c.reference(e.left); result != "" { return result }
    return c.reference(e.right)
}

func (c *chart) actionReferences(actions []action) string {
    for _, a := range actions {
        if a.kind == "assign" {
            if _, exists := c.variables[a.name]; !exists { return "unknown variable "+a.name }
        }
        if result := c.reference(a.value); result != "" { return result }
    }
    return ""
}

func (c *chart) parseTransition(text string) *transition {
    parts := strings.SplitN(text, " ", 3)
    t := &transition{id: len(c.transitions), source: c.names[parts[1]], target: -1, mode: "internal"}
    tail := parts[2]
    bracket := 0
    for i := 0; i+2 < len(tail); i++ {
        if tail[i] == '[' { bracket++ }
        if tail[i] == ']' { bracket-- }
        if bracket == 0 && tail[i:i+3] == " / " {
            t.actions = parseActions(tail[i+3:])
            tail = tail[:i]
            break
        }
    }
    if start := strings.Index(tail, " ["); start >= 0 {
        end := strings.IndexByte(tail[start+2:], ']')+start+2
        t.guard = parseExpression(tail[start+2:end])
        tail = tail[:start]+tail[end+1:]
    }
    for _, arrow := range []string{" -> ", " ~> "} {
        if index := strings.Index(tail, arrow); index >= 0 {
            t.mode = "external"
            if arrow == " ~> " { t.mode = "local" }
            target := tail[index+4:]
            if id, exists := c.names[target]; exists { t.target = id } else { t.target = -2; t.descriptors = []string{target} }
            tail = tail[:index]
            break
        }
    }
    if tail == "always" { t.kind = "always" } else if strings.HasPrefix(tail, "after ") {
        t.kind = "timer"
        t.delay, _ = strconv.ParseInt(tail[6:], 10, 64)
    } else {
        t.kind = "event"
        if t.target != -2 { t.descriptors = strings.Split(tail, "|") }
    }
    return t
}

func (c *chart) define(definitions []*definition) bool {
    for _, d := range definitions {
        fields := strings.Fields(d.text)
        d.kind, d.state = fields[0], -1
        if contains([]string{"state", "parallel", "final", "history"}, d.kind) {
            name := fields[1]
            if _, exists := c.names[name]; exists { d.error = "duplicate state "+name; continue }
            parentName := ""
            if len(fields) > 2 && fields[2] != "initial" { parentName = fields[2] }
            parent := 0
            if parentName != "" {
                var exists bool
                parent, exists = c.names[parentName]
                if !exists { d.error = "unknown state "+parentName; continue }
                if c.states[parent].kind == "final" || c.states[parent].kind == "history" { d.error = parentName+" cannot have children"; continue }
            }
            s := &state{name: name, kind: d.kind, parent: parent, depth: c.states[parent].depth+1}
            if d.kind == "state" {
                for i := 2; i < len(fields); i++ { if fields[i] == "initial" { s.initialName = fields[i+1]; break } }
            }
            if d.kind == "history" {
                s.deep = fields[3] == "deep"
                if len(fields) == 5 { s.defaultName = fields[4] }
            }
            d.state = len(c.states)
            c.names[name] = d.state
            c.states = append(c.states, s)
            c.states[parent].children = append(c.states[parent].children, d.state)
            if s.kind != "history" { c.states[parent].childStates = append(c.states[parent].childStates, d.state) }
        } else if d.kind == "var" {
            if _, exists := c.variables[fields[1]]; exists { d.error = "duplicate variable "+fields[1] } else {
                c.variables[fields[1]], _ = strconv.ParseInt(fields[2], 10, 64)
                c.variableNames = append(c.variableNames, fields[1])
            }
        }
    }
    for _, d := range definitions {
        if d.error != "" { continue }
        fields := strings.Fields(d.text)
        switch d.kind {
        case "state":
            s := c.states[d.state]
            if s.initialName != "" {
                child, exists := c.names[s.initialName]
                if !exists { d.error = "unknown state "+s.initialName } else if c.states[child].parent != d.state || c.states[child].kind == "history" { d.error = s.initialName+" is not a child of "+s.name }
            }
        case "final", "history":
            s := c.states[d.state]
            parent := c.states[s.parent]
            if parent.kind != "state" || len(parent.childStates) == 0 { d.error = s.name+" needs a compound parent" } else if s.kind == "history" && s.defaultName != "" {
                target, exists := c.names[s.defaultName]
                if !exists { d.error = "unknown state "+s.defaultName } else if !c.descendant(target, s.parent) || c.states[target].kind == "history" { d.error = s.defaultName+" is not a descendant of "+parent.name }
            }
        case "entry", "exit":
            id, exists := c.names[fields[1]]
            if !exists { d.error = "unknown state "+fields[1] } else if c.states[id].kind == "history" { d.error = fields[1]+" cannot have actions" } else {
                actions := parseActions(d.text[strings.Index(d.text, " / ")+3:])
                d.error = c.actionReferences(actions)
                if d.error == "" {
                    if d.kind == "entry" { c.states[id].entries = append(c.states[id].entries, actions) } else { c.states[id].exits = append(c.states[id].exits, actions) }
                }
            }
        case "on":
            id, exists := c.names[fields[1]]
            if !exists { d.error = "unknown state "+fields[1] } else if c.states[id].kind == "final" || c.states[id].kind == "history" { d.error = fields[1]+" cannot have transitions" } else {
                t := c.parseTransition(d.text)
                d.error = c.reference(t.guard)
                if d.error == "" && t.target == -2 { d.error = "unknown state "+t.descriptors[0] }
                if d.error == "" { d.error = c.actionReferences(t.actions) }
                if d.error == "" {
                    c.transitions = append(c.transitions, t)
                    c.states[id].transitions = append(c.states[id].transitions, t)
                }
            }
        }
    }
    valid := true
    for _, d := range definitions { if d.error != "" { fmt.Fprintf(c.out, "error line %d: %s\n", d.line, d.error); valid = false } }
    if !valid { return false }
    for _, s := range c.states {
        if len(s.childStates) > 0 {
            s.initial = s.childStates[0]
            if s.initialName != "" { s.initial = c.names[s.initialName] }
        }
    }
    for _, s := range c.states {
        if s.kind == "history" {
            s.defaultTarget = c.states[s.parent].initial
            if s.defaultName != "" { s.defaultTarget = c.names[s.defaultName] }
        }
    }
    var visit func(int)
    visit = func(id int) { c.document = append(c.document, id); for _, child := range c.states[id].children { visit(child) } }
    for _, child := range c.states[0].children { visit(child) }
    sort.Strings(c.variableNames)
    c.active = make([]bool, len(c.states))
    return true
}

func (c *chart) descendant(id, ancestor int) bool {
    for id != 0 { id = c.states[id].parent; if id == ancestor { return true } }
    return false
}

func (c *chart) compound(id int) bool { return id == 0 || c.states[id].kind == "state" && len(c.states[id].childStates) > 0 }
func (c *chart) parallel(id int) bool { return c.states[id].kind == "parallel" && len(c.states[id].childStates) > 0 }

func (c *chart) warn() {
    reachable := make([]bool, len(c.states))
    reachable[c.states[0].initial] = true
    changed := true
    for changed {
        changed = false
        add := func(id int) { if id != 0 && !reachable[id] { reachable[id] = true; changed = true } }
        for _, id := range c.document {
            if !reachable[id] { continue }
            s := c.states[id]
            add(s.parent)
            if c.compound(id) { add(s.initial) }
            if c.parallel(id) { for _, child := range s.childStates { add(child) } }
            for _, t := range s.transitions {
                if t.target >= 0 {
                    target := t.target
                    if c.states[target].kind == "history" { target = c.states[target].defaultTarget }
                    add(target)
                }
            }
        }
    }
    for _, id := range c.document { if c.states[id].kind != "history" && !reachable[id] { fmt.Fprintf(c.out, "warning: unreachable state %s\n", c.states[id].name) } }
}

func truth(value bool) int64 { if value { return 1 }; return 0 }

func (c *chart) evaluate(e *expression) (int64, bool) {
    switch e.op {
    case "number": return e.value, true
    case "variable": if e.name == "_data" { return c.data, true }; return c.variables[e.name], true
    case "in": return truth(c.active[c.names[e.name]]), true
    }
    a, ok := c.evaluate(e.left)
    if !ok { return 0, false }
    if e.op == "unary!" { return truth(a == 0), true }
    if e.op == "unary-" { return -a, true }
    if e.op == "&&" && a == 0 { return 0, true }
    if e.op == "||" && a != 0 { return 1, true }
    b, ok := c.evaluate(e.right)
    if !ok { return 0, false }
    switch e.op {
    case "+": return a+b, true
    case "-": return a-b, true
    case "*": return a*b, true
    case "/": if b == 0 { return 0, false }; return a/b, true
    case "%": if b == 0 { return 0, false }; return a%b, true
    case "==": return truth(a == b), true
    case "!=": return truth(a != b), true
    case "<": return truth(a < b), true
    case "<=": return truth(a <= b), true
    case ">": return truth(a > b), true
    case ">=": return truth(a >= b), true
    case "&&": return truth(b != 0), true
    default: return truth(b != 0), true
    }
}

func (c *chart) reserve(r reservation) {
    c.creation++
    r.order = c.creation
    c.reservations = append(c.reservations, r)
}

func (c *chart) perform(actions []action) {
    for _, a := range actions {
        value := int64(0)
        if a.value != nil {
            var ok bool
            value, ok = c.evaluate(a.value)
            if !ok { c.queue = append(c.queue, event{"error.execution", 0}); return }
        }
        switch a.kind {
        case "assign": c.variables[a.name] = value
        case "raise": c.queue = append(c.queue, event{a.name, value})
        case "send": c.reserve(reservation{due: c.time+a.delay, event: event{a.name, value}})
        case "cancel":
            kept := c.reservations[:0]
            for _, r := range c.reservations { if r.timer != nil || r.event.name != a.name { kept = append(kept, r) } }
            c.reservations = kept
        case "log":
            if a.value != nil { fmt.Fprintf(c.out, "%s%d\n", a.text, value) } else { fmt.Fprintln(c.out, a.text) }
        }
    }
}

func (c *chart) targets(t *transition) []int {
    if c.states[t.target].kind != "history" { return []int{t.target} }
    if recorded, exists := c.history[t.target]; exists { return recorded }
    return []int{c.states[t.target].defaultTarget}
}

func (c *chart) transitionSet(t *transition) selected {
    result := selected{transition: t, exits: make([]bool, len(c.states))}
    if t.mode == "internal" { return result }
    targets := c.targets(t)
    containsTargets := func(id int) bool { for _, target := range targets { if !c.descendant(target, id) { return false } }; return true }
    if t.mode == "local" && c.compound(t.source) && containsTargets(t.source) { result.scope = t.source } else {
        id := c.states[t.source].parent
        for !(c.compound(id) && containsTargets(id)) { id = c.states[id].parent }
        result.scope = id
    }
    for _, id := range c.document { result.exits[id] = c.active[id] && c.descendant(id, result.scope) }
    return result
}

func matches(t *transition, tr trigger) bool {
    if t.kind != tr.kind { return false }
    if tr.kind == "always" { return true }
    if tr.kind == "timer" { return t == tr.timer }
    for _, descriptor := range t.descriptors {
        if descriptor == "*" || descriptor == tr.event.name || strings.HasPrefix(tr.event.name, descriptor+".") { return true }
    }
    return false
}

func (c *chart) selectTransitions(tr trigger) []selected {
    result := []selected{}
    seen := map[*transition]bool{}
    occupied := make([]bool, len(c.states))
    for _, atomic := range c.document {
        if !c.active[atomic] || len(c.states[atomic].childStates) != 0 { continue }
        var found *transition
        for id := atomic; id != 0 && found == nil; id = c.states[id].parent {
            for _, t := range c.states[id].transitions {
                if !matches(t, tr) { continue }
                value, ok := int64(1), true
                if t.guard != nil { value, ok = c.evaluate(t.guard) }
                if !ok { c.queue = append(c.queue, event{"error.execution", 0}) } else if value != 0 { found = t; break }
            }
        }
        if found == nil || seen[found] { continue }
        seen[found] = true
        item := c.transitionSet(found)
        conflict := false
        for _, id := range c.document { if item.exits[id] && occupied[id] { conflict = true; break } }
        if !conflict {
            result = append(result, item)
            for _, id := range c.document { occupied[id] = occupied[id] || item.exits[id] }
        }
    }
    return result
}

func (c *chart) expand(entries []bool) {
    changed := true
    for changed {
        changed = false
        add := func(id int) { if !entries[id] { entries[id] = true; changed = true } }
        for _, id := range c.document {
            if !entries[id] { continue }
            if c.parallel(id) { for _, child := range c.states[id].childStates { add(child) } } else if c.compound(id) {
                hasChild := false
                for _, child := range c.states[id].childStates { if entries[child] { hasChild = true; break } }
                if !hasChild { add(c.states[id].initial) }
            }
        }
    }
}

func (c *chart) complete(id int) bool {
    if c.compound(id) {
        for _, child := range c.states[id].childStates { if c.states[child].kind == "final" && c.active[child] { return true } }
    } else if c.parallel(id) {
        for _, child := range c.states[id].childStates { if !c.complete(child) { return false } }
        return true
    }
    return false
}

func (c *chart) enter(entries []bool) {
    for _, id := range c.document {
        if !entries[id] { continue }
        s := c.states[id]
        c.active[id] = true
        s.entered++
        s.entryTime = c.time
        for _, t := range s.transitions { if t.kind == "timer" { c.reserve(reservation{due: c.time+t.delay, timer: t}) } }
        for _, actions := range s.entries { c.perform(actions) }
        if s.kind == "final" {
            parent := s.parent
            c.queue = append(c.queue, event{"done.state."+c.states[parent].name, 0})
            grandparent := c.states[parent].parent
            if c.parallel(grandparent) && c.complete(grandparent) { c.queue = append(c.queue, event{"done.state."+c.states[grandparent].name, 0}) }
        }
    }
}

func (c *chart) list(set []bool, reverse bool) string {
    names := []string{}
    if reverse {
        for i := len(c.document)-1; i >= 0; i-- { id := c.document[i]; if set[id] { names = append(names, c.states[id].name) } }
    } else { for _, id := range c.document { if set[id] { names = append(names, c.states[id].name) } } }
    if len(names) == 0 { return "-" }
    return strings.Join(names, ",")
}

func (c *chart) microstep(tr trigger, transitions []selected) {
    exits := make([]bool, len(c.states))
    for _, item := range transitions { for _, id := range c.document { exits[id] = exits[id] || item.exits[id] } }
    for _, id := range c.document {
        h := c.states[id]
        if h.kind != "history" || !exits[h.parent] { continue }
        recorded := []int{}
        for _, candidate := range c.document {
            if c.active[candidate] && (h.deep && len(c.states[candidate].childStates) == 0 && c.descendant(candidate, h.parent) || !h.deep && c.states[candidate].parent == h.parent) { recorded = append(recorded, candidate) }
        }
        c.history[id] = recorded
    }
    entries := make([]bool, len(c.states))
    for _, item := range transitions {
        if item.transition.mode == "internal" { continue }
        for _, target := range c.targets(item.transition) {
            entries[target] = true
            for parent := c.states[target].parent; parent != 0 && c.descendant(parent, item.scope); parent = c.states[parent].parent { entries[parent] = true }
        }
    }
    c.expand(entries)
    if c.trace {
        sources := []string{}
        for _, item := range transitions { sources = append(sources, c.states[item.transition.source].name) }
        display := "always"
        if tr.kind == "timer" { display = fmt.Sprintf("after(%d)@%s", tr.timer.delay, c.states[tr.timer.source].name) } else if tr.kind == "event" {
            display = tr.event.name
            if tr.event.value != 0 { display += "="+strconv.FormatInt(tr.event.value, 10) }
        }
        fmt.Fprintf(c.out, "[t=%d] %s (%s): exit %s; enter %s\n", c.time, display, strings.Join(sources, ","), c.list(exits, true), c.list(entries, false))
    }
    for i := len(c.document)-1; i >= 0; i-- {
        id := c.document[i]
        if !exits[id] { continue }
        s := c.states[id]
        for _, actions := range s.exits { c.perform(actions) }
        c.active[id] = false
        s.dwell += c.time-s.entryTime
        kept := c.reservations[:0]
        for _, r := range c.reservations { if r.timer == nil || r.timer.source != id { kept = append(kept, r) } }
        c.reservations = kept
    }
    for _, item := range transitions { c.perform(item.transition.actions); c.states[item.transition.source].taken++ }
    c.enter(entries)
}

func (c *chart) macrostep(start bool, tr trigger) {
    c.macrosteps++
    count := 0
    perform := func(tr trigger, transitions []selected) bool {
        if len(transitions) == 0 { return true }
        if count == 1000 { fmt.Fprintf(c.out, "LIVELOCK t=%d\n", c.time); c.halted = true; return false }
        count++
        c.microsteps++
        c.microstep(tr, transitions)
        return true
    }
    c.data = 0
    if start {
        entries := make([]bool, len(c.states))
        entries[c.states[0].initial] = true
        c.expand(entries)
        c.enter(entries)
    } else {
        if tr.kind == "event" { c.data = tr.event.value }
        if !perform(tr, c.selectTransitions(tr)) { return }
    }
    for {
        c.data = 0
        always := trigger{kind: "always"}
        transitions := c.selectTransitions(always)
        if len(transitions) > 0 {
            if !perform(always, transitions) { return }
            continue
        }
        if c.queueHead == len(c.queue) { return }
        e := c.queue[c.queueHead]
        c.queueHead++
        c.data = e.value
        next := trigger{kind: "event", event: e}
        if !perform(next, c.selectTransitions(next)) { return }
    }
}

func reservationLess(a, b reservation) bool { return a.due < b.due || a.due == b.due && a.order < b.order }

func (c *chart) dump() {
    fmt.Fprintf(c.out, "dump t=%d\n", c.time)
    for _, id := range c.document { if c.active[id] { fmt.Fprintf(c.out, "%s%s\n", strings.Repeat(" ", 2*c.states[id].depth), c.states[id].name) } }
    for _, name := range c.variableNames { fmt.Fprintf(c.out, "  var %s = %d\n", name, c.variables[name]) }
    for _, id := range c.document {
        if recorded, exists := c.history[id]; exists {
            names := []string{}
            for _, target := range recorded { names = append(names, c.states[target].name) }
            list := strings.Join(names, ",")
            if list == "" { list = "-" }
            fmt.Fprintf(c.out, "  history %s = %s\n", c.states[id].name, list)
        }
    }
    reservations := append([]reservation(nil), c.reservations...)
    sort.Slice(reservations, func(i, j int) bool { return reservationLess(reservations[i], reservations[j]) })
    for _, r := range reservations {
        if r.timer != nil { fmt.Fprintf(c.out, "  timer %d after(%d)@%s\n", r.due, r.timer.delay, c.states[r.timer.source].name) } else { fmt.Fprintf(c.out, "  send %d %s %d\n", r.due, r.event.name, r.event.value) }
    }
}

func (c *chart) script(text string) {
    if c.halted { return }
    fields := strings.Fields(text)
    switch fields[0] {
    case "event":
        e := event{name: fields[1]}
        if len(fields) == 3 { e.value, _ = strconv.ParseInt(fields[2], 10, 64) }
        c.macrostep(false, trigger{kind: "event", event: e})
    case "tick":
        amount, _ := strconv.ParseInt(fields[1], 10, 64)
        finish := c.time+amount
        for !c.halted {
            best := -1
            for i, r := range c.reservations { if r.due <= finish && (best < 0 || reservationLess(r, c.reservations[best])) { best = i } }
            if best < 0 { break }
            r := c.reservations[best]
            c.reservations = append(c.reservations[:best], c.reservations[best+1:]...)
            c.time = r.due
            tr := trigger{kind: "event", event: r.event}
            if r.timer != nil { tr.kind, tr.timer = "timer", r.timer }
            c.macrostep(false, tr)
        }
        if !c.halted { c.time = finish }
    case "set":
        if _, exists := c.variables[fields[1]]; exists { c.variables[fields[1]], _ = strconv.ParseInt(fields[2], 10, 64) } else { fmt.Fprintf(c.out, "error: unknown variable %s\n", fields[1]) }
    case "trace": c.trace = fields[1] == "on"
    case "eval":
        raw := text[5:]
        e := parseExpression(raw)
        if problem := c.reference(e); problem != "" { fmt.Fprintf(c.out, "error: %s\n", problem) } else {
            c.data = 0
            if value, ok := c.evaluate(e); ok { fmt.Fprintf(c.out, "%s -> %d\n", raw, value) } else { fmt.Fprintln(c.out, "error: division by zero") }
        }
    case "dump": c.dump()
    }
}

func (c *chart) statistics() {
    fmt.Fprintf(c.out, "end t=%d macrosteps=%d microsteps=%d\n", c.time, c.macrosteps, c.microsteps)
    for _, id := range c.document {
        s := c.states[id]
        if s.kind == "history" { continue }
        dwell := s.dwell
        if c.active[id] { dwell += c.time-s.entryTime }
        fmt.Fprintf(c.out, "  %s entered=%d taken=%d time=%d\n", s.name, s.entered, s.taken, dwell)
    }
}

func main() {
    scanner := bufio.NewScanner(os.Stdin)
    out := bufio.NewWriter(os.Stdout)
    defer out.Flush()
    scanner.Scan()
    charts, _ := strconv.Atoi(scanner.Text())
    line := 1
    for chartIndex := 0; chartIndex < charts; chartIndex++ {
        scanner.Scan()
        line++
        name := scanner.Text()[6:]
        fmt.Fprintf(out, "chart %s\n", name)
        definitions := []*definition{}
        for scanner.Scan() {
            line++
            if scanner.Text() == "RUN" { break }
            definitions = append(definitions, &definition{text: scanner.Text(), line: line})
        }
        c := newChart(out)
        valid := c.define(definitions)
        if valid { c.warn(); c.macrostep(true, trigger{}) }
        for scanner.Scan() {
            line++
            if scanner.Text() == "END" { break }
            if valid { c.script(scanner.Text()) }
        }
        if valid { c.statistics() }
    }
}
