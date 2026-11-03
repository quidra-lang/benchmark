import kotlin.math.abs
typealias Composition = Map<String, Long>
val symbols="H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe".split(" ")
val weights=longArrayOf(1008,4003,6941,9012,10811,12011,14007,15999,18998,20180,22990,24305,26982,28086,30974,32065,35453,39948,39098,40078,44956,47867,50942,51996,54938,55845,58933,58693,63546,65380,69723,72630,74922,78971,79904,83798,85468,87620,88906,91224,92906,95950,98000,101070,102906,106420,107868,112414,114818,118710,121760,127600,126904,131293)
val W=symbols.zip(weights.toList()).toMap()
val valence=listOf("H F Cl Br I","O S Se","B N P As","C Si Ge").flatMapIndexed {
    i,s->s.split(" ").map {
        it to (i+1).toLong()
    }
}.toMap()
val metals=mapOf("Li" to 1L,"Na" to 1L,"K" to 1L,"Rb" to 1L,"Be" to 2L,"Mg" to 2L,"Ca" to 2L,"Sr" to 2L,"Al" to 3L)
class ChemError(message:String):RuntimeException(message)
fun fail(s:String):Nothing=throw ChemError("error: $s")
fun gcd(a:Long,b:Long):Long {
    var x=abs(a);
    var y=abs(b);
    while(y!=0L){
        val t=x%y;
        x=y;
        y=t
    };
    return x
}
fun dec(n:Long,d:Int):String {
    var p=1L;
    repeat(d){
        p*=10
    };
    return "${n/p}.${(n%p).toString().padStart(d,'0')}"
}
fun ent(n:Long)=(if(n<0)"-" else "")+dec(abs(n),2)
fun signed(n:Long)=(if(n>0)"+" else "")+n
class Fraction(n:Long,d:Long=1) {
    val n:Long;
    val d:Long
    init {
        val g=gcd(n,d);
        this.n=n/g*(if(d<0)-1 else 1);
        this.d=abs(d)/g
    }
    operator fun minus(b:Fraction)=Fraction(n*b.d-b.n*d,d*b.d)
    operator fun times(b:Fraction)=Fraction(n*b.n,d*b.d)
    operator fun div(b:Fraction)=Fraction(n*b.d,d*b.n)
    override fun toString()=signed(n)+(if(d==1L)"" else "/$d")
}
fun order(c:Composition):List<String>{
    val es=c.keys.sorted();
    return if("C" in c)listOf("C")+(if("H" in c)listOf("H")else emptyList())+es.filter {
        it!="C"&&it!="H"
    }else es
}
fun add(a:Composition,b:Composition,k:Long=1):Map<String,Long>{
    val c=a.toMutableMap();
    b.forEach{
        (e,n)->c[e]=c.getOrDefault(e,0)+n*k
    };
    return c
}
fun scale(c:Composition,k:Long)=c.mapValues{
    it.value*k
}
fun mass(c:Composition)=c.entries.sumOf{
    it.value*W.getValue(it.key)
}
fun hill(c:Composition,q:Long=0)=order(c).joinToString(""){
    it+(if(c[it]==1L)""else c.getValue(it).toString())
}+(if(q==0L)""else "^"+(if(abs(q)==1L)""else abs(q).toString())+(if(q>0)"+"else "-"))
data class Formula(val c:Composition,val q:Long){
    val mass get()=mass(c)
}
data class Species(val f:String,val state:String,val coefficient:Long,val formula:Formula){
    val name get()=f+state;
    val mass get()=formula.mass
}
data class Equation(val list:List<Species>,val r:Int){
    val signs get()=list.indices.map{
        if(it<r)1L else -1L
    }
}
class Parser(val text:String){
    var p=0;
    val seen=mutableListOf<String>()
    fun peek()=text.getOrNull(p)?:'\u0000'
    fun number():Long {
        val start=p;
        while(peek() in '0'..'9')p++;
        if(start==p)return 1;
        if(text[start]=='0')throw IllegalArgumentException();
        return text.substring(start,p).toLong()
    }
    fun sequence():Composition {
        var c:Composition=emptyMap();
        var items=0;
        while(true){
            val ch=peek();
            val item:Composition;
            if(ch in 'A'..'Z'){
                var e=text[p++].toString();
                if(peek() in 'a'..'z')e+=text[p++];
                seen+=e;
                item=mapOf(e to 1L)
            }else if(ch=='('||ch=='['){
                p++;
                item=sequence();
                if(peek()!=(if(ch=='(')')'else ']'))throw IllegalArgumentException();
                p++
            }else break;
            c=add(c,item,number());
            items++
        };
        if(items==0)throw IllegalArgumentException();
        return c
    }
    fun parse():Formula {
        var c=sequence();
        while(peek()=='.'){
            p++;
            val k=number();
            c=add(c,sequence(),k)
        };
        var q=0L;
        if(peek()=='^'){
            p++;
            val k=number();
            val ch=peek();
            if(ch!='+'&&ch!='-')throw IllegalArgumentException();
            p++;
            q=if(ch=='+')k else -k
        };
        if(p!=text.length)throw IllegalArgumentException();
        return Formula(c,q)
    }
}
fun formula(text:String,word:String=text):Formula {
    val p=Parser(text);
    val f=try{
        p.parse()
    }catch(e:IllegalArgumentException){
        fail("invalid formula $word")
    };
    for(e in p.seen)if(e !in W)fail("unknown element $e");
    return f
}
fun species(word:String,check:Boolean=false):Species {
    val state=listOf("(s)","(l)","(g)","(aq)").firstOrNull{
        word.endsWith(it)
    }?:"";
    var f=word.removeSuffix(state);
    var k=1L;
    if(check){
        val m=Regex("^[0-9]+").find(f);
        if(m!=null){
            if(f[0]=='0')fail("invalid formula $word");
            k=m.value.toLong();
            f=f.substring(m.value.length)
        }
    };
    return Species(f,state,k,formula(f,word))
}
fun equation(a:List<String>,check:Boolean=false):Equation {
    var valid=a.size%2==1;
    var arrow=-1;
    for(i in a.indices){
        val op=a[i]=="+"||a[i]=="->";
        if(i%2==1){
            if(!op)valid=false;
            if(a[i]=="->"){
                if(arrow>=0)valid=false;
                arrow=i
            }
        }else if(op)valid=false
    };
    if(!valid||arrow<0)fail("malformed equation");
    return Equation(a.filterIndexed{
        i,_->i%2==0
    }.map{
        species(it,check)
    },(arrow+1)/2)
}
fun quantity(s:String):Long {
    if(!Regex("(0|[1-9][0-9]{0,3})(\\.[0-9]{1,3})?").matches(s))fail("invalid quantity $s");
    val p=s.split('.');
    val q=p[0].toLong()*1000+(if(p.size==1)0 else p[1].padEnd(3,'0').toLong());
    if(q==0L)fail("invalid quantity $s");
    return q
}
fun enthalpy(s:String):Long {
    if(!Regex("-?(0|[1-9][0-9]{0,4})(\\.[0-9]{1,2})?").matches(s))fail("invalid enthalpy $s");
    val p=s.removePrefix("-").split('.');
    return (if(s[0]=='-')-1 else 1)*(p[0].toLong()*100+(if(p.size==1)0 else p[1].padEnd(2,'0').toLong()))
}
fun matrix(list:List<Species>,signs:List<Long>):Pair<List<String>,List<List<Long>>>{
    var all:Composition=emptyMap();
    for(s in list)all=add(all,s.formula.c);
    val labels=order(all)+"charge";
    return labels to labels.map{
        e->list.mapIndexed{
            i,s->signs[i]*(if(e=="charge")s.formula.q else s.formula.c.getOrDefault(e,0))
        }
    }
}
fun nullspace(rows:List<List<Long>>,n:Int):Pair<Int,List<List<Long>>>{
    val a=rows.map{
        r->r.map{
            Fraction(it)
        }.toMutableList()
    }.toMutableList();
    val piv=mutableListOf<Int>();
    val free=mutableListOf<Int>();
    for(j in 0 until n){
        val r=piv.size;
        val i=(r until a.size).firstOrNull{
            a[it][j].n!=0L
        };
        if(i==null){
            free+=j;
            continue
        };
        val tmp=a[r];
        a[r]=a[i];
        a[i]=tmp;
        val t=a[r][j];
        a[r]=a[r].map{
            it/t
        }.toMutableList();
        for(k in a.indices)if(k!=r&&a[k][j].n!=0L){
            val f=a[k][j];
            for(z in 0 until n)a[k][z]=a[k][z]-f*a[r][z]
        };
        piv+=j
    };
    val basis=free.map{
        f->val v=MutableList(n){
            Fraction(0)
        };
        v[f]=Fraction(1);
        piv.forEachIndexed{
            i,j->v[j]=Fraction(-a[i][f].n,a[i][f].d)
        };
        var l=1L;
        for(x in v)l=l/gcd(l,x.d)*x.d;
        val b=v.map{
            it.n*(l/it.d)
        };
        val g=b.fold(0L,::gcd);
        b.map{
            it/g
        }
    };
    return piv.size to basis
}
fun coefficients(list:List<Species>,signs:List<Long>,required:Int=list.size):List<Long>{
    val (_,basis)=nullspace(matrix(list,signs).second,list.size);
    val d=basis.size;
    if(d>=2)throw ChemError("AMBIGUOUS (nullity $d)");
    if(d==0)throw ChemError("IMPOSSIBLE");
    var v=basis[0];
    if(v[0]<0)v=v.map{
        -it
    };
    if(v.take(required).any{
        it<=0
    })throw ChemError("IMPOSSIBLE");
    return v
}
fun term(s:String,k:Long)=(if(k==1L)""else k.toString())+s
fun notation(eq:Equation,v:List<Long>):String {
    val t=eq.list.mapIndexed{
        i,s->term(s.name,v[i])
    };
    return t.take(eq.r).joinToString(" + ")+" -> "+t.drop(eq.r).joinToString(" + ")
}
fun gas(s:Species,n:Long,d:Long)=if(s.state=="(g)")" ${dec(n*22414/d,3)} L"else ""
fun ratios(a:Composition):List<String>{
    val es=order(a);
    var f=es[0];
    for(e in es)if(a.getValue(e)*W.getValue(f)<a.getValue(f)*W.getValue(e))f=e;
    val out=es.map{
        "$it ${dec(1000*a.getValue(it)*W.getValue(f)/(W.getValue(it)*a.getValue(f)),3)}"
    };
    for(k in 1L..12L){
        val c=mutableMapOf<String,Long>();
        var ok=true;
        for(e in es){
            val n=k*a.getValue(e)*W.getValue(f);
            val d=W.getValue(e)*a.getValue(f);
            val i=(2*n+d)/(2*d);
            c[e]=i;
            if(20*abs(n-i*d)>d)ok=false
        };
        if(ok)return out+"${hill(c)} (k = $k)"
    };
    return out+"no simple ratio"
}
fun group(f:String,k:Long):String {
    val c=f.substringBefore('^');
    if(k==1L)return c;
    var depth=0;
    var last=-1;
    if(c[0]=='[')for(i in c.indices){
        if(c[i]=='[')depth++;
        if(c[i]==']'&&--depth==0){
            last=i;
            break
        }
    };
    return (if(Regex("[A-Z][a-z]?").matches(c)||last==c.length-1)c else "($c)")+k
}
val counts=mapOf("ELEMENT" to 1,"PARSE" to 1,"MASS" to 1,"PERCENT" to 1,"EMPIRICAL" to 1,"DBE" to 1,"OXSTATE" to 1,"MOLES" to 2,"GRAMS" to 2,"MOLECULAR" to 2,"SALT" to 2,"HEAT" to 2,"COMBUST" to 3,"HEATS" to 0,"DERIVE" to -2,"BALANCE" to -1,"MATRIX" to -1,"CHECK" to -1,"DELTAH" to -1,"REDOX" to -3,"HALF" to -3,"STOICH" to -4,"LIMITING" to -4,"YIELD" to -4)
class Chemistry {
    val heats=mutableMapOf<String,Long>()
    fun execute(line:String):List<String>{
        val parts=line.split(' ');
        val cmd=parts[0];
        val a=parts.drop(1);
        val n=a.size;
        val expected=counts[cmd]?:fail("unknown command $cmd");
        if((expected>=0&&n!=expected)||(expected==-1&&n<1)||(expected==-2&&(n<2||n%2!=0))||(expected==-3&&n<2))fail("wrong argument count for $cmd")
        if(cmd=="ELEMENT"){
            if(a[0] !in W)fail("unknown element ${a[0]}");
            return listOf("${a[0]} (Z = ${symbols.indexOf(a[0])+1}) ${dec(W.getValue(a[0]),3)} u")
        }
        if(cmd=="HEATS")return if(heats.isEmpty())listOf("no enthalpies")else heats.keys.sorted().map{
            "$it ${ent(heats.getValue(it))} kJ/mol"
        }
        if(cmd=="HEAT"){
            species(a[0]);
            val h=enthalpy(a[1]);
            val s="dHf(${a[0]}) = ${ent(h)} kJ/mol"+(if(a[0] in heats)" (was ${ent(heats.getValue(a[0]))})"else "");
            heats[a[0]]=h;
            return listOf(s)
        }
        if(cmd=="DERIVE"){
            val b=mutableMapOf<String,Long>();
            for(i in a.indices step 2){
                val e=a[i];
                if(e !in W)fail("unknown element $e");
                if(e in b)fail("duplicate element $e");
                val q=quantity(a[i+1]);
                if(q>100000)fail("invalid percentage ${a[i+1]}");
                b[e]=q
            };
            val t=b.values.sum();
            if(abs(t-100000)>1000)fail("percentages sum to ${dec(t,3)}");
            return ratios(b)
        }
        if(cmd=="COMBUST"){
            val qs=a.map(::quantity);
            val sample=qs[0];
            val c=qs[1]*12011/44009;
            val h=qs[2]*2016/18015;
            val o=sample-c-h;
            if(c==0L||h==0L||100*o < -sample)fail("inconsistent masses");
            val b=mutableMapOf("C" to c,"H" to h);
            if(100*o>sample)b["O"]=o;
            return order(b).map{
                "mass $it ${dec(b.getValue(it),3)} g"
            }+ratios(b)
        }
        if(cmd in listOf("PARSE","MASS","PERCENT","EMPIRICAL","DBE","OXSTATE","MOLES","GRAMS","MOLECULAR","SALT")){
            val f=formula(a[0]);
            val c=f.c;
            val q=f.q;
            val m=f.mass;
            val es=order(c)
            if(cmd=="PARSE")return listOf("${hill(c,q)} (${es.joinToString(", "){"$it ${c.getValue(it)}"}}; charge ${signed(q)})")
            if(cmd=="MASS")return listOf("M(${a[0]}) = ${dec(m,3)} g/mol")
            if(cmd=="PERCENT")return es.map{
                "$it ${dec(10000*c.getValue(it)*W.getValue(it)/m,2)}%"
            }
            if(cmd=="EMPIRICAL"){
                val g=c.values.fold(0L,::gcd);
                return listOf("${hill(c.mapValues{it.value/g})} (n = $g)")
            }
            if(cmd=="DBE"){
                if(q!=0L)fail("charged formula ${a[0]}");
                var t=2L;
                for(e in es){
                    if(e !in valence)fail("no valence for $e");
                    t+=c.getValue(e)*(valence.getValue(e)-2)
                };
                return listOf("DBE = ${if(t<0)"-"else ""}${abs(t)/2}.${if(t%2!=0L)5 else 0}")
            }
            if(cmd=="OXSTATE"){
                val st=mutableMapOf<String,Fraction>();
                var last="";
                fun assign(e:String,x:Long){
                    st[e]=Fraction(x);
                    last=e
                };
                if(es.size==1)st[es[0]]=Fraction(q,c.getValue(es[0]))else{
                    if("F" in c)assign("F",-1);
                    for(e in es)if(e in metals)assign(e,metals.getValue(e));
                    if("H" in c)assign("H",if(es.all{
                        it=="H"||it in metals
                    })-1 else 1);
                    if("O" in c)assign("O",-2)else if("F" !in c)for(e in listOf("Cl","Br","I"))if(e in c){
                        assign(e,-1);
                        break
                    };
                    val u=es.filter{
                        it !in st
                    };
                    if(u.size>1)return listOf("indeterminate: ${u.joinToString(" ")}");
                    val total=st.entries.sumOf{
                        c.getValue(it.key)*it.value.n
                    };
                    if(u.isNotEmpty())st[u[0]]=Fraction(q-total,c.getValue(u[0]))else if(total!=q)st[last]=Fraction(q-total+c.getValue(last)*st.getValue(last).n,c.getValue(last))
                };
                return listOf(es.joinToString(", "){
                    "$it ${st.getValue(it)}"
                })
            }
            if(cmd=="SALT"){
                val b=formula(a[1]);
                if(q<=0)fail("not a cation ${a[0]}");
                if(b.q>=0)fail("not an anion ${a[1]}");
                for(s in a)if('.' in s)fail("hydrate ion $s");
                val g=gcd(q,b.q);
                val x=-b.q/g;
                val y=q/g;
                val z=add(scale(c,x),b.c,y);
                return listOf("${group(a[0],x)}${group(a[1],y)} (${hill(z)}, ${dec(mass(z),3)} g/mol)")
            }
            if(cmd=="MOLECULAR"&&q!=0L)fail("charged formula ${a[0]}");
            val x=quantity(a[1]);
            if(cmd=="MOLES")return listOf("${dec(x,3)} g ${a[0]} = ${dec(x*1000000/m,6)} mol");
            if(cmd=="GRAMS")return listOf("${dec(x,3)} mol ${a[0]} = ${dec(x*m/1000,3)} g");
            val k=(2*x+m)/(2*m);
            return if(k==0L||10*abs(x-k*m)>m)listOf("no integer multiple (ratio ${dec(1000*x/m,3)})")else listOf("${hill(scale(c,k))} (n = $k, ${dec(k*m,3)} g/mol)")
        }
        if(cmd=="REDOX"||cmd=="HALF"){
            if(a[0] !in listOf("acidic","basic"))fail("invalid medium ${a[0]}");
            val eq=equation(a.drop(1));
            for(s in eq.list)if(s.f in listOf("H^+","OH^-","H2O"))fail("reserved species ${s.name}");
            val aux=mutableListOf(species(if(a[0]=="acidic")"H^+"else "OH^-"),species("H2O"));
            if(cmd=="HALF")aux+=Species("e^-","",1,Formula(emptyMap(),-1));
            val list=eq.list+aux;
            val v=coefficients(list,eq.signs+List(aux.size){
                1L
            },eq.list.size);
            val left=mutableListOf<String>();
            val right=mutableListOf<String>();
            for(i in eq.list.indices)(if(i<eq.r)left else right).add(term(list[i].name,v[i]));
            for(i in eq.list.size until list.size)if(v[i]!=0L)(if(v[i]>0)left else right).add(term(list[i].name,abs(v[i])));
            val out=mutableListOf(left.joinToString(" + ")+" -> "+right.joinToString(" + "));
            if(cmd=="HALF")out+=if(v.last()>0)"reduction"else if(v.last()<0)"oxidation"else "no electron transfer";
            return out
        }
        var words=a;
        var rest=emptyList<String>();
        if(cmd in listOf("STOICH","LIMITING","YIELD")){
            if(a.count{
                it==":"
            }!=1)fail("invalid separator");
            val i=a.indexOf(":");
            words=a.take(i);
            rest=a.drop(i+1);
            if((cmd=="STOICH"&&rest.size!=2)||(cmd=="YIELD"&&rest.size!=4))fail("wrong argument count for $cmd")
        }
        val eq=equation(words,cmd=="CHECK");
        val list=eq.list;
        val r=eq.r
        if(cmd=="MATRIX"){
            val(labels,rows)=matrix(list,eq.signs);
            val(rank,basis)=nullspace(rows,list.size);
            return listOf("columns: ${list.joinToString(" "){it.name}}")+rows.mapIndexed{
                i,row->"${labels[i]}: ${row.joinToString(" ")}"
            }+"rank $rank, nullity ${basis.size}"+basis.map{
                "null: ${it.joinToString(" ")}"
            }
        }
        if(cmd=="CHECK"){
            val(labels,rows)=matrix(list,eq.signs);
            val diff=mutableListOf<String>();
            rows.forEachIndexed{
                i,row->val l=(0 until r).sumOf{
                    row[it]*list[it].coefficient
                };
                val rr=-(r until list.size).sumOf{
                    row[it]*list[it].coefficient
                };
                if(l!=rr)diff+="${labels[i]}: ${if(labels[i]=="charge")signed(l)else l.toString()} != ${if(labels[i]=="charge")signed(rr)else rr.toString()}"
            };
            if(diff.isNotEmpty())return listOf("not balanced")+diff;
            val g=list.map{
                it.coefficient
            }.fold(0L,::gcd);
            return listOf(if(g==1L)"balanced"else "balanced, not in lowest terms (gcd $g)")
        }
        var target=-1;
        var product=-1;
        var qs=emptyList<Long>();
        if(cmd=="DELTAH")for(s in list)if(s.name !in heats)fail("no enthalpy for ${s.name}")
        if(cmd=="STOICH"){
            target=list.indexOfFirst{
                it.name==rest[0]
            };
            if(target<0)fail("species ${rest[0]} not in equation");
            qs=listOf(quantity(rest[1]))
        }
        if(cmd=="LIMITING"){
            if(rest.size!=r)fail("expected $r masses, got ${rest.size}");
            qs=rest.map(::quantity)
        }
        if(cmd=="YIELD"){
            target=list.take(r).indexOfFirst{
                it.name==rest[0]
            };
            if(target<0)fail("${rest[0]} is not a reactant");
            val p=list.drop(r).indexOfFirst{
                it.name==rest[2]
            };
            if(p<0)fail("${rest[2]} is not a product");
            product=p+r;
            qs=listOf(quantity(rest[1]),quantity(rest[3]))
        }
        val v=coefficients(list,eq.signs);
        val out=mutableListOf(notation(eq,v));
        if(cmd=="BALANCE")return out
        if(cmd=="DELTAH"){
            val h=list.indices.sumOf{
                -eq.signs[it]*v[it]*heats.getValue(list[it].name)
            };
            return out+"dH = ${ent(h)} kJ (${if(h<0)"exothermic"else if(h>0)"endothermic"else "thermoneutral"})"
        }
        if(cmd=="STOICH"){
            val d=v[target]*list[target].mass;
            return out+list.mapIndexed{
                i,s->"${s.name} ${dec(qs[0]*v[i]*1000000/d,6)} mol ${dec(qs[0]*v[i]*s.mass/d,3)} g"+gas(s,qs[0]*v[i],d)
            }
        }
        if(cmd=="YIELD"){
            val t=qs[0]*v[product]*list[product].mass/(v[target]*list[target].mass);
            return out+listOf("theoretical ${dec(t,3)} g","actual ${dec(qs[1],3)} g",if(t==0L)"yield undefined"else "yield ${dec(qs[1]*10000/t,2)}%")
        }
        var l=0;
        for(i in 1 until r)if(qs[i]*v[l]*list[l].mass<qs[l]*v[i]*list[i].mass)l=i;
        val d=v[l]*list[l].mass;
        out+="limiting ${list[l].name}";
        out+="extent ${dec(qs[l]*1000000/d,6)} mol";
        for(i in r until list.size)out+="product ${list[i].name} ${dec(qs[l]*v[i]*list[i].mass/d,3)} g"+gas(list[i],qs[l]*v[i],d);
        for(i in 0 until r)if(i!=l)out+="remaining ${list[i].name} ${dec((qs[i]*d-qs[l]*v[i]*list[i].mass)/d,3)} g";
        return out
    }
}
fun main(){
    val n=readln().toInt();
    val engine=Chemistry();
    repeat(n){
        val line=readln();
        try{
            engine.execute(line).forEach(::println)
        }catch(e:ChemError){
            println(e.message)
        }
    }
}
