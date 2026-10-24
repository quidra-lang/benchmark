package main

import (
    "bufio"
    "fmt"
    "os"
    "regexp"
    "strconv"
    "strings"
)

type node struct {
    kind byte
    n, row, flags int
    text string
    a, b *node
    args []*node
}
type commandError string
func fail(s string) { panic(commandError(s)) }
func num(n int) *node { return &node{kind:'N',n:n} }
func text(s string) *node { return &node{kind:'S',text:s} }
func errorValue(s string) *node { return &node{kind:'E',text:s} }
func ref(c,r,f int) *node { return &node{kind:'R',n:c,row:r,flags:f} }
var invalid=&node{kind:'X'}
func id(r *node) int { return r.row*26+r.n }
func label(i int) string { return string(rune('A'+i%26))+strconv.Itoa(i/26+1) }
func inside(r *node) bool { return r.n>=0&&r.n<26&&r.row>=0&&r.row<99 }
func makeRange(a,b *node) *node {
    c,d,r,t,ac,bc,ar,br:=a.n,b.n,a.row,b.row,a.flags&1,b.flags&1,a.flags&2,b.flags&2
    if c>d {c,d,ac,bc=d,c,bc,ac};if r>t {r,t,ar,br=t,r,br,ar}
    return &node{kind:'G',a:ref(c,r,ac|ar),b:ref(d,t,bc|br)}
}
var addressPattern=regexp.MustCompile(`^[A-Z][1-9][0-9]?$`)
var referencePattern=regexp.MustCompile(`^(\$?)([A-Z])(\$?)([1-9][0-9]?)$`)
var wordPattern=regexp.MustCompile(`^[A-Z][A-Z0-9]*$`)
var integerPattern=regexp.MustCompile(`^(0|-?[1-9][0-9]{0,8})$`)
var rowPattern=regexp.MustCompile(`^[1-9][0-9]?$`)
func address(s string) *node {
    if !addressPattern.MatchString(s){fail("bad address")};r,_:=strconv.Atoi(s[1:]);return ref(int(s[0]-'A'),r-1,0)
}
func area(s string) *node {p:=strings.IndexByte(s,':');if p<0 {a:=address(s);return makeRange(a,a)};a:=address(s[:p]);b:=address(s[p+1:]);return makeRange(a,b)}
func cells(g *node) []int {out:=[]int{};for r:=g.a.row;r<=g.b.row;r++ {for c:=g.a.n;c<=g.b.n;c++ {out=append(out,r*26+c)}};return out}
func contains(g,r *node) bool {return r.n>=g.a.n&&r.n<=g.b.n&&r.row>=g.a.row&&r.row<=g.b.row}
var levels=[][]string{{"=","<>","<","<=",">",">="},{"&"},{"+","-"},{"*","/"}}
func member(s string,xs []string) bool {for _,x:=range xs {if s==x{return true}};return false}
func precedence(s string) int {for i,xs:=range levels {if member(s,xs){return i}};return -1}
func digit(c byte) bool {return c>='0'&&c<='9'}
func letter(c byte) bool {return c>='A'&&c<='Z'||c>='a'&&c<='z'}
type token struct {value *node;position int}
type parser struct {tokens []token;at int}
func syntax(p int){fail("syntax error at "+strconv.Itoa(p))}
func tokenize(s string) []token {
    ts:=[]token{}
    for i:=1;i<len(s); {
        p,ch:=i+1,s[i];if ch==' ' {i++;continue};var x *node
        if digit(ch) {
            j:=i;for j<len(s)&&digit(s[j]){j++};if j-i>=10 {syntax(p)};n,_:=strconv.Atoi(s[i:j]);x=num(n);i=j
        }else if ch=='"' {
            offset:=strings.IndexByte(s[i+1:],'"');if offset<0 {syntax(p)};j:=i+1+offset;x=text(s[i+1:j]);i=j+1
        }else if letter(ch)||ch=='$' {
            j:=i;for j<len(s)&&(letter(s[j])||digit(s[j])||s[j]=='$'){j++};w:=strings.ToUpper(s[i:j]);i=j;m:=referencePattern.FindStringSubmatch(w)
            if m!=nil {r,_:=strconv.Atoi(m[4]);f:=0;if m[1]!=""{f|=1};if m[3]!=""{f|=2};x=ref(int(m[2][0]-'A'),r-1,f)
            }else if wordPattern.MatchString(w){k:=byte('W');if strings.HasPrefix(strings.TrimLeft(s[j:]," "),"("){k='C'};x=&node{kind:k,text:w}
            }else {syntax(p)}
        }else {
            op:=s[i:min(i+2,len(s))];if !member(op,[]string{"<>","<=",">="}){op=string(ch)}
            if !strings.ContainsRune("+-*/&(),:=<>",rune(ch)){syntax(p)};x=&node{kind:'T',text:op};i+=len(op)
        };ts=append(ts,token{x,p})
    };return append(ts,token{&node{kind:'Z'},len(s)+1})
}
func (p *parser) take(s string) bool {x:=p.tokens[p.at].value;if x.kind=='T'&&x.text==s {p.at++;return true};return false}
func (p *parser) expect(s string){if !p.take(s){syntax(p.tokens[p.at].position)}}
func (p *parser) expression(level int) *node {
    if level==4 {return p.primary()};a:=p.expression(level+1)
    for p.tokens[p.at].value.kind=='T'&&member(p.tokens[p.at].value.text,levels[level]) {op:=p.tokens[p.at].value.text;p.at++;a=&node{kind:'B',text:op,a:a,b:p.expression(level+1)}};return a
}
func (p *parser) primary() *node {
    if p.take("-"){return &node{kind:'U',a:p.primary()}};t:=p.tokens[p.at];p.at++;x:=t.value
    switch x.kind {
    case 'N','S','W':return x
    case 'R':if !p.take(":"){return x};if p.tokens[p.at].value.kind!='R'{syntax(p.tokens[p.at].position)};b:=p.tokens[p.at].value;p.at++;return makeRange(x,b)
    case 'C':p.expect("(");args:=[]*node{};if !p.take(")"){args=append(args,p.expression(0));for p.take(","){args=append(args,p.expression(0))};p.expect(")")};return &node{kind:'F',text:x.text,args:args}
    case 'T':if x.text=="(" {a:=p.expression(0);p.expect(")");return a}
    };syntax(t.position);return nil
}
func parseFormula(s string) *node {p:=parser{tokens:tokenize(s)};x:=p.expression(0);if p.tokens[p.at].value.kind!='Z'{syntax(p.tokens[p.at].position)};return x}
func canonical(x *node) string {
    switch x.kind {
    case 'N':return strconv.Itoa(x.n)
    case 'S':return `"`+x.text+`"`
    case 'W':return x.text
    case 'X':return "#REF!"
    case 'R':a,b:="","";if x.flags&1!=0{a="$"};if x.flags&2!=0{b="$"};return a+string(rune('A'+x.n))+b+strconv.Itoa(x.row+1)
    case 'G':return canonical(x.a)+":"+canonical(x.b)
    case 'F':args:=[]string{};for _,a:=range x.args{args=append(args,canonical(a))};return x.text+"("+strings.Join(args,",")+")"
    case 'U':a:=canonical(x.a);if x.a.kind=='B'{a="("+a+")"};return "-"+a
    default:a,b:=canonical(x.a),canonical(x.b);if x.a.kind=='B'&&precedence(x.a.text)<precedence(x.text){a="("+a+")"};if x.b.kind=='B'&&precedence(x.b.text)<=precedence(x.text){b="("+b+")"};return a+x.text+b
    }
}
func display(x *node) string {if x==nil{return ""};if x.kind=='N'{return strconv.Itoa(x.n)};return x.text}
func notation(x *node) string {if x==nil{return "(empty)"};if x.kind=='='{return "="+canonical(x.a)};if x.kind=='S'{return `"`+x.text+`"`};return display(x)}
func number(x *node) *node {if x==nil{return num(0)};if x.kind=='S'||x.kind=='G'{return errorValue("#VALUE!")};return x}
func stringValue(x *node) *node {if x==nil{return text("")};if x.kind=='N'{return text(strconv.Itoa(x.n))};if x.kind=='G'{return errorValue("#VALUE!")};return x}
func rewrite(x *node,f func(*node)*node) *node {
    if x==nil{return nil};if x.kind=='R'||x.kind=='G'{return f(x)};v:=*x;v.a=rewrite(x.a,f);v.b=rewrite(x.b,f);v.args=make([]*node,len(x.args));for i,a:=range x.args{v.args[i]=rewrite(a,f)};return &v
}
func collectDependencies(x *node,out *[2574]bool){if x==nil{return};if x.kind=='R'{out[id(x)]=true}else if x.kind=='G'{for _,i:=range cells(x){out[i]=true}}else{collectDependencies(x.a,out);collectDependencies(x.b,out);for _,a:=range x.args{collectDependencies(a,out)}}}
type grid [2574]*node
type historyEntry struct {name string;contents grid}
type sheet struct {contents,values grid;deps [2574][]int;history []historyEntry}
func (s *sheet) evaluate(x *node) *node {
    switch x.kind {case 'N','S','G':return x;case 'R':return s.values[id(x)];case 'W':return errorValue("#NAME?");case 'X':return errorValue("#REF!");case 'U':a:=number(s.evaluate(x.a));if a.kind=='E'{return a};return num(-a.n)}
    if x.kind=='B' {
        a:=s.evaluate(x.a);b:=s.evaluate(x.b);op:=x.text;if a!=nil&&a.kind=='E'{return a};if b!=nil&&b.kind=='E'{return b}
        if precedence(op)==0 {
            if a!=nil&&a.kind=='G'||b!=nil&&b.kind=='G'{return errorValue("#VALUE!")};stringsPresent:=a!=nil&&a.kind=='S'||b!=nil&&b.kind=='S';blank:=num(0);if stringsPresent{blank=text("")};if a==nil{a=blank};if b==nil{b=blank}
            c:=0;if a.kind!=b.kind{if a.kind=='N'{c=-1}else{c=1}}else if a.kind=='N'{if a.n<b.n{c=-1}else if a.n>b.n{c=1}}else{c=strings.Compare(a.text,b.text)}
            yes:=op=="="&&c==0||op=="<>"&&c!=0||op=="<"&&c<0||op=="<="&&c<=0||op==">"&&c>0||op==">="&&c>=0;if yes{return num(1)};return num(0)
        }
        if op=="&"{a=stringValue(a);b=stringValue(b)}else{a=number(a);b=number(b)};if a.kind=='E'{return a};if b.kind=='E'{return b}
        switch op{case "&":return text(a.text+b.text);case "+":return num(a.n+b.n);case "-":return num(a.n-b.n);case "*":return num(a.n*b.n);default:if b.n==0{return errorValue("#DIV/0!")};return num(a.n/b.n)}
    }
    name,args:=x.text,x.args
    if member(name,[]string{"SUM","MIN","MAX","COUNT","AVERAGE","AND","OR","CONCAT"}) {
        if len(args)==0{return errorValue("#VALUE!")};items:=[]*node{};ns:=[]int{}
        for _,a:=range args{v:=s.evaluate(a);if v!=nil&&v.kind=='G'{for _,i:=range cells(v){items=append(items,s.values[i])}}else{items=append(items,v)}}
        for _,v:=range items{if v!=nil&&v.kind=='N'{ns=append(ns,v.n)}};if name=="COUNT"{return num(len(ns))};for _,v:=range items{if v!=nil&&v.kind=='E'{return v}}
        if name=="CONCAT"{var out strings.Builder;for _,v:=range items{out.WriteString(stringValue(v).text)};return text(out.String())};sum,lo,hi,all,any:=0,0,0,true,false
        for i,n:=range ns{sum+=n;if i==0||n<lo{lo=n};if i==0||n>hi{hi=n};all=all&&n!=0;any=any||n!=0}
        switch name{case "SUM":return num(sum);case "MIN":return num(lo);case "MAX":return num(hi)}
        if len(ns)==0{if name=="AVERAGE"{return errorValue("#DIV/0!")};return errorValue("#VALUE!")};if name=="AVERAGE"{return num(sum/len(ns))};if name=="AND"&&all||name=="OR"&&any{return num(1)};return num(0)
    }
    if name=="IF"{if len(args)!=2&&len(args)!=3{return errorValue("#VALUE!")};c:=number(s.evaluate(args[0]));if c.kind=='E'{return c};if c.n!=0{return s.evaluate(args[1])};if len(args)==3{return s.evaluate(args[2])};return num(0)}
    if !member(name,[]string{"ABS","NOT","LEN"}){return errorValue("#NAME?")};if len(args)!=1{return errorValue("#VALUE!")};v:=s.evaluate(args[0]);if name=="LEN"{v=stringValue(v)}else{v=number(v)};if v.kind=='E'{return v};if name=="LEN"{return num(len(v.text))};if name=="ABS"{if v.n<0{return num(-v.n)};return v};if v.n==0{return num(1)};return num(0)
}
func (s *sheet) recalculate(){
    var indices,low [2574]int;var on,cyclic,done [2574]bool;stack:=[]int{};serial:=0
    for i,x:=range s.contents{indices[i]=-1;s.deps[i]=nil;if x!=nil&&x.kind=='=' {var found [2574]bool;collectDependencies(x.a,&found);for j,yes:=range found{if yes{s.deps[i]=append(s.deps[i],j)}};s.values[i]=nil}else{s.values[i]=x}}
    var visit func(int);visit=func(i int){
        indices[i]=serial;low[i]=serial;serial++;stack=append(stack,i);on[i]=true
        for _,j:=range s.deps[i]{if s.contents[j]!=nil&&s.contents[j].kind=='='{if indices[j]<0{visit(j);low[i]=min(low[i],low[j])}else if on[j]{low[i]=min(low[i],indices[j])}}}
        if low[i]==indices[i]{part:=[]int{};for {j:=stack[len(stack)-1];stack=stack[:len(stack)-1];on[j]=false;part=append(part,j);if j==i{break}};self:=false;for _,j:=range s.deps[i]{self=self||j==i};if len(part)>1||self{for _,j:=range part{cyclic[j]=true}}}
    }
    for i,x:=range s.contents{if x!=nil&&x.kind=='='&&indices[i]<0{visit(i)}}
    var calculate func(int);calculate=func(i int){
        if s.contents[i]==nil||s.contents[i].kind!='='||done[i]{return};done[i]=true;if cyclic[i]{s.values[i]=errorValue("#CYCLE!");return};for _,j:=range s.deps[i]{calculate(j)};v:=s.evaluate(s.contents[i].a);if v==nil{v=num(0)}else if v.kind=='G'{v=errorValue("#VALUE!")};s.values[i]=v
    };for i:=range s.contents{calculate(i)}
}
func (s *sheet) replace(next grid) int {old:=s.values;s.contents=next;s.recalculate();changed:=0;for i,v:=range old{if notation(v)!=notation(s.values[i]){changed++}};return changed}
func (s *sheet) describe(i int) string{return label(i)+": "+notation(s.contents[i])+" -> "+notation(s.values[i])}
func formatted(xs []int) string {if len(xs)==0{return "none"};out:=[]string{};for _,i:=range xs{out=append(out,label(i))};return strings.Join(out,",")}
func (s *sheet) execute(line string) []string {
    name,rest,_:=strings.Cut(line," ")
    switch name {
    case "SHOW":return []string{s.describe(id(address(rest)))}
    case "LIST":out:=[]string{};for i,x:=range s.contents{if x!=nil{out=append(out,s.describe(i))}};if len(out)==0{return []string{"(no cells)"}};return out
    case "DEPS":i:=id(address(rest));ds:=[]int{};for j,xs:=range s.deps{for _,k:=range xs{if k==i{ds=append(ds,j);break}}};return []string{rest+": precedents="+formatted(s.deps[i])+" dependents="+formatted(ds)}
    case "PRINT":
        g:=area(rest);rw:=len(strconv.Itoa(g.b.row+1));ws:=[]int{};sep,head:="+"+strings.Repeat("-",rw)+"+","|"+strings.Repeat(" ",rw)+"|"
        for c:=g.a.n;c<=g.b.n;c++{w:=1;for r:=g.a.row;r<=g.b.row;r++{w=max(w,len(display(s.values[r*26+c])))};ws=append(ws,w);sep+=strings.Repeat("-",w)+"+";head+=string(rune('A'+c))+strings.Repeat(" ",w-1)+"|"}
        out:=[]string{sep,head,sep};for r:=g.a.row;r<=g.b.row;r++{row:=fmt.Sprintf("|%*d|",rw,r+1);for j,w:=range ws{v:=s.values[r*26+g.a.n+j];t:=display(v);pad:=strings.Repeat(" ",w-len(t));if v!=nil&&v.kind=='N'{row+=pad+t+"|"}else{row+=t+pad+"|"}};out=append(out,row)};return append(out,sep)
    case "UNDO":if len(s.history)==0{fail("nothing to undo")};e:=s.history[len(s.history)-1];s.history=s.history[:len(s.history)-1];return []string{"UNDO "+e.name+" changed="+strconv.Itoa(s.replace(e.contents))}
    }
    next:=s.contents;target:=-1
    switch name {
    case "SET":
        a,v,_:=strings.Cut(rest," ");target=id(address(a));if strings.HasPrefix(v,"="){next[target]=&node{kind:'=',a:parseFormula(v)}}else if len(v)>=2&&v[0]=='"'&&v[len(v)-1]=='"'&&!strings.Contains(v[1:len(v)-1],`"`){next[target]=text(v[1:len(v)-1])}else if integerPattern.MatchString(v){n,_:=strconv.Atoi(v);next[target]=num(n)}else{fail("bad value")}
    case "CLEAR":for _,i:=range cells(area(rest)){next[i]=nil}
    case "COPY","MOVE":
        a,b,_:=strings.Cut(rest," ");source:=area(a);dest:=address(b);dc,dr:=dest.n-source.a.n,dest.row-source.a.row
        shift:=func(r *node,relative bool)*node{c,t:=r.n,r.row;if !relative||r.flags&1==0{c+=dc};if !relative||r.flags&2==0{t+=dr};return ref(c,t,r.flags)}
        destination:=makeRange(shift(source.a,false),shift(source.b,false));if !inside(destination.a)||!inside(destination.b){fail("out of grid")}
        transform:=func(x *node)*node{
            if x.kind=='R'{if name=="COPY"{r:=shift(x,true);if inside(r){return r};return invalid};if contains(source,x){return shift(x,false)};if contains(destination,x){return invalid};return x}
            if name=="MOVE"&&!(contains(source,x.a)&&contains(source,x.b)){return x};a,b:=shift(x.a,name=="COPY"),shift(x.b,name=="COPY");if inside(a)&&inside(b){return makeRange(a,b)};return invalid
        }
        if name=="MOVE"{for i,x:=range next{next[i]=rewrite(x,transform)}};ids:=cells(source);moving:=make([]*node,len(ids));for j,i:=range ids{if name=="COPY"{moving[j]=rewrite(s.contents[i],transform)}else{moving[j]=next[i]}};if name=="MOVE"{for _,i:=range ids{next[i]=nil}};for j,i:=range ids{next[i+dr*26+dc]=moving[j]}
    case "INSERTROW","DELETEROW","INSERTCOL","DELETECOL":
        row,insert:=strings.HasSuffix(name,"ROW"),strings.HasPrefix(name,"INSERT");at,limit:=0,26
        if row{if !rowPattern.MatchString(rest){fail("bad address")};at,_=strconv.Atoi(rest);at--;limit=99}else{if len(rest)!=1||rest[0]<'A'||rest[0]>'Z'{fail("bad address")};at=int(rest[0]-'A')}
        axis:=func(x *node)int{if row{return x.row};return x.n};change:=func(x *node,v int)*node{if row{return ref(x.n,v,x.flags)};return ref(v,x.row,x.flags)}
        if insert{for i,x:=range s.contents{v:=i%26;if row{v=i/26};if x!=nil&&v==limit-1{if row{fail("last row not empty")};fail("last column not empty")}}}
        transform:=func(x *node)*node{
            if x.kind=='R'{v:=axis(x);if !insert&&v==at{return invalid};n:=v;if insert&&v>=at{n++}else if !insert&&v>at{n--};if n>=limit{return invalid};return change(x,n)}
            a,b:=axis(x.a),axis(x.b);if !insert&&a==at&&b==at{return invalid};u,v:=a,b;if insert{if a>=at{u++};if b>=at{v++}}else{if a>at{u--};if b>=at{v--}};if v>=limit{return invalid};return makeRange(change(x.a,u),change(x.b,v))
        }
        next=grid{};for i,x:=range s.contents{if x==nil{continue};r:=ref(i%26,i/26,0);v:=axis(r);if !insert&&v==at{continue};n:=v;if insert&&v>=at{n++}else if !insert&&v>at{n--};t:=change(r,n);next[id(t)]=rewrite(x,transform)}
    default:fail("unknown command")
    }
    s.history=append(s.history,historyEntry{name,s.contents});changed:=s.replace(next);prefix:=name;if name=="SET"{prefix+=" "+label(target)+"="+notation(s.values[target])};return []string{prefix+" changed="+strconv.Itoa(changed)}
}
func handle(s *sheet,line string)(out []string){defer func(){if e:=recover();e!=nil{if problem,ok:=e.(commandError);ok{out=[]string{"ERROR "+string(problem)}}else{panic(e)}}}();return s.execute(line)}
func main(){input:=bufio.NewScanner(os.Stdin);input.Buffer(make([]byte,1024),1024*1024);input.Scan();n,_:=strconv.Atoi(input.Text());s:=sheet{};out:=bufio.NewWriter(os.Stdout);defer out.Flush();for i:=0;i<n&&input.Scan();i++{for _,line:=range handle(&s,input.Text()){fmt.Fprintln(out,line)}}}
