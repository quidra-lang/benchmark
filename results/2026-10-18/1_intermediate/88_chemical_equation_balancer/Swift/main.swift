import Foundation

typealias Composition = [String: Int]
let symbols="H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe".components(separatedBy:" ")
let weights=[1008,4003,6941,9012,10811,12011,14007,15999,18998,20180,22990,24305,26982,28086,30974,32065,35453,39948,39098,40078,44956,47867,50942,51996,54938,55845,58933,58693,63546,65380,69723,72630,74922,78971,79904,83798,85468,87620,88906,91224,92906,95950,98000,101070,102906,106420,107868,112414,114818,118710,121760,127600,126904,131293]
let W=Dictionary(uniqueKeysWithValues:zip(symbols,weights))
let valence:Composition=["H":1,"F":1,"Cl":1,"Br":1,"I":1,"O":2,"S":2,"Se":2,"B":3,"N":3,"P":3,"As":3,"C":4,"Si":4,"Ge":4]
let metals:Composition=["Li":1,"Na":1,"K":1,"Rb":1,"Be":2,"Mg":2,"Ca":2,"Sr":2,"Al":3]
enum ChemError:Error {case message(String)}
func fail(_ s:String)throws->Never {throw ChemError.message("error: "+s)}
func gcd(_ a:Int,_ b:Int)->Int {var x=abs(a),y=abs(b);while y != 0 {(x,y)=(y,x%y)};return x}
func dec(_ n:Int,_ d:Int)->String {var p=1;for _ in 0..<d {p*=10};let f=String(n%p);return "\(n/p)."+String(repeating:"0",count:d-f.count)+f}
func ent(_ n:Int)->String {(n<0 ? "-":"")+dec(abs(n),2)}
func signed(_ n:Int)->String {(n>0 ? "+":"")+String(n)}
func matches(_ s:String,_ pattern:String)->Bool {s.range(of:pattern,options:.regularExpression) != nil}
struct Fraction:CustomStringConvertible {
    let n:Int,d:Int
    init(_ a:Int,_ b:Int=1){let g=gcd(a,b);n=a/g*(b<0 ? -1:1);d=abs(b)/g}
    static func - (a:Fraction,b:Fraction)->Fraction {Fraction(a.n*b.d-b.n*a.d,a.d*b.d)}
    static func * (a:Fraction,b:Fraction)->Fraction {Fraction(a.n*b.n,a.d*b.d)}
    static func / (a:Fraction,b:Fraction)->Fraction {Fraction(a.n*b.d,a.d*b.n)}
    var description:String {signed(n)+(d==1 ? "":"/\(d)")}
}
func order(_ c:Composition)->[String] {let es=c.keys.sorted();return c["C"] == nil ? es:["C"]+(c["H"] == nil ? []:["H"])+es.filter{$0 != "C" && $0 != "H"}}
func add(_ a:Composition,_ b:Composition,_ k:Int=1)->Composition {var c=a;for(e,n)in b {c[e,default:0]+=n*k};return c}
func scale(_ c:Composition,_ k:Int)->Composition {c.mapValues{$0*k}}
func mass(_ c:Composition)->Int {c.reduce(0){$0+$1.value*W[$1.key]!}}
func hill(_ c:Composition,_ q:Int=0)->String {order(c).map{$0+(c[$0]==1 ? "":String(c[$0]!))}.joined()+(q==0 ? "":"^"+(abs(q)==1 ? "":String(abs(q)))+(q>0 ? "+":"-"))}
struct Formula {let c:Composition;let q:Int;var molarMass:Int{mass(c)}}
struct Species {let f:String,state:String;let coefficient:Int;let formula:Formula;var name:String{f+state};var molarMass:Int{formula.molarMass}}
struct Equation {let list:[Species];let r:Int;var signs:[Int]{list.indices.map{$0<r ? 1:-1}}}
struct Parser {
    let chars:[Character];var p=0;var seen:[String]=[]
    init(_ text:String){chars=Array(text)}
    func peek()->Character {p<chars.count ? chars[p]:"\0"}
    mutating func number()throws->Int {let start=p;while peek()>="0" && peek()<="9" {p+=1};if start==p{return 1};if chars[start]=="0"{throw ChemError.message("syntax")};return Int(String(chars[start..<p]))!}
    mutating func sequence()throws->Composition {var c:Composition=[:];var items=0;while true {let ch=peek();let item:Composition;if ch>="A" && ch<="Z" {var e=String(chars[p]);p+=1;if peek()>="a" && peek()<="z" {e+=String(chars[p]);p+=1};seen.append(e);item=[e:1]}else if ch=="(" || ch=="[" {p+=1;item=try sequence();if peek() != (ch=="(" ? ")":"]"){throw ChemError.message("syntax")};p+=1}else{break};let k=try number();c=add(c,item,k);items+=1};if items==0{throw ChemError.message("syntax")};return c}
    mutating func parse()throws->Formula {var c=try sequence();while peek()=="." {p+=1;let k=try number();c=add(c,try sequence(),k)};var q=0;if peek()=="^" {p+=1;let k=try number();let ch=peek();if ch != "+" && ch != "-" {throw ChemError.message("syntax")};p+=1;q=ch=="+" ? k:-k};if p != chars.count {throw ChemError.message("syntax")};return Formula(c:c,q:q)}
}
func formula(_ text:String,_ word:String?=nil)throws->Formula {var p=Parser(text);let f:Formula;do{f=try p.parse()}catch{return try fail("invalid formula "+(word ?? text))};for e in p.seen{if W[e]==nil{return try fail("unknown element "+e)}};return f}
func species(_ word:String,_ check:Bool=false)throws->Species {let state=["(s)","(l)","(g)","(aq)"].first{word.hasSuffix($0)} ?? "";var f=String(word.dropLast(state.count));var k=1;if check {let chars=Array(f);let n=chars.prefix{$0 >= "0" && $0 <= "9"}.count;if n>0{if chars[0]=="0"{return try fail("invalid formula "+word)};k=Int(String(chars.prefix(n)))!;f=String(chars.dropFirst(n))}};return Species(f:f,state:state,coefficient:k,formula:try formula(f,word))}
func equation(_ a:[String],_ check:Bool=false)throws->Equation {var valid=a.count%2==1;var arrow = -1;for i in a.indices{let op=a[i]=="+" || a[i]=="->";if i%2==1{if !op{valid=false};if a[i]=="->"{if arrow>=0{valid=false};arrow=i}}else if op{valid=false}};if !valid || arrow<0{return try fail("malformed equation")};var list:[Species]=[];for i in stride(from:0,to:a.count,by:2){list.append(try species(a[i],check))};return Equation(list:list,r:(arrow+1)/2)}
func quantity(_ s:String)throws->Int {if !matches(s,"\\A(0|[1-9][0-9]{0,3})(\\.[0-9]{1,3})?\\z"){return try fail("invalid quantity "+s)};let p=s.components(separatedBy:".");let q=Int(p[0])! * 1000+(p.count==1 ? 0:Int(p[1]+String(repeating:"0",count:3-p[1].count))!);if q==0{return try fail("invalid quantity "+s)};return q}
func enthalpy(_ s:String)throws->Int {if !matches(s,"\\A-?(0|[1-9][0-9]{0,4})(\\.[0-9]{1,2})?\\z"){return try fail("invalid enthalpy "+s)};let p=(s.hasPrefix("-") ? String(s.dropFirst()):s).components(separatedBy:".");return (s.hasPrefix("-") ? -1:1)*(Int(p[0])! * 100+(p.count==1 ? 0:Int(p[1]+String(repeating:"0",count:2-p[1].count))!))}
func matrix(_ list:[Species],_ signs:[Int])->([String],[[Int]]) {var all:Composition=[:];for s in list{all=add(all,s.formula.c)};let labels=order(all)+["charge"];return (labels,labels.map{e in list.enumerated().map{i,s in signs[i]*(e=="charge" ? s.formula.q:s.formula.c[e,default:0])}})}
func nullspace(_ rows:[[Int]],_ n:Int)->(Int,[[Int]]) {var a=rows.map{$0.map{Fraction($0)}};var piv:[Int]=[],free:[Int]=[];for j in 0..<n{let r=piv.count;guard let i=(r..<a.count).first(where:{a[$0][j].n != 0})else{free.append(j);continue};a.swapAt(r,i);let t=a[r][j];a[r]=a[r].map{$0/t};for k in a.indices where k != r && a[k][j].n != 0{let f=a[k][j];for z in 0..<n{a[k][z]=a[k][z]-f*a[r][z]}};piv.append(j)};var basis:[[Int]]=[];for f in free{var v=Array(repeating:Fraction(0),count:n);v[f]=Fraction(1);for(i,j)in piv.enumerated(){v[j]=Fraction(-a[i][f].n,a[i][f].d)};var l=1;for x in v{l=l/gcd(l,x.d)*x.d};let b=v.map{$0.n*(l/$0.d)};let g=b.reduce(0,gcd);basis.append(b.map{$0/g})};return (piv.count,basis)}
func coefficients(_ list:[Species],_ signs:[Int],_ required:Int?=nil)throws->[Int] {let(_,rows)=matrix(list,signs);let(_,basis)=nullspace(rows,list.count);if basis.count>=2{throw ChemError.message("AMBIGUOUS (nullity \(basis.count))")};if basis.isEmpty{throw ChemError.message("IMPOSSIBLE")};var v=basis[0];if v[0]<0{v=v.map{-$0}};if v.prefix(required ?? list.count).contains(where:{$0<=0}){throw ChemError.message("IMPOSSIBLE")};return v}
func term(_ s:String,_ k:Int)->String {(k==1 ? "":String(k))+s}
func notation(_ eq:Equation,_ v:[Int])->String {let t=eq.list.enumerated().map{term($1.name,v[$0])};return t.prefix(eq.r).joined(separator:" + ")+" -> "+t.dropFirst(eq.r).joined(separator:" + ")}
func gas(_ s:Species,_ n:Int,_ d:Int)->String {s.state=="(g)" ? " \(dec(n*22414/d,3)) L":""}
func ratios(_ a:Composition)->[String] {let es=order(a);var f=es[0];for e in es where a[e]! * W[f]! < a[f]! * W[e]!{f=e};let out=es.map{"\($0) \(dec(1000*a[$0]! * W[f]! / (W[$0]! * a[f]!),3))"};for k in 1...12{var c:Composition=[:];var ok=true;for e in es{let n=k*a[e]! * W[f]!,d=W[e]! * a[f]!,i=(2*n+d)/(2*d);c[e]=i;if 20*abs(n-i*d)>d{ok=false}};if ok{return out+["\(hill(c)) (k = \(k))"]}};return out+["no simple ratio"]}
func group(_ f:String,_ k:Int)->String {let c=String(f.split(separator:"^")[0]);if k==1{return c};let chars=Array(c);var depth=0,last = -1;if chars[0]=="["{for i in chars.indices{if chars[i]=="["{depth+=1};if chars[i]=="]"{depth-=1;if depth==0{last=i;break}}}};return (matches(c,"\\A[A-Z][a-z]?\\z") || last==chars.count-1 ? c:"(\(c))")+String(k)}
let counts=["ELEMENT":1,"PARSE":1,"MASS":1,"PERCENT":1,"EMPIRICAL":1,"DBE":1,"OXSTATE":1,"MOLES":2,"GRAMS":2,"MOLECULAR":2,"SALT":2,"HEAT":2,"COMBUST":3,"HEATS":0,"DERIVE":-2,"BALANCE":-1,"MATRIX":-1,"CHECK":-1,"DELTAH":-1,"REDOX":-3,"HALF":-3,"STOICH":-4,"LIMITING":-4,"YIELD":-4]
class Chemistry {
    var heats:Composition=[:]
    func execute(_ line:String)throws->[String] {let words=line.components(separatedBy:" "),cmd=words[0],a=Array(words.dropFirst()),n=a.count;guard let e=counts[cmd]else{return try fail("unknown command "+cmd)};if (e>=0 && n != e)||(e == -1 && n<1)||(e == -2 && (n<2 || n%2 != 0))||(e == -3 && n<2){return try fail("wrong argument count for "+cmd)}
        if cmd=="ELEMENT"{guard let w=W[a[0]]else{return try fail("unknown element "+a[0])};return ["\(a[0]) (Z = \(symbols.firstIndex(of:a[0])! + 1)) \(dec(w,3)) u"]}
        if cmd=="HEATS"{return heats.isEmpty ? ["no enthalpies"]:heats.keys.sorted().map{"\($0) \(ent(heats[$0]!)) kJ/mol"}}
        if cmd=="HEAT"{_ = try species(a[0]);let h=try enthalpy(a[1]);let text="dHf(\(a[0])) = \(ent(h)) kJ/mol"+(heats[a[0]] == nil ? "":" (was \(ent(heats[a[0]]!)))");heats[a[0]]=h;return [text]}
        if cmd=="DERIVE"{var b:Composition=[:];for i in stride(from:0,to:n,by:2){let s=a[i];if W[s]==nil{return try fail("unknown element "+s)};if b[s] != nil{return try fail("duplicate element "+s)};let q=try quantity(a[i+1]);if q>100000{return try fail("invalid percentage "+a[i+1])};b[s]=q};let t=b.values.reduce(0,+);if abs(t-100000)>1000{return try fail("percentages sum to "+dec(t,3))};return ratios(b)}
        if cmd=="COMBUST"{let qs=try a.map{try quantity($0)};let sample=qs[0],c=qs[1]*12011/44009,h=qs[2]*2016/18015,o=sample-c-h;if c==0 || h==0 || 100*o < -sample{return try fail("inconsistent masses")};var b=["C":c,"H":h];if 100*o>sample{b["O"]=o};return order(b).map{"mass \($0) \(dec(b[$0]!,3)) g"}+ratios(b)}
        if ["PARSE","MASS","PERCENT","EMPIRICAL","DBE","OXSTATE","MOLES","GRAMS","MOLECULAR","SALT"].contains(cmd){let f=try formula(a[0]);let c=f.c,q=f.q,m=f.molarMass,es=order(c)
            if cmd=="PARSE"{return ["\(hill(c,q)) (\(es.map{"\($0) \(c[$0]!)"}.joined(separator:", ")); charge \(signed(q)))"]}
            if cmd=="MASS"{return ["M(\(a[0])) = \(dec(m,3)) g/mol"]}
            if cmd=="PERCENT"{return es.map{"\($0) \(dec(10000*c[$0]! * W[$0]! / m,2))%"}}
            if cmd=="EMPIRICAL"{let g=c.values.reduce(0,gcd);return ["\(hill(c.mapValues{$0/g})) (n = \(g))"]}
            if cmd=="DBE"{if q != 0{return try fail("charged formula "+a[0])};var t=2;for s in es{guard let v=valence[s]else{return try fail("no valence for "+s)};t+=c[s]! * (v-2)};return ["DBE = \(t<0 ? "-":"")\(abs(t)/2).\(t%2 != 0 ? 5:0)"]}
            if cmd=="OXSTATE"{var st:[String:Fraction]=[:];var last="";func assign(_ e:String,_ n:Int){st[e]=Fraction(n);last=e};if es.count==1{st[es[0]]=Fraction(q,c[es[0]]!)}else{if c["F"] != nil{assign("F",-1)};for s in es{if let x=metals[s]{assign(s,x)}};if c["H"] != nil{assign("H",es.allSatisfy{$0=="H" || metals[$0] != nil} ? -1:1)};if c["O"] != nil{assign("O",-2)}else if c["F"]==nil{for s in ["Cl","Br","I"] where c[s] != nil{assign(s,-1);break}};let u=es.filter{st[$0]==nil};if u.count>1{return ["indeterminate: "+u.joined(separator:" ")]};let total=st.reduce(0){$0+c[$1.key]! * $1.value.n};if !u.isEmpty{st[u[0]]=Fraction(q-total,c[u[0]]!)}else if total != q{st[last]=Fraction(q-total+c[last]! * st[last]!.n,c[last]!)}};return [es.map{"\($0) \(st[$0]!)"}.joined(separator:", ")]}
            if cmd=="SALT"{let b=try formula(a[1]);if q<=0{return try fail("not a cation "+a[0])};if b.q>=0{return try fail("not an anion "+a[1])};for s in a where s.contains("."){return try fail("hydrate ion "+s)};let g=gcd(q,b.q),x = -b.q/g,y=q/g,z=add(scale(c,x),b.c,y);return ["\(group(a[0],x))\(group(a[1],y)) (\(hill(z)), \(dec(mass(z),3)) g/mol)"]}
            if cmd=="MOLECULAR" && q != 0{return try fail("charged formula "+a[0])};let x=try quantity(a[1]);if cmd=="MOLES"{return ["\(dec(x,3)) g \(a[0]) = \(dec(x*1000000/m,6)) mol"]};if cmd=="GRAMS"{return ["\(dec(x,3)) mol \(a[0]) = \(dec(x*m/1000,3)) g"]};let k=(2*x+m)/(2*m);return k==0 || 10*abs(x-k*m)>m ? ["no integer multiple (ratio \(dec(1000*x/m,3)))"]:["\(hill(scale(c,k))) (n = \(k), \(dec(k*m,3)) g/mol)"]
        }
        if cmd=="REDOX" || cmd=="HALF"{if !["acidic","basic"].contains(a[0]){return try fail("invalid medium "+a[0])};let eq=try equation(Array(a.dropFirst()));for s in eq.list where ["H^+","OH^-","H2O"].contains(s.f){return try fail("reserved species "+s.name)};var aux=[try species(a[0]=="acidic" ? "H^+":"OH^-"),try species("H2O")];if cmd=="HALF"{aux.append(Species(f:"e^-",state:"",coefficient:1,formula:Formula(c:[:],q:-1)))};let list=eq.list+aux,v=try coefficients(list,eq.signs+Array(repeating:1,count:aux.count),eq.list.count);var left:[String]=[],right:[String]=[];for i in eq.list.indices{if i<eq.r{left.append(term(list[i].name,v[i]))}else{right.append(term(list[i].name,v[i]))}};for i in eq.list.count..<list.count{if v[i]>0{left.append(term(list[i].name,v[i]))}else if v[i]<0{right.append(term(list[i].name,-v[i]))}};var out=[left.joined(separator:" + ")+" -> "+right.joined(separator:" + ")];if cmd=="HALF"{out.append(v.last! > 0 ? "reduction":v.last! < 0 ? "oxidation":"no electron transfer")};return out}
        var eqWords=a,rest:[String]=[];if ["STOICH","LIMITING","YIELD"].contains(cmd){if a.filter({$0==":"}).count != 1{return try fail("invalid separator")};let i=a.firstIndex(of:":")!;eqWords=Array(a.prefix(i));rest=Array(a.dropFirst(i+1));if (cmd=="STOICH" && rest.count != 2)||(cmd=="YIELD" && rest.count != 4){return try fail("wrong argument count for "+cmd)}}
        let eq=try equation(eqWords,cmd=="CHECK");let list=eq.list,r=eq.r
        if cmd=="MATRIX"{let(labels,rows)=matrix(list,eq.signs);let(rank,basis)=nullspace(rows,list.count);return ["columns: "+list.map{$0.name}.joined(separator:" ")]+rows.enumerated().map{"\(labels[$0.offset]): "+$0.element.map{String($0)}.joined(separator:" ")}+["rank \(rank), nullity \(basis.count)"]+basis.map{"null: "+$0.map{String($0)}.joined(separator:" ")}}
        if cmd=="CHECK"{let(labels,rows)=matrix(list,eq.signs);var diff:[String]=[];for(i,row)in rows.enumerated(){let l=(0..<r).reduce(0){$0+row[$1]*list[$1].coefficient},rr = -(r..<list.count).reduce(0){$0+row[$1]*list[$1].coefficient};if l != rr{diff.append("\(labels[i]): \(labels[i]=="charge" ? signed(l):String(l)) != \(labels[i]=="charge" ? signed(rr):String(rr))")}};if !diff.isEmpty{return ["not balanced"]+diff};let g=list.map{$0.coefficient}.reduce(0,gcd);return [g==1 ? "balanced":"balanced, not in lowest terms (gcd \(g))"]}
        var target = -1,product = -1;var qs:[Int]=[];if cmd=="DELTAH"{for s in list where heats[s.name]==nil{return try fail("no enthalpy for "+s.name)}}
        if cmd=="STOICH"{target=list.firstIndex{$0.name==rest[0]} ?? -1;if target<0{return try fail("species \(rest[0]) not in equation")};qs=[try quantity(rest[1])]}
        if cmd=="LIMITING"{if rest.count != r{return try fail("expected \(r) masses, got \(rest.count)")};qs=try rest.map{try quantity($0)}}
        if cmd=="YIELD"{target=(0..<r).first{list[$0].name==rest[0]} ?? -1;if target<0{return try fail(rest[0]+" is not a reactant")};product=(r..<list.count).first{list[$0].name==rest[2]} ?? -1;if product<0{return try fail(rest[2]+" is not a product")};qs=[try quantity(rest[1]),try quantity(rest[3])]}
        let v=try coefficients(list,eq.signs);var out=[notation(eq,v)];if cmd=="BALANCE"{return out}
        if cmd=="DELTAH"{let h=list.indices.reduce(0){$0-eq.signs[$1]*v[$1]*heats[list[$1].name]!};return out+["dH = \(ent(h)) kJ (\(h<0 ? "exothermic":h>0 ? "endothermic":"thermoneutral"))"]}
        if cmd=="STOICH"{let d=v[target]*list[target].molarMass;return out+list.enumerated().map{i,s in "\(s.name) \(dec(qs[0]*v[i]*1000000/d,6)) mol \(dec(qs[0]*v[i]*s.molarMass/d,3)) g"+gas(s,qs[0]*v[i],d)}}
        if cmd=="YIELD"{let t=qs[0]*v[product]*list[product].molarMass/(v[target]*list[target].molarMass);return out+["theoretical \(dec(t,3)) g","actual \(dec(qs[1],3)) g",t==0 ? "yield undefined":"yield \(dec(qs[1]*10000/t,2))%"]}
        var l=0;for i in 1..<r where qs[i]*v[l]*list[l].molarMass<qs[l]*v[i]*list[i].molarMass{l=i};let d=v[l]*list[l].molarMass;out += ["limiting "+list[l].name,"extent \(dec(qs[l]*1000000/d,6)) mol"];for i in r..<list.count{out.append("product \(list[i].name) \(dec(qs[l]*v[i]*list[i].molarMass/d,3)) g"+gas(list[i],qs[l]*v[i],d))};for i in 0..<r where i != l{out.append("remaining \(list[i].name) \(dec((qs[i]*d-qs[l]*v[i]*list[i].molarMass)/d,3)) g")};return out
    }
}
let n=Int(readLine()!)!,engine=Chemistry()
for _ in 0..<n{let line=readLine()!;do{for s in try engine.execute(line){print(s)}}catch ChemError.message(let s){print(s)}catch{fatalError("unexpected error")}}
