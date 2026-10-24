package main

import (
    "bufio"
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

type variable struct { simple bool; value string }
type recipeLine struct { number int; text string }
type recipe struct { lines []recipeLine }
type rule struct { target string; prerequisites []string; recipe *recipe; stem string }
type group struct { targets []*rule; explicit bool; recipe *recipe }
type condition struct { outer, value, otherwise bool; number int }
type scope struct { name, word string; call []string }
type expansionError struct { location, reason string }
type abortBuild struct{}
type simulator struct {
    files map[string]int
    clock int
    loaded bool
    variables map[string]variable
    rules map[string]*rule
    patterns []*rule
    phony map[string]bool
    goal, location string
    scopes []scope
    expanding map[string]bool
    automatic map[string]string
    output []string
}

func trim(s string) string { return strings.Trim(s, " ") }
func words(s string) []string {
    result := []string{}
    for _, w := range strings.Split(s, " ") { if w != "" { result = append(result, w) } }
    return result
}
func unique(list []string) []string {
    seen := map[string]bool{}
    result := []string{}
    for _, item := range list { if !seen[item] { seen[item] = true; result = append(result, item) } }
    return result
}
func keys[V any](table map[string]V) []string {
    result := make([]string, 0, len(table))
    for key := range table { result = append(result, key) }
    sort.Strings(result)
    return result
}
func integer(s string) (int, bool) {
    if s == "" { return 0, false }
    for _, c := range s { if c < '0' || c > '9' { return 0, false } }
    n, _ := strconv.Atoi(s)
    return n, true
}
func match(pattern, word string) (string, bool) {
    at := strings.IndexByte(pattern, '%')
    if at < 0 { return "", pattern == word }
    a, b := pattern[:at], pattern[at+1:]
    if len(word) < len(a)+len(b) || !strings.HasPrefix(word, a) || !strings.HasSuffix(word, b) { return "", false }
    return word[len(a):len(word)-len(b)], true
}
func substitute(pattern, stem string) string { return strings.Replace(pattern, "%", stem, 1) }
func replacement(word, pattern, value string) string {
    stem, ok := match(pattern, word)
    if !ok { return word }
    if strings.Contains(pattern, "%") { return substitute(value, stem) }
    return value
}
func wildcard(pattern, name string) bool {
    type position struct { p, n int }
    memo := map[position]bool{}
    known := map[position]bool{}
    var visit func(int, int) bool
    visit = func(p, n int) bool {
        key := position{p, n}
        if known[key] { return memo[key] }
        result := false
        if p == len(pattern) { result = n == len(name) } else if pattern[p] == '*' {
            result = visit(p+1, n) || n < len(name) && name[n] != '/' && visit(p, n+1)
        } else if n < len(name) && (pattern[p] == name[n] || pattern[p] == '?' && name[n] != '/') { result = visit(p+1, n+1) }
        known[key], memo[key] = true, result
        return result
    }
    return visit(0, 0)
}
func (m *simulator) emit(format string, args ...any) { m.output = append(m.output, fmt.Sprintf(format, args...)) }
func (m *simulator) fail(reason string) { panic(expansionError{m.location, reason}) }
func (m *simulator) clear() {
    m.loaded = false
    m.variables = map[string]variable{}
    m.rules = map[string]*rule{}
    m.patterns = nil
    m.phony = map[string]bool{}
    m.goal = ""
}
func (m *simulator) resetExpansion() {
    m.location = "make"
    m.scopes = nil
    m.expanding = map[string]bool{}
    m.automatic = nil
}
func (m *simulator) glob(pattern string) []string {
    result := []string{}
    for _, name := range keys(m.files) { if wildcard(pattern, name) { result = append(result, name) } }
    return result
}
func (m *simulator) reference(name string) string {
    for i := len(m.scopes)-1; i >= 0; i-- {
        s := m.scopes[i]
        if s.call != nil {
            if n, ok := integer(name); ok { if n < len(s.call) { return s.call[n] }; return "" }
        } else if s.name == name { return s.word }
    }
    if value, ok := m.automatic[name]; ok { return value }
    v, ok := m.variables[name]
    if !ok { return "" }
    if v.simple { return v.value }
    if m.expanding[name] { m.fail("Recursive variable '" + name + "' references itself (eventually)") }
    m.expanding[name] = true
    defer delete(m.expanding, name)
    return m.expand(v.value)
}
func (m *simulator) closing(s string, open int) int {
    close := byte(')')
    if s[open] == '{' { close = '}' }
    depth := 0
    for i := open; i < len(s); i++ {
        if s[i] == s[open] { depth++ } else if s[i] == close { depth--; if depth == 0 { return i } }
    }
    m.fail("unterminated variable reference")
    return 0
}
func (m *simulator) outside(s string, wanted byte) int {
    found := -1
    for i := 0; i < len(s); i++ {
        if s[i] == '$' {
            if i+1 < len(s) && (s[i+1] == '(' || s[i+1] == '{') { i = m.closing(s, i+1) } else if i+1 < len(s) { i++ }
        } else if s[i] == wanted && found < 0 { found = i }
    }
    return found
}
var limits = map[string][2]int{
    "subst": {3,3}, "patsubst": {3,3}, "strip": {1,1}, "findstring": {2,2},
    "filter": {2,2}, "filter-out": {2,2}, "sort": {1,1}, "word": {2,2},
    "wordlist": {3,3}, "words": {1,1}, "firstword": {1,1}, "lastword": {1,1},
    "dir": {1,1}, "notdir": {1,1}, "suffix": {1,1}, "basename": {1,1},
    "addsuffix": {2,2}, "addprefix": {2,2}, "wildcard": {1,1}, "foreach": {3,3},
    "if": {2,3}, "call": {1,0}, "value": {1,1}, "info": {1,1}, "warning": {1,1}, "error": {1,1},
}
func (m *simulator) expand(s string) string {
    var result strings.Builder
    for i := 0; i < len(s); i++ {
        if s[i] != '$' { result.WriteByte(s[i]); continue }
        i++
        if i == len(s) { break }
        if s[i] == '$' { result.WriteByte('$') } else if s[i] == '(' || s[i] == '{' {
            end := m.closing(s, i)
            content := s[i+1:end]
            at := strings.IndexByte(content, ' ')
            if at >= 0 {
                if _, ok := limits[content[:at]]; ok { result.WriteString(m.function(content[:at], strings.TrimLeft(content[at+1:], " "), s[i])); i = end; continue }
            }
            name := m.expand(content)
            colon := strings.IndexByte(name, ':')
            if colon >= 0 && strings.Contains(name[colon+1:], "=") {
                eq := colon+1+strings.IndexByte(name[colon+1:], '=')
                from, to := name[colon+1:eq], name[eq+1:]
                if !strings.Contains(from, "%") { from, to = "%"+from, "%"+to }
                list := words(m.reference(name[:colon]))
                for n, word := range list { list[n] = replacement(word, from, to) }
                result.WriteString(strings.Join(list, " "))
            } else { result.WriteString(m.reference(name)) }
            i = end
        } else { result.WriteString(m.reference(s[i:i+1])) }
    }
    return result.String()
}
func (m *simulator) function(name, text string, open byte) string {
    bound := limits[name]
    args := []string{}
    depth, start := 0, 0
    close := byte(')')
    if open == '{' { close = '}' }
    for i := 0; i < len(text); i++ {
        if text[i] == open { depth++ } else if text[i] == close { depth-- }
        if text[i] == ',' && depth == 0 && (bound[1] == 0 || len(args) < bound[1]-1) { args = append(args, text[start:i]); start = i+1 }
    }
    args = append(args, text[start:])
    if len(args) < bound[0] { m.fail(fmt.Sprintf("insufficient number of arguments (%d) to function '%s'", len(args), name)) }
    if name == "if" {
        if trim(m.expand(args[0])) != "" { return m.expand(args[1]) }
        if len(args) > 2 { return m.expand(args[2]) }
        return ""
    }
    if name == "foreach" {
        variableName := trim(m.expand(args[0]))
        list := words(m.expand(args[1]))
        result := []string{}
        for _, word := range list {
            m.scopes = append(m.scopes, scope{name: variableName, word: word})
            value := func() string { defer func(){m.scopes=m.scopes[:len(m.scopes)-1]}(); return m.expand(args[2]) }()
            result = append(result, value)
        }
        return strings.Join(result, " ")
    }
    for i := range args { args[i] = m.expand(args[i]); if name != "subst" && name != "call" { args[i] = trim(args[i]) } }
    if name == "call" {
        called := trim(args[0])
        v, ok := m.variables[called]
        if !ok { return "" }
        if v.simple { return v.value }
        args[0] = called
        m.scopes = append(m.scopes, scope{call: args})
        defer func(){m.scopes=m.scopes[:len(m.scopes)-1]}()
        return m.expand(v.value)
    }
    switch name {
    case "subst": if args[0] == "" { return args[2] }; return strings.ReplaceAll(args[2], args[0], args[1])
    case "patsubst":
        list := words(args[2]); for i, word := range list { list[i] = replacement(word, args[0], args[1]) }; return strings.Join(list, " ")
    case "strip": return strings.Join(words(args[0]), " ")
    case "findstring": if strings.Contains(args[1], args[0]) { return args[0] }; return ""
    case "filter", "filter-out":
        result := []string{}
        for _, word := range words(args[1]) {
            matched := false
            for _, pattern := range words(args[0]) { if _, ok := match(pattern, word); ok { matched = true; break } }
            if matched == (name == "filter") { result = append(result, word) }
        }
        return strings.Join(result, " ")
    case "sort": list := unique(words(args[0])); sort.Strings(list); return strings.Join(list, " ")
    case "word":
        n, ok := integer(args[0]); if !ok { m.fail("non-numeric first argument to 'word' function: '"+args[0]+"'") }
        if n == 0 { m.fail("first argument to 'word' function must be greater than 0") }
        list := words(args[1]); if n <= len(list) { return list[n-1] }; return ""
    case "wordlist":
        a, ok := integer(args[0]); if !ok { m.fail("non-numeric first argument to 'wordlist' function: '"+args[0]+"'") }
        b, ok := integer(args[1]); if !ok { m.fail("non-numeric second argument to 'wordlist' function: '"+args[1]+"'") }
        if a == 0 { m.fail("invalid first argument to 'wordlist' function: '"+args[0]+"'") }
        list := words(args[2]); if b > len(list) { b = len(list) }; if a > b { return "" }; return strings.Join(list[a-1:b], " ")
    case "words": return strconv.Itoa(len(words(args[0])))
    case "firstword", "lastword": list := words(args[0]); if len(list) == 0 { return "" }; if name == "firstword" { return list[0] }; return list[len(list)-1]
    case "dir", "notdir", "suffix", "basename":
        result := []string{}
        for _, word := range words(args[0]) {
            slash, dot := strings.LastIndexByte(word, '/'), strings.LastIndexByte(word, '.')
            switch name {
            case "dir": if slash < 0 { result = append(result, "./") } else { result = append(result, word[:slash+1]) }
            case "notdir": result = append(result, word[slash+1:])
            case "suffix": if dot > slash { result = append(result, word[dot:]) }
            case "basename": if dot > slash { word = word[:dot] }; result = append(result, word)
            }
        }
        return strings.Join(result, " ")
    case "addprefix", "addsuffix":
        list := words(args[1]); for i, word := range list { if name == "addprefix" { list[i] = args[0]+word } else { list[i] = word+args[0] } }; return strings.Join(list, " ")
    case "wildcard": result := []string{}; for _, pattern := range words(args[0]) { result = append(result, m.glob(pattern)...) }; return strings.Join(result, " ")
    case "value": return m.variables[args[0]].value
    case "info": m.emit("%s", args[0])
    case "warning": m.emit("%s: %s", m.location, args[0])
    case "error": m.fail(args[0])
    }
    return ""
}
func (m *simulator) register(target string, prerequisites []string) *rule {
    r := m.rules[target]
    if r == nil { r = &rule{target: target}; m.rules[target] = r }
    r.prerequisites = unique(append(r.prerequisites, prerequisites...))
    if m.goal == "" && !strings.HasPrefix(target, ".") { m.goal = target }
    return r
}
func (m *simulator) addRecipe(g *group, line recipeLine) {
    if len(g.targets) == 0 { return }
    if g.recipe == nil {
        g.recipe = &recipe{}
        for _, r := range g.targets {
            if g.explicit && r.recipe != nil {
                m.emit("Makefile:%d: warning: overriding recipe for target '%s'", line.number, r.target)
                m.emit("Makefile:%d: warning: ignoring old recipe for target '%s'", r.recipe.lines[0].number, r.target)
            }
            r.recipe = g.recipe
        }
    }
    g.recipe.lines = append(g.recipe.lines, line)
}
func (m *simulator) load(body []string) {
    m.clear()
    defer func(){
        if caught := recover(); caught != nil {
            if e, ok := caught.(expansionError); ok { m.emit("%s: *** %s.  Stop.", e.location, e.reason); m.clear() } else { panic(caught) }
        }
    }()
    var current *group
    stack := []condition{}
    active := func() bool { return len(stack) == 0 || stack[len(stack)-1].outer && stack[len(stack)-1].value }
    for index := 0; index < len(body); index++ {
        number, text := index+1, body[index]
        m.location = fmt.Sprintf("Makefile:%d", number)
        if strings.HasPrefix(text, ">") {
            if !active() { continue }
            if current == nil { m.fail("recipe commences before first target") }
            m.addRecipe(current, recipeLine{number, strings.TrimLeft(text[1:], " ")}); continue
        }
        for strings.HasSuffix(text, "\\") && index+1 < len(body) { index++; text = strings.TrimRight(text[:len(text)-1], " ")+" "+strings.TrimLeft(body[index], " ") }
        if hash := strings.IndexByte(text, '#'); hash >= 0 { text = text[:hash] }
        text = trim(text)
        first, rest, _ := strings.Cut(text, " ")
        rest = trim(rest)
        if first == "else" {
            if len(stack) == 0 { m.fail("extraneous 'else'") }
            top := &stack[len(stack)-1]
            if top.otherwise { m.fail("only one 'else' per conditional") }
            top.value, top.otherwise = !top.value, true; continue
        }
        if first == "endif" { if len(stack) == 0 { m.fail("extraneous 'endif'") }; stack = stack[:len(stack)-1]; continue }
        if first == "ifdef" || first == "ifndef" || first == "ifeq" || first == "ifneq" {
            outer, value := active(), false
            if outer {
                if first == "ifdef" || first == "ifndef" { v, exists := m.variables[trim(m.expand(rest))]; value = exists && v.value != ""; if first == "ifndef" { value = !value } } else {
                    if len(rest) < 2 || rest[0] != '(' || rest[len(rest)-1] != ')' { m.fail("invalid syntax in conditional") }
                    inside, depth, comma := rest[1:len(rest)-1], 0, -1
                    for i := 0; i < len(inside); i++ { if inside[i] == '(' { depth++ } else if inside[i] == ')' { depth-- } else if inside[i] == ',' && depth == 0 { comma = i; break } }
                    if comma < 0 { m.fail("invalid syntax in conditional") }
                    left := trim(m.expand(inside[:comma])); right := trim(m.expand(inside[comma+1:])); value = left == right; if first == "ifneq" { value = !value }
                }
            }
            stack = append(stack, condition{outer: outer, value: value, number: number}); continue
        }
        if text == "" || !active() { continue }
        eq, colon := m.outside(text, '='), m.outside(text, ':')
        if eq >= 0 && (colon < 0 || colon >= eq-1) {
            start, op := eq, byte('=')
            if eq > 0 && strings.ContainsRune(":+?", rune(text[eq-1])) { start, op = eq-1, text[eq-1] }
            name, value := trim(text[:start]), trim(text[eq+1:])
            if name == "" { m.fail("empty variable name") }
            old, exists := m.variables[name]
            switch op {
            case '=': m.variables[name] = variable{value: value}
            case ':': m.variables[name] = variable{simple: true, value: m.expand(value)}
            case '?': if !exists { m.variables[name] = variable{value: value} }
            case '+': if exists { if old.simple { value = m.expand(value) }; if old.value != "" { value = old.value+" "+value }; old.value = value; m.variables[name] = old } else { m.variables[name] = variable{value: value} }
            }
            current = nil; continue
        }
        if colon < 0 { if trim(m.expand(text)) != "" { m.fail("missing separator") }; continue }
        targets := unique(words(m.expand(text[:colon])))
        remainder := text[colon+1:]
        inline := ""
        hasInline := false
        if semi := m.outside(remainder, ';'); semi >= 0 { inline, remainder, hasInline = strings.TrimLeft(remainder[semi+1:], " "), remainder[:semi], true }
        pattern := ""
        static := false
        if at := m.outside(remainder, ':'); at >= 0 { pattern, remainder, static = trim(m.expand(remainder[:at])), remainder[at+1:], true }
        prerequisites := words(m.expand(remainder))
        current = &group{explicit: true}
        if len(targets) == 1 && targets[0] == ".PHONY" { for _, p := range prerequisites { m.phony[p] = true } } else if static {
            if !strings.Contains(pattern, "%") { m.fail("target pattern contains no '%'") }
            for _, target := range targets {
                stem, ok := match(pattern, target)
                if !ok || stem == "" { m.emit("Makefile:%d: target '%s' doesn't match the target pattern", number, target); continue }
                list := make([]string, len(prerequisites)); for i, p := range prerequisites { list[i] = substitute(p, stem) }
                r := m.register(target, list); r.stem = stem; current.targets = append(current.targets, r)
            }
        } else {
            patterns := 0
            for _, target := range targets { if strings.Contains(target, "%") { patterns++ } }
            if patterns > 0 && patterns != len(targets) { m.fail("mixed implicit and normal rules") }
            if patterns > 0 {
                current.explicit = false
                for _, target := range targets { r := &rule{target: target, prerequisites: append([]string(nil), prerequisites...)}; m.patterns = append(m.patterns, r); current.targets = append(current.targets, r) }
            } else { for _, target := range targets { current.targets = append(current.targets, m.register(target, prerequisites)) } }
        }
        if hasInline { m.addRecipe(current, recipeLine{number, inline}) }
    }
    if len(stack) > 0 { m.location = fmt.Sprintf("Makefile:%d", stack[len(stack)-1].number); m.fail("missing 'endif'") }
    m.loaded = true
    count := 0; for _, r := range m.patterns { if r.recipe != nil { count++ } }
    goal := m.goal; if goal == "" { goal = "(none)" }
    m.emit("Makefile loaded: lines=%d variables=%d targets=%d patterns=%d goal=%s", len(body), len(m.variables), len(m.rules), count, goal)
}

type chosenRule struct { prerequisites []string; recipe *recipe; stem string; source, missing bool }
func (m *simulator) determine(target string) chosenRule {
    explicit := m.rules[target]
    if explicit != nil && explicit.recipe != nil { return chosenRule{prerequisites: append([]string(nil), explicit.prerequisites...), recipe: explicit.recipe, stem: explicit.stem} }
    if !m.phony[target] {
        type candidate struct { rule *rule; stem string }
        candidates := []candidate{}
        for _, r := range m.patterns { if r.recipe != nil { if stem, ok := match(r.target, target); ok && stem != "" { candidates = append(candidates, candidate{r, stem}) } } }
        sort.SliceStable(candidates, func(i,j int) bool { return len(candidates[i].stem) < len(candidates[j].stem) })
        for _, c := range candidates {
            list, usable := []string{}, true
            for _, p := range c.rule.prerequisites { p = substitute(p, c.stem); list = append(list, p); if _, exists := m.files[p]; !exists && m.rules[p] == nil { usable = false } }
            if usable { if explicit != nil { list = append(list, explicit.prerequisites...) }; return chosenRule{prerequisites: unique(list), recipe: c.rule.recipe, stem: c.stem} }
        }
    }
    if explicit != nil { return chosenRule{prerequisites: append([]string(nil), explicit.prerequisites...), stem: explicit.stem} }
    if m.phony[target] { return chosenRule{} }
    if _, exists := m.files[target]; exists { return chosenRule{source: true} }
    return chosenRule{missing: true}
}
func (m *simulator) touch(name string) { m.clock++; m.files[name] = m.clock }
func (m *simulator) executeCommand(text string) int {
    list := words(text)
    switch list[0] {
    case "echo": m.emit("%s", strings.Join(list[1:], " "))
    case "touch": for _, name := range list[1:] { m.touch(name) }
    case "rm":
        forced, start, result := false, 1, 0
        if len(list) > 1 && list[1] == "-f" { forced, start = true, 2 }
        for _, pattern := range list[start:] {
            names := m.glob(pattern); if len(names) == 0 { names = []string{pattern} }
            for _, name := range names { if _, exists := m.files[name]; exists { delete(m.files, name) } else if !forced { m.emit("rm: cannot remove '%s': No such file or directory", name); result = 1 } }
        }
        return result
    case "false": return 1
    case "exit": if len(list) > 1 { n, _ := integer(list[1]); return n }
    }
    return 0
}
func (m *simulator) make(args []string) {
    options := map[byte]bool{}
    goals := []string{}
    for _, arg := range args {
        if strings.HasPrefix(arg, "-") { for i:=1; i<len(arg); i++ { if !strings.ContainsRune("nBkis", rune(arg[i])) { m.emit("make: invalid option -- '%c'", arg[i]); return }; options[arg[i]] = true } } else { goals = append(goals, arg) }
    }
    if len(goals) == 0 {
        if !m.loaded { m.emit("make: *** No targets specified and no makefile found.  Stop."); return }
        if m.goal == "" { m.emit("make: *** No targets.  Stop."); return }
        goals = []string{m.goal}
    }
    if options['n'] {
        saved := map[string]int{}; for name, t := range m.files { saved[name] = t }; clock := m.clock
        defer func(){ m.files, m.clock = saved, clock }()
    }
    defer func(){ if caught:=recover(); caught!=nil { if _,ok:=caught.(abortBuild); !ok { panic(caught) } } }()
    results := map[string]int{}
    selected := map[string]chosenRule{}
    building := map[string]bool{}
    runs := 0
    var build func(string,string) int
    build = func(target,parent string) int {
        if result, ok := results[target]; ok { return result }
        r := m.determine(target); selected[target] = r
        if r.missing {
            message := fmt.Sprintf("make: *** No rule to make target '%s'", target)
            if parent != "" { message += fmt.Sprintf(", needed by '%s'", parent) }; message += "."
            if !options['k'] { message += "  Stop." }; m.emit("%s", message); results[target] = 1
            if !options['k'] { panic(abortBuild{}) }; return 1
        }
        if r.source { results[target] = 0; return 0 }
        building[target] = true
        failed := false
        prerequisites := []string{}
        for _, p := range r.prerequisites {
            if building[p] { m.emit("make: Circular %s <- %s dependency dropped.", target, p); continue }
            prerequisites = append(prerequisites, p)
            if build(p,target) != 0 { failed = true }
        }
        delete(building,target)
        if failed { results[target] = 2; return 2 }
        time, exists := m.files[target]; exists = exists && !m.phony[target]
        newer := []string{}
        for _, p := range prerequisites { pt, present := m.files[p]; if options['B'] || !exists || !present || m.phony[p] || pt > time { newer = append(newer,p) } }
        if r.recipe == nil || !options['B'] && exists && len(newer) == 0 { results[target] = 0; return 0 }
        runs++
        first := ""; if len(prerequisites)>0 { first = prerequisites[0] }
        m.automatic = map[string]string{"@":target,"<":first,"^":strings.Join(prerequisites," "),"?":strings.Join(newer," "),"*":r.stem}
        expanded := make([]string,len(r.recipe.lines))
        for i,line := range r.recipe.lines { m.location=fmt.Sprintf("Makefile:%d",line.number); expanded[i]=m.expand(line.text) }
        m.automatic=nil
        for i,text := range expanded {
            pos:=0; for pos<len(text) && (text[pos]==' ' || text[pos]=='@' || text[pos]=='-') { pos++ }
            prefix, command := text[:pos], strings.TrimRight(text[pos:]," ")
            if command=="" { continue }
            if options['n'] || !strings.Contains(prefix,"@") && !options['s'] { m.emit("%s",command) }
            if options['n'] { continue }
            code:=m.executeCommand(command)
            if code==0 { continue }
            number:=r.recipe.lines[i].number
            if strings.Contains(prefix,"-") || options['i'] { m.emit("make: [Makefile:%d: %s] Error %d (ignored)",number,target,code) } else {
                m.emit("make: *** [Makefile:%d: %s] Error %d",number,target,code); results[target]=1
                if !options['k'] { panic(abortBuild{}) }; return 1
            }
        }
        if !m.phony[target] { m.touch(target) }
        results[target]=0; return 0
    }
    for _, goal := range goals {
        before:=runs; result:=build(goal,"")
        if result==0 && runs==before {
            if m.phony[goal] || selected[goal].recipe==nil { m.emit("make: Nothing to be done for '%s'.",goal) } else { m.emit("make: '%s' is up to date.",goal) }
        } else if result==2 { m.emit("make: Target '%s' not remade because of errors.",goal) }
    }
}
func (m *simulator) command(line string, body []string) {
    m.resetExpansion()
    defer func(){ if caught:=recover(); caught!=nil { if e,ok:=caught.(expansionError); ok { m.emit("%s: *** %s.  Stop.",e.location,e.reason) } else { panic(caught) } } }()
    m.emit("$ %s",line)
    command,text,_:=strings.Cut(line," ")
    switch command {
    case "MAKEFILE": m.load(body)
    case "MAKE": m.make(words(text))
    case "TOUCH": for _, name:=range words(text) { m.touch(name) }
    case "RM": for _, name:=range words(text) { if _,exists:=m.files[name]; exists { delete(m.files,name) } else { m.emit("rm: cannot remove '%s': No such file or directory",name) } }
    case "FILES": m.emit("clock %d",m.clock); for _,name:=range keys(m.files) { m.emit("%s %d",name,m.files[name]) }
    case "VARS": for _,name:=range keys(m.variables) { value:=trim(m.reference(name)); symbol:="="; if m.variables[name].simple { symbol=":=" }; if value=="" { m.emit("%s %s",name,symbol) } else { m.emit("%s %s %s",name,symbol,value) } }
    case "RULES":
        display:=func(r *rule){ m.emit("%s:",r.target); if len(r.prerequisites)>0 { m.output[len(m.output)-1]+=" "+strings.Join(r.prerequisites," ") }; if r.recipe!=nil { for _,line:=range r.recipe.lines { m.emit(">%s",line.text) } } }
        for _,name:=range keys(m.rules) { display(m.rules[name]) }; for _,r:=range m.patterns { if r.recipe!=nil { display(r) } }; if len(m.phony)>0 { m.emit(".PHONY: %s",strings.Join(keys(m.phony)," ")) }
    case "EXPAND": m.emit("[%s]",m.expand(text))
    }
}
func main() {
    scanner:=bufio.NewScanner(os.Stdin)
    m:=&simulator{files:map[string]int{}}
    m.clear(); scanner.Scan()
    for scanner.Scan() { line:=scanner.Text(); if line=="END FILES" { break }; name,text,_:=strings.Cut(line," "); n,_:=strconv.Atoi(text); m.files[name]=n; if n>m.clock { m.clock=n } }
    for scanner.Scan() {
        line:=scanner.Text(); if line=="QUIT" { break }
        body:=[]string{}
        if line=="MAKEFILE" { for scanner.Scan() { next:=scanner.Text(); if next=="END MAKEFILE" { break }; body=append(body,next) } }
        m.command(line,body)
    }
    writer:=bufio.NewWriter(os.Stdout); defer writer.Flush()
    for _,line:=range m.output { fmt.Fprintln(writer,line) }
}
