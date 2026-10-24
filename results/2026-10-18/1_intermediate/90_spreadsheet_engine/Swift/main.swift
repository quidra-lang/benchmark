import Foundation

struct Problem: Error { let message: String }
final class Expr {
    let kind: Character
    let n, row, flags: Int
    let text: String
    let a, b: Expr?
    let args: [Expr]
    init(_ kind: Character, _ n: Int = 0, _ row: Int = 0, _ flags: Int = 0, _ text: String = "", _ a: Expr? = nil, _ b: Expr? = nil, _ args: [Expr] = []) {
        self.kind=kind;self.n=n;self.row=row;self.flags=flags;self.text=text;self.a=a;self.b=b;self.args=args
    }
}
func num(_ n: Int) -> Expr { Expr("N",n) }
func text(_ s: String) -> Expr { Expr("S",0,0,0,s) }
func errorValue(_ s: String) -> Expr { Expr("E",0,0,0,s) }
func ref(_ c: Int,_ r: Int,_ f: Int = 0) -> Expr { Expr("R",c,r,f) }
let invalid=Expr("X")
func id(_ r: Expr) -> Int { r.row*26+r.n }
func letter(_ c: Int) -> String { String(UnicodeScalar(65+c)!) }
func label(_ i: Int) -> String { letter(i%26)+String(i/26+1) }
func inside(_ r: Expr) -> Bool { (0..<26).contains(r.n)&&(0..<99).contains(r.row) }
func slice(_ s: String,_ start: Int,_ end: Int? = nil) -> String { let b=Array(s.utf8);return String(decoding:b[start..<(end ?? b.count)],as:UTF8.self) }
func matches(_ s: String,_ pattern: String) -> Bool { s.range(of:"\\A(?:"+pattern+")\\z",options:.regularExpression) != nil }
func makeRange(_ a: Expr,_ b: Expr) -> Expr {
    var c=a.n,d=b.n,r=a.row,t=b.row,ac=a.flags&1,bc=b.flags&1,ar=a.flags&2,br=b.flags&2
    if c>d {swap(&c,&d);swap(&ac,&bc)};if r>t {swap(&r,&t);swap(&ar,&br)}
    return Expr("G",0,0,0,"",ref(c,r,ac|ar),ref(d,t,bc|br))
}
func address(_ s: String) throws -> Expr {
    guard matches(s,"[A-Z][1-9][0-9]?") else {throw Problem(message:"bad address")}
    return ref(Int(s.utf8.first!)-65,Int(s.dropFirst())!-1)
}
func area(_ s: String) throws -> Expr {
    let p=s.split(separator:":",omittingEmptySubsequences:false).map(String.init)
    guard p.count<=2 else {throw Problem(message:"bad address")}
    let a=try address(p[0]);let b: Expr
    if p.count==1 {b=a}else {b=try address(p[1])};return makeRange(a,b)
}
func cells(_ g: Expr) -> [Int] { (g.a!.row...g.b!.row).flatMap {r in (g.a!.n...g.b!.n).map {c in r*26+c}} }
func contains(_ g: Expr,_ r: Expr) -> Bool { (g.a!.n...g.b!.n).contains(r.n)&&(g.a!.row...g.b!.row).contains(r.row) }
let levels=[Set(["=","<>","<","<=",">",">="]),Set(["&"]),Set(["+","-"]),Set(["*","/"])]
func precedence(_ op: String) -> Int { levels.firstIndex { $0.contains(op) } ?? -1 }
final class Parser {
    var tokens: [(Expr,Int)]=[]
    var at=0
    func syntax(_ p: Int) -> Problem { Problem(message:"syntax error at \(p)") }
    init(_ s: String) throws {
        let bytes=Array(s.utf8);var i=1
        func digit(_ c: UInt8) -> Bool { c>=48&&c<=57 }
        func alpha(_ c: UInt8) -> Bool { c>=65&&c<=90||c>=97&&c<=122 }
        while i<bytes.count {
            let p=i+1,ch=bytes[i];if ch==32 {i+=1;continue};let x: Expr
            if digit(ch) {
                var j=i;while j<bytes.count&&digit(bytes[j]) {j+=1}
                if j-i>=10 {throw syntax(p)};x=num(Int(slice(s,i,j))!);i=j
            }else if ch==34 {
                var j=i+1;while j<bytes.count&&bytes[j] != 34 {j+=1}
                if j==bytes.count {throw syntax(p)};x=text(slice(s,i+1,j));i=j+1
            }else if alpha(ch)||ch==36 {
                var j=i;while j<bytes.count&&(alpha(bytes[j])||digit(bytes[j])||bytes[j]==36) {j+=1}
                let w=slice(s,i,j).uppercased();i=j
                let regex=try! NSRegularExpression(pattern:"\\A(\\$?)([A-Z])(\\$?)([1-9][0-9]?)\\z")
                if let m=regex.firstMatch(in:w,range:NSRange(location:0,length:w.utf8.count)) {
                    let ns=w as NSString;let ac=ns.substring(with:m.range(at:1)),c=ns.substring(with:m.range(at:2)),ar=ns.substring(with:m.range(at:3)),r=ns.substring(with:m.range(at:4))
                    x=ref(Int(c.utf8.first!)-65,Int(r)!-1,(ac.isEmpty ? 0 : 1)|(ar.isEmpty ? 0 : 2))
                }else if matches(w,"[A-Z][A-Z0-9]*") {
                    x=Expr(slice(s,j).drop(while:{$0==" "}).hasPrefix("(") ? "C" : "W",0,0,0,w)
                }else {throw syntax(p)}
            }else{
                var op=slice(s,i,min(i+2,bytes.count));if !["<>","<=",">="].contains(op) {op=slice(s,i,i+1)}
                if !Array("+-*/&(),:=<>".utf8).contains(ch) {throw syntax(p)};x=Expr("T",0,0,0,op);i+=op.utf8.count
            }
            tokens.append((x,p))
        }
        tokens.append((Expr("Z"),bytes.count+1))
    }
    func take(_ op: String) -> Bool {let x=tokens[at].0;if x.kind=="T"&&x.text==op {at+=1;return true};return false}
    func expect(_ op: String) throws {if !take(op) {throw syntax(tokens[at].1)}}
    func expression(_ level: Int = 0) throws -> Expr {
        if level==4 {return try primary()};var a=try expression(level+1)
        while tokens[at].0.kind=="T"&&levels[level].contains(tokens[at].0.text) {let op=tokens[at].0.text;at+=1;a=Expr("B",0,0,0,op,a,try expression(level+1))};return a
    }
    func primary() throws -> Expr {
        if take("-") {return Expr("U",0,0,0,"",try primary())};let (x,p)=tokens[at];at+=1
        if "NSW".contains(x.kind) {return x}
        if x.kind=="R" {if !take(":") {return x};if tokens[at].0.kind != "R" {throw syntax(tokens[at].1)};let b=tokens[at].0;at+=1;return makeRange(x,b)}
        if x.kind=="C" {try expect("(");var args:[Expr]=[];if !take(")") {args.append(try expression());while take(",") {args.append(try expression())};try expect(")")};return Expr("F",0,0,0,x.text,nil,nil,args)}
        if x.kind=="T"&&x.text=="(" {let a=try expression();try expect(")");return a};throw syntax(p)
    }
    func parse() throws -> Expr {let a=try expression();if tokens[at].0.kind != "Z" {throw syntax(tokens[at].1)};return a}
}
func canonical(_ x: Expr) -> String {
    switch x.kind {
    case "N":return String(x.n)
    case "S":return "\""+x.text+"\""
    case "W":return x.text
    case "X":return "#REF!"
    case "R":return (x.flags&1 != 0 ? "$" : "")+letter(x.n)+(x.flags&2 != 0 ? "$" : "")+String(x.row+1)
    case "G":return canonical(x.a!)+":"+canonical(x.b!)
    case "F":return x.text+"("+x.args.map(canonical).joined(separator:",")+")"
    case "U":return "-"+(x.a!.kind=="B" ? "("+canonical(x.a!)+")" : canonical(x.a!))
    default:
        var a=canonical(x.a!),b=canonical(x.b!)
        if x.a!.kind=="B"&&precedence(x.a!.text)<precedence(x.text) {a="("+a+")"}
        if x.b!.kind=="B"&&precedence(x.b!.text)<=precedence(x.text) {b="("+b+")"};return a+x.text+b
    }
}
func display(_ x: Expr?) -> String {guard let x else {return ""};return x.kind=="N" ? String(x.n) : x.text}
func notation(_ x: Expr?) -> String {guard let x else {return "(empty)"};return x.kind=="=" ? "="+canonical(x.a!) : x.kind=="S" ? "\""+x.text+"\"" : display(x)}
func number(_ x: Expr?) -> Expr {guard let x else {return num(0)};return "SG".contains(x.kind) ? errorValue("#VALUE!") : x}
func stringValue(_ x: Expr?) -> Expr {guard let x else {return text("")};return x.kind=="N" ? text(String(x.n)) : x.kind=="G" ? errorValue("#VALUE!") : x}
func rewrite(_ x: Expr?,_ transform: (Expr)->Expr) -> Expr? {
    guard let x else {return nil};if "RG".contains(x.kind) {return transform(x)}
    return Expr(x.kind,x.n,x.row,x.flags,x.text,rewrite(x.a,transform),rewrite(x.b,transform),x.args.map {rewrite($0,transform)!})
}
func dependencies(_ x: Expr?) -> Set<Int> {
    guard let x else {return []};if x.kind=="R" {return [id(x)]};if x.kind=="G" {return Set(cells(x))}
    var result=dependencies(x.a).union(dependencies(x.b));for a in x.args {result.formUnion(dependencies(a))};return result
}
final class Sheet {
    var contents=[Expr?](repeating:nil,count:2574),values=[Expr?](repeating:nil,count:2574)
    var deps=[Set<Int>](repeating:[],count:2574)
    var history:[(String,[Expr?])]=[]
    func evaluate(_ x: Expr) -> Expr? {
        if "NSG".contains(x.kind) {return x};if x.kind=="R" {return values[id(x)]};if x.kind=="W" {return errorValue("#NAME?")};if x.kind=="X" {return errorValue("#REF!")}
        if x.kind=="U" {let a=number(evaluate(x.a!));return a.kind=="E" ? a : num(-a.n)}
        if x.kind=="B" {
            var a=evaluate(x.a!),b=evaluate(x.b!);let op=x.text
            if a?.kind=="E" {return a};if b?.kind=="E" {return b}
            if precedence(op)==0 {
                if a?.kind=="G"||b?.kind=="G" {return errorValue("#VALUE!")}
                let blank=a?.kind=="S"||b?.kind=="S" ? text("") : num(0);a=a ?? blank;b=b ?? blank
                let c: Int
                if a!.kind != b!.kind {c=a!.kind=="N" ? -1 : 1}
                else if a!.kind=="N" {c=a!.n==b!.n ? 0 : a!.n<b!.n ? -1 : 1}
                else {c=a!.text==b!.text ? 0 : a!.text.utf8.lexicographicallyPrecedes(b!.text.utf8) ? -1 : 1}
                let yes=op=="=" ? c==0 : op=="<>" ? c != 0 : op=="<" ? c<0 : op=="<=" ? c<=0 : op==">" ? c>0 : c>=0
                return num(yes ? 1 : 0)
            }
            let u=op=="&" ? stringValue(a) : number(a),v=op=="&" ? stringValue(b) : number(b)
            if u.kind=="E" {return u};if v.kind=="E" {return v}
            switch op {case "&":return text(u.text+v.text);case "+":return num(u.n+v.n);case "-":return num(u.n-v.n);case "*":return num(u.n*v.n);default:return v.n==0 ? errorValue("#DIV/0!") : num(u.n/v.n)}
        }
        let name=x.text,args=x.args
        if ["SUM","MIN","MAX","COUNT","AVERAGE","AND","OR","CONCAT"].contains(name) {
            if args.isEmpty {return errorValue("#VALUE!")};var items:[Expr?]=[]
            for a in args {let v=evaluate(a);if v?.kind=="G" {items.append(contentsOf:cells(v!).map {values[$0]})}else {items.append(v)}}
            let ns=items.compactMap {v -> Int? in v?.kind=="N" ? v!.n : nil}
            if name=="COUNT" {return num(ns.count)};for v in items {if v?.kind=="E" {return v}}
            switch name {
            case "SUM":return num(ns.reduce(0,+))
            case "MIN":return num(ns.min() ?? 0)
            case "MAX":return num(ns.max() ?? 0)
            case "AVERAGE":return ns.isEmpty ? errorValue("#DIV/0!") : num(ns.reduce(0,+)/ns.count)
            case "AND":return ns.isEmpty ? errorValue("#VALUE!") : num(ns.allSatisfy {$0 != 0} ? 1 : 0)
            case "OR":return ns.isEmpty ? errorValue("#VALUE!") : num(ns.contains {$0 != 0} ? 1 : 0)
            default:return text(items.map {stringValue($0).text}.joined())
            }
        }
        if name=="IF" {if args.count != 2&&args.count != 3 {return errorValue("#VALUE!")};let c=number(evaluate(args[0]));if c.kind=="E" {return c};return c.n != 0 ? evaluate(args[1]) : args.count==3 ? evaluate(args[2]) : num(0)}
        if !["ABS","NOT","LEN"].contains(name) {return errorValue("#NAME?")};if args.count != 1 {return errorValue("#VALUE!")}
        let v=name=="LEN" ? stringValue(evaluate(args[0])) : number(evaluate(args[0]));return v.kind=="E" ? v : num(name=="LEN" ? v.text.utf8.count : name=="ABS" ? abs(v.n) : v.n==0 ? 1 : 0)
    }
    func recalculate() {
        deps=contents.map {$0?.kind=="=" ? dependencies($0!.a) : []};values=contents.map {$0?.kind=="=" ? nil : $0}
        var indices=[Int](repeating:-1,count:2574),low=[Int](repeating:0,count:2574),on=Set<Int>(),cyclic=Set<Int>(),stack:[Int]=[],serial=0
        func visit(_ i: Int) {
            indices[i]=serial;low[i]=serial;serial+=1;stack.append(i);on.insert(i)
            for j in deps[i] where contents[j]?.kind=="=" {if indices[j]<0 {visit(j);low[i]=min(low[i],low[j])}else if on.contains(j) {low[i]=min(low[i],indices[j])}}
            if low[i]==indices[i] {var part:[Int]=[];while true {let j=stack.removeLast();on.remove(j);part.append(j);if j==i {break}};if part.count>1||deps[i].contains(i) {cyclic.formUnion(part)}}
        }
        for i in 0..<2574 where contents[i]?.kind=="="&&indices[i]<0 {visit(i)}
        var done=Set<Int>()
        func calculate(_ i: Int) {
            if contents[i]?.kind != "="||done.contains(i) {return};done.insert(i)
            if cyclic.contains(i) {values[i]=errorValue("#CYCLE!");return};for j in deps[i] {calculate(j)}
            let v=evaluate(contents[i]!.a!);values[i]=v==nil ? num(0) : v!.kind=="G" ? errorValue("#VALUE!") : v
        }
        for i in 0..<2574 {calculate(i)}
    }
    func replace(_ next: [Expr?]) -> Int {let old=values;contents=next;recalculate();return old.indices.filter {notation(old[$0]) != notation(values[$0])}.count}
    func describe(_ i: Int) -> String {"\(label(i)): \(notation(contents[i])) -> \(notation(values[i]))"}
    func formatted(_ xs: Set<Int>) -> String {xs.isEmpty ? "none" : xs.sorted().map(label).joined(separator:",")}
    func execute(_ line: String) throws -> [String] {
        let parts=line.split(separator:" ",maxSplits:1).map(String.init);let name=parts[0],rest=parts.count==2 ? parts[1] : ""
        if name=="SHOW" {return [describe(id(try address(rest)))]}
        if name=="LIST" {let out=contents.indices.filter {contents[$0] != nil}.map(describe);return out.isEmpty ? ["(no cells)"] : out}
        if name=="DEPS" {let i=id(try address(rest));let ds=Set(deps.indices.filter {deps[$0].contains(i)});return ["\(rest): precedents=\(formatted(deps[i])) dependents=\(formatted(ds))"]}
        if name=="PRINT" {
            let g=try area(rest),rw=String(g.b!.row+1).count;let cs=g.a!.n...g.b!.n,rs=g.a!.row...g.b!.row
            let ws=cs.map {c in max(1,rs.map {r in display(values[r*26+c]).utf8.count}.max()!)}
            let sep="+"+String(repeating:"-",count:rw)+"+"+ws.map {String(repeating:"-",count:$0)+"+"}.joined()
            let head="|"+String(repeating:" ",count:rw)+"|"+zip(cs,ws).map {letter($0.0)+String(repeating:" ",count:$0.1-1)+"|"}.joined();var out=[sep,head,sep]
            for r in rs {let label=String(r+1);var row="|"+String(repeating:" ",count:rw-label.count)+label+"|";for(c,w) in zip(cs,ws) {let v=values[r*26+c],s=display(v);let pad=String(repeating:" ",count:w-s.utf8.count);row+=(v?.kind=="N" ? pad+s : s+pad)+"|"};out.append(row)};out.append(sep);return out
        }
        if name=="UNDO" {guard let e=history.popLast() else {throw Problem(message:"nothing to undo")};return ["UNDO \(e.0) changed=\(replace(e.1))"]}
        var next=contents,target=0
        if name=="SET" {
            let p=rest.split(separator:" ",maxSplits:1).map(String.init);target=id(try address(p[0]));let s=p[1]
            if s.hasPrefix("=") {next[target]=Expr("=",0,0,0,"",try Parser(s).parse())}
            else if matches(s,"\"[^\"]*\"") {next[target]=text(slice(s,1,s.utf8.count-1))}
            else if matches(s,"0|-?[1-9][0-9]{0,8}") {next[target]=num(Int(s)!)}else {throw Problem(message:"bad value")}
        }else if name=="CLEAR" {for i in cells(try area(rest)) {next[i]=nil}}
        else if name=="COPY"||name=="MOVE" {
            let p=rest.split(separator:" ",maxSplits:1).map(String.init);let source=try area(p[0]),dest=try address(p[1]);let dc=dest.n-source.a!.n,dr=dest.row-source.a!.row
            func shift(_ r: Expr,_ relative: Bool) -> Expr {ref(r.n+(relative&&r.flags&1 != 0 ? 0 : dc),r.row+(relative&&r.flags&2 != 0 ? 0 : dr),r.flags)}
            let destination=makeRange(shift(source.a!,false),shift(source.b!,false));if !inside(destination.a!) || !inside(destination.b!) {throw Problem(message:"out of grid")}
            func transform(_ x: Expr) -> Expr {
                if x.kind=="R" {if name=="COPY" {let r=shift(x,true);return inside(r) ? r : invalid};return contains(source,x) ? shift(x,false) : contains(destination,x) ? invalid : x}
                if name=="MOVE" && !(contains(source,x.a!)&&contains(source,x.b!)) {return x};let a=shift(x.a!,name=="COPY"),b=shift(x.b!,name=="COPY");return inside(a)&&inside(b) ? makeRange(a,b) : invalid
            }
            if name=="MOVE" {next=next.map {rewrite($0,transform)}};let ids=cells(source);let moving=ids.map {name=="COPY" ? rewrite(contents[$0],transform) : next[$0]}
            if name=="MOVE" {for i in ids {next[i]=nil}};for(i,x) in zip(ids,moving) {next[i+dr*26+dc]=x}
        }else if ["INSERTROW","DELETEROW","INSERTCOL","DELETECOL"].contains(name) {
            let row=name.hasSuffix("ROW"),insert=name.hasPrefix("INSERT")
            if !matches(rest,row ? "[1-9][0-9]?" : "[A-Z]") {throw Problem(message:"bad address")}
            let at=row ? Int(rest)!-1 : Int(rest.utf8.first!)-65,limit=row ? 99 : 26
            func axis(_ x: Expr) -> Int {row ? x.row : x.n}
            func change(_ x: Expr,_ v: Int) -> Expr {ref(row ? x.n : v,row ? v : x.row,x.flags)}
            if insert&&contents.indices.contains(where:{contents[$0] != nil&&(row ? $0/26 : $0%26)==limit-1}) {throw Problem(message:"last \(row ? "row" : "column") not empty")}
            func transform(_ x: Expr) -> Expr {
                if x.kind=="R" {let v=axis(x);if !insert&&v==at {return invalid};let n=v+(insert ? (v>=at ? 1 : 0) : (v>at ? -1 : 0));return n>=limit ? invalid : change(x,n)}
                let a=axis(x.a!),b=axis(x.b!);if !insert&&a==at&&b==at {return invalid};let u=a+(insert ? (a>=at ? 1 : 0) : (a>at ? -1 : 0)),v=b+(insert ? (b>=at ? 1 : 0) : (b>=at ? -1 : 0));return v>=limit ? invalid : makeRange(change(x.a!,u),change(x.b!,v))
            }
            next=[Expr?](repeating:nil,count:2574);for i in contents.indices where contents[i] != nil {let r=ref(i%26,i/26),v=axis(r);if !insert&&v==at {continue};let t=change(r,v+(insert ? (v>=at ? 1 : 0) : (v>at ? -1 : 0)));next[id(t)]=rewrite(contents[i],transform)}
        }else {throw Problem(message:"unknown command")}
        history.append((name,contents));let changed=replace(next)
        return [name+(name=="SET" ? " \(label(target))=\(notation(values[target]))" : "")+" changed=\(changed)"]
    }
}
let count=Int(readLine()!)!,sheet=Sheet()
for _ in 0..<count {
    let line=readLine()!
    do {for row in try sheet.execute(line) {print(row)}}catch let problem as Problem {print("ERROR \(problem.message)")}catch {fatalError(String(describing:error))}
}
