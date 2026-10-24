package main

import (
    "bufio"
    "fmt"
    "os"
    "strconv"
    "strings"
)

type token struct {
    text,kind,name string
    value int64
    line int
    sign bool
}
type expression struct { kind string; token token; args []*expression }
type input struct { expression *expression; quoted *token; list []*command }
type command struct { token token; kind string; inputs []input }
type procedure struct { name string; line int; parameters []string; tokens []token; body []*command }
type sourceLine struct { text string; number int }
type logoError struct { line int; reason string }
type point struct { x,y int64 }
type environment struct { variables map[string]int64; test *bool }
type control struct { output bool; value int64 }
type runtime struct {
    procedures map[string]*procedure
    environments []*environment
    calls []string
    repetitions []int64
    traced map[string]bool
    canvas map[point]byte
    x,y,heading int64
    pen string
    character byte
    random int64
    output *[]string
}
type primitive struct { canonical,inputs string; function bool }
var primitives = map[string]primitive{}
func initialize() {
    groups := []struct { names,canonical,inputs string; function bool }{
        {"FD FORWARD","FD","E",false},{"BK BACK","BK","E",false},
        {"RT RIGHT","RT","E",false},{"LT LEFT","LT","E",false},{"SETH SETHEADING","SETH","E",false},
        {"PU PENUP","PU","",false},{"PD PENDOWN","PD","",false},{"PE PENERASE","PE","",false},
        {"SETPEN","SETPEN","E",false},{"SETXY","SETXY","EE",false},{"SETX","SETX","E",false},{"SETY","SETY","E",false},
        {"HOME","HOME","",false},{"CS CLEARSCREEN","CS","",false},{"CLEAN","CLEAN","",false},{"FILL","FILL","",false},
        {"LABEL","LABEL","P",false},{"SNAPSHOT","SNAPSHOT","",false},{"REPEAT","REPEAT","EL",false},
        {"FOR","FOR","QEEL",false},{"WHILE","WHILE","EL",false},{"IF","IF","EL",false},{"IFELSE","IFELSE","ELL",false},
        {"TEST","TEST","E",false},{"IFTRUE IFT","IFTRUE","L",false},{"IFFALSE IFF","IFFALSE","L",false},
        {"STOP","STOP","",false},{"OUTPUT OP","OUTPUT","E",false},{"MAKE","MAKE","QE",false},
        {"LOCAL","LOCAL","Q",false},{"LOCALMAKE","LOCALMAKE","QE",false},{"TRACE","TRACE","Q",false},{"UNTRACE","UNTRACE","Q",false},
        {"SEED","SEED","E",false},{"PRINT PR","PRINT","P",false},
        {"XCOR","XCOR","",true},{"YCOR","YCOR","",true},{"HEADING","HEADING","",true},{"REPCOUNT","REPCOUNT","",true},
        {"RANDOM","RANDOM","E",true},{"ABS","ABS","E",true},{"NOT","NOT","E",true},
        {"AND","AND","EE",true},{"OR","OR","EE",true},{"MAX","MAX","EE",true},{"MIN","MIN","EE",true},
        {"TO","TO","",false},{"END","END","",false},{"MOD","MOD","",false},
    }
    for _,group := range groups {
        for _,name := range strings.Split(group.names," ") { primitives[name] = primitive{group.canonical,group.inputs,group.function} }
    }
}
func fail(t token,format string,args ...any) { panic(logoError{t.line,fmt.Sprintf(format,args...)}) }
func isName(s string) bool {
    if s == "" || s[0] < 'A' || s[0] > 'Z' { return false }
    for _,c := range s { if !(c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_') { return false } }
    return true
}
func isNumber(s string) bool {
    if s == "" { return false }
    for _,c := range s { if c < '0' || c > '9' { return false } }
    return true
}
func lex(line sourceLine) []token {
    text := line.text
    if at := strings.IndexByte(text,';'); at >= 0 { text = text[:at] }
    text = strings.ToUpper(text)
    result := []token{}
    for i := 0; i < len(text); {
        if text[i] == ' ' { i++; continue }
        start := i
        t := token{line:line.number,kind:"symbol"}
        if strings.ContainsRune("[]()+*/=",rune(text[i])) { i++ } else if text[i] == '<' || text[i] == '>' {
            i++
            if i < len(text) && (text[i] == '=' || text[start] == '<' && text[i] == '>') { i++ }
        } else if text[i] == '-' {
            t.sign = (i == 0 || strings.ContainsRune(" [(",rune(text[i-1]))) && i+1 < len(text) && text[i+1] != ' '
            i++
        } else {
            for i < len(text) && !strings.ContainsRune(" []()+-*/=<>",rune(text[i])) { i++ }
            word := text[start:i]
            if isNumber(word) {
                t.kind = "number"
                t.value,_ = strconv.ParseInt(word,10,64)
            } else if word[0] == ':' && isName(word[1:]) { t.kind,t.name = "variable",word[1:] } else if word[0] == '"' && isName(word[1:]) { t.kind,t.name = "quoted",word[1:] } else if isName(word) { t.kind,t.name = "word",word } else { fail(t,"bad token '%s'",word) }
        }
        t.text = text[start:i]
        result = append(result,t)
    }
    return result
}
type parser struct { tokens []token; position int; procedures map[string]*procedure; inside bool }
func (p *parser) peek() *token { if p.position == len(p.tokens) { return nil }; return &p.tokens[p.position] }
func (p *parser) take() token { t := p.tokens[p.position]; p.position++; return t }
func (p *parser) unknown(t token) bool { _,primitive := primitives[t.text]; return t.kind == "word" && !primitive && p.procedures[t.text] == nil }
func (p *parser) check(owner token) token {
    next := p.peek()
    if next == nil || next.text == "]" || next.text == ")" { fail(owner,"not enough inputs to %s",owner.text) }
    if p.unknown(*next) { fail(*next,"I don't know how to %s",next.text) }
    return *next
}
func (p *parser) readInput(kind byte,owner token) input {
    next := p.check(owner)
    if kind == 'L' {
        if next.text != "[" { fail(next,"%s doesn't like %s as input",owner.text,next.text) }
        opening := p.take()
        commands := []*command{}
        for {
            t := p.peek()
            if t == nil { fail(opening,"missing ]") }
            if t.text == "]" { p.take(); break }
            commands = append(commands,p.readCommand())
        }
        return input{list:commands}
    }
    if kind == 'Q' || kind == 'P' && next.kind == "quoted" {
        if next.kind != "quoted" { fail(next,"%s doesn't like %s as input",owner.text,next.text) }
        word := p.take()
        return input{quoted:&word}
    }
    return input{expression:p.comparison(owner)}
}
func (p *parser) term(owner token) *expression {
    t := p.check(owner)
    p.take()
    result := &expression{token:t}
    switch {
    case t.kind == "number": result.kind = "number"
    case t.kind == "variable": result.kind = "variable"
    case t.text == "-": result.kind,result.args = "unary",[]*expression{p.term(t)}
    case t.text == "(":
        value := p.comparison(t)
        if p.peek() == nil || p.peek().text != ")" { fail(t,"missing )") }
        p.take()
        return value
    default:
        if primitive,exists := primitives[t.text]; exists && primitive.function {
            result.kind = "function"
            for range primitive.inputs { result.args = append(result.args,p.readInput('E',t).expression) }
        } else if procedure := p.procedures[t.text]; t.kind == "word" && procedure != nil {
            result.kind = "procedure"
            for range procedure.parameters { result.args = append(result.args,p.readInput('E',t).expression) }
        } else { fail(t,"%s doesn't like %s as input",owner.text,t.text) }
    }
    return result
}
func (p *parser) product(owner token) *expression {
    result := p.term(owner)
    for p.peek() != nil && (p.peek().text == "*" || p.peek().text == "/" || p.peek().text == "MOD") {
        op := p.take()
        result = &expression{kind:"binary",token:op,args:[]*expression{result,p.term(op)}}
    }
    return result
}
func (p *parser) sum(owner token) *expression {
    result := p.product(owner)
    for p.peek() != nil && (p.peek().text == "+" || p.peek().text == "-" && !p.peek().sign) {
        op := p.take()
        result = &expression{kind:"binary",token:op,args:[]*expression{result,p.product(op)}}
    }
    return result
}
func (p *parser) comparison(owner token) *expression {
    result := p.sum(owner)
    for p.peek() != nil && contains(p.peek().text,"=","<>","<",">","<=",">=") {
        op := p.take()
        result = &expression{kind:"binary",token:op,args:[]*expression{result,p.sum(op)}}
    }
    return result
}
func contains(value string,list ...string) bool { for _,item := range list { if value == item { return true } }; return false }
func (p *parser) readCommand() *command {
    t := p.take()
    if t.text == "]" { fail(t,"unexpected ]") }
    if t.text == "(" && p.peek() != nil && p.peek().kind == "word" && contains(p.peek().text,"PRINT","PR") {
        owner := p.take()
        result := &command{token:owner,kind:"multiple"}
        for {
            next := p.peek()
            if next == nil || next.text == "]" { fail(t,"missing )") }
            if next.text == ")" { p.take(); return result }
            result.inputs = append(result.inputs,p.readInput('P',owner))
        }
    }
    if t.kind == "word" && contains(t.text,"TO","END") { fail(t,"misplaced %s",t.text) }
    result := &command{token:t}
    if primitive,exists := primitives[t.text]; exists && t.kind == "word" && !primitive.function && primitive.canonical != "MOD" {
        result.kind = primitive.canonical
        if !p.inside && contains(result.kind,"STOP","OUTPUT","LOCAL","LOCALMAKE") { fail(t,"can only use %s inside a procedure",t.text) }
        for _,kind := range []byte(primitive.inputs) { result.inputs = append(result.inputs,p.readInput(kind,t)) }
        if contains(result.kind,"TRACE","UNTRACE") && p.procedures[result.inputs[0].quoted.name] == nil { fail(*result.inputs[0].quoted,"I don't know how to %s",result.inputs[0].quoted.name) }
    } else if procedure := p.procedures[t.text]; t.kind == "word" && procedure != nil {
        result.kind = "procedure"
        for range procedure.parameters { result.inputs = append(result.inputs,p.readInput('E',t)) }
    } else if p.unknown(t) { fail(t,"I don't know how to %s",t.text) } else { fail(t,"you don't say what to do with %s",t.text) }
    return result
}
func (p *parser) sequence() []*command {
    result := []*command{}
    for p.peek() != nil { result = append(result,p.readCommand()) }
    return result
}
func (r *runtime) emit(format string,args ...any) { *r.output = append(*r.output,fmt.Sprintf(format,args...)) }
func (r *runtime) current() *environment { return r.environments[len(r.environments)-1] }
func (r *runtime) assign(name string,value int64) {
    for i := len(r.environments)-1; i > 0; i-- {
        if _,exists := r.environments[i].variables[name]; exists { r.environments[i].variables[name] = value; return }
    }
    r.environments[0].variables[name] = value
}
func truth(value bool) int64 { if value { return 1 }; return 0 }
func (r *runtime) evaluate(e *expression) int64 {
    t := e.token
    if e.kind == "number" { return t.value }
    if e.kind == "variable" {
        for i := len(r.environments)-1; i >= 0; i-- { if value,exists := r.environments[i].variables[t.name]; exists { return value } }
        fail(t,"%s has no value",t.name)
    }
    if e.kind == "unary" { return -r.evaluate(e.args[0]) }
    values := []int64{}
    for _,argument := range e.args { values = append(values,r.evaluate(argument)) }
    if e.kind == "procedure" {
        value := r.call(t,values)
        if value == nil { fail(t,"%s did not output",t.text) }
        return *value
    }
    if e.kind == "binary" {
        a,b := values[0],values[1]
        switch t.text {
        case "+": return a+b
        case "-": return a-b
        case "*": return a*b
        case "/","MOD":
            if b == 0 { fail(t,"%s doesn't like 0 as input",t.text) }
            if t.text == "/" { return a/b }
            return a%b
        case "=": return truth(a == b)
        case "<>": return truth(a != b)
        case "<": return truth(a < b)
        case ">": return truth(a > b)
        case "<=": return truth(a <= b)
        case ">=": return truth(a >= b)
        }
    }
    switch t.text {
    case "XCOR": return r.x
    case "YCOR": return r.y
    case "HEADING": return r.heading
    case "REPCOUNT":
        if len(r.repetitions) == 0 { fail(t,"REPCOUNT outside REPEAT") }
        return r.repetitions[len(r.repetitions)-1]
    case "RANDOM":
        if values[0] < 1 { fail(t,"RANDOM doesn't like %d as input",values[0]) }
        r.random = 48271*r.random%2147483647
        return r.random%values[0]
    case "ABS": if values[0] < 0 { return -values[0] }; return values[0]
    case "NOT": return truth(values[0] == 0)
    case "AND": return truth(values[0] != 0 && values[1] != 0)
    case "OR": return truth(values[0] != 0 || values[1] != 0)
    case "MAX": if values[0] > values[1] { return values[0] }; return values[1]
    case "MIN": if values[0] < values[1] { return values[0] }; return values[1]
    }
    panic("invalid expression")
}
func (r *runtime) call(t token,values []int64) *int64 {
    if len(r.calls) == 100 { fail(t,"recursion too deep") }
    procedure := r.procedures[t.text]
    traced,indent := r.traced[t.text],strings.Repeat(" ",2*len(r.calls))
    if traced {
        parts := []string{procedure.name}
        for _,value := range values { parts = append(parts,strconv.FormatInt(value,10)) }
        r.emit("%s( %s )",indent,strings.Join(parts," "))
    }
    environment := &environment{variables:map[string]int64{}}
    for i,name := range procedure.parameters { environment.variables[name] = values[i] }
    r.environments = append(r.environments,environment)
    r.calls = append(r.calls,procedure.name)
    signal := r.sequence(procedure.body)
    r.environments = r.environments[:len(r.environments)-1]
    r.calls = r.calls[:len(r.calls)-1]
    if traced {
        if signal != nil && signal.output { r.emit("%s%s outputs %d",indent,procedure.name,signal.value) } else { r.emit("%s%s stops",indent,procedure.name) }
    }
    if signal != nil && signal.output { value := signal.value; return &value }
    return nil
}
var directions = [8]point{{0,1},{1,1},{1,0},{1,-1},{0,-1},{-1,-1},{-1,0},{-1,1}}
func (r *runtime) apply(p point) {
    if r.pen == "DOWN" { r.canvas[p] = r.character } else if r.pen == "ERASE" { delete(r.canvas,p) }
}
func (r *runtime) forward(steps int64) {
    delta := directions[r.heading/45]
    if steps < 0 { steps = -steps; delta.x,delta.y = -delta.x,-delta.y }
    r.apply(point{r.x,r.y})
    for i := int64(0); i < steps; i++ { r.x += delta.x; r.y += delta.y; r.apply(point{r.x,r.y}) }
}
func floorDivide(a,b int64) int64 { q := a/b; if a%b < 0 { q-- }; return q }
func (r *runtime) move(x,y int64) {
    x0,y0 := r.x,r.y
    dx,dy := x-x0,y-y0
    steps := dx
    if steps < 0 { steps = -steps }
    other := dy
    if other < 0 { other = -other }
    if other > steps { steps = other }
    if steps == 0 { r.apply(point{x0,y0}) } else {
        for i := int64(0); i <= steps; i++ { r.apply(point{x0+floorDivide(2*i*dx+steps,2*steps),y0+floorDivide(2*i*dy+steps,2*steps)}) }
    }
    r.x,r.y = x,y
}
func (r *runtime) canvasBounds() (int64,int64,int64,int64) {
    first := true
    var x1,y1,x2,y2 int64
    for p := range r.canvas {
        if first { x1,y1,x2,y2 = p.x,p.y,p.x,p.y; first = false }
        if p.x < x1 { x1 = p.x }; if p.x > x2 { x2 = p.x }
        if p.y < y1 { y1 = p.y }; if p.y > y2 { y2 = p.y }
    }
    return x1,y1,x2,y2
}
func (r *runtime) fill() {
    if len(r.canvas) == 0 { return }
    start := point{r.x,r.y}
    if _,marked := r.canvas[start]; marked { return }
    x1,y1,x2,y2 := r.canvasBounds()
    if r.x < x1 || r.x > x2 || r.y < y1 || r.y > y2 { return }
    queue := []point{start}
    r.canvas[start] = r.character
    for i := 0; i < len(queue); i++ {
        p := queue[i]
        for _,delta := range []point{{1,0},{-1,0},{0,1},{0,-1}} {
            q := point{p.x+delta.x,p.y+delta.y}
            if q.x < x1 || q.x > x2 || q.y < y1 || q.y > y2 { continue }
            if _,marked := r.canvas[q]; !marked { r.canvas[q] = r.character; queue = append(queue,q) }
        }
    }
}
func (r *runtime) picture() {
    if len(r.canvas) == 0 { r.emit("CANVAS 0 0 0"); return }
    x1,y1,x2,y2 := r.canvasBounds()
    r.emit("CANVAS %d %d %d",x2-x1+1,y2-y1+1,len(r.canvas))
    for y := y2; y >= y1; y-- {
        row := []byte{}
        for x := x1; x <= x2; x++ { character,marked := r.canvas[point{x,y}]; if !marked { character = ' ' }; row = append(row,character) }
        r.emit("%s",strings.TrimRight(string(row)," "))
    }
}
func (r *runtime) item(value input) string {
    if value.quoted != nil { return value.quoted.name }
    return strconv.FormatInt(r.evaluate(value.expression),10)
}
func (r *runtime) sequence(commands []*command) *control {
    for _,command := range commands { if signal := r.execute(command); signal != nil { return signal } }
    return nil
}
func (r *runtime) execute(c *command) *control {
    if c.kind == "multiple" {
        parts := []string{}
        for _,item := range c.inputs { parts = append(parts,r.item(item)) }
        r.emit("%s",strings.Join(parts," "))
        return nil
    }
    if c.kind == "WHILE" {
        for r.evaluate(c.inputs[0].expression) != 0 { if signal := r.sequence(c.inputs[1].list); signal != nil { return signal } }
        return nil
    }
    values := make([]int64,len(c.inputs))
    for i,item := range c.inputs { if item.expression != nil { values[i] = r.evaluate(item.expression) } }
    t := c.token
    if c.kind == "procedure" {
        if value := r.call(t,values); value != nil { fail(t,"you don't say what to do with %d",*value) }
        return nil
    }
    switch c.kind {
    case "FD": r.forward(values[0])
    case "BK": r.forward(-values[0])
    case "RT","LT","SETH":
        angle := values[0]
        if angle%45 != 0 { fail(t,"%s doesn't like %d as input",t.text,angle) }
        if c.kind == "RT" { angle += r.heading } else if c.kind == "LT" { angle = r.heading-angle }
        r.heading = (angle%360+360)%360
    case "PU": r.pen = "UP"
    case "PD": r.pen = "DOWN"
    case "PE": r.pen = "ERASE"
    case "SETPEN":
        if values[0] < 33 || values[0] > 126 { fail(t,"SETPEN doesn't like %d as input",values[0]) }
        r.character = byte(values[0])
    case "SETXY": r.move(values[0],values[1])
    case "SETX": r.move(values[0],r.y)
    case "SETY": r.move(r.x,values[0])
    case "HOME": r.move(0,0); r.heading = 0
    case "CS": r.canvas = map[point]byte{}; r.x,r.y,r.heading = 0,0,0
    case "CLEAN": r.canvas = map[point]byte{}
    case "FILL": r.fill()
    case "LABEL":
        text := ""
        if c.inputs[0].quoted != nil { text = c.inputs[0].quoted.name } else { text = strconv.FormatInt(values[0],10) }
        delta := directions[r.heading/45]
        for i := 0; i < len(text); i++ { r.canvas[point{r.x+int64(i)*delta.x,r.y+int64(i)*delta.y}] = text[i] }
    case "SNAPSHOT": r.picture()
    case "REPEAT":
        if len(c.inputs[1].list) == 0 { return nil }
        for n := int64(1); n <= values[0]; n++ {
            r.repetitions = append(r.repetitions,n)
            signal := r.sequence(c.inputs[1].list)
            r.repetitions = r.repetitions[:len(r.repetitions)-1]
            if signal != nil { return signal }
        }
    case "FOR":
        if len(c.inputs[3].list) == 0 { r.assign(c.inputs[0].quoted.name,values[2]); return nil }
        a,b := values[1],values[2]
        step := int64(1)
        if a > b { step = -1 }
        for value := a; ; value += step {
            r.assign(c.inputs[0].quoted.name,value)
            if signal := r.sequence(c.inputs[3].list); signal != nil { return signal }
            if value == b { break }
        }
    case "IF": if values[0] != 0 { return r.sequence(c.inputs[1].list) }
    case "IFELSE": if values[0] != 0 { return r.sequence(c.inputs[1].list) }; return r.sequence(c.inputs[2].list)
    case "TEST": value := values[0] != 0; r.current().test = &value
    case "IFTRUE","IFFALSE":
        value := r.current().test
        if value == nil { fail(t,"%s without TEST",t.text) }
        if *value == (c.kind == "IFTRUE") { return r.sequence(c.inputs[0].list) }
    case "STOP": return &control{}
    case "OUTPUT": return &control{output:true,value:values[0]}
    case "MAKE": r.assign(c.inputs[0].quoted.name,values[1])
    case "LOCAL": r.current().variables[c.inputs[0].quoted.name] = 0
    case "LOCALMAKE": r.current().variables[c.inputs[0].quoted.name] = values[1]
    case "TRACE": r.traced[c.inputs[0].quoted.name] = true
    case "UNTRACE": delete(r.traced,c.inputs[0].quoted.name)
    case "SEED":
        if values[0] < 1 { fail(t,"SEED doesn't like %d as input",values[0]) }
        r.random = values[0]
    case "PRINT":
        text := ""
        if c.inputs[0].quoted != nil { text = c.inputs[0].quoted.name } else { text = strconv.FormatInt(values[0],10) }
        r.emit("%s",text)
    }
    return nil
}
func runProgram(name string,lines []sourceLine,output *[]string) {
    *output = append(*output,"PROGRAM "+name)
    var machine *runtime
    executing := false
    defer func() {
        if caught := recover(); caught != nil {
            e,ok := caught.(logoError)
            if !ok { panic(caught) }
            *output = append(*output,fmt.Sprintf("ERROR line %d: %s",e.line,e.reason))
            if executing {
                for i := len(machine.calls)-1; i >= 0; {
                    name,count := machine.calls[i],1
                    i--
                    for i >= 0 && machine.calls[i] == name { count++; i-- }
                    line := "  in "+name
                    if count > 1 { line += fmt.Sprintf(" x%d",count) }
                    *output = append(*output,line)
                }
            }
        }
    }()
    procedures := map[string]*procedure{}
    ordered := []*procedure{}
    var current *procedure
    top := []token{}
    for _,line := range lines {
        tokens := lex(line)
        if len(tokens) == 0 { continue }
        first := tokens[0]
        if first.kind == "word" && first.text == "TO" {
            if current != nil { fail(first,"TO inside definition of %s",current.name) }
            if len(tokens) < 2 || tokens[1].kind != "word" { fail(first,"bad procedure header") }
            name := tokens[1].text
            if _,exists := primitives[name]; exists { fail(first,"%s is a primitive",name) }
            if procedures[name] != nil { fail(first,"%s is already defined",name) }
            parameters := []string{}
            seen := map[string]bool{}
            for _,t := range tokens[2:] {
                if t.kind != "variable" { fail(first,"bad procedure header") }
                if seen[t.name] { fail(first,"duplicate input %s",t.text) }
                seen[t.name] = true
                parameters = append(parameters,t.name)
            }
            current = &procedure{name:name,line:first.line,parameters:parameters}
            procedures[name] = current
            ordered = append(ordered,current)
        } else if len(tokens) == 1 && first.kind == "word" && first.text == "END" {
            if current == nil { fail(first,"END without TO") }
            current = nil
        } else if current != nil { current.tokens = append(current.tokens,tokens...) } else { top = append(top,tokens...) }
    }
    if current != nil { fail(token{line:current.line},"missing END for %s",current.name) }
    for _,procedure := range ordered {
        parser := parser{tokens:procedure.tokens,procedures:procedures,inside:true}
        procedure.body = parser.sequence()
    }
    parser := parser{tokens:top,procedures:procedures}
    commands := parser.sequence()
    machine = &runtime{
        procedures:procedures,environments:[]*environment{{variables:map[string]int64{}}},
        traced:map[string]bool{},canvas:map[point]byte{},pen:"DOWN",character:'*',random:1,output:output,
    }
    executing = true
    machine.sequence(commands)
    machine.emit("TURTLE %d %d %d %s %c",machine.x,machine.y,machine.heading,machine.pen,machine.character)
    machine.picture()
}
func main() {
    initialize()
    scanner := bufio.NewScanner(os.Stdin)
    output := []string{}
    name := ""
    lines := []sourceLine{}
    lineNumber := 0
    for scanner.Scan() {
        lineNumber++
        line := scanner.Text()
        if line == "#EOF" {
            runProgram(name,lines,&output)
            break
        }
        if strings.HasPrefix(line,"#PROGRAM ") {
            if name != "" { runProgram(name,lines,&output) }
            name,lines = line[9:],nil
        } else { lines = append(lines,sourceLine{line,lineNumber}) }
    }
    writer := bufio.NewWriter(os.Stdout)
    defer writer.Flush()
    for _,line := range output { fmt.Fprintln(writer,line) }
}
