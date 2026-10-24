package main

import (
    "bufio"
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

type term struct {
    kind, name string
    value int
    left, right *term
    free map[string]bool
}
func variable(name string) *term { return &term{kind:"variable", name:name} }
func abstraction(name string, body *term) *term { return &term{kind:"abstraction", name:name, left:body} }
func application(function, argument *term) *term { return &term{kind:"application", left:function, right:argument} }
func freeVariables(t *term) map[string]bool {
    if t.free != nil { return t.free }
    result := map[string]bool{}
    switch t.kind {
    case "variable": result[t.name] = true
    case "abstraction": for name := range freeVariables(t.left) { if name != t.name { result[name] = true } }
    case "application":
        for name := range freeVariables(t.left) { result[name] = true }
        for name := range freeVariables(t.right) { result[name] = true }
    }
    t.free = result
    return result
}
func orderedNames(set map[string]bool) []string { names := []string{}; for name := range set { names = append(names, name) }; sort.Strings(names); return names }
func printTerm(t *term, end, debruijn bool) string {
    switch t.kind {
    case "variable", "macro", "constant": return t.name
    case "index": return strconv.Itoa(t.value)
    case "numeral": return "#"+strconv.Itoa(t.value)
    case "abstraction":
        names := []string{}
        body := t
        for body.kind == "abstraction" { names = append(names, body.name); body = body.left }
        text := ""
        if debruijn { text = strings.Repeat("\\", len(names))+printTerm(body, true, true) } else { text = "\\"+strings.Join(names, " ")+". "+printTerm(body, true, false) }
        if !end { text = "("+text+")" }
        return text
    default:
        left := printTerm(t.left, false, debruijn)
        right := ""
        if t.right.kind == "application" { right = "("+printTerm(t.right, true, debruijn)+")" } else { right = printTerm(t.right, end, debruijn) }
        return left+" "+right
    }
}
func substitute(t *term, name string, replacement *term) *term {
    if t.kind == "variable" { if t.name == name { return replacement }; return t }
    if t.kind == "application" { return application(substitute(t.left, name, replacement), substitute(t.right, name, replacement)) }
    if t.kind != "abstraction" || t.name == name || !freeVariables(t.left)[name] { return t }
    binder, body := t.name, t.left
    if freeVariables(replacement)[binder] {
        base := strings.TrimRight(binder, "0123456789")
        for i := 1; ; i++ {
            candidate := base+strconv.Itoa(i)
            if !freeVariables(replacement)[candidate] && !freeVariables(body)[candidate] { binder = candidate; break }
        }
        body = substitute(body, t.name, variable(binder))
    }
    return abstraction(binder, substitute(body, name, replacement))
}
func nameSequence(index int) string {
    result := string(rune('a'+index%26))
    if index >= 26 { result += strconv.Itoa(index/26) }
    return result
}
func canonical(t *term) *term {
    free, counter := freeVariables(t), 0
    bound := map[string][]string{}
    var visit func(*term) *term
    visit = func(t *term) *term {
        if t.kind == "variable" {
            values := bound[t.name]
            if len(values) > 0 { return variable(values[len(values)-1]) }
            return t
        }
        if t.kind == "application" { return application(visit(t.left), visit(t.right)) }
        name := ""
        for { name = nameSequence(counter); counter++; if !free[name] { break } }
        bound[t.name] = append(bound[t.name], name)
        body := visit(t.left)
        bound[t.name] = bound[t.name][:len(bound[t.name])-1]
        return abstraction(name, body)
    }
    return visit(t)
}
func deBruijn(t *term, bound []string) *term {
    if t.kind == "variable" {
        for i := len(bound)-1; i >= 0; i-- { if bound[i] == t.name { return &term{kind:"index", value:len(bound)-1-i} } }
        return t
    }
    if t.kind == "application" { return application(deBruijn(t.left, bound), deBruijn(t.right, bound)) }
    next := append(append([]string(nil), bound...), t.name)
    return abstraction("", deBruijn(t.left, next))
}
func fromDeBruijn(t *term) *term {
    counter, free := 0, freeVariables(t)
    var visit func(*term, []string) *term
    visit = func(t *term, bound []string) *term {
        if t.kind == "variable" { return t }
        if t.kind == "index" { return variable(bound[len(bound)-1-t.value]) }
        if t.kind == "application" { return application(visit(t.left, bound), visit(t.right, bound)) }
        name := ""
        for { name = nameSequence(counter); counter++; if !free[name] { break } }
        next := append(append([]string(nil), bound...), name)
        return abstraction(name, visit(t.left, next))
    }
    return visit(t, nil)
}
func equivalent(a, b *term) bool { return printTerm(deBruijn(a, nil), true, true) == printTerm(deBruijn(b, nil), true, true) }

type commandError string
func fail(format string, args ...any) { panic(commandError(fmt.Sprintf(format, args...))) }
type token struct { kind, text string; column, value int }
type parser struct { tokens []token; at int }
func lower(c byte) bool { return c >= 'a' && c <= 'z' }
func upper(c byte) bool { return c >= 'A' && c <= 'Z' }
func digit(c byte) bool { return c >= '0' && c <= '9' }
func lex(line, text string, offset int) []token {
    tokens := []token{}
    for i := 0; i < len(text); {
        if text[i] == ' ' { i++; continue }
        start, kind := i, ""
        switch {
        case strings.ContainsRune("\\.()=;", rune(text[i])): kind = text[i:i+1]; i++
        case lower(text[i]): kind = "variable"; for i < len(text) && (lower(text[i]) || digit(text[i])) { i++ }
        case upper(text[i]): kind = "macro"; for i < len(text) && (upper(text[i]) || digit(text[i]) || text[i] == '_') { i++ }
        case text[i] == '#' && i+1 < len(text) && digit(text[i+1]): kind = "numeral"; i++; for i < len(text) && digit(text[i]) { i++ }
        default: fail("column %d: unexpected character '%c'", offset+i+1, text[i])
        }
        item := token{kind:kind, text:text[start:i], column:offset+start+1}
        if kind == "numeral" { item.value, _ = strconv.Atoi(item.text[1:]) }
        tokens = append(tokens, item)
    }
    return append(tokens, token{kind:"end", column:len(line)+1})
}
func (p *parser) peek() token { return p.tokens[p.at] }
func (p *parser) expect(kind string) token {
    t := p.peek()
    if t.kind != kind {
        notation := "'"+kind+"'"
        if kind == "variable" { notation = "variable" }
        if kind == "macro" { notation = "macro name" }
        fail("column %d: expected %s", t.column, notation)
    }
    p.at++
    return t
}
func (p *parser) readTerm() *term {
    elements := []*term{}
    for {
        t := p.peek()
        if t.kind != "variable" && t.kind != "macro" && t.kind != "numeral" && t.kind != "(" { break }
        p.at++
        if t.kind == "(" { value := p.readTerm(); p.expect(")"); elements = append(elements, value) } else { elements = append(elements, &term{kind:t.kind, name:t.text, value:t.value}) }
    }
    if p.peek().kind == "\\" {
        p.at++
        names := []string{p.expect("variable").text}
        for p.peek().kind == "variable" { names = append(names, p.expect("variable").text) }
        p.expect(".")
        value := p.readTerm()
        for i := len(names)-1; i >= 0; i-- { value = abstraction(names[i], value) }
        elements = append(elements, value)
    }
    if len(elements) == 0 { fail("column %d: expected term", p.peek().column) }
    result := elements[0]
    for _, next := range elements[1:] { result = application(result, next) }
    return result
}
func (p *parser) end() { if p.peek().kind != "end" { t := p.peek(); fail("column %d: unexpected '%s'", t.column, t.text) } }
func macroReferences(t *term) []string {
    if t.kind == "macro" { return []string{t.name} }
    if t.kind == "abstraction" { return macroReferences(t.left) }
    if t.kind == "application" { return append(macroReferences(t.left), macroReferences(t.right)...) }
    return nil
}
func validMacro(name string) bool {
    if name == "" || !upper(name[0]) { return false }
    for i := range name { if !upper(name[i]) && !digit(name[i]) && name[i] != '_' { return false } }
    return true
}
var reserved = []string{"S", "K", "I", "NORMAL", "APPLICATIVE", "CBN", "CBV"}
func has(items []string, value string) bool { for _, item := range items { if item == value { return true } }; return false }

type workbench struct { macros map[string]*term; steps, eta bool; limit int; out *bufio.Writer }
func newWorkbench(out *bufio.Writer) *workbench {
    w := &workbench{macros:map[string]*term{}, limit:10000, out:out}
    w.macros["I"] = abstraction("x", variable("x"))
    w.macros["K"] = abstraction("x", abstraction("y", variable("x")))
    sBody := application(application(variable("x"), variable("z")), application(variable("y"), variable("z")))
    w.macros["S"] = abstraction("x", abstraction("y", abstraction("z", sBody)))
    return w
}
func (w *workbench) emit(format string, args ...any) { fmt.Fprintf(w.out, format+"\n", args...) }
func (w *workbench) expand(t *term) *term {
    switch t.kind {
    case "variable": return t
    case "macro": value := w.macros[t.name]; if value == nil { fail("unbound macro %s", t.name) }; return w.expand(value)
    case "numeral":
        body := variable("x")
        for i := 0; i < t.value; i++ { body = application(variable("f"), body) }
        return abstraction("f", abstraction("x", body))
    case "abstraction": return abstraction(t.name, w.expand(t.left))
    default: return application(w.expand(t.left), w.expand(t.right))
    }
}
func (w *workbench) depends(name, target string, seen map[string]bool) bool {
    if name == target { return true }
    if seen[name] || name == "S" || name == "K" || name == "I" || w.macros[name] == nil { return false }
    seen[name] = true
    for _, reference := range macroReferences(w.macros[name]) { if w.depends(reference, target, seen) { return true } }
    return false
}
func etaRedex(t *term) bool { return t.kind == "abstraction" && t.left.kind == "application" && t.left.right.kind == "variable" && t.left.right.name == t.name && !freeVariables(t.left.left)[t.name] }
func oneStep(t *term, strategy string, eta bool) (*term, string) {
    if t.kind == "application" {
        if (strategy == "NORMAL" || strategy == "CBN") && t.left.kind == "abstraction" { return substitute(t.left.left, t.left.name, t.right), "beta" }
        if value, kind := oneStep(t.left, strategy, eta); value != nil { return application(value, t.right), kind }
        if strategy == "CBN" { return nil, "" }
        if value, kind := oneStep(t.right, strategy, eta); value != nil { return application(t.left, value), kind }
        if t.left.kind == "abstraction" && (strategy != "CBV" || t.right.kind == "variable" || t.right.kind == "abstraction") { return substitute(t.left.left, t.left.name, t.right), "beta" }
    } else if t.kind == "abstraction" && strategy != "CBN" && strategy != "CBV" {
        if strategy == "NORMAL" && eta && etaRedex(t) { return t.left.left, "eta" }
        if value, kind := oneStep(t.left, strategy, eta); value != nil { return abstraction(t.name, value), kind }
        if eta && etaRedex(t) { return t.left.left, "eta" }
    }
    return nil, ""
}
func (w *workbench) reduce(t *term, strategy string, eta, display bool) (*term, int, bool) {
    for count := 0; ; count++ {
        next, kind := oneStep(t, strategy, eta)
        if next == nil { return t, count, true }
        if count == w.limit { return t, count, false }
        t = next
        if display { w.emit("step %d (%s): %s", count+1, kind, printTerm(t, true, false)) }
    }
}
func size(t *term) int { if t.kind == "variable" { return 1 }; if t.kind == "abstraction" { return 1+size(t.left) }; return 1+size(t.left)+size(t.right) }
func depth(t *term) int { if t.kind == "variable" { return 1 }; if t.kind == "abstraction" { return 1+depth(t.left) }; a, b := depth(t.left), depth(t.right); if b > a { a = b }; return 1+a }

type simpleType struct { left, right, link *simpleType }
type notTypable struct{}
func resolve(t *simpleType) *simpleType { if t.link != nil { t.link = resolve(t.link); return t.link }; return t }
func occurs(variable, t *simpleType) bool { t = resolve(t); return variable == t || t.left != nil && (occurs(variable, t.left) || occurs(variable, t.right)) }
func unify(a, b *simpleType) {
    a, b = resolve(a), resolve(b)
    if a == b { return }
    if a.left == nil { if occurs(a, b) { panic(notTypable{}) }; a.link = b; return }
    if b.left == nil { unify(b, a); return }
    unify(a.left, b.left)
    unify(a.right, b.right)
}
func inferType(t *term) (result string) {
    defer func() { if caught := recover(); caught != nil { if _, ok := caught.(notTypable); !ok { panic(caught) }; result = "not typable" } }()
    free := map[string]*simpleType{}
    bound := map[string][]*simpleType{}
    var infer func(*term) *simpleType
    infer = func(t *term) *simpleType {
        if t.kind == "variable" {
            if stack := bound[t.name]; len(stack) > 0 { return stack[len(stack)-1] }
            if free[t.name] == nil { free[t.name] = &simpleType{} }
            return free[t.name]
        }
        if t.kind == "abstraction" {
            argument := &simpleType{}
            bound[t.name] = append(bound[t.name], argument)
            body := infer(t.left)
            bound[t.name] = bound[t.name][:len(bound[t.name])-1]
            return &simpleType{left:argument, right:body}
        }
        function := infer(t.left)
        argument := infer(t.right)
        value := &simpleType{}
        unify(function, &simpleType{left:argument, right:value})
        return value
    }
    principal := infer(t)
    names := map[*simpleType]string{}
    var print func(*simpleType) string
    print = func(t *simpleType) string {
        t = resolve(t)
        if t.left == nil { if _, exists := names[t]; !exists { names[t] = nameSequence(len(names)) }; return names[t] }
        left := print(t.left)
        if resolve(t.left).left != nil { left = "("+left+")" }
        return left+" -> "+print(t.right)
    }
    return print(principal)
}
func church(t *term) string {
    if t.kind == "abstraction" && t.left.kind == "abstraction" {
        outer, inner, body, count := t.name, t.left.name, t.left.left, 0
        for body.kind == "application" && body.left.kind == "variable" && body.left.name == outer { count++; body = body.right }
        if body.kind == "variable" && body.name == inner { return strconv.Itoa(count) }
        if t.left.left.kind == "variable" && t.left.left.name == outer { return "true" }
    }
    if t.kind == "abstraction" && t.left.kind == "application" && t.left.left.kind == "application" {
        body := t.left
        function := body.left.left
        if function.kind == "variable" && function.name == t.name && !freeVariables(body.left.right)[t.name] && !freeVariables(body.right)[t.name] { return "("+church(body.left.right)+", "+church(body.right)+")" }
    }
    return printTerm(canonical(t), true, false)
}
func constant(name string) *term { return &term{kind:"constant", name:name} }
func abstractSKI(name string, t *term) *term {
    if !freeVariables(t)[name] { return application(constant("K"), t) }
    if t.kind == "variable" { return constant("I") }
    if t.right.kind == "variable" && t.right.name == name && !freeVariables(t.left)[name] { return t.left }
    return application(application(constant("S"), abstractSKI(name, t.left)), abstractSKI(name, t.right))
}
func ski(t *term) *term { if t.kind == "variable" { return t }; if t.kind == "application" { return application(ski(t.left), ski(t.right)) }; return abstractSKI(t.name, ski(t.left)) }
func skiStep(t *term) (*term, string) {
    head, arguments := t, []*term{}
    for head.kind == "application" { arguments = append(arguments, head.right); head = head.left }
    for i, j := 0, len(arguments)-1; i < j; i, j = i+1, j-1 { arguments[i], arguments[j] = arguments[j], arguments[i] }
    var result *term
    used, kind := 0, ""
    if head.kind == "constant" {
        if head.name == "I" && len(arguments) >= 1 { result, used, kind = arguments[0], 1, "I" }
        if head.name == "K" && len(arguments) >= 2 { result, used, kind = arguments[0], 2, "K" }
        if head.name == "S" && len(arguments) >= 3 { result, used, kind = application(application(arguments[0], arguments[2]), application(arguments[1], arguments[2])), 3, "S" }
    }
    if result != nil { for _, argument := range arguments[used:] { result = application(result, argument) }; return result, kind }
    for i, argument := range arguments {
        if next, contraction := skiStep(argument); next != nil {
            result = head
            for j, item := range arguments { if j == i { item = next }; result = application(result, item) }
            return result, contraction
        }
    }
    return nil, ""
}

type closure struct { code *term; environment []*closure }
func reify(code *term, environment []*closure, inside int) *term {
    for code.kind == "index" && code.value >= inside {
        value := environment[code.value-inside]
        code, environment, inside = value.code, value.environment, 0
    }
    if code.kind == "variable" || code.kind == "index" { return code }
    if code.kind == "abstraction" { return abstraction("", reify(code.left, environment, inside+1)) }
    return application(reify(code.left, environment, inside), reify(code.right, environment, inside))
}
func (w *workbench) kam(t *term) {
    code, environment, stack := deBruijn(t, nil), []*closure{}, []*closure{}
    count := 0
    for {
        kind := ""
        if code.kind == "application" { kind = "push" } else if code.kind == "index" { kind = "access" } else if code.kind == "abstraction" && len(stack) > 0 { kind = "grab" }
        if kind == "" { break }
        if count == w.limit { w.emit("no result within %d transitions", w.limit); return }
        count++
        switch kind {
        case "push": stack = append(stack, &closure{code.right, environment}); code = code.left
        case "grab": environment = append([]*closure{stack[len(stack)-1]}, environment...); stack = stack[:len(stack)-1]; code = code.left
        case "access": value := environment[code.value]; code, environment = value.code, value.environment
        }
        if w.steps { w.emit("step %d (%s): %s [env %d, stack %d]", count, kind, printTerm(code, true, true), len(environment), len(stack)) }
    }
    result := reify(code, environment, 0)
    for i := len(stack)-1; i >= 0; i-- { result = application(result, reify(stack[i].code, stack[i].environment, 0)) }
    w.emit("result: %s (transitions: %d)", printTerm(fromDeBruijn(result), true, false), count)
}
func (w *workbench) command(line string) {
    defer func() { if caught := recover(); caught != nil { if reason, ok := caught.(commandError); ok { w.emit("error: %s", reason) } else { panic(caught) } } }()
    if line == "" || strings.HasPrefix(line, "--") { return }
    command, arguments, offset := line, "", len(line)
    if space := strings.IndexByte(line, ' '); space >= 0 { command, arguments, offset = line[:space], line[space+1:], space+1 }
    if !has([]string{"let", "unlet", "macros", "steps", "eta", "limit", "expand", "subst", "reduce", "equal", "alpha", "debruijn", "fv", "size", "depth", "type", "church", "ski", "skireduce", "kam"}, command) { fail("unknown command %s", command) }
    if has([]string{"unlet", "macros", "steps", "eta", "limit"}, command) {
        words := strings.Fields(arguments)
        switch command {
        case "steps", "eta":
            if len(words) != 1 || !has([]string{"on", "off"}, words[0]) { fail("bad argument") }
            if command == "steps" { w.steps = words[0] == "on" } else { w.eta = words[0] == "on" }
        case "limit":
            valid := len(words) == 1
            if valid { valid = len(words[0]) >= 1 && len(words[0]) <= 5; for i := range words[0] { if !digit(words[0][i]) { valid = false } } }
            if !valid { fail("bad argument") }
            value, _ := strconv.Atoi(words[0])
            if value < 1 || value > 10000 { fail("bad argument") }
            w.limit = value
        case "macros":
            if len(words) != 0 { fail("bad argument") }
            names := []string{}
            for name := range w.macros { if name != "S" && name != "K" && name != "I" { names = append(names, name) } }
            sort.Strings(names)
            if len(names) == 0 { w.emit("(none)") }
            for _, name := range names { w.emit("%s = %s", name, printTerm(w.macros[name], true, false)) }
        case "unlet":
            if len(words) != 1 || !validMacro(words[0]) { fail("bad argument") }
            name := words[0]
            if has(reserved, name) { fail("reserved name %s", name) }
            if w.macros[name] == nil { fail("unbound macro %s", name) }
            users := []string{}
            for other, value := range w.macros { if has(macroReferences(value), name) { users = append(users, other) } }
            sort.Strings(users)
            if len(users) > 0 { fail("%s is used by %s", name, users[0]) }
            delete(w.macros, name)
            w.emit("removed %s", name)
        }
        return
    }
    p := parser{tokens:lex(line, arguments, offset)}
    name, strategy := "", "NORMAL"
    var first, second *term
    if command == "let" || command == "subst" {
        kind := "macro"
        if command == "subst" { kind = "variable" }
        name = p.expect(kind).text
        p.expect("=")
    }
    if command == "reduce" && p.peek().kind == "macro" && has(reserved[3:], p.peek().text) { strategy = p.peek().text; p.at++ }
    first = p.readTerm()
    if command == "subst" || command == "equal" || command == "alpha" { p.expect(";"); second = p.readTerm() }
    p.end()
    if command == "let" {
        if has(reserved, name) { fail("reserved name %s", name) }
        seen := map[string]bool{}
        for _, reference := range macroReferences(first) {
            if w.depends(reference, name, seen) { fail("recursive definition of %s", name) }
            if w.macros[reference] == nil { fail("unbound macro %s", reference) }
        }
        free := orderedNames(freeVariables(first))
        if len(free) > 0 { fail("free variable %s in definition of %s", free[0], name) }
        prefix := "defined"
        if w.macros[name] != nil { prefix = "redefined" }
        w.macros[name] = first
        w.emit("%s %s", prefix, name)
        return
    }
    first = w.expand(first)
    if second != nil { second = w.expand(second) }
    switch command {
    case "expand": w.emit("%s", printTerm(first, true, false))
    case "subst": w.emit("%s", printTerm(substitute(second, name, first), true, false))
    case "alpha": if equivalent(first, second) { w.emit("yes") } else { w.emit("no") }
    case "equal":
        a, _, okA := w.reduce(first, "NORMAL", w.eta, false)
        b, _, okB := w.reduce(second, "NORMAL", w.eta, false)
        if !okA || !okB { w.emit("unknown") } else if equivalent(a, b) { w.emit("yes") } else { w.emit("no") }
    case "debruijn": w.emit("%s", printTerm(deBruijn(first, nil), true, true))
    case "fv": names := orderedNames(freeVariables(first)); if len(names) == 0 { w.emit("(none)") } else { w.emit("%s", strings.Join(names, " ")) }
    case "size": w.emit("%d", size(first))
    case "depth": w.emit("%d", depth(first))
    case "type": w.emit("%s", inferType(first))
    case "church":
        result, _, ok := w.reduce(first, "NORMAL", false, false)
        if !ok { w.emit("no normal form within %d steps", w.limit) } else { w.emit("%s", church(canonical(result))) }
    case "ski": w.emit("%s", printTerm(ski(first), true, false))
    case "skireduce":
        value := ski(first)
        for count := 0; ; count++ {
            next, kind := skiStep(value)
            if next == nil { w.emit("result: %s (steps: %d)", printTerm(value, true, false), count); break }
            if count == w.limit { w.emit("no normal form within %d steps", w.limit); break }
            value = next
            if w.steps { w.emit("step %d (%s): %s", count+1, kind, printTerm(value, true, false)) }
        }
    case "kam": w.kam(first)
    case "reduce":
        result, count, ok := w.reduce(first, strategy, w.eta, w.steps)
        if !ok { w.emit("no normal form within %d steps", w.limit) } else { w.emit("result: %s (steps: %d)", printTerm(canonical(result), true, false), count) }
    }
}
func main() {
    scanner := bufio.NewScanner(os.Stdin)
    out := bufio.NewWriter(os.Stdout)
    defer out.Flush()
    w := newWorkbench(out)
    for scanner.Scan() { if scanner.Text() == "quit" { break }; w.command(scanner.Text()) }
}
