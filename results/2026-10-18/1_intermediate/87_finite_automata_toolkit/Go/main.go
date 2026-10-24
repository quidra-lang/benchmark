package main

import (
    "bufio"
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

type automaton struct {
    kind string
    states []string
    alphabet string
    start int
    final []bool
    transitions [][][]int
}
func makeAutomaton(kind string, states []string, alphabet string, start int) *automaton {
    a := &automaton{kind:kind, states:states, alphabet:alphabet, start:start, final:make([]bool,len(states)), transitions:make([][][]int,len(states))}
    for i := range states { a.transitions[i] = make([][]int,len(alphabet)+1) }
    return a
}
func series(prefix string,n int) []string { names := make([]string,n); for i := range names { names[i] = prefix+strconv.Itoa(i) }; return names }
func (a *automaton) add(p,c,q int) {
    for _,old := range a.transitions[p][c] { if old == q { return } }
    a.transitions[p][c] = append(a.transitions[p][c],q)
    sort.Ints(a.transitions[p][c])
}
func orderedSet(set []bool) []int { result := []int{}; for i,present := range set { if present { result = append(result,i) } }; return result }
func (a *automaton) closure(states []int) []int {
    seen := make([]bool,len(a.states)); queue := []int{}
    for _,state := range states { if !seen[state] { seen[state] = true; queue = append(queue,state) } }
    for i := 0; i < len(queue); i++ { for _,next := range a.transitions[queue[i]][len(a.alphabet)] { if !seen[next] { seen[next] = true; queue = append(queue,next) } } }
    return orderedSet(seen)
}
func (a *automaton) destination(states []int,c int) []int { next := []int{}; for _,state := range states { next = append(next,a.transitions[state][c]...) }; return a.closure(next) }
func (a *automaton) accepts(states []int) bool { for _,state := range states { if a.final[state] { return true } }; return false }
func (a *automaton) stateSet(states []int) string { names := []string{}; for _,state := range states { names = append(names,a.states[state]) }; return "{"+strings.Join(names,",")+"}" }
func (a *automaton) stateList(states []int) string { if len(states) == 0 { return "none" }; names := []string{}; for _,state := range states { names = append(names,a.states[state]) }; return strings.Join(names,",") }
func (a *automaton) summary(name string) string {
    finals,count := 0,0
    for _,accepting := range a.final { if accepting { finals++ } }
    for _,row := range a.transitions { for _,destinations := range row { count += len(destinations) } }
    return fmt.Sprintf("%s %s: alphabet=%s states=%d accepting=%d transitions=%d",a.kind,name,a.alphabet,len(a.states),finals,count)
}
func setKey(states []int) string { parts := []string{}; for _,state := range states { parts = append(parts,strconv.Itoa(state)) }; return strings.Join(parts,",") }
func determinize(a *automaton) (*automaton,[][]int) {
    sets := [][]int{a.closure([]int{a.start})}
    indices := map[string]int{setKey(sets[0]):0}
    rows := [][]int{}
    for i := 0; i < len(sets); i++ {
        row := []int{}
        for c := range a.alphabet {
            next := a.destination(sets[i],c)
            key := setKey(next)
            index,exists := indices[key]
            if !exists { index = len(sets); indices[key] = index; sets = append(sets,next) }
            row = append(row,index)
        }
        rows = append(rows,row)
    }
    d := makeAutomaton("DFA",series("D",len(sets)),a.alphabet,0)
    for i,set := range sets { d.final[i] = a.accepts(set); for c,next := range rows[i] { d.add(i,c,next) } }
    return d,sets
}
func graphReach(a *automaton,starts []int,reverse bool) []bool {
    edges := make([][]int,len(a.states))
    for p,row := range a.transitions { for _,destinations := range row { for _,q := range destinations { if reverse { edges[q] = append(edges[q],p) } else { edges[p] = append(edges[p],q) } } } }
    seen := make([]bool,len(a.states)); queue := []int{}
    for _,state := range starts { if !seen[state] { seen[state] = true; queue = append(queue,state) } }
    for i := 0; i < len(queue); i++ { for _,next := range edges[queue[i]] { if !seen[next] { seen[next] = true; queue = append(queue,next) } } }
    return seen
}
func partitionText(a *automaton,blocks [][]int) string { parts := []string{}; for _,block := range blocks { parts = append(parts,a.stateSet(block)) }; return strings.Join(parts," ") }
func minimize(a *automaton) (*automaton,[]string) {
    reachable := graphReach(a,[]int{a.start},false)
    missing := []int{}
    blocks := [][]int{}; byFinal := map[bool]int{}
    for state := range a.states {
        if !reachable[state] { missing = append(missing,state); continue }
        group,exists := byFinal[a.final[state]]
        if !exists { group = len(blocks); byFinal[a.final[state]] = group; blocks = append(blocks,[]int{}) }
        blocks[group] = append(blocks[group],state)
    }
    details := []string{"  unreachable: "+a.stateList(missing),"  round 0: "+partitionText(a,blocks)}
    for round := 1; ; round++ {
        membership := make([]int,len(a.states)); for i,block := range blocks { for _,state := range block { membership[state] = i } }
        next := [][]int{}; signatures := map[string]int{}
        for state := range a.states {
            if !reachable[state] { continue }
            signature := []int{membership[state]}
            for c := range a.alphabet { signature = append(signature,membership[a.transitions[state][c][0]]) }
            key := setKey(signature); group,exists := signatures[key]
            if !exists { group = len(next); signatures[key] = group; next = append(next,[]int{}) }
            next[group] = append(next[group],state)
        }
        if len(next) == len(blocks) { break }
        blocks = next
        details = append(details,fmt.Sprintf("  round %d: %s",round,partitionText(a,blocks)))
    }
    membership := make([]int,len(a.states)); for i,block := range blocks { for _,state := range block { membership[state] = i } }
    order := []int{membership[a.start]}; indices := map[int]int{order[0]:0}
    rows := [][]int{}
    for i := 0; i < len(order); i++ {
        representative := blocks[order[i]][0]
        row := []int{}
        for c := range a.alphabet { group := membership[a.transitions[representative][c][0]]; index,exists := indices[group]; if !exists { index = len(order); indices[group] = index; order = append(order,group) }; row = append(row,index) }
        rows = append(rows,row)
    }
    result := makeAutomaton("DFA",series("M",len(order)),a.alphabet,0)
    for i,group := range order { result.final[i] = a.final[blocks[group][0]]; for c,next := range rows[i] { result.add(i,c,next) }; details = append(details,fmt.Sprintf("  M%d = %s",i,a.stateSet(blocks[group]))) }
    return result,details
}
type pair struct { left,right int }
func product(a,b *automaton,command string) (*automaton,[]string) {
    pairs := []pair{{a.start,b.start}}; indices := map[pair]int{pairs[0]:0}; rows := [][]int{}
    for i := 0; i < len(pairs); i++ {
        row := []int{}
        for c := range a.alphabet { next := pair{a.transitions[pairs[i].left][c][0],b.transitions[pairs[i].right][c][0]}; index,exists := indices[next]; if !exists { index = len(pairs); indices[next] = index; pairs = append(pairs,next) }; row = append(row,index) }
        rows = append(rows,row)
    }
    result := makeAutomaton("DFA",series("P",len(pairs)),a.alphabet,0); details := []string{}
    for i,p := range pairs {
        x,y := a.final[p.left],b.final[p.right]
        result.final[i] = command == "UNION" && (x || y) || command == "INTERSECT" && x && y || command == "DIFF" && x && !y
        for c,next := range rows[i] { result.add(i,c,next) }
        details = append(details,fmt.Sprintf("  P%d = (%s,%s)",i,a.states[p.left],b.states[p.right]))
    }
    return result,details
}
func wordText(word string) string { if word == "" { return "e" }; return word }
func witness(a *automaton) (string,bool) {
    type item struct { state int; word string }
    queue := []item{{a.start,""}}; seen := map[int]bool{a.start:true}
    for i := 0; i < len(queue); i++ {
        current := queue[i]
        if a.final[current.state] { return current.word,true }
        for c := range a.alphabet { next := a.transitions[current.state][c][0]; if !seen[next] { seen[next] = true; queue = append(queue,item{next,current.word+a.alphabet[c:c+1]}) } }
    }
    return "",false
}
func equivalent(a,b *automaton) (string,bool,bool) {
    type item struct { pair pair; word string }
    initial := pair{a.start,b.start}; queue := []item{{initial,""}}; seen := map[pair]bool{initial:true}
    for i := 0; i < len(queue); i++ {
        current := queue[i]; p := current.pair
        if a.final[p.left] != b.final[p.right] { return current.word,a.final[p.left],false }
        for c := range a.alphabet { next := pair{a.transitions[p.left][c][0],b.transitions[p.right][c][0]}; if !seen[next] { seen[next] = true; queue = append(queue,item{next,current.word+a.alphabet[c:c+1]}) } }
    }
    return "",false,true
}
func language(a *automaton) (string,[]bool) {
    finals := []int{}; for state,accepting := range a.final { if accepting { finals = append(finals,state) } }
    live := graphReach(a,finals,true)
    if !live[a.start] { return "empty",live }
    colors := make([]int,len(a.states))
    var cycle func(int) bool
    cycle = func(state int) bool {
        colors[state] = 1
        for c := range a.alphabet { next := a.transitions[state][c][0]; if !live[next] { continue }; if colors[next] == 1 || colors[next] == 0 && cycle(next) { return true } }
        colors[state] = 2
        return false
    }
    if cycle(a.start) { return "infinite",live }
    return "finite",live
}
func finiteCount(a *automaton,live []bool) int64 {
    memo := map[int]int64{}
    var count func(int) int64
    count = func(state int) int64 {
        if !live[state] { return 0 }
        if value,exists := memo[state]; exists { return value }
        result := int64(0); if a.final[state] { result = 1 }
        for c := range a.alphabet { result += count(a.transitions[state][c][0]) }
        memo[state] = result
        return result
    }
    return count(a.start)
}
func countLength(a *automaton,n int) int64 {
    counts := make([]int64,len(a.states)); counts[a.start] = 1
    for step := 0; step < n; step++ { next := make([]int64,len(a.states)); for state,count := range counts { for c := range a.alphabet { next[a.transitions[state][c][0]] += count } }; counts = next }
    total := int64(0); for state,count := range counts { if a.final[state] { total += count } }; return total
}
func synchronize(a *automaton) (string,int,bool) {
    type item struct { states []int; word string }
    initial := make([]int,len(a.states)); for i := range initial { initial[i] = i }
    queue := []item{{initial,""}}; seen := map[string]bool{setKey(initial):true}
    for i := 0; i < len(queue); i++ {
        current := queue[i]
        if len(current.states) == 1 { return current.word,current.states[0],true }
        for c := range a.alphabet {
            present := make([]bool,len(a.states)); for _,state := range current.states { present[a.transitions[state][c][0]] = true }; next := orderedSet(present); key := setKey(next)
            if !seen[key] { seen[key] = true; queue = append(queue,item{next,current.word+a.alphabet[c:c+1]}) }
        }
    }
    return "",0,false
}
type regex struct { kind byte; children []*regex }
type regexParser struct { text string; at int }
func (p *regexParser) peek() byte { if p.at == len(p.text) { return 0 }; return p.text[p.at] }
func (p *regexParser) invalid() { fail("syntax error at %d",p.at+1) }
func (p *regexParser) atom() *regex {
    c := p.peek()
    if c >= 'a' && c <= 'z' || c >= '0' && c <= '9' { p.at++; return &regex{kind:c} }
    if c == '(' { p.at++; result := p.alternation(); if p.peek() != ')' { p.invalid() }; p.at++; return result }
    p.invalid(); return nil
}
func (p *regexParser) factor() *regex { result := p.atom(); for p.peek() == '*' || p.peek() == '+' || p.peek() == '?' { c := p.peek(); p.at++; result = &regex{kind:c,children:[]*regex{result}} }; return result }
func (p *regexParser) concatenation() *regex {
    children := []*regex{p.factor()}
    for { c := p.peek(); if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '(') { break }; children = append(children,p.factor()) }
    if len(children) == 1 { return children[0] }; return &regex{kind:'.',children:children}
}
func (p *regexParser) alternation() *regex { children := []*regex{p.concatenation()}; for p.peek() == '|' { p.at++; children = append(children,p.concatenation()) }; if len(children) == 1 { return children[0] }; return &regex{kind:'|',children:children} }
func regexAutomaton(tree *regex,alphabet string) *automaton {
    type transition struct { p,c,q int }
    transitions := []transition{}; count := 0
    state := func() int { result := count; count++; return result }
    add := func(p,c,q int) { transitions = append(transitions,transition{p,c,q}) }
    var build func(*regex) (int,int)
    build = func(tree *regex) (int,int) {
        if len(tree.children) == 0 { s,f := state(),state(); c := len(alphabet); if tree.kind != 'e' { c = strings.IndexByte(alphabet,tree.kind) }; add(s,c,f); return s,f }
        if tree.kind == '.' {
            start,previous := build(tree.children[0])
            for _,child := range tree.children[1:] { s,f := build(child); add(previous,len(alphabet),s); previous = f }
            return start,previous
        }
        start := state()
        if tree.kind == '|' {
            parts := [][2]int{}
            for _,child := range tree.children { s,f := build(child); parts = append(parts,[2]int{s,f}) }
            end := state()
            for _,part := range parts { add(start,len(alphabet),part[0]); add(part[1],len(alphabet),end) }
            return start,end
        }
        s,f := build(tree.children[0]); end := state()
        add(start,len(alphabet),s); add(f,len(alphabet),end)
        if tree.kind != '?' { add(f,len(alphabet),s) }
        if tree.kind != '+' { add(start,len(alphabet),end) }
        return start,end
    }
    start,end := build(tree)
    result := makeAutomaton("NFA",series("N",count),alphabet,start); result.final[end] = true
    for _,t := range transitions { result.add(t.p,t.c,t.q) }
    return result
}
type problem string
func fail(format string,args ...any) { panic(problem(fmt.Sprintf(format,args...))) }
func sortedAlphabet(text string) string { chars := []byte(text); sort.Slice(chars,func(i,j int) bool { return chars[i] < chars[j] }); return string(chars) }
func stateIndex(a *automaton,name string) int { for i,state := range a.states { if state == name { return i } }; fail("unknown state %s",name); return -1 }
type entry struct { name string; automaton *automaton }
type toolkit struct { table []entry }
func (t *toolkit) find(name string) *automaton { for _,entry := range t.table { if entry.name == name { return entry.automaton } }; return nil }
func (t *toolkit) register(name string,a *automaton,details []string) []string { t.table = append(t.table,entry{name,a}); return append([]string{a.summary(name)},details...) }
func (t *toolkit) define(command string,args []string) []string {
    if len(args) < 5 { fail("wrong number of arguments") }
    name := args[0]; if t.find(name) != nil { fail("%s already exists",name) }
    states := strings.Split(args[1],","); seen := map[string]bool{}
    for _,state := range states { if seen[state] { fail("duplicate state %s",state) }; seen[state] = true }
    a := makeAutomaton(command,states,sortedAlphabet(args[2]),0); a.start = stateIndex(a,args[3])
    if args[4] != "-" { for _,state := range strings.Split(args[4],",") { index := stateIndex(a,state); if a.final[index] { fail("duplicate state %s",state) }; a.final[index] = true } }
    triples := map[string]bool{}; pairs := map[[2]int]bool{}
    for _,word := range args[5:] {
        parts := strings.Split(word,":"); p := stateIndex(a,parts[0]); c := strings.IndexByte(a.alphabet,parts[1][0])
        if parts[1] == "e" { if command == "DFA" { fail("epsilon transition in DFA") }; c = len(a.alphabet) } else if c < 0 { fail("unknown symbol %s",parts[1]) }
        q := stateIndex(a,parts[2])
        if triples[word] { fail("duplicate transition %s",word) }; triples[word] = true
        key := [2]int{p,c}; if command == "DFA" && pairs[key] { fail("conflicting transition %s",word) }; pairs[key] = true
        a.add(p,c,q)
    }
    if command == "DFA" { for state := range states { for c := range a.alphabet { if len(a.transitions[state][c]) == 0 { fail("missing transition %s:%c",states[state],a.alphabet[c]) } } } }
    return t.register(name,a,nil)
}
func (t *toolkit) command(words []string) []string {
    command,args := words[0],words[1:]
    counts := map[string]int{"ACCEPT":2,"CLOSURE":2,"TODFA":2,"EPSFREE":2,"MINIMIZE":2,"EQUIV":2,"UNION":3,"INTERSECT":3,"DIFF":3,"COMPLEMENT":2,"REVERSE":2,"CONCAT":3,"STAR":2,"ENUM":2,"COUNT":2,"EMPTY":1,"FINITE":1,"INFO":1,"TABLE":1,"SHOW":1,"SYNC":1,"LIST":0,"DELETE":1}
    if command == "DFA" || command == "NFA" { return t.define(command,args) }
    if command == "REGEX" {
        if len(args) != 3 { fail("wrong number of arguments") }; if t.find(args[0]) != nil { fail("%s already exists",args[0]) }
        alphabet := sortedAlphabet(args[1])
        for i := range args[2] { c := args[2][i]; if (c >= 'a' && c <= 'z' || c >= '0' && c <= '9') && c != 'e' && strings.IndexByte(alphabet,c) < 0 { fail("unknown symbol %c",c) } }
        parser := regexParser{text:args[2]}; tree := parser.alternation(); if parser.at != len(parser.text) { parser.invalid() }
        return t.register(args[0],regexAutomaton(tree,alphabet),nil)
    }
    count,known := counts[command]
    if !known { fail("unknown command %s",command) }; if len(args) != count { fail("wrong number of arguments") }
    if command == "LIST" { if len(t.table) == 0 { return []string{"(none)"} }; lines := []string{}; for _,entry := range t.table { lines = append(lines,entry.automaton.summary(entry.name)) }; return lines }
    references := 1
    if command == "EQUIV" || command == "UNION" || command == "INTERSECT" || command == "DIFF" || command == "CONCAT" { references = 2 }
    autos := []*automaton{}
    for i := 0; i < references; i++ { a := t.find(args[i]); if a == nil { fail("unknown automaton %s",args[i]) }; autos = append(autos,a) }
    creates := command == "TODFA" || command == "EPSFREE" || command == "MINIMIZE" || command == "UNION" || command == "INTERSECT" || command == "DIFF" || command == "COMPLEMENT" || command == "REVERSE" || command == "CONCAT" || command == "STAR"
    if creates && t.find(args[len(args)-1]) != nil { fail("%s already exists",args[len(args)-1]) }
    requiresDfa := command == "MINIMIZE" || command == "UNION" || command == "INTERSECT" || command == "DIFF" || command == "COMPLEMENT" || command == "SYNC"
    if requiresDfa { for i,a := range autos { if a.kind != "DFA" { fail("%s is not a DFA",args[i]) } } }
    if references == 2 && autos[0].alphabet != autos[1].alphabet { fail("alphabets differ") }
    a := autos[0]
    switch command {
    case "DELETE": for i,entry := range t.table { if entry.name == args[0] { t.table = append(t.table[:i],t.table[i+1:]...); break } }; return []string{"deleted "+args[0]}
    case "ACCEPT":
        word := args[1]; if word == "e" { word = "" }
        for i := range word { if strings.IndexByte(a.alphabet,word[i]) < 0 { fail("unknown symbol %c",word[i]) } }
        states := a.closure([]int{a.start}); display := func(states []int) string { if a.kind == "DFA" { return a.states[states[0]] }; return a.stateSet(states) }
        path := display(states)
        for i := range word { states = a.destination(states,strings.IndexByte(a.alphabet,word[i])); path += fmt.Sprintf(" -%c-> %s",word[i],display(states)) }
        verdict := "REJECT"; if a.accepts(states) { verdict = "ACCEPT" }; return []string{verdict+" "+path}
    case "CLOSURE": states := []int{}; for _,state := range strings.Split(args[1],",") { states = append(states,stateIndex(a,state)) }; return []string{a.stateSet(a.closure(states))}
    case "TODFA": result,sets := determinize(a); details := []string{}; for i,set := range sets { details = append(details,fmt.Sprintf("  D%d = %s",i,a.stateSet(set))) }; return t.register(args[1],result,details)
    case "EPSFREE":
        result := makeAutomaton("NFA",append([]string(nil),a.states...),a.alphabet,a.start)
        for state := range a.states { closure := a.closure([]int{state}); result.final[state] = a.accepts(closure); for c := range a.alphabet { for _,next := range a.destination(closure,c) { result.add(state,c,next) } } }; return t.register(args[1],result,nil)
    case "MINIMIZE": result,details := minimize(a); return t.register(args[1],result,details)
    case "UNION", "INTERSECT", "DIFF": result,details := product(a,autos[1],command); return t.register(args[2],result,details)
    case "EQUIV":
        x,_ := determinize(a); z,_ := determinize(autos[1]); word,left,same := equivalent(x,z)
        if same { return []string{"EQUIVALENT"} }; owner := args[1]; if left { owner = args[0] }; return []string{fmt.Sprintf("NOT EQUIVALENT: %s is accepted only by %s",wordText(word),owner)}
    case "COMPLEMENT": result := makeAutomaton("DFA",append([]string(nil),a.states...),a.alphabet,a.start); for state := range a.states { result.final[state] = !a.final[state]; for c := range a.alphabet { result.add(state,c,a.transitions[state][c][0]) } }; return t.register(args[1],result,nil)
    case "REVERSE", "CONCAT", "STAR":
        total,start := len(a.states)+1,0
        if command == "CONCAT" { total,start = len(a.states)+len(autos[1].states),a.start }
        result := makeAutomaton("NFA",series("N",total),a.alphabet,start); epsilon := len(a.alphabet)
        if command == "REVERSE" {
            for p,row := range a.transitions { for c,destinations := range row { for _,q := range destinations { result.add(q+1,c,p+1) } } }; for state,accepting := range a.final { if accepting { result.add(0,epsilon,state+1) } }; result.final[a.start+1] = true
        } else if command == "STAR" {
            for p,row := range a.transitions { for c,destinations := range row { for _,q := range destinations { result.add(p+1,c,q+1) } } }; result.final[0] = true; result.add(0,epsilon,a.start+1); for state,accepting := range a.final { if accepting { result.final[state+1] = true; result.add(state+1,epsilon,a.start+1) } }
        } else {
            for p,row := range a.transitions { for c,destinations := range row { for _,q := range destinations { result.add(p,c,q) } } }
            b := autos[1]; offset := len(a.states)
            for p,row := range b.transitions { for c,destinations := range row { for _,q := range destinations { result.add(p+offset,c,q+offset) } } }
            for state,accepting := range a.final { if accepting { result.add(state,epsilon,b.start+offset) } }; for state,accepting := range b.final { result.final[state+offset] = accepting }
        }
        return t.register(args[len(args)-1],result,nil)
    case "SYNC": word,state,found := synchronize(a); if !found { return []string{"NOT SYNCHRONIZING"} }; return []string{fmt.Sprintf("SYNCHRONIZING %s -> %s",wordText(word),a.states[state])}
    case "COUNT": n,_ := strconv.Atoi(args[1]); d,_ := determinize(a); return []string{strconv.FormatInt(countLength(d,n),10)}
    case "ENUM":
        k,_ := strconv.Atoi(args[1]); d,_ := determinize(a)
        type item struct { state int; word string }
        queue := []item{{d.start,""}}; total := 0; accepted := []string{}
        for i := 0; i < len(queue); i++ { current := queue[i]; if d.final[current.state] { total++; if len(accepted) < 50 { accepted = append(accepted,wordText(current.word)) } }; if len(current.word) < k { for c := range d.alphabet { queue = append(queue,item{d.transitions[current.state][c][0],current.word+d.alphabet[c:c+1]}) } } }
        text := strconv.Itoa(total); if len(accepted) > 0 { text += " "+strings.Join(accepted," ") }; if total > 50 { text += " ..." }; return []string{text}
    case "EMPTY": d,_ := determinize(a); word,found := witness(d); if !found { return []string{"EMPTY"} }; return []string{"NOT EMPTY "+wordText(word)}
    case "FINITE": d,_ := determinize(a); classification,live := language(d); if classification == "infinite" { return []string{"INFINITE"} }; return []string{fmt.Sprintf("FINITE %d",finiteCount(d,live))}
    case "INFO":
        epsilon,deterministic,complete := 0,true,true
        finals := []int{}; for state,accepting := range a.final { if accepting { finals = append(finals,state) }; epsilon += len(a.transitions[state][len(a.alphabet)]); for c := range a.alphabet { if len(a.transitions[state][c]) > 1 { deterministic = false }; if len(a.transitions[state][c]) == 0 { complete = false } } }
        if epsilon > 0 { deterministic = false }
        d,_ := determinize(a); classification,_ := language(d); minimal,_ := minimize(d)
        yes := func(value bool) string { if value { return "yes" }; return "no" }
        return []string{a.summary(args[0]),fmt.Sprintf("  epsilon transitions: %d",epsilon),"  reachable: "+a.stateList(orderedSet(graphReach(a,[]int{a.start},false))),"  live: "+a.stateList(orderedSet(graphReach(a,finals,true))),"  deterministic: "+yes(deterministic),"  complete: "+yes(complete),"  language: "+classification,fmt.Sprintf("  minimal DFA states: %d",len(minimal.states))}
    case "SHOW":
        finals := []string{}; for state,accepting := range a.final { if accepting { finals = append(finals,a.states[state]) } }; finalText := "-"; if len(finals) > 0 { finalText = strings.Join(finals,",") }
        parts := []string{a.kind,args[0],strings.Join(a.states,","),a.alphabet,a.states[a.start],finalText}
        for p,row := range a.transitions { for c,destinations := range row { symbol := "e"; if c < len(a.alphabet) { symbol = a.alphabet[c:c+1] }; for _,q := range destinations { parts = append(parts,a.states[p]+":"+symbol+":"+a.states[q]) } } }
        return []string{strings.Join(parts," ")}
    case "TABLE":
        columns := len(a.alphabet)+1; epsilon := false
        if a.kind == "NFA" { for state := range a.states { if len(a.transitions[state][len(a.alphabet)]) > 0 { epsilon = true; break } } }; if epsilon { columns++ }
        rows := [][]string{make([]string,columns)}
        for c := 0; c < columns-1; c++ { if c < len(a.alphabet) { rows[0][c+1] = a.alphabet[c:c+1] } else { rows[0][c+1] = "e" } }
        for state,name := range a.states {
            row := make([]string,columns); row[0] = "  "; if state == a.start { row[0] = "->" }; if a.final[state] { row[0] += "*" } else { row[0] += " " }; row[0] += name
            for c := 0; c < columns-1; c++ { if a.kind == "DFA" { row[c+1] = a.states[a.transitions[state][c][0]] } else if len(a.transitions[state][c]) == 0 { row[c+1] = "-" } else { row[c+1] = a.stateSet(a.transitions[state][c]) } }; rows = append(rows,row)
        }
        widths := make([]int,columns); for _,row := range rows { for c,text := range row { widths[c] = max(widths[c],len(text)) } }
        lines := []string{}; for _,row := range rows { cells := []string{}; for c,text := range row { cells = append(cells,text+strings.Repeat(" ",widths[c]-len(text))) }; lines = append(lines,strings.TrimRight(strings.Join(cells,"  ")," ")) }; return lines
    }
    return nil
}
func (t *toolkit) process(line string,out *bufio.Writer) {
    if strings.HasPrefix(line,"#") { return }
    defer func() { if caught := recover(); caught != nil { if reason,ok := caught.(problem); ok { fmt.Fprintf(out,"error: %s\n",reason) } else { panic(caught) } } }()
    for _,text := range t.command(strings.Split(line," ")) { fmt.Fprintln(out,text) }
}
func main() {
    scanner := bufio.NewScanner(os.Stdin); out := bufio.NewWriter(os.Stdout); defer out.Flush()
    scanner.Scan(); count,_ := strconv.Atoi(scanner.Text()); toolkit := toolkit{}
    for i := 0; i < count && scanner.Scan(); i++ { toolkit.process(scanner.Text(),out) }
}
