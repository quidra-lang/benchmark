import Foundation

struct Fault: Error { let reason:String }
func fail(_ s:String)throws->Never{throw Fault(reason:s)}
indirect enum Value {
    case integer(Int64), boolean(Bool), string(String), symbol(String), nilValue, pair(Pair), procedure(Procedure), void, uninitialized
}
final class Pair {let car:Value,cdr:Value;init(_ a:Value,_ b:Value){car=a;cdr=b}}
final class Env {
    var frame=[String:Value]();let parent:Env?
    init(_ p:Env?=nil){parent=p}
    func find(_ n:String)throws->Env{var e:Env?=self;while let current=e{if current.frame[n] != nil{return current};e=current.parent};try fail("unbound variable: "+n)}
    func get(_ n:String)throws->Value{let v=try find(n).frame[n]!;if case .uninitialized=v{try fail("uninitialized variable: "+n)};return v}
}
final class Procedure {
    var name:String?;let minimum:Int,variadic:Bool;let rest:String?,params:[String],expressions:[Value],env:Env?;let builtin:(([Value])throws->Value)?
    init(_ name:String?,_ minimum:Int,_ variadic:Bool,rest:String?=nil,params:[String]=[],body:[Value]=[],env:Env?=nil,builtin:(([Value])throws->Value)?=nil){self.name=name;self.minimum=minimum;self.variadic=variadic;self.rest=rest;self.params=params;self.expressions=body;self.env=env;self.builtin=builtin}
    func call(_ a:[Value])throws->Value{
        if a.count<minimum || (!variadic && a.count != minimum){try fail("\(name ?? "lambda"): wrong number of arguments (expected \(variadic ? "at least " : "")\(minimum), got \(a.count))")}
        if let fn=builtin{return try fn(a)};let e=Env(env);for(i,n)in params.enumerated(){e.frame[n]=a[i]};if let r=rest{e.frame[r]=makeList(Array(a.dropFirst(minimum)))};return try body(expressions,e)
    }
}
func makeList(_ a:[Value],_ tail:Value = .nilValue)->Value{a.reversed().reduce(tail){.pair(Pair($1,$0))}}
func items(_ value:Value)->[Value]?{var v=value,a=[Value]();while case .pair(let p)=v{a.append(p.car);v=p.cdr};if case .nilValue=v{return a};return nil}
func truth(_ v:Value)->Bool{if case .boolean(false)=v{return false};return true}
func repr(_ value:Value,_ quoted:Bool=true)->String{
    switch value{case .integer(let n):return String(n);case .boolean(let b):return b ? "#t" : "#f";case .string(let s):return quoted ? "\""+s.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"").replacingOccurrences(of:"\n",with:"\\n")+"\"" : s;case .symbol(let s):return s;case .nilValue:return "()";case .procedure(let f):return f.name.map{"#<procedure \($0)>"} ?? "#<procedure>";case .pair:
        var v=value,a=[String]();while case .pair(let p)=v{a.append(repr(p.car,quoted));v=p.cdr};if case .nilValue=v{}else{a.append(".");a.append(repr(v,quoted))};return "("+a.joined(separator:" ")+")"
    default:return "#<void>"}
}
func same(_ a:Value,_ b:Value,_ deep:Bool=false)->Bool{switch(a,b){case(.integer(let a),.integer(let b)):return a==b;case(.boolean(let a),.boolean(let b)):return a==b;case(.string(let a),.string(let b)),(.symbol(let a),.symbol(let b)):return a==b;case(.nilValue,.nilValue),(.void,.void):return true;case(.pair(let p),.pair(let q)):return deep ? same(p.car,q.car,true)&&same(p.cdr,q.cdr,true) : p===q;case(.procedure(let p),.procedure(let q)):return p===q;default:return false}}
func shape(_ ok:Bool,_ x:Value)throws{if !ok{try fail("bad syntax: "+repr(x))}}
func parameters(_ value:Value)->([String],String?)?{var v=value,names=[String]();while case .pair(let p)=v{guard case .symbol(let s)=p.car else{return nil};names.append(s);v=p.cdr};let rest:String?;switch v{case .nilValue:rest=nil;case .symbol(let n):rest=n;default:return nil};let all=names+(rest.map{[$0]} ?? []);return Set(all).count==all.count ? (names,rest) : nil}
func closure(_ p:([String],String?),_ b:[Value],_ e:Env,_ name:String?=nil)->Value{.procedure(Procedure(name,p.0.count,p.1 != nil,rest:p.1,params:p.0,body:b,env:e))}
func bindings(_ value:Value,_ unique:Bool)->[(String,Value)]?{guard let a=items(value)else{return nil};var bs=[(String,Value)](),seen=Set<String>();for x in a{guard let b=items(x),b.count==2,case .symbol(let name)=b[0] else{return nil};if unique && !seen.insert(name).inserted{return nil};bs.append((name,b[1]))};return bs}
func body(_ a:[Value],_ e:Env)throws->Value{var v=Value.void;for x in a{v=try evaluate(x,e)};return v}
func evaluate(_ x:Value,_ e:Env)throws->Value{
    if case .symbol(let n)=x{return try e.get(n)};guard case .pair=x else{if case .nilValue=x{try shape(false,x)};return x}
    guard let a=items(x)else{try fail("bad syntax: "+repr(x))};let n=a.count;let h:String;if case .symbol(let name)=a[0]{h=name}else{h=""}
    switch h{
    case "quote":try shape(n==2,x);return a[1]
    case "if":try shape(n==3||n==4,x);if truth(try evaluate(a[1],e)){return try evaluate(a[2],e)};return n==4 ? try evaluate(a[3],e) : .void
    case "begin":return try body(Array(a.dropFirst()),e)
    case "lambda":let p=n>=3 ? parameters(a[1]) : nil;try shape(p != nil,x);return closure(p!,Array(a.dropFirst(2)),e)
    case "define":
        if n>1,case .symbol(let name)=a[1]{try shape(n==3,x);let v=try evaluate(a[2],e);if case .procedure(let f)=v,f.builtin==nil,f.name==nil{f.name=name};e.frame[name]=v}
        else{guard n>=3,case .pair(let t)=a[1],case .symbol(let name)=t.car,let p=parameters(t.cdr)else{try fail("bad syntax: "+repr(x))};e.frame[name]=closure(p,Array(a.dropFirst(2)),e,name)};return .void
    case "set!":guard n==3,case .symbol(let name)=a[1]else{try fail("bad syntax: "+repr(x))};let v=try evaluate(a[2],e);let target=try e.find(name);target.frame[name]=v;return .void
    case "let","let*","letrec":
        var loop:String?;if h=="let",n>1,case .symbol(let name)=a[1]{loop=name};let at=loop==nil ? 1 : 2;let bs=n>=at+2 ? bindings(a[at],h != "let*") : nil;try shape(bs != nil,x);var scope=Env(e)
        if h=="let*"{if !bs!.isEmpty{scope=e};for(name,expr)in bs!{let v=try evaluate(expr,scope);scope=Env(scope);scope.frame[name]=v}}
        else if h=="letrec"{for(name,_)in bs!{scope.frame[name] = .uninitialized};for(name,expr)in bs!{scope.frame[name]=try evaluate(expr,scope)}}
        else{var vs=[Value]();for(_,expr)in bs!{vs.append(try evaluate(expr,e))};if let name=loop{let f=closure((bs!.map{$0.0},nil),Array(a.dropFirst(3)),scope,name);scope.frame[name]=f;if case .procedure(let p)=f{return try p.call(vs)}};for(i,b)in bs!.enumerated(){scope.frame[b.0]=vs[i]}};return try body(Array(a.dropFirst(at+1)),scope)
    case "cond":
        var cs=[[Value]]();for(i,c0)in a.dropFirst().enumerated(){guard let c=items(c0),!c.isEmpty else{try fail("bad syntax: "+repr(x))};if case .symbol("else")=c[0]{try shape(c.count>=2&&i==n-2,x)};cs.append(c)}
        for c in cs{if case .symbol("else")=c[0]{return try body(Array(c.dropFirst()),e)};let v=try evaluate(c[0],e);if truth(v){return c.count==1 ? v : try body(Array(c.dropFirst()),e)}};return .void
    case "and":var v=Value.boolean(true);for z in a.dropFirst(){v=try evaluate(z,e);if !truth(v){break}};return v
    case "or":for z in a.dropFirst(){let v=try evaluate(z,e);if truth(v){return v}};return .boolean(false)
    case "when","unless":try shape(n>=3,x);return truth(try evaluate(a[1],e))==(h=="when") ? try body(Array(a.dropFirst(2)),e) : .void
    default:break
    }
    let f=try evaluate(a[0],e);var args=[Value]();for z in a.dropFirst(){args.append(try evaluate(z,e))};guard case .procedure(let p)=f else{try fail("not a procedure: "+repr(f))};return try p.call(args)
}
var output="",mid=false
func write(_ s:String){output+=s;if !s.isEmpty{mid = !s.hasSuffix("\n")}}
func line(_ s:String){if mid{write("\n")};write(s+"\n")}
func expect(_ n:String,_ v:Value,_ k:String)throws->Value{let ok:Bool;switch(k,v){case("integer",.integer), ("string",.string),("pair",.pair),("procedure",.procedure):ok=true;case("list",_):ok=items(v) != nil;default:ok=false};if !ok{try fail("\(n): expected \(k), got "+repr(v))};return v}
func asList(_ n:String,_ v:Value)throws->[Value]{_ = try expect(n,v,"list");return items(v)!}
func intValue(_ v:Value)->Int64{if case .integer(let n)=v{return n};preconditionFailure()}
func global()->Env{
    let e=Env();func add(_ n:String,_ m:Int,_ r:Bool,_ fn:@escaping([Value])throws->Value){e.frame[n] = .procedure(Procedure(n,m,r,builtin:fn))}
    for name in ["+","*","-","quotient","remainder","modulo","abs","min","max","gcd","=","<",">","<=",">="]{
        let fixed=["quotient","remainder","modulo"].contains(name) ? 2 : name=="abs" ? 1 : -1
        add(name,fixed>=0 ? fixed : ["+","*","gcd"].contains(name) ? 0 : 1,fixed<0){a in
            for v in a{_ = try expect(name,v,"integer")};let z=a.map(intValue);let v=z.first ?? 0
            switch name{case "+":return .integer(z.reduce(0,+));case "*":return .integer(z.reduce(1,*));case "-":return .integer(z.count==1 ? -v : v-z.dropFirst().reduce(0,+));case "abs":return .integer(abs(v));case "min":return .integer(z.min()!);case "max":return .integer(z.max()!);case "gcd":var g:Int64=0;for x in z{var b=abs(x);while b != 0{let r=g%b;g=b;b=r}};return .integer(g)
            case "quotient","remainder","modulo":let b=z[1];if b==0{try fail(name+": division by zero")};let r=v%b;return .integer(name=="quotient" ? v/b : name=="modulo" && r != 0 && ((r<0) != (b<0)) ? r+b : r)
            default:for i in 1..<z.count{let l=z[i-1],r=z[i];let ok=name=="=" ? l==r : name=="<" ? l<r : name==">" ? l>r : name=="<=" ? l<=r : l>=r;if !ok{return .boolean(false)}};return .boolean(true)}
        }
    }
    add("not",1,false){.boolean(!truth($0[0]))};for n in ["eq?","equal?"]{add(n,2,false){.boolean(same($0[0],$0[1],n=="equal?"))}}
    for n in ["null?","pair?","list?","number?","symbol?","procedure?"]{add(n,1,false){a in let b:Bool;switch(n,a[0]){case("null?",.nilValue),("pair?",.pair),("number?",.integer),("symbol?",.symbol),("procedure?",.procedure):b=true;case("list?",_):b=items(a[0]) != nil;default:b=false};return .boolean(b)}}
    add("cons",2,false){.pair(Pair($0[0],$0[1]))};add("list",0,true){makeList($0)}
    for n in ["car","cdr","cadr"]{add(n,1,false){a in guard case .pair(let p)=try expect(n,a[0],"pair")else{preconditionFailure()};if n=="car"{return p.car};if n=="cdr"{return p.cdr};guard case .pair(let q)=try expect(n,p.cdr,"pair")else{preconditionFailure()};return q.car}}
    for n in ["length","reverse","list-ref"]{add(n,n=="list-ref" ? 2 : 1,false){a in let z=try asList(n,a[0]);if n=="length"{return .integer(Int64(z.count))};if n=="reverse"{return makeList(Array(z.reversed()))};let k=intValue(try expect(n,a[1],"integer"));if k<0||k>=Int64(z.count){try fail("list-ref: index out of range: \(k)")};return z[Int(k)]}}
    add("append",0,true){a in if a.isEmpty{return .nilValue};var z=[Value]();for v in a.dropLast(){z+=try asList("append",v)};return makeList(z,a.last!)}
    for n in ["map","filter","fold-left","apply"]{add(n,n=="fold-left" ? 3 : 2,n != "filter"){a in
        guard case .procedure(let f)=try expect(n,a[0],"procedure")else{preconditionFailure()};if n=="apply"{return try f.call(Array(a.dropFirst().dropLast())+asList(n,a.last!))};let ls=try a.dropFirst(n=="fold-left" ? 2 : 1).map{try asList(n,$0)};let count=ls.map{$0.count}.min()!;var out=[Value](),acc=a[1]
        for i in 0..<count{if n=="filter"{if truth(try f.call([ls[0][i]])){out.append(ls[0][i])}}else{let args=(n=="fold-left" ? [acc] : [])+ls.map{$0[i]};let v=try f.call(args);if n=="map"{out.append(v)}else{acc=v}}};return n=="fold-left" ? acc : makeList(out)
    }}
    add("string-append",0,true){a in var s="";for v in a{if case .string(let t)=try expect("string-append",v,"string"){s+=t}};return .string(s)};add("number->string",1,false){.string(repr(try expect("number->string",$0[0],"integer")))}
    add("display",1,false){write(repr($0[0],false));return .void};add("newline",0,false){_ in write("\n");return .void};add("error",1,true){a in guard case .string(var s)=try expect("error",a[0],"string")else{preconditionFailure()};for v in a.dropFirst(){s+=" "+repr(v)};try fail(s)};return e
}
final class Reader{
    let lines:[[UInt8]];var row=0,col=0;init(_ lines:[String]){self.lines=lines.map{Array($0.utf8)}}
    func skip(){row+=1;col=0}
    func end()->Bool{while row<lines.count{let s=lines[row];while col<s.count&&s[col]==32{col+=1};if col<s.count&&s[col] != 59{return false};skip()};return true}
    func token()throws->(UInt8,Value?){if end(){try fail("unexpected end of input")};let s=lines[row];var c=s[col];col+=1;if [40,41,39].contains(c){return(c,nil)};if c==34{var v=[UInt8]();while col<s.count{c=s[col];col+=1;if c==34{return(118,.string(String(decoding:v,as:UTF8.self)))};if c==92{if col==s.count{break};c=s[col];col+=1;if ![34,92,110].contains(c){try fail("bad escape")};if c==110{c=10}};v.append(c)};try fail("unterminated string")};let first=col-1;while col<s.count && ![32,40,41,39,34,59].contains(s[col]){col+=1};let a=String(decoding:s[first..<col],as:UTF8.self);if a=="."{return(46,nil)};if a.range(of:"^[+-]?[0-9]+$",options:.regularExpression) != nil{return(118,.integer(Int64(a)!))};if a=="#t"||a=="#f"{return(118,.boolean(a=="#t"))};if a.hasPrefix("#"){try fail("bad token: "+a)};return(118,.symbol(a))}
    func datum()throws->Value{try from(token())}
    func from(_ t:(UInt8,Value?))throws->Value{if t.0==118{return t.1!};if t.0==39{return makeList([.symbol("quote"),try datum()])};if t.0 != 40{try fail("unexpected "+String(UnicodeScalar(t.0)))};var a=[Value]();while true{let t=try token();if t.0==41{return makeList(a)};if t.0==46 && !a.isEmpty{let tail=try datum();if try token().0 != 41{try fail("expected )")};return makeList(a,tail)};a.append(try from(t))}}
}
var lines=[String]();while let s=readLine(),s != "(exit)"{lines.append(s)};let reader=Reader(lines),environment=global()
while !reader.end(){let x:Value;do{x=try reader.datum()}catch let err as Fault{line("Error: read: "+err.reason);if err.reason=="unexpected end of input"{break};reader.skip();continue}catch{fatalError()};do{let v=try evaluate(x,environment);if case .void=v{}else{line(repr(v))}}catch let err as Fault{line("Error: "+err.reason)}catch{fatalError()}}
if mid{write("\n")};FileHandle.standardOutput.write(output.data(using:.utf8)!)
