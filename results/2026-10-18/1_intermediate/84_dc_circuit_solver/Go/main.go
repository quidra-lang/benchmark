package main

import (
    "bufio"
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

type rational struct { numerator, denominator int64 }
func gcd(a, b int64) int64 { if a < 0 { a = -a }; for b != 0 { a, b = b, a%b }; return a }
func fraction(n, d int64) rational {
    if d < 0 { n, d = -n, -d }
    common := gcd(n, d)
    return rational{n/common, d/common}
}
var zero = rational{0, 1}
var one = rational{1, 1}
func (a rational) add(b rational) rational { return fraction(a.numerator*b.denominator+b.numerator*a.denominator, a.denominator*b.denominator) }
func (a rational) subtract(b rational) rational { return fraction(a.numerator*b.denominator-b.numerator*a.denominator, a.denominator*b.denominator) }
func (a rational) multiply(b rational) rational { return fraction(a.numerator*b.numerator, a.denominator*b.denominator) }
func (a rational) divide(b rational) rational { return fraction(a.numerator*b.denominator, a.denominator*b.numerator) }
func (a rational) negate() rational { return rational{-a.numerator, a.denominator} }
func (a rational) compare(b rational) int { x, y := a.numerator*b.denominator, b.numerator*a.denominator; if x < y { return -1 }; if x > y { return 1 }; return 0 }
func (a rational) String() string { if a.denominator == 1 { return strconv.FormatInt(a.numerator, 10) }; return fmt.Sprintf("%d/%d", a.numerator, a.denominator) }
func (a rational) value() string {
    n, sign := a.numerator, ""
    if n < 0 { n, sign = -n, "-" }
    scaled := n*1000000/a.denominator
    return fmt.Sprintf("%s (%s%d.%06d)", a.String(), sign, scaled/1000000, scaled%1000000)
}
func digits(text string) bool { if text == "" { return false }; for i := range text { if text[i] < '0' || text[i] > '9' { return false } }; return true }
func integer(text string) int64 { value, _ := strconv.ParseInt(text, 10, 64); return value }
func parseNumber(text string) (rational, bool) {
    multiplier := one
    if strings.HasSuffix(text, "meg") { multiplier, text = rational{1000000,1}, strings.TrimSuffix(text,"meg") } else if strings.HasSuffix(text,"k") { multiplier, text = rational{1000,1}, strings.TrimSuffix(text,"k") } else if strings.HasSuffix(text,"m") { multiplier, text = rational{1,1000}, strings.TrimSuffix(text,"m") } else if strings.HasSuffix(text,"u") { multiplier, text = rational{1,1000000}, strings.TrimSuffix(text,"u") }
    negative := strings.HasPrefix(text,"-")
    if negative { text = text[1:] }
    result := zero
    if digits(text) { result = fraction(integer(text),1) } else if parts := strings.Split(text,"."); len(parts)==2 && digits(parts[0]) && digits(parts[1]) {
        denominator := int64(1)
        for range parts[1] { denominator *= 10 }
        result = fraction(integer(parts[0])*denominator+integer(parts[1]),denominator)
    } else if parts := strings.Split(text,"/"); len(parts)==2 && digits(parts[0]) && digits(parts[1]) && integer(parts[1])!=0 { result = fraction(integer(parts[0]),integer(parts[1])) } else { return zero,false }
    result = result.multiply(multiplier)
    if negative { result = result.negate() }
    return result,true
}
func validNode(name string) bool {
    if name == "0" { return true }
    if len(name)<1 || len(name)>8 || name[0]<'a' || name[0]>'z' { return false }
    for i := range name { if !(name[i]>='a'&&name[i]<='z'||name[i]>='0'&&name[i]<='9') { return false } }
    return true
}

type element struct { name, n1, n2, c1, c2, reference string; kind byte; value rational }
func (e element) terminals() []string { result:=[]string{e.n1,e.n2};if e.kind=='E'||e.kind=='G' {result=append(result,e.c1,e.c2)};return result }
func voltageSource(e element) bool { return e.kind=='V'||e.kind=='E'||e.kind=='H' }
func independent(e element) bool { return e.kind=='V'||e.kind=='I' }
type circuit struct { elements []element }
type commandError string
func fail(format string,args ...any) { panic(commandError(fmt.Sprintf(format,args...))) }
func sorted(set map[string]bool) []string { result:=[]string{};for name:=range set {result=append(result,name)};sort.Strings(result);return result }
func (c *circuit) nodes(includeGround bool) []string {
    set:=map[string]bool{}
    for _,e:=range c.elements {for _,node:=range e.terminals() {if includeGround||node!="0" {set[node]=true}}}
    return sorted(set)
}
func (c *circuit) node(name string) { if name=="0" {return};for _,node:=range c.nodes(false) {if name==node {return}};fail("unknown node %s",name) }
func (c *circuit) index(name string) int {for i,e:=range c.elements {if e.name==name {return i}};fail("unknown element %s",name);return -1}
func number(text string) rational {value,ok:=parseNumber(text);if !ok {fail("invalid value %s",text)};return value}
func (c *circuit) add(fields []string) {
    name,kind:=fields[0],fields[0][0]
    expected:=4
    if kind=='E'||kind=='G' {expected=6};if kind=='F'||kind=='H' {expected=5}
    if !strings.ContainsRune("RVIEGFH",rune(kind)) {fail("unknown element type %s",name)}
    if len(fields)!=expected {fail("wrong field count for %s",name)}
    for _,e:=range c.elements {if e.name==name {fail("duplicate element %s",name)}}
    nodes:=fields[1:3]
    if kind=='E'||kind=='G' {nodes=fields[1:5]}
    for _,node:=range nodes {if !validNode(node) {fail("invalid node %s",node)}}
    e:=element{name:name,kind:kind,n1:fields[1],n2:fields[2]}
    if kind=='E'||kind=='G' {e.c1,e.c2=fields[3],fields[4]}
    if kind=='F'||kind=='H' {
        e.reference=fields[3]
        found:=false
        for _,source:=range c.elements {if source.name==e.reference&&source.kind=='V' {found=true}}
        if !found {fail("unknown voltage source %s",e.reference)}
    }
    e.value=number(fields[len(fields)-1])
    if kind=='R'&&e.value.numerator<=0 {fail("nonpositive resistance %s",name)}
    c.elements=append(c.elements,e)
}

type unionFind struct { parent map[string]string }
func newUnion(nodes []string) *unionFind {u:=&unionFind{map[string]string{"0":"0"}};for _,name:=range nodes {u.parent[name]=name};return u}
func (u *unionFind) root(name string) string {if u.parent[name]!=name {u.parent[name]=u.root(u.parent[name])};return u.parent[name]}
func (u *unionFind) join(a,b string) {a,b=u.root(a),u.root(b);if a>b {a,b=b,a};u.parent[b]=a}
func (c *circuit) floating() []string {
    u:=newUnion(c.nodes(false))
    for _,e:=range c.elements {if e.kind=='R'||voltageSource(e) {u.join(e.n1,e.n2)}}
    result:=[]string{}
    for _,name:=range c.nodes(false) {if u.root(name)!=u.root("0") {result=append(result,name)}}
    return result
}
func (c *circuit) sourceLoops() []string {
    u:=newUnion(c.nodes(false));result:=[]string{}
    for _,e:=range c.elements {if voltageSource(e) {if u.root(e.n1)==u.root(e.n2) {result=append(result,e.name)};u.join(e.n1,e.n2)}}
    return result
}
func (c *circuit) structure() {
    if len(c.nodes(false))==0 {fail("no nodes")}
    if floating:=c.floating();len(floating)>0 {fail("floating node %s",floating[0])}
    if loops:=c.sourceLoops();len(loops)>0 {fail("voltage source loop at %s",loops[0])}
}

type equations struct { a [][]rational; b []rational; names,labels,nodes,sources []string; indices map[string]int }
func zeroVector(n int) []rational {result:=make([]rational,n);for i:=range result {result[i]=zero};return result}
func zeroMatrix(n int) [][]rational {result:=make([][]rational,n);for i:=range result {result[i]=zeroVector(n)};return result}
func (m *equations) add(row,column string,value rational) {if row!="0"&&column!="0" {i,j:=m.indices[row],m.indices[column];m.a[i][j]=m.a[i][j].add(value)}}
func (m *equations) rhs(vector []rational,row string,value rational) {if row!="0" {i:=m.indices[row];vector[i]=vector[i].add(value)}}
func (c *circuit) build() *equations {
    m:=&equations{nodes:c.nodes(false),indices:map[string]int{}}
    for _,node:=range m.nodes {m.indices[node]=len(m.names);m.names=append(m.names,"V("+node+")");m.labels=append(m.labels,node)}
    for _,e:=range c.elements {if voltageSource(e) {m.indices[e.name]=len(m.names);m.sources=append(m.sources,e.name);m.names=append(m.names,"I("+e.name+")");m.labels=append(m.labels,e.name)}}
    m.a,m.b=zeroMatrix(len(m.names)),zeroVector(len(m.names))
    for _,e:=range c.elements {
        w:=e.value
        switch e.kind {
        case 'R':g:=one.divide(w);m.add(e.n1,e.n1,g);m.add(e.n2,e.n2,g);m.add(e.n1,e.n2,g.negate());m.add(e.n2,e.n1,g.negate())
        case 'I':m.rhs(m.b,e.n1,w.negate());m.rhs(m.b,e.n2,w)
        case 'G':m.add(e.n1,e.c1,w);m.add(e.n2,e.c2,w);m.add(e.n1,e.c2,w.negate());m.add(e.n2,e.c1,w.negate())
        case 'F':m.add(e.n1,e.reference,w);m.add(e.n2,e.reference,w.negate())
        default:
            m.add(e.n1,e.name,one);m.add(e.name,e.n1,one);m.add(e.n2,e.name,one.negate());m.add(e.name,e.n2,one.negate())
            if e.kind=='V' {m.rhs(m.b,e.name,w)} else if e.kind=='E' {m.add(e.name,e.c1,w.negate());m.add(e.name,e.c2,w)} else {m.add(e.name,e.reference,w.negate())}
        }
    }
    return m
}
func solve(a [][]rational,b []rational) []rational {
    n:=len(b);rows:=make([][]rational,n)
    for i:=range rows {rows[i]=append(append([]rational(nil),a[i]...),b[i])}
    for k:=0;k<n;k++ {
        pivot:=k
        for pivot<n&&rows[pivot][k].numerator==0 {pivot++}
        if pivot==n {return nil}
        rows[k],rows[pivot]=rows[pivot],rows[k]
        divisor:=rows[k][k]
        for j:=0;j<=n;j++ {rows[k][j]=rows[k][j].divide(divisor)}
        for i:=0;i<n;i++ {if i!=k {factor:=rows[i][k];if factor.numerator!=0 {for j:=0;j<=n;j++ {rows[i][j]=rows[i][j].subtract(factor.multiply(rows[k][j]))}}}}
    }
    result:=zeroVector(n);for i:=range result {result[i]=rows[i][n]};return result
}
func (m *equations) potential(solution []rational,node string) rational {if node=="0" {return zero};return solution[m.indices[node]]}
func (m *equations) current(solution []rational,e element) rational {
    switch e.kind {
    case 'R':return m.potential(solution,e.n1).subtract(m.potential(solution,e.n2)).divide(e.value)
    case 'I':return e.value
    case 'G':return e.value.multiply(m.potential(solution,e.c1).subtract(m.potential(solution,e.c2)))
    case 'F':return e.value.multiply(solution[m.indices[e.reference]])
    default:return solution[m.indices[e.name]]
    }
}
func (m *equations) injection(a,b string) []rational {rhs:=zeroVector(len(m.b));m.rhs(rhs,a,one);m.rhs(rhs,b,one.negate());return solve(m.a,rhs)}
func (m *equations) alone(e element,value rational) []rational {rhs:=zeroVector(len(m.b));if e.kind=='V' {m.rhs(rhs,e.name,value)}else{m.rhs(rhs,e.n1,value.negate());m.rhs(rhs,e.n2,value)};return solve(m.a,rhs)}
func voltage(m *equations,solution []rational,a,b string) rational {return m.potential(solution,a).subtract(m.potential(solution,b))}

type resistor struct { name,a,b string; value rational }
func reachable(start string,edges []resistor) map[string]bool {
    seen:=map[string]bool{start:true};changed:=true
    for changed {changed=false;for _,e:=range edges {if seen[e.a]&&!seen[e.b] {seen[e.b]=true;changed=true};if seen[e.b]&&!seen[e.a] {seen[e.a]=true;changed=true}}}
    return seen
}
func (c *circuit) resistance(a,b string) string {
    groups:=newUnion(c.nodes(false))
    for _,e:=range c.elements {if e.kind=='V' {groups.join(e.n1,e.n2)}}
    a,b=groups.root(a),groups.root(b)
    if a==b {return "Req = "+zero.value()}
    edges:=[]resistor{}
    for _,e:=range c.elements {if e.kind=='R' {x,y:=groups.root(e.n1),groups.root(e.n2);if x!=y {edges=append(edges,resistor{e.name,x,y,e.value})}}}
    component:=reachable(a,edges)
    if !component[b] {return "Req = INFINITE"}
    names:=[]string{}
    for node:=range component {if node!=b {names=append(names,node)}};sort.Strings(names)
    indices:=map[string]int{};for i,name:=range names {indices[name]=i}
    matrix,rhs:=zeroMatrix(len(names)),zeroVector(len(names))
    add:=func(x,y string,value rational) {if x!=b&&y!=b {i,j:=indices[x],indices[y];matrix[i][j]=matrix[i][j].add(value)}}
    for _,e:=range edges {if component[e.a] {g:=one.divide(e.value);add(e.a,e.a,g);add(e.b,e.b,g);add(e.a,e.b,g.negate());add(e.b,e.a,g.negate())}}
    rhs[indices[a]]=one
    return "Req = "+solve(matrix,rhs)[indices[a]].value()
}
func (c *circuit) reduce(a,b string) []string {
    if a==b {return []string{"Req = "+zero.value()}}
    list:=[]resistor{}
    for _,e:=range c.elements {if e.kind=='R' {list=append(list,resistor{e.name,e.n1,e.n2,e.value})}}
    component:=reachable(a,list)
    if !component[b] {return []string{"Req = INFINITE"}}
    kept:=[]resistor{};for _,e:=range list {if component[e.a] {kept=append(kept,e)}};list=kept
    lines:=[]string{};serial:=0
    remove:=func(i int) {list=append(list[:i],list[i+1:]...)}
    for {
        self:=-1;for i,e:=range list {if e.a==e.b {self=i;break}}
        if self>=0 {lines=append(lines,"remove "+list[self].name);remove(self);continue}
        degrees:=map[string]int{};for _,e:=range list {degrees[e.a]++;degrees[e.b]++}
        internal:=[]string{};for node:=range degrees {if node!=a&&node!=b {internal=append(internal,node)}};sort.Strings(internal)
        dangling:="";for _,node:=range internal {if degrees[node]==1 {dangling=node;break}}
        if dangling!="" {for i,e:=range list {if e.a==dangling||e.b==dangling {lines=append(lines,"remove "+e.name);remove(i);break}};continue}
        first,second:=-1,-1
        for i:=0;i<len(list)&&first<0;i++ {for j:=i+1;j<len(list);j++ {x,y:=list[i],list[j];if x.a==y.a&&x.b==y.b||x.a==y.b&&x.b==y.a {first,second=i,j;break}}}
        if first>=0 {
            x,y:=list[first],list[second];serial++;name:="#"+strconv.Itoa(serial);value:=x.value.multiply(y.value).divide(x.value.add(y.value))
            lines=append(lines,fmt.Sprintf("%s = %s || %s = %s",name,x.name,y.name,value.value()))
            remove(second);remove(first);list=append(list,resistor{name,x.a,x.b,value});continue
        }
        middle:="";for _,node:=range internal {if degrees[node]==2 {middle=node;break}}
        if middle!="" {
            indices:=[]int{};for i,e:=range list {if e.a==middle||e.b==middle {indices=append(indices,i)}}
            first,second=indices[0],indices[1];x,y:=list[first],list[second];u,v:=x.a,y.a;if u==middle {u=x.b};if v==middle {v=y.b}
            serial++;name:="#"+strconv.Itoa(serial);value:=x.value.add(y.value)
            lines=append(lines,fmt.Sprintf("%s = %s + %s = %s",name,x.name,y.name,value.value()))
            remove(second);remove(first);list=append(list,resistor{name,u,v,value});continue
        }
        break
    }
    if len(list)==1 {lines=append(lines,"Req = "+list[0].value.value())}else{lines=append(lines,fmt.Sprintf("not series-parallel: %d resistors remain",len(list)))}
    return lines
}
var argumentCounts = map[string]int{
    ".OP": 0, ".CURRENT": 1, ".VOLTAGE": 2, ".POWER": 0, ".KCL": 1,
    ".THEVENIN": 2, ".NORTON": 2, ".MAXPOWER": 2, ".TF": 2, ".SENS": 1,
    ".ZPARAM": 4, ".SUPERPOSITION": 1, ".SWEEP": 5, ".MATRIX": 0,
    ".REQ": 2, ".REDUCE": 2, ".CHECK": 0, ".ALTER": 2, ".DELETE": 1,
    ".CLEAR": 0, ".NODES": 0, ".PRINT": 0,
}

func (c *circuit) command(fields []string) []string {
    name, args := fields[0], fields[1:]
    count, known := argumentCounts[name]
    if !known { fail("unknown command %s", name) }
    if len(args) != count { fail("wrong argument count for %s", name) }
    lines := []string{}
    emit := func(format string, values ...any) {
        lines = append(lines, fmt.Sprintf(format, values...))
    }
    switch name {
    case ".ALTER":
        index := c.index(args[0])
        value := number(args[1])
        e := c.elements[index]
        if e.kind == 'R' && value.numerator <= 0 {
            fail("nonpositive resistance %s", e.name)
        }
        emit("altered %s: %s -> %s", e.name, e.value.String(), value.String())
        c.elements[index].value = value
        return lines
    case ".DELETE":
        index := c.index(args[0])
        for _, e := range c.elements {
            if (e.kind == 'F' || e.kind == 'H') && e.reference == args[0] {
                fail("%s is referenced by %s", args[0], e.name)
            }
        }
        c.elements = append(c.elements[:index], c.elements[index+1:]...)
        emit("deleted %s", args[0])
        return lines
    case ".CLEAR":
        emit("cleared %d elements", len(c.elements))
        c.elements = nil
        return lines
    case ".PRINT":
        if len(c.elements) == 0 { emit("empty netlist") }
        for _, e := range c.elements {
            extra := ""
            if e.kind == 'E' || e.kind == 'G' { extra = e.c1+" "+e.c2+" " }
            if e.kind == 'F' || e.kind == 'H' { extra = e.reference+" " }
            emit("%s %s %s %s%s", e.name, e.n1, e.n2, extra, e.value.String())
        }
        return lines
    case ".NODES":
        nodes := c.nodes(true)
        if len(nodes) == 0 { emit("no nodes") }
        for _, node := range nodes {
            names := []string{}
            for _, e := range c.elements {
                for _, terminal := range e.terminals() {
                    if terminal == node { names = append(names, e.name); break }
                }
            }
            emit("%s: %s", node, strings.Join(names, " "))
        }
        return lines
    case ".CHECK":
        nodes := c.nodes(false)
        if len(nodes) == 0 { return []string{"no nodes"} }
        degrees := map[string]int{}
        for _, e := range c.elements { degrees[e.n1]++; degrees[e.n2]++ }
        for _, node := range nodes {
            if degrees[node] < 2 { emit("dangling node %s", node) }
        }
        for _, node := range c.floating() { emit("floating node %s", node) }
        for _, source := range c.sourceLoops() { emit("voltage source loop at %s", source) }
        if len(lines) == 0 {
            m := c.build()
            if solve(m.a, m.b) == nil { emit("singular matrix") } else { emit("ok") }
        }
        return lines
    case ".REQ", ".REDUCE":
        c.node(args[0])
        c.node(args[1])
        if name == ".REQ" { return []string{c.resistance(args[0], args[1])} }
        return c.reduce(args[0], args[1])
    case ".SWEEP":
        index := c.index(args[0])
        from := number(args[1])
        to := number(args[2])
        step := number(args[3])
        c.node(args[4])
        if step.numerator <= 0 { fail("invalid sweep step") }
        if from.compare(to) > 0 { fail("invalid sweep range") }
        ratio := to.subtract(from).divide(step)
        points := ratio.numerator/ratio.denominator+1
        if points > 20 { fail("too many sweep points") }
        if c.elements[index].kind == 'R' && from.numerator <= 0 {
            fail("nonpositive resistance %s", args[0])
        }
        c.structure()
        temporary := circuit{elements:append([]element(nil), c.elements...)}
        for k := int64(0); k < points; k++ {
            value := from.add(step.multiply(rational{k, 1}))
            temporary.elements[index].value = value
            m := temporary.build()
            solution := solve(m.a, m.b)
            if solution == nil {
                emit("%s = %s: singular matrix", args[0], value.String())
            } else {
                emit("%s = %s: V(%s) = %s", args[0], value.String(), args[4], m.potential(solution, args[4]).value())
            }
        }
        return lines
    }
    if name == ".CURRENT" {
        c.index(args[0])
    } else if name == ".TF" {
        c.node(args[0])
        index := c.index(args[1])
        if !independent(c.elements[index]) { fail("not an independent source %s", args[1]) }
    } else {
        for _, node := range args { c.node(node) }
    }
    c.structure()
    m := c.build()
    if name == ".MATRIX" {
        emit("unknowns: %s", strings.Join(m.names, " "))
        for i, row := range m.a {
            values := []string{}
            for _, value := range row { values = append(values, value.String()) }
            emit("%s: %s | %s", m.labels[i], strings.Join(values, " "), m.b[i].String())
        }
        return lines
    }
    solution := solve(m.a, m.b)
    if solution == nil { fail("singular matrix") }
    switch name {
    case ".OP":
        for _, node := range m.nodes { emit("V(%s) = %s", node, m.potential(solution, node).value()) }
        for _, source := range m.sources { emit("I(%s) = %s", source, solution[m.indices[source]].value()) }
    case ".CURRENT":
        e := c.elements[c.index(args[0])]
        emit("I(%s) = %s", e.name, m.current(solution, e).value())
    case ".VOLTAGE":
        emit("V(%s,%s) = %s", args[0], args[1], voltage(m, solution, args[0], args[1]).value())
    case ".POWER":
        absorbed, delivered, total := zero, zero, zero
        for _, e := range c.elements {
            power := voltage(m, solution, e.n1, e.n2).multiply(m.current(solution, e))
            emit("P(%s) = %s", e.name, power.value())
            if power.numerator > 0 { absorbed = absorbed.add(power) }
            if power.numerator < 0 { delivered = delivered.add(power.negate()) }
            total = total.add(power)
        }
        emit("absorbed = %s", absorbed.value())
        emit("delivered = %s", delivered.value())
        emit("total = %s", total.value())
    case ".KCL":
        sum := zero
        for _, e := range c.elements {
            if e.n1 == args[0] || e.n2 == args[0] {
                current := zero
                if e.n1 != e.n2 {
                    current = m.current(solution, e)
                    if e.n2 == args[0] { current = current.negate() }
                }
                emit("I(%s) leaving %s = %s", e.name, args[0], current.value())
                sum = sum.add(current)
            }
        }
        emit("sum = %s", sum.value())
    case ".THEVENIN", ".NORTON", ".MAXPOWER":
        vth := voltage(m, solution, args[0], args[1])
        rth := voltage(m, m.injection(args[0], args[1]), args[0], args[1])
        if name == ".NORTON" {
            if rth.numerator == 0 { fail("zero thevenin resistance") }
            emit("In = %s", vth.divide(rth).value())
            emit("Rn = %s", rth.value())
        } else if name == ".MAXPOWER" {
            if rth.numerator <= 0 { fail("nonpositive thevenin resistance") }
            emit("RL = %s", rth.value())
            emit("Pmax = %s", vth.multiply(vth).divide(rational{4, 1}.multiply(rth)).value())
        } else {
            emit("Vth = %s", vth.value())
            emit("Rth = %s", rth.value())
        }
    case ".TF":
        source := c.elements[c.index(args[1])]
        unit := m.alone(source, one)
        emit("gain = %s", m.potential(unit, args[0]).value())
        if source.kind == 'V' {
            current := unit[m.indices[source.name]]
            if current.numerator == 0 {
                emit("input resistance = INFINITE")
            } else {
                emit("input resistance = %s", one.negate().divide(current).value())
            }
        } else {
            emit("input resistance = %s", voltage(m, unit, source.n2, source.n1).value())
        }
        emit("output resistance = %s", m.potential(m.injection(args[0], "0"), args[0]).value())
    case ".SENS":
        for _, e := range c.elements {
            rhs := zeroVector(len(m.b))
            switch e.kind {
            case 'R':
                value := m.current(solution, e).divide(e.value)
                m.rhs(rhs, e.n1, value)
                m.rhs(rhs, e.n2, value.negate())
            case 'I':
                m.rhs(rhs, e.n1, one.negate())
                m.rhs(rhs, e.n2, one)
            case 'G', 'F':
                value := zero
                if e.kind == 'G' { value = voltage(m, solution, e.c1, e.c2) } else { value = solution[m.indices[e.reference]] }
                m.rhs(rhs, e.n1, value.negate())
                m.rhs(rhs, e.n2, value)
            case 'V':
                m.rhs(rhs, e.name, one)
            case 'E':
                m.rhs(rhs, e.name, voltage(m, solution, e.c1, e.c2))
            case 'H':
                m.rhs(rhs, e.name, solution[m.indices[e.reference]])
            }
            emit("dV(%s)/d%s = %s", args[0], e.name, m.potential(solve(m.a, rhs), args[0]).value())
        }
    case ".ZPARAM":
        z1 := m.injection(args[0], args[1])
        z2 := m.injection(args[2], args[3])
        emit("z11 = %s", voltage(m, z1, args[0], args[1]).value())
        emit("z12 = %s", voltage(m, z2, args[0], args[1]).value())
        emit("z21 = %s", voltage(m, z1, args[2], args[3]).value())
        emit("z22 = %s", voltage(m, z2, args[2], args[3]).value())
    case ".SUPERPOSITION":
        total := zero
        for _, e := range c.elements {
            if independent(e) {
                value := m.potential(m.alone(e, e.value), args[0])
                emit("%s: V(%s) = %s", e.name, args[0], value.value())
                total = total.add(value)
            }
        }
        emit("total: V(%s) = %s", args[0], total.value())
    }
    return lines
}

func (c *circuit) process(line string, number int, out *bufio.Writer) {
    defer func() {
        if caught := recover(); caught != nil {
            if reason, ok := caught.(commandError); ok {
                fmt.Fprintf(out, "error: line %d: %s\n", number, reason)
            } else {
                panic(caught)
            }
        }
    }()
    if line[0] == '*' { return }
    fields := strings.Split(line, " ")
    if line[0] != '.' { c.add(fields); return }
    for _, text := range c.command(fields) { fmt.Fprintln(out, text) }
}

func main() {
    scanner := bufio.NewScanner(os.Stdin)
    out := bufio.NewWriter(os.Stdout)
    defer out.Flush()
    c := circuit{}
    lineNumber := 0
    for scanner.Scan() {
        lineNumber++
        line := scanner.Text()
        if line == ".END" { break }
        c.process(line, lineNumber, out)
    }
}
