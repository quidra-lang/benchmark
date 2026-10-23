package main

import (
    "bufio"
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

type value struct {
    integer bool
    number int64
    symbol string
}
type term struct {
    kind string
    name string
    value value
}
type expression struct {
    kind, operator string
    term term
    left, right *expression
}
type atom struct { name string; terms []term }
type literal struct { kind, operator string; atom atom; left, right *expression }
type statement struct {
    kind, name, aggregate, variable string
    head *atom
    body []literal
    number int
}
type token struct { kind, text string; number int64 }
type problem string
func fail(format string, args ...any) { panic(problem(fmt.Sprintf(format, args...))) }
var reserved = strings.Fields("not mod count sum min max retract dump why forget listing strata stats check predicates undo halt")
func contains(items []string, text string) bool { for _, item := range items { if item == text { return true } }; return false }
func lower(c byte) bool { return c >= 'a' && c <= 'z' }
func upper(c byte) bool { return c >= 'A' && c <= 'Z' }
func digit(c byte) bool { return c >= '0' && c <= '9' }
func wordCharacter(c byte) bool { return lower(c) || upper(c) || digit(c) || c == '_' }
func lexical(line string) []token {
    result := []token{}
    for i := 0; i < len(line); {
        if line[i] == ' ' { i++; continue }
        if line[i] == '%' { break }
        start := i
        if line[i] == '"' {
            i++
            for i < len(line) && line[i] != '"' { i++ }
            if i == len(line) { fail("unterminated string") }
            i++
            result = append(result, token{kind:"string", text:line[start:i]})
            continue
        }
        if i+1 < len(line) && contains([]string{":-", "?-", "!=", "<=", ">="}, line[i:i+2]) {
            result = append(result, token{kind:line[i:i+2], text:line[i:i+2]})
            i += 2
            continue
        }
        if strings.ContainsRune("(),.:=<>+-*/", rune(line[i])) {
            result = append(result, token{kind:line[i:i+1], text:line[i:i+1]})
            i++
            continue
        }
        if !wordCharacter(line[i]) { fail("bad character '%c'", line[i]) }
        for i < len(line) && wordCharacter(line[i]) { i++ }
        text := line[start:i]
        item := token{text:text}
        switch {
        case lower(text[0]):
            item.kind = "name"
            if contains(reserved, text) { item.kind = text }
        case upper(text[0]): item.kind = "variable"
        case text == "_": item.kind = "anonymous"
        default:
            allDigits := true
            for j := range text { if !digit(text[j]) { allDigits = false } }
            if !allDigits { fail("bad token '%s'", text) }
            item.kind = "integer"
            item.number, _ = strconv.ParseInt(text, 10, 64)
            if item.number > 1000000000 { fail("integer out of range '%s'", text) }
        }
        result = append(result, item)
    }
    return result
}
type parser struct { tokens []token; position int }
func (p *parser) peek() string { if p.position == len(p.tokens) { return "end" }; return p.tokens[p.position].kind }
func (p *parser) invalid() { if p.peek() == "end" { fail("syntax error at end of line") }; fail("syntax error at '%s'", p.tokens[p.position].text) }
func (p *parser) take(kind string) token {
    if p.peek() != kind { p.invalid() }
    item := p.tokens[p.position]
    p.position++
    return item
}
func (p *parser) term() term {
    switch p.peek() {
    case "name": return term{kind:"constant", value:value{symbol:p.take("name").text}}
    case "string": text := p.take("string").text; return term{kind:"constant", value:value{symbol:text[1:len(text)-1]}}
    case "integer": return term{kind:"constant", value:value{integer:true, number:p.take("integer").number}}
    case "-": p.take("-"); return term{kind:"constant", value:value{integer:true, number:-p.take("integer").number}}
    case "variable": return term{kind:"variable", name:p.take("variable").text}
    case "anonymous": p.take("anonymous"); return term{kind:"anonymous"}
    }
    p.invalid()
    return term{}
}
func (p *parser) atom() atom {
    result := atom{name:p.take("name").text}
    if p.peek() == "(" {
        p.take("(")
        result.terms = append(result.terms, p.term())
        for p.peek() == "," { p.take(","); result.terms = append(result.terms, p.term()) }
        p.take(")")
    }
    return result
}
func (p *parser) factor() *expression {
    if p.peek() == "(" {
        p.take("(")
        inside := p.expression()
        p.take(")")
        return &expression{kind:"group", left:inside}
    }
    return &expression{kind:"term", term:p.term()}
}
func (p *parser) product() *expression {
    result := p.factor()
    for contains([]string{"*", "/", "mod"}, p.peek()) {
        operator := p.take(p.peek()).kind
        result = &expression{kind:"operation", operator:operator, left:result, right:p.factor()}
    }
    return result
}
func (p *parser) expression() *expression {
    result := p.product()
    for p.peek() == "+" || p.peek() == "-" {
        operator := p.take(p.peek()).kind
        result = &expression{kind:"operation", operator:operator, left:result, right:p.product()}
    }
    return result
}
func (p *parser) literal() literal {
    if p.peek() == "not" { p.take("not"); return literal{kind:"negative", atom:p.atom()} }
    if p.peek() == "name" {
        next := "end"
        if p.position+1 < len(p.tokens) { next = p.tokens[p.position+1].kind }
        if !contains([]string{"=", "!=", "<", "<=", ">", ">=", "+", "-", "*", "/", "mod"}, next) {
            return literal{kind:"positive", atom:p.atom()}
        }
    }
    left := p.expression()
    if !contains([]string{"=", "!=", "<", "<=", ">", ">="}, p.peek()) { p.invalid() }
    operator := p.take(p.peek()).kind
    return literal{kind:"comparison", operator:operator, left:left, right:p.expression()}
}
func (p *parser) body() []literal {
    result := []literal{p.literal()}
    for p.peek() == "," { p.take(","); result = append(result, p.literal()) }
    return result
}
func (p *parser) statement() statement {
    result := statement{}
    switch p.peek() {
    case "name":
        head := p.atom()
        result.head, result.kind = &head, "fact"
        if p.peek() == ":-" { p.take(":-"); result.kind, result.body = "rule", p.body() }
    case ":-": p.take(":-"); result.kind, result.body = "constraint", p.body()
    case "?-":
        p.take("?-")
        result.kind = "query"
        if contains([]string{"count", "sum", "min", "max"}, p.peek()) {
            result.aggregate = p.take(p.peek()).kind
            if result.aggregate != "count" { result.variable = p.take("variable").text; p.take(":") }
        }
        result.body = p.body()
    case "retract", "why":
        result.kind = p.take(p.peek()).kind
        head := p.atom()
        result.head = &head
    case "dump": result.kind = p.take("dump").kind; result.name = p.take("name").text
    case "forget": result.kind = p.take("forget").kind; result.number = int(p.take("integer").number)
    case "listing": result.kind = p.take("listing").kind; if p.peek() == "name" { result.name = p.take("name").text }
    case "strata", "stats", "check", "predicates", "undo", "halt": result.kind = p.take(p.peek()).kind
    default: p.invalid()
    }
    p.take(".")
    if p.peek() != "end" { p.invalid() }
    return result
}

func compareValue(a, b value) int {
    if a.integer != b.integer { if a.integer { return -1 }; return 1 }
    if a.integer { if a.number < b.number { return -1 }; if a.number > b.number { return 1 }; return 0 }
    return strings.Compare(a.symbol, b.symbol)
}
func compareTuple(a, b []value) int { for i := range a { if c := compareValue(a[i], b[i]); c != 0 { return c } }; return 0 }
func notation(v value) string {
    if v.integer { return strconv.FormatInt(v.number, 10) }
    simple := len(v.symbol) > 0 && lower(v.symbol[0]) && !contains(reserved, v.symbol)
    for i := range v.symbol { if !wordCharacter(v.symbol[i]) { simple = false } }
    if simple { return v.symbol }
    return "\""+v.symbol+"\""
}
func termText(t term, assignment map[string]value) string {
    if t.kind == "constant" { return notation(t.value) }
    if t.kind == "anonymous" { return "_" }
    if assignment != nil { return notation(assignment[t.name]) }
    return t.name
}
func atomText(a atom, assignment map[string]value) string {
    if len(a.terms) == 0 { return a.name }
    parts := []string{}
    for _, t := range a.terms { parts = append(parts, termText(t, assignment)) }
    return a.name+"("+strings.Join(parts, ", ")+")"
}
func expressionText(e *expression, assignment map[string]value) string {
    if e.kind == "term" { return termText(e.term, assignment) }
    if e.kind == "group" { return "("+expressionText(e.left, assignment)+")" }
    return expressionText(e.left, assignment)+" "+e.operator+" "+expressionText(e.right, assignment)
}
func literalText(l literal, assignment map[string]value) string {
    if l.kind == "comparison" { return expressionText(l.left, assignment)+" "+l.operator+" "+expressionText(l.right, assignment) }
    prefix := ""
    if l.kind == "negative" { prefix = "not " }
    return prefix+atomText(l.atom, assignment)
}
func ruleText(s statement) string {
    parts := []string{}
    for _, l := range s.body { parts = append(parts, literalText(l, nil)) }
    prefix := ":- "
    if s.head != nil { prefix = atomText(*s.head, nil)+" :- " }
    return prefix+strings.Join(parts, ", ")+"."
}
func expressionTerms(e *expression) []term {
    if e.kind == "term" { return []term{e.term} }
    result := expressionTerms(e.left)
    if e.kind == "operation" { result = append(result, expressionTerms(e.right)...) }
    return result
}
func literalTerms(l literal) []term {
    if l.kind != "comparison" { return l.atom.terms }
    return append(expressionTerms(l.left), expressionTerms(l.right)...)
}
func allTerms(s statement) []term {
    result := []term{}
    if s.head != nil { result = append(result, s.head.terms...) }
    for _, l := range s.body { result = append(result, literalTerms(l)...) }
    return result
}
func variables(terms []term) []string {
    result := []string{}
    for _, t := range terms { if t.kind == "variable" && !contains(result, t.name) { result = append(result, t.name) } }
    return result
}
func tupleKey(tuple []value) string {
    var out strings.Builder
    for _, v := range tuple {
        if v.integer { fmt.Fprintf(&out, "i%d;", v.number) } else { fmt.Fprintf(&out, "s%d:%s", len(v.symbol), v.symbol) }
    }
    return out.String()
}
type tuple struct { values []value; round, rule int }
type predicate struct { arity int; facts map[string][]value }
type rule struct { number int; statement statement }
type snapshot struct { predicates map[string]*predicate; rules []rule; line int }
type database struct { predicates map[string]*predicate; rules []rule; history []snapshot; next int }
func newDatabase() *database { return &database{predicates:map[string]*predicate{}, next:1} }
func sortedPredicates(predicates map[string]*predicate) []string {
    result := []string{}
    for name := range predicates { result = append(result, name) }
    sort.Strings(result)
    return result
}
func (d *database) save(line int) {
    predicates := map[string]*predicate{}
    for name, p := range d.predicates {
        copy := &predicate{arity:p.arity, facts:map[string][]value{}}
        for key, tuple := range p.facts { copy.facts[key] = tuple }
        predicates[name] = copy
    }
    d.history = append(d.history, snapshot{predicates, append([]rule(nil), d.rules...), line})
}
func atoms(s statement) []atom {
    result := []atom{}
    if s.head != nil { result = append(result, *s.head) }
    for _, l := range s.body { if l.kind != "comparison" { result = append(result, l.atom) } }
    return result
}
func (d *database) checkPredicates(s statement, clause bool) map[string]int {
    arities := map[string]int{}
    for name, p := range d.predicates { arities[name] = p.arity }
    for _, a := range atoms(s) {
        expected, known := arities[a.name]
        if !known && !clause { fail("unknown predicate %s", a.name) }
        if known && expected != len(a.terms) { fail("arity mismatch for %s: expected %d, got %d", a.name, expected, len(a.terms)) }
        arities[a.name] = len(a.terms)
    }
    return arities
}
func safety(s statement) {
    if s.head != nil { for _, t := range s.head.terms { if t.kind == "anonymous" { fail("anonymous variable in head") } } }
    bound := []string{}
    for _, l := range s.body {
        if l.kind == "comparison" { for _, t := range literalTerms(l) { if t.kind == "anonymous" { fail("anonymous variable in comparison") } } }
        if l.kind == "positive" { bound = append(bound, variables(l.atom.terms)...) }
    }
    checked := []term{}
    if s.head != nil { checked = append(checked, s.head.terms...) }
    if s.aggregate != "" && s.aggregate != "count" { checked = append(checked, term{kind:"variable", name:s.variable}) }
    for _, l := range s.body { if l.kind != "positive" { checked = append(checked, literalTerms(l)...) } }
    for _, t := range checked { if t.kind == "variable" && !contains(bound, t.name) { fail("unsafe variable %s", t.name) } }
}
func strata(arities map[string]int, rules []rule) (map[string]int, map[string]bool, bool) {
    names := []string{}
    for name := range arities { names = append(names, name) }
    sort.Strings(names)
    indices := map[string]int{}
    for i, name := range names { indices[name] = i }
    reach := make([][]bool, len(names))
    levels, recursive := map[string]int{}, map[string]bool{}
    for i, name := range names { reach[i] = make([]bool, len(names)); levels[name] = 0 }
    for _, r := range rules {
        if r.statement.head == nil { continue }
        for _, l := range r.statement.body { if l.kind != "comparison" { reach[indices[r.statement.head.name]][indices[l.atom.name]] = true } }
    }
    for k := range names { for i := range names { for j := range names { reach[i][j] = reach[i][j] || reach[i][k] && reach[k][j] } } }
    for i, name := range names { recursive[name] = reach[i][i] }
    for _, r := range rules {
        if r.statement.head == nil { continue }
        for _, l := range r.statement.body {
            if l.kind == "negative" && (l.atom.name == r.statement.head.name || reach[indices[l.atom.name]][indices[r.statement.head.name]]) { return nil, nil, false }
        }
    }
    changed := true
    for changed {
        changed = false
        for _, r := range rules {
            if r.statement.head == nil { continue }
            for _, l := range r.statement.body {
                if l.kind == "comparison" { continue }
                required := levels[l.atom.name]
                if l.kind == "negative" { required++ }
                if levels[r.statement.head.name] < required { levels[r.statement.head.name], changed = required, true }
            }
        }
    }
    return levels, recursive, true
}
func (d *database) levels() (map[string]int, map[string]bool) {
    arities := map[string]int{}
    for name, p := range d.predicates { arities[name] = p.arity }
    levels, recursive, _ := strata(arities, d.rules)
    return levels, recursive
}
func assignmentCopy(a map[string]value) map[string]value { b := map[string]value{}; for k, v := range a { b[k] = v }; return b }
func match(a atom, values []value, assignment map[string]value) (map[string]value, bool) {
    result := assignmentCopy(assignment)
    for i, t := range a.terms {
        if t.kind == "constant" && t.value != values[i] { return nil, false }
        if t.kind == "variable" {
            if previous, exists := result[t.name]; exists && previous != values[i] { return nil, false }
            result[t.name] = values[i]
        }
    }
    return result, true
}
func evaluate(e *expression, assignment map[string]value) (value, bool) {
    if e.kind == "term" { if e.term.kind == "constant" { return e.term.value, true }; v, ok := assignment[e.term.name]; return v, ok }
    if e.kind == "group" { return evaluate(e.left, assignment) }
    a, okA := evaluate(e.left, assignment)
    b, okB := evaluate(e.right, assignment)
    if !okA || !okB || !a.integer || !b.integer { return value{}, false }
    n := int64(0)
    switch e.operator {
    case "+": n = a.number+b.number
    case "-": n = a.number-b.number
    case "*": n = a.number*b.number
    default:
        if b.number == 0 { return value{}, false }
        n = a.number/b.number
        if a.number%b.number != 0 && (a.number < 0) != (b.number < 0) { n-- }
        if e.operator == "mod" { n = a.number-b.number*n }
    }
    return value{integer:true, number:n}, true
}
func comparison(l literal, assignment map[string]value) bool {
    a, okA := evaluate(l.left, assignment)
    b, okB := evaluate(l.right, assignment)
    if !okA || !okB { return false }
    if l.operator == "=" { return a == b }
    if l.operator == "!=" { return a != b }
    if !a.integer || !b.integer { return false }
    switch l.operator {
    case "<": return a.number < b.number
    case "<=": return a.number <= b.number
    case ">": return a.number > b.number
    default: return a.number >= b.number
    }
}
func orderedTuples(set map[string]tuple) []tuple {
    result := []tuple{}
    for _, t := range set { result = append(result, t) }
    sort.Slice(result, func(i, j int) bool { return compareTuple(result[i].values, result[j].values) < 0 })
    return result
}
func solutions(body []literal, model map[string]map[string]tuple, before int) []map[string]value {
    positives := []literal{}
    for _, l := range body { if l.kind == "positive" { positives = append(positives, l) } }
    accepts := func(binding map[string]value) bool {
        for _, l := range body {
            if l.kind == "positive" { continue }
            ready := true
            for _, t := range literalTerms(l) {
                if t.kind == "variable" { if _, exists := binding[t.name]; !exists { ready = false; break } }
            }
            if !ready { continue }
            if l.kind == "comparison" && !comparison(l, binding) { return false }
            if l.kind == "negative" {
                for _, t := range model[l.atom.name] { if _, ok := match(l.atom, t.values, binding); ok { return false } }
            }
        }
        return true
    }
    result := []map[string]value{}
    finished := map[string]bool{}
    bindingKey := func(binding map[string]value) string {
        names := []string{}
        for name := range binding { names = append(names, name) }
        sort.Strings(names)
        values := []value{}
        for _, name := range names { values = append(values, binding[name]) }
        return tupleKey(values)
    }
    var visit func(map[string]value, []literal)
    visit = func(binding map[string]value, remaining []literal) {
        if !accepts(binding) { return }
        if len(remaining) == 0 {
            key := bindingKey(binding)
            if !finished[key] { finished[key] = true; result = append(result, binding) }
            return
        }
        selected := -1
        var candidates []map[string]value
        for i, l := range remaining {
            matches := []map[string]value{}
            seen := map[string]bool{}
            for _, t := range model[l.atom.name] {
                if before > 0 && t.round >= before { continue }
                if matched, ok := match(l.atom, t.values, binding); ok && accepts(matched) {
                    key := bindingKey(matched)
                    if !seen[key] { seen[key] = true; matches = append(matches, matched) }
                }
            }
            if len(matches) == 0 { return }
            if selected < 0 || len(matches) < len(candidates) { selected, candidates = i, matches }
        }
        nextRemaining := make([]literal, 0, len(remaining)-1)
        nextRemaining = append(nextRemaining, remaining[:selected]...)
        nextRemaining = append(nextRemaining, remaining[selected+1:]...)
        for _, matched := range candidates { visit(matched, nextRemaining) }
    }
    visit(map[string]value{}, positives)
    return result
}
func atomValues(a atom, assignment map[string]value) []value {
    result := []value{}
    for _, t := range a.terms { if t.kind == "constant" { result = append(result, t.value) } else { result = append(result, assignment[t.name]) } }
    return result
}
type model struct { tuples map[string]map[string]tuple; levels map[string]int; rounds, added []int }
func (d *database) model() model {
    levels, _ := d.levels()
    maximum := -1
    result := model{tuples:map[string]map[string]tuple{}, levels:levels}
    for name, p := range d.predicates {
        result.tuples[name] = map[string]tuple{}
        for key, values := range p.facts { result.tuples[name][key] = tuple{values:values} }
        if levels[name] > maximum { maximum = levels[name] }
    }
    result.rounds, result.added = make([]int, maximum+1), make([]int, maximum+1)
    serial := 0
    for level := 0; level <= maximum; level++ {
        for {
            pending := map[string]map[string]tuple{}
            count := 0
            for _, r := range d.rules {
                if r.statement.head == nil || levels[r.statement.head.name] != level { continue }
                head := *r.statement.head
                if pending[head.name] == nil { pending[head.name] = map[string]tuple{} }
                for _, assignment := range solutions(r.statement.body, result.tuples, 0) {
                    values := atomValues(head, assignment)
                    key := tupleKey(values)
                    if _, exists := result.tuples[head.name][key]; exists { continue }
                    if _, exists := pending[head.name][key]; !exists { count++; pending[head.name][key] = tuple{values:values, rule:r.number} }
                }
            }
            if count == 0 { break }
            serial++
            result.rounds[level]++
            result.added[level] += count
            for name, set := range pending { for key, t := range set { t.round = serial; result.tuples[name][key] = t } }
        }
    }
    return result
}
func answerRows(s statement, m model) ([]string, [][]value) {
    names := variables(allTerms(statement{body:s.body}))
    result := [][]value{}
    for _, binding := range solutions(s.body, m.tuples, 0) {
        row := []value{}
        for _, name := range names { row = append(row, binding[name]) }
        result = append(result, row)
    }
    sort.Slice(result, func(i, j int) bool { return compareTuple(result[i], result[j]) < 0 })
    return names, result
}
func answerText(names []string, row []value) string {
    parts := []string{}
    for i, name := range names { parts = append(parts, name+" = "+notation(row[i])) }
    return strings.Join(parts, ", ")
}
func tupleAtom(name string, values []value) atom {
    a := atom{name:name}
    for _, v := range values { a.terms = append(a.terms, term{kind:"constant", value:v}) }
    return a
}
func (d *database) proof(name string, target tuple, depth int, m model) []string {
    prefix := strings.Repeat(" ", depth*2)+atomText(tupleAtom(name, target.values), nil)
    if target.round == 0 { return []string{prefix+" [fact]"} }
    for _, r := range d.rules {
        if r.statement.head == nil || r.statement.head.name != name { continue }
        candidates := []map[string]value{}
        for _, binding := range solutions(r.statement.body, m.tuples, target.round) {
            if compareTuple(atomValues(*r.statement.head, binding), target.values) == 0 { candidates = append(candidates, binding) }
        }
        if len(candidates) == 0 { continue }
        names := variables(allTerms(r.statement))
        sort.Slice(candidates, func(i, j int) bool {
            for _, name := range names { if c := compareValue(candidates[i][name], candidates[j][name]); c != 0 { return c < 0 } }
            return false
        })
        binding := candidates[0]
        lines := []string{fmt.Sprintf("%s [rule %d]", prefix, r.number)}
        for _, l := range r.statement.body {
            if l.kind == "positive" {
                for _, t := range orderedTuples(m.tuples[l.atom.name]) {
                    if t.round >= target.round { continue }
                    if _, ok := match(l.atom, t.values, binding); ok { lines = append(lines, d.proof(l.atom.name, t, depth+1, m)...); break }
                }
            } else { lines = append(lines, strings.Repeat(" ", (depth+1)*2)+literalText(l, binding)) }
        }
        return lines
    }
    return nil
}
func plural(count int, singular string) string { if count == 1 { return singular }; return singular+"s" }
func (d *database) execute(s statement, line int) []string {
    out := []string{}
    emit := func(format string, args ...any) { out = append(out, fmt.Sprintf(format, args...)) }
    if contains([]string{"fact", "rule", "constraint"}, s.kind) {
        arities := d.checkPredicates(s, true)
        safety(s)
        if s.kind == "fact" {
            values := atomValues(*s.head, nil)
            key := tupleKey(values)
            if p := d.predicates[s.head.name]; p != nil { if _, exists := p.facts[key]; exists { return out } }
            d.save(line)
            if d.predicates[s.head.name] == nil { d.predicates[s.head.name] = &predicate{arity:len(values), facts:map[string][]value{}} }
            d.predicates[s.head.name].facts[key] = values
            return out
        }
        text := ruleText(s)
        for _, r := range d.rules { if ruleText(r.statement) == text { fail("duplicate of rule %d", r.number) } }
        candidate := append(append([]rule(nil), d.rules...), rule{d.next, s})
        if s.kind == "rule" { if _, _, valid := strata(arities, candidate); !valid { fail("negative cycle through %s", s.head.name) } }
        d.save(line)
        for name, arity := range arities { if d.predicates[name] == nil { d.predicates[name] = &predicate{arity:arity, facts:map[string][]value{}} } }
        d.rules = candidate
        d.next++
        terms := allTerms(s)
        for _, name := range variables(terms) {
            count := 0
            for _, t := range terms { if t.kind == "variable" && t.name == name { count++ } }
            if count == 1 { emit("WARNING line %d: singleton variable %s", line, name) }
        }
        return out
    }
    if s.kind == "undo" {
        if len(d.history) == 0 { fail("nothing to undo") }
        last := d.history[len(d.history)-1]
        d.history = d.history[:len(d.history)-1]
        d.predicates, d.rules = last.predicates, last.rules
        emit("undid line %d", last.line)
        return out
    }
    if s.kind == "forget" {
        index := -1
        for i, r := range d.rules { if r.number == s.number { index = i; break } }
        if index < 0 { fail("no rule %d", s.number) }
        d.save(line)
        d.rules = append(d.rules[:index], d.rules[index+1:]...)
        return out
    }
    if s.kind == "listing" {
        if s.name != "" && d.predicates[s.name] == nil { fail("unknown predicate %s", s.name) }
        for _, r := range d.rules { if s.name == "" || r.statement.head != nil && r.statement.head.name == s.name { emit("%d: %s", r.number, ruleText(r.statement)) } }
        if len(out) == 0 { emit("no rules") }
        return out
    }
    if s.kind == "strata" {
        levels, recursive := d.levels()
        maximum := -1
        for _, level := range levels { if level > maximum { maximum = level } }
        if maximum < 0 { emit("no predicates") }
        for k := 0; k <= maximum; k++ {
            names := []string{}
            for _, name := range sortedPredicates(d.predicates) { if levels[name] == k { marked := name; if recursive[name] { marked += "*" }; names = append(names, marked) } }
            emit("stratum %d: %s", k, strings.Join(names, ", "))
        }
        return out
    }
    if contains([]string{"query", "retract", "why"}, s.kind) {
        d.checkPredicates(s, false)
        if s.kind == "query" { safety(s) }
    }
    if s.kind == "retract" {
        p := d.predicates[s.head.name]
        keys := []string{}
        for key, values := range p.facts { if _, ok := match(*s.head, values, nil); ok { keys = append(keys, key) } }
        if len(keys) == 0 { fail("no matching facts") }
        d.save(line)
        for _, key := range keys { delete(p.facts, key) }
        emit("%d %s retracted", len(keys), plural(len(keys), "fact"))
        return out
    }
    if s.kind == "why" { for _, t := range s.head.terms { if t.kind != "constant" { fail("why needs a ground atom") } } }
    if s.kind == "dump" && d.predicates[s.name] == nil { fail("unknown predicate %s", s.name) }
    m := d.model()
    switch s.kind {
    case "query":
        names, answers := answerRows(s, m)
        switch s.aggregate {
        case "count": emit("%d", len(answers))
        case "sum":
            column := 0
            for i, name := range names { if name == s.variable { column = i } }
            total := int64(0)
            for _, row := range answers { if !row[column].integer { fail("non-integer value in sum") }; total += row[column].number }
            emit("%d", total)
        case "min", "max":
            if len(answers) == 0 { emit("no answers"); break }
            column := 0
            for i, name := range names { if name == s.variable { column = i } }
            selected := answers[0][column]
            for _, row := range answers { c := compareValue(row[column], selected); if s.aggregate == "min" && c < 0 || s.aggregate == "max" && c > 0 { selected = row[column] } }
            emit("%s", notation(selected))
        default:
            if len(names) == 0 { if len(answers) > 0 { emit("true.") } else { emit("false.") } } else {
                for _, row := range answers { emit("%s", answerText(names, row)) }
                emit("%d %s", len(answers), plural(len(answers), "answer"))
            }
        }
    case "dump":
        rows := orderedTuples(m.tuples[s.name])
        for _, t := range rows { emit("%s.", atomText(tupleAtom(s.name, t.values), nil)) }
        emit("%d %s", len(rows), plural(len(rows), "tuple"))
    case "why":
        t, exists := m.tuples[s.head.name][tupleKey(atomValues(*s.head, nil))]
        if !exists { emit("false.") } else { out = append(out, d.proof(s.head.name, t, 0, m)...) }
    case "check":
        count := 0
        for _, r := range d.rules {
            if r.statement.head != nil { continue }
            count++
            names, answers := answerRows(r.statement, m)
            if len(answers) == 0 { emit("constraint %d: ok", r.number) } else {
                emit("constraint %d: %d %s", r.number, len(answers), plural(len(answers), "violation"))
                if len(names) > 0 { for _, row := range answers { emit("  %s", answerText(names, row)) } }
            }
        }
        if count == 0 { emit("no constraints") }
    case "predicates":
        if len(d.predicates) == 0 { emit("no predicates") }
        for _, name := range sortedPredicates(d.predicates) {
            count := 0
            for _, r := range d.rules { if r.statement.head != nil && r.statement.head.name == name { count++ } }
            emit("%s/%d: facts %d, rules %d, tuples %d", name, d.predicates[name].arity, len(d.predicates[name].facts), count, len(m.tuples[name]))
        }
    case "stats":
        facts, rules, constraints, tuples := 0, 0, 0, 0
        for name, p := range d.predicates { facts += len(p.facts); tuples += len(m.tuples[name]) }
        for _, r := range d.rules { if r.statement.head == nil { constraints++ } else { rules++ } }
        emit("facts %d, rules %d, constraints %d, tuples %d", facts, rules, constraints, tuples)
        for k := range m.rounds { emit("stratum %d: rounds %d, new %d", k, m.rounds[k], m.added[k]) }
        for _, r := range d.rules {
            if r.statement.head == nil { continue }
            count := 0
            for _, set := range m.tuples { for _, t := range set { if t.round > 0 && t.rule == r.number { count++ } } }
            emit("rule %d: new %d", r.number, count)
        }
    }
    return out
}
func (d *database) process(line string, number int, out *bufio.Writer) (halt bool) {
    defer func() { if caught := recover(); caught != nil { if reason, ok := caught.(problem); ok { fmt.Fprintf(out, "ERROR line %d: %s\n", number, reason) } else { panic(caught) } } }()
    tokens := lexical(line)
    if len(tokens) == 0 { return false }
    p := parser{tokens:tokens}
    s := p.statement()
    if s.kind == "halt" { return true }
    for _, text := range d.execute(s, number) { fmt.Fprintln(out, text) }
    return false
}
func main() {
    scanner := bufio.NewScanner(os.Stdin)
    out := bufio.NewWriter(os.Stdout)
    defer out.Flush()
    d := newDatabase()
    line := 0
    for scanner.Scan() { line++; if d.process(scanner.Text(), line, out) { break } }
}
