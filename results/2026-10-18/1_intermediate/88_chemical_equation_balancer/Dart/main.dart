import 'dart:io';
typedef Composition = Map<String, int>;
final symbols='H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe'.split(' ');
const weights=[1008,4003,6941,9012,10811,12011,14007,15999,18998,20180,22990,24305,26982,28086,30974,32065,35453,39948,39098,40078,44956,47867,50942,51996,54938,55845,58933,58693,63546,65380,69723,72630,74922,78971,79904,83798,85468,87620,88906,91224,92906,95950,98000,101070,102906,106420,107868,112414,114818,118710,121760,127600,126904,131293];
final W={
    for(var i=0;i<symbols.length;i++)symbols[i]:weights[i]
};
const valence={
    'H':1,'F':1,'Cl':1,'Br':1,'I':1,'O':2,'S':2,'Se':2,'B':3,'N':3,'P':3,'As':3,'C':4,'Si':4,'Ge':4
};
const metals={
    'Li':1,'Na':1,'K':1,'Rb':1,'Be':2,'Mg':2,'Ca':2,'Sr':2,'Al':3
};
class ChemError implements Exception {
    final String message;
    ChemError(this.message);
}
Never fail(String s)=>throw ChemError('error: $s');
int gcd(int a,int b){
    a=a.abs();
    b=b.abs();
    while(b!=0){
        var t=a%b;
        a=b;
        b=t;
    }
    return a;
}
String dec(int n,int d){
    var p=1;
    for(var i=0;i<d;i++)p*=10;
    return '${n~/p}.${(n%p).toString().padLeft(d,'0')}';
}
String ent(int n)=>'${n<0?'-':''}${dec(n.abs(),2)}';
String signed(int n)=>'${n>0?'+':''}$n';
class Fraction {
    late final int n,d;
    Fraction(int a,[int b=1]){
        var g=gcd(a,b);
        n=a~/g*(b<0?-1:1);
        d=b.abs()~/g;
    }
    Fraction operator -(Fraction b)=>Fraction(n*b.d-b.n*d,d*b.d);
    Fraction operator *(Fraction b)=>Fraction(n*b.n,d*b.d);
    Fraction operator /(Fraction b)=>Fraction(n*b.d,d*b.n);
    @override String toString()=>signed(n)+(d==1?'':'/$d');
}
List<String> order(Composition c){
    var es=c.keys.toList()..sort();
    return c.containsKey('C')?['C',if(c.containsKey('H'))'H',...es.where((e)=>e!='C'&&e!='H')]:es;
}
Composition add(Composition a,Composition b,[int k=1]){
    b.forEach((e,n)=>a[e]=(a[e]??0)+n*k);
    return a;
}
Composition scale(Composition c,int k)=>c.map((e,n)=>MapEntry(e,n*k));
int mass(Composition c)=>c.entries.fold(0,(sum,e)=>sum+e.value*W[e.key]!);
String hill(Composition c,[int q=0])=>order(c).map((e)=>e+(c[e]==1?'':'${c[e]}')).join()+(q==0?'':'^${q.abs()==1?'':q.abs()}${q>0?'+':'-'}');
class Formula {
    final Composition c;
    final int q;
    Formula(this.c,this.q);
    int get m=>mass(c);
}
class Species {
    final String f,state;
    final int coefficient;
    final Formula formula;
    Species(this.f,this.state,this.coefficient,this.formula);
    String get name=>f+state;
    int get m=>formula.m;
}
class Equation {
    final List<Species> list;
    final int r;
    Equation(this.list,this.r);
    List<int> get signs=>List.generate(list.length,(i)=>i<r?1:-1);
}
class Parser {
    final String text;
    int p=0;
    final seen=<String>[];
    Parser(this.text);
    String peek()=>p<text.length?text[p]:'';
    int number(){
        var start=p;
        while(RegExp(r'^[0-9]$').hasMatch(peek()))p++;
        if(start==p)return 1;
        if(text[start]=='0')throw const FormatException();
        return int.parse(text.substring(start,p));
    }
    Composition sequence(){
        var c=<String,int>{
        };
        var items=0;
        while(true){
            var ch=peek();
            Composition item;
            if(RegExp(r'^[A-Z]$').hasMatch(ch)){
                var e=text[p++];
                if(RegExp(r'^[a-z]$').hasMatch(peek()))e+=text[p++];
                seen.add(e);
                item={
                    e:1
                };
            }else if(ch=='('||ch=='['){
                p++;
                item=sequence();
                if(peek()!=(ch=='('?')':']'))throw const FormatException();
                p++;
            }else break;
            add(c,item,number());
            items++;
        }
        if(items==0)throw const FormatException();
        return c;
    }
    Formula parse(){
        var c=sequence();
        while(peek()=='.'){
            p++;
            var k=number();
            add(c,sequence(),k);
        }
        var q=0;
        if(peek()=='^'){
            p++;
            var k=number();
            var ch=peek();
            if(ch!='+'&&ch!='-')throw const FormatException();
            p++;
            q=ch=='+'?k:-k;
        }
        if(p!=text.length)throw const FormatException();
        return Formula(c,q);
    }
}
Formula formula(String text,[String? word]){
    var p=Parser(text);
    late Formula f;
    try{
        f=p.parse();
    }
    on FormatException{
        fail('invalid formula ${word??text}');
    }
    for(var e in p.seen){
        if(!W.containsKey(e))fail('unknown element $e');
    }
    return f;
}
Species species(String word,[bool check=false]){
    var state='';
    var f=word;
    var k=1;
    for(var s in ['(s)','(l)','(g)','(aq)']){
        if(word.endsWith(s)){
            state=s;
            f=word.substring(0,word.length-s.length);
            break;
        }
    }
    if(check){
        var m=RegExp(r'^[0-9]+').firstMatch(f);
        if(m!=null){
            if(f[0]=='0')fail('invalid formula $word');
            k=int.parse(m[0]!);
            f=f.substring(m.end);
        }
    }
    return Species(f,state,k,formula(f,word));
}
Equation equation(List<String> a,[bool check=false]){
    var valid=a.length.isOdd;
    var arrow=-1;
    for(var i=0;i<a.length;i++){
        var op=a[i]=='+'||a[i]=='->';
        if(i.isOdd){
            if(!op)valid=false;
            if(a[i]=='->'){
                if(arrow>=0)valid=false;
                arrow=i;
            }
        }else if(op)valid=false;
    }
    if(!valid||arrow<0)fail('malformed equation');
    return Equation([for(var i=0;i<a.length;i+=2)species(a[i],check)],(arrow+1)~/2);
}
int quantity(String s){
    if(!RegExp(r'^(0|[1-9][0-9]{0,3})(\.[0-9]{1,3})?$').hasMatch(s))fail('invalid quantity $s');
    var p=s.split('.');
    var q=int.parse(p[0])*1000+(p.length==1?0:int.parse(p[1].padRight(3,'0')));
    if(q==0)fail('invalid quantity $s');
    return q;
}
int enthalpy(String s){
    if(!RegExp(r'^-?(0|[1-9][0-9]{0,4})(\.[0-9]{1,2})?$').hasMatch(s))fail('invalid enthalpy $s');
    var p=s.replaceFirst('-','').split('.');
    return (s[0]=='-'?-1:1)*(int.parse(p[0])*100+(p.length==1?0:int.parse(p[1].padRight(2,'0'))));
}
(List<String>,List<List<int>>) matrix(List<Species> list,List<int> signs){
    var all=<String,int>{
    };
    for(var s in list)add(all,s.formula.c);
    var labels=[...order(all),'charge'];
    return(labels,[for(var e in labels)[for(var i=0;i<list.length;i++)signs[i]*(e=='charge'?list[i].formula.q:list[i].formula.c[e]??0)]]);
}
(int,List<List<int>>) nullspace(List<List<int>> rows,int n){
    var a=rows.map((r)=>r.map((x)=>Fraction(x)).toList()).toList();
    var piv=<int>[];
    var free=<int>[];
    for(var j=0;j<n;j++){
        var r=piv.length;
        var i=r;
        while(i<a.length&&a[i][j].n==0)i++;
        if(i==a.length){
            free.add(j);
            continue;
        }
        var row=a[r];
        a[r]=a[i];
        a[i]=row;
        var t=a[r][j];
        a[r]=a[r].map((x)=>x/t).toList();
        for(var k=0;k<a.length;k++){
            if(k!=r&&a[k][j].n!=0){
                var f=a[k][j];
                for(var z=0;z<n;z++)a[k][z]=a[k][z]-f*a[r][z];
            }
        }
        piv.add(j);
    }
    var basis=<List<int>>[];
    for(var f in free){
        var v=List.generate(n,(_)=>Fraction(0));
        v[f]=Fraction(1);
        for(var i=0;i<piv.length;i++)v[piv[i]]=Fraction(-a[i][f].n,a[i][f].d);
        var l=1;
        for(var x in v)l=l~/gcd(l,x.d)*x.d;
        var b=v.map((x)=>x.n*(l~/x.d)).toList();
        var g=0;
        for(var x in b)g=gcd(g,x);
        basis.add(b.map((x)=>x~/g).toList());
    }
    return(piv.length,basis);
}
List<int> coefficients(List<Species> list,List<int> signs,[int? required]){
    var (_,rows)=matrix(list,signs);
    var (_,basis)=nullspace(rows,list.length);
    var d=basis.length;
    if(d>=2)throw ChemError('AMBIGUOUS (nullity $d)');
    if(d==0)throw ChemError('IMPOSSIBLE');
    var v=basis[0];
    if(v[0]<0)v=v.map((x)=>-x).toList();
    if(v.take(required??list.length).any((x)=>x<=0))throw ChemError('IMPOSSIBLE');
    return v;
}
String term(String s,int k)=>(k==1?'':'$k')+s;
String notation(Equation eq,List<int> v){
    var t=[for(var i=0;i<eq.list.length;i++)term(eq.list[i].name,v[i])];
    return t.take(eq.r).join(' + ')+' -> '+t.skip(eq.r).join(' + ');
}
String gas(Species s,int n,int d)=>s.state=='(g)'?' ${dec(n*22414~/d,3)} L':'';
List<String> ratios(Composition a){
    var es=order(a);
    var f=es[0];
    for(var e in es){
        if(a[e]!*W[f]!<a[f]!*W[e]!)f=e;
    }
    var out=[for(var e in es)'$e ${dec(1000*a[e]!*W[f]!~/(W[e]!*a[f]!),3)}'];
    for(var k=1;k<=12;k++){
        var c=<String,int>{
        };
        var ok=true;
        for(var e in es){
            var n=k*a[e]!*W[f]!;
            var d=W[e]!*a[f]!;
            var i=(2*n+d)~/(2*d);
            c[e]=i;
            if(20*(n-i*d).abs()>d)ok=false;
        }
        if(ok)return [...out,'${hill(c)} (k = $k)'];
    }
    return [...out,'no simple ratio'];
}
String group(String f,int k){
    var c=f.split('^')[0];
    if(k==1)return c;
    var depth=0;
    var last=-1;
    if(c[0]=='['){
        for(var i=0;i<c.length;i++){
            if(c[i]=='[')depth++;
            if(c[i]==']'&&--depth==0){
                last=i;
                break;
            }
        }
    }
    return (RegExp(r'^[A-Z][a-z]?$').hasMatch(c)||last==c.length-1?c:'($c)')+'$k';
}
const counts={
    'ELEMENT':1,'PARSE':1,'MASS':1,'PERCENT':1,'EMPIRICAL':1,'DBE':1,'OXSTATE':1,'MOLES':2,'GRAMS':2,'MOLECULAR':2,'SALT':2,'HEAT':2,'COMBUST':3,'HEATS':0,'DERIVE':-2,'BALANCE':-1,'MATRIX':-1,'CHECK':-1,'DELTAH':-1,'REDOX':-3,'HALF':-3,'STOICH':-4,'LIMITING':-4,'YIELD':-4
};
class Chemistry {
    final heats=<String,int>{
    };
    List<String> execute(String line){
        var all=line.split(' ');
        var cmd=all[0];
        var a=all.sublist(1);
        var n=a.length;
        if(!counts.containsKey(cmd))fail('unknown command $cmd');
        var e=counts[cmd]!;
        if((e>=0&&n!=e)||(e==-1&&n<1)||(e==-2&&(n<2||n.isOdd))||(e==-3&&n<2))fail('wrong argument count for $cmd');
        if(cmd=='ELEMENT'){
            if(!W.containsKey(a[0]))fail('unknown element ${a[0]}');
            return ['${a[0]} (Z = ${symbols.indexOf(a[0])+1}) ${dec(W[a[0]]!,3)} u'];
        }
        if(cmd=='HEATS'){
            var keys=heats.keys.toList()..sort();
            return keys.isEmpty?['no enthalpies']:[for(var s in keys)'$s ${ent(heats[s]!)} kJ/mol'];
        }
        if(cmd=='HEAT'){
            species(a[0]);
            var h=enthalpy(a[1]);
            var s='dHf(${a[0]}) = ${ent(h)} kJ/mol'+(heats.containsKey(a[0])?' (was ${ent(heats[a[0]]!)})':'');
            heats[a[0]]=h;
            return [s];
        }
        if(cmd=='DERIVE'){
            var b=<String,int>{
            };
            for(var i=0;i<n;i+=2){
                var s=a[i];
                if(!W.containsKey(s))fail('unknown element $s');
                if(b.containsKey(s))fail('duplicate element $s');
                var q=quantity(a[i+1]);
                if(q>100000)fail('invalid percentage ${a[i+1]}');
                b[s]=q;
            }
            var t=b.values.fold(0,(x,y)=>x+y);
            if((t-100000).abs()>1000)fail('percentages sum to ${dec(t,3)}');
            return ratios(b);
        }
        if(cmd=='COMBUST'){
            var qs=a.map(quantity).toList();
            var sample=qs[0];
            var c=qs[1]*12011~/44009;
            var h=qs[2]*2016~/18015;
            var o=sample-c-h;
            if(c==0||h==0||100*o < -sample)fail('inconsistent masses');
            var b={
                'C':c,'H':h
            };
            if(100*o>sample)b['O']=o;
            return [for(var e in order(b))'mass $e ${dec(b[e]!,3)} g',...ratios(b)];
        }
        if(['PARSE','MASS','PERCENT','EMPIRICAL','DBE','OXSTATE','MOLES','GRAMS','MOLECULAR','SALT'].contains(cmd)){
            var f=formula(a[0]);
            var c=f.c;
            var q=f.q;
            var m=f.m;
            var es=order(c);
            if(cmd=='PARSE')return ['${hill(c,q)} (${es.map((e)=>'$e ${c[e]}').join(', ')}; charge ${signed(q)})'];
            if(cmd=='MASS')return ['M(${a[0]}) = ${dec(m,3)} g/mol'];
            if(cmd=='PERCENT')return [for(var e in es)'$e ${dec(10000*c[e]!*W[e]!~/m,2)}%'];
            if(cmd=='EMPIRICAL'){
                var g=c.values.fold(0,gcd);
                return ['${hill(c.map((e,x)=>MapEntry(e,x~/g)))} (n = $g)'];
            }
            if(cmd=='DBE'){
                if(q!=0)fail('charged formula ${a[0]}');
                var t=2;
                for(var e in es){
                    if(!valence.containsKey(e))fail('no valence for $e');
                    t+=c[e]!*(valence[e]!-2);
                }
                return ['DBE = ${t<0?'-':''}${t.abs()~/2}.${t.isOdd?5:0}'];
            }
            if(cmd=='OXSTATE'){
                var st=<String,Fraction>{
                };
                var last='';
                void assign(String e,int x){
                    st[e]=Fraction(x);
                    last=e;
                }
                if(es.length==1){
                    st[es[0]]=Fraction(q,c[es[0]]!);
                }else{
                    if(c.containsKey('F'))assign('F',-1);
                    for(var e in es){
                        if(metals.containsKey(e))assign(e,metals[e]!);
                    }
                    if(c.containsKey('H'))assign('H',es.every((e)=>e=='H'||metals.containsKey(e))?-1:1);
                    if(c.containsKey('O'))assign('O',-2);
                    else if(!c.containsKey('F')){
                        for(var e in ['Cl','Br','I']){
                            if(c.containsKey(e)){
                                assign(e,-1);
                                break;
                            }
                        }
                    }
                    var u=es.where((e)=>!st.containsKey(e)).toList();
                    if(u.length>1)return ['indeterminate: ${u.join(' ')}'];
                    var sum=st.entries.fold(0,(s,e)=>s+c[e.key]!*e.value.n);
                    if(u.isNotEmpty)st[u[0]]=Fraction(q-sum,c[u[0]]!);
                    else if(sum!=q)st[last]=Fraction(q-sum+c[last]!*st[last]!.n,c[last]!);
                }
                return [es.map((e)=>'$e ${st[e]}').join(', ')];
            }
            if(cmd=='SALT'){
                var b=formula(a[1]);
                if(q<=0)fail('not a cation ${a[0]}');
                if(b.q>=0)fail('not an anion ${a[1]}');
                for(var s in a){
                    if(s.contains('.'))fail('hydrate ion $s');
                }
                var g=gcd(q,b.q);
                var x=-b.q~/g;
                var y=q~/g;
                var z=add(scale(c,x),b.c,y);
                return ['${group(a[0],x)}${group(a[1],y)} (${hill(z)}, ${dec(mass(z),3)} g/mol)'];
            }
            if(cmd=='MOLECULAR'&&q!=0)fail('charged formula ${a[0]}');
            var x=quantity(a[1]);
            if(cmd=='MOLES')return ['${dec(x,3)} g ${a[0]} = ${dec(x*1000000~/m,6)} mol'];
            if(cmd=='GRAMS')return ['${dec(x,3)} mol ${a[0]} = ${dec(x*m~/1000,3)} g'];
            var k=(2*x+m)~/(2*m);
            return k==0||10*(x-k*m).abs()>m?['no integer multiple (ratio ${dec(1000*x~/m,3)})']:['${hill(scale(c,k))} (n = $k, ${dec(k*m,3)} g/mol)'];
        }
        if(cmd=='REDOX'||cmd=='HALF'){
            if(!['acidic','basic'].contains(a[0]))fail('invalid medium ${a[0]}');
            var eq=equation(a.sublist(1));
            for(var s in eq.list){
                if(['H^+','OH^-','H2O'].contains(s.f))fail('reserved species ${s.name}');
            }
            var aux=[species(a[0]=='acidic'?'H^+':'OH^-'),species('H2O')];
            if(cmd=='HALF')aux.add(Species('e^-','',1,Formula({
            },-1)));
            var list=[...eq.list,...aux];
            var v=coefficients(list,[...eq.signs,...List.filled(aux.length,1)],eq.list.length);
            var left=<String>[];
            var right=<String>[];
            for(var i=0;i<eq.list.length;i++)(i<eq.r?left:right).add(term(list[i].name,v[i]));
            for(var i=eq.list.length;i<list.length;i++){
                if(v[i]!=0)(v[i]>0?left:right).add(term(list[i].name,v[i].abs()));
            }
            return ['${left.join(' + ')} -> ${right.join(' + ')}',if(cmd=='HALF')v.last>0?'reduction':v.last<0?'oxidation':'no electron transfer'];
        }
        var words=a;
        var rest=<String>[];
        if(['STOICH','LIMITING','YIELD'].contains(cmd)){
            if(a.where((s)=>s==':').length!=1)fail('invalid separator');
            var i=a.indexOf(':');
            words=a.sublist(0,i);
            rest=a.sublist(i+1);
            if((cmd=='STOICH'&&rest.length!=2)||(cmd=='YIELD'&&rest.length!=4))fail('wrong argument count for $cmd');
        }
        var eq=equation(words,cmd=='CHECK');
        var list=eq.list;
        var r=eq.r;
        if(cmd=='MATRIX'){
            var (labels,rows)=matrix(list,eq.signs);
            var (rank,basis)=nullspace(rows,list.length);
            return ['columns: ${list.map((s)=>s.name).join(' ')}',for(var i=0;i<rows.length;i++)'${labels[i]}: ${rows[i].join(' ')}','rank $rank, nullity ${basis.length}',for(var v in basis)'null: ${v.join(' ')}'];
        }
        if(cmd=='CHECK'){
            var (labels,rows)=matrix(list,eq.signs);
            var diff=<String>[];
            for(var i=0;i<rows.length;i++){
                var l=0;
                var rr=0;
                for(var j=0;j<list.length;j++){
                    if(j<r)l+=rows[i][j]*list[j].coefficient;
                    else rr-=rows[i][j]*list[j].coefficient;
                }
                if(l!=rr)diff.add('${labels[i]}: ${labels[i]=='charge'?signed(l):l} != ${labels[i]=='charge'?signed(rr):rr}');
            }
            if(diff.isNotEmpty)return ['not balanced',...diff];
            var g=list.map((s)=>s.coefficient).fold(0,gcd);
            return [g==1?'balanced':'balanced, not in lowest terms (gcd $g)'];
        }
        var target=-1;
        var product=-1;
        var qs=<int>[];
        if(cmd=='DELTAH'){
            for(var s in list){
                if(!heats.containsKey(s.name))fail('no enthalpy for ${s.name}');
            }
        }
        if(cmd=='STOICH'){
            target=list.indexWhere((s)=>s.name==rest[0]);
            if(target<0)fail('species ${rest[0]} not in equation');
            qs=[quantity(rest[1])];
        }
        if(cmd=='LIMITING'){
            if(rest.length!=r)fail('expected $r masses, got ${rest.length}');
            qs=rest.map(quantity).toList();
        }
        if(cmd=='YIELD'){
            target=list.take(r).toList().indexWhere((s)=>s.name==rest[0]);
            if(target<0)fail('${rest[0]} is not a reactant');
            product=list.indexWhere((s)=>s.name==rest[2],r);
            if(product<0)fail('${rest[2]} is not a product');
            qs=[quantity(rest[1]),quantity(rest[3])];
        }
        var v=coefficients(list,eq.signs);
        var out=[notation(eq,v)];
        if(cmd=='BALANCE')return out;
        if(cmd=='DELTAH'){
            var h=0;
            for(var i=0;i<list.length;i++)h-=eq.signs[i]*v[i]*heats[list[i].name]!;
            return [...out,'dH = ${ent(h)} kJ (${h<0?'exothermic':h>0?'endothermic':'thermoneutral'})'];
        }
        if(cmd=='STOICH'){
            var d=v[target]*list[target].m;
            return [...out,for(var i=0;i<list.length;i++)'${list[i].name} ${dec(qs[0]*v[i]*1000000~/d,6)} mol ${dec(qs[0]*v[i]*list[i].m~/d,3)} g${gas(list[i],qs[0]*v[i],d)}'];
        }
        if(cmd=='YIELD'){
            var t=qs[0]*v[product]*list[product].m~/(v[target]*list[target].m);
            return [...out,'theoretical ${dec(t,3)} g','actual ${dec(qs[1],3)} g',t==0?'yield undefined':'yield ${dec(qs[1]*10000~/t,2)}%'];
        }
        var l=0;
        for(var i=1;i<r;i++){
            if(qs[i]*v[l]*list[l].m<qs[l]*v[i]*list[i].m)l=i;
        }
        var d=v[l]*list[l].m;
        out.addAll(['limiting ${list[l].name}','extent ${dec(qs[l]*1000000~/d,6)} mol']);
        for(var i=r;i<list.length;i++)out.add('product ${list[i].name} ${dec(qs[l]*v[i]*list[i].m~/d,3)} g${gas(list[i],qs[l]*v[i],d)}');
        for(var i=0;i<r;i++){
            if(i!=l)out.add('remaining ${list[i].name} ${dec((qs[i]*d-qs[l]*v[i]*list[i].m)~/d,3)} g');
        }
        return out;
    }
}
void main(){
    var engine=Chemistry();
    var n=int.parse(stdin.readLineSync()!);
    for(var i=0;i<n;i++){
        var line=stdin.readLineSync()!;
        try{
            for(var s in engine.execute(line))stdout.writeln(s);
        }
        on ChemError catch(e){
            stdout.writeln(e.message);
        }
    }
}
