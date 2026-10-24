import java.util.Locale
import kotlin.math.*

data class Rational(val p:Long,val q:Long):Comparable<Rational> {
    operator fun plus(b:Rational)=rational(p*b.q+b.p*q,q*b.q)
    operator fun times(b:Rational)=rational(p*b.p,q*b.q)
    operator fun unaryMinus()=rational(-p,q)
    override fun compareTo(b:Rational)=(p*b.q).compareTo(b.p*q)
}
fun rational(n:Long,d:Long=1):Rational {if(d==0L)error("division by zero");var p=n;var q=d;if(q<0){p=-p;q=-q};var a=abs(p);var b=q;while(b!=0L){val t=a%b;a=b;b=t};return Rational(p/a,q/a)}
data class Expr(val kind:Int,val q:Rational,val name:String,val args:List<Expr>)
data class Parts(val coefficient:Rational,val factors:List<Expr>)
data class Syntax(val op:String,val value:Expr?=null,val args:List<Syntax> = emptyList())
fun number(q:Rational)=Expr(5,q,"",emptyList())
fun num(p:Long,q:Long=1)=number(rational(p,q))
fun num(p:Int)=num(p.toLong())
fun node(k:Int,a:List<Expr> = emptyList(),s:String="")=Expr(k,rational(0),s,a.toList())
val zero=num(0);val one=num(1);val minus=num(-1);val half=num(1L,2)
val functions=setOf("sin","cos","tan","exp","ln","sqrt")
fun compare(a:Expr,b:Expr):Int {
    if(a.kind!=b.kind)return a.kind.compareTo(b.kind)
    if(a.kind==5)return a.q.compareTo(b.q)
    val c=a.name.compareTo(b.name);if(c!=0)return c
    for(i in 0 until min(a.args.size,b.args.size)){val c=compare(a.args[i],b.args[i]);if(c!=0)return c}
    return a.args.size.compareTo(b.args.size)
}
fun integer(f:Expr)=f.kind==5&&f.q.q==1L
fun negative(f:Expr)=f.kind==3&&f.args[1].kind==5&&f.args[1].q.p<0
fun base(f:Expr)=if(f.kind==3)f.args[0] else f
fun exponent(f:Expr)=if(f.kind==3)f.args[1] else one
fun coefficient(f:Expr):Parts =when {f.kind==5->Parts(f.q,emptyList());f.kind==2&&f.args[0].kind==5->Parts(f.args[0].q,f.args.drop(1));f.kind==2->Parts(rational(1),f.args);else->Parts(rational(1),listOf(f))}
fun product(c:Rational,a:List<Expr>):Expr {if(a.isEmpty())return number(c);val r=if(c!=rational(1))listOf(number(c))+a else a;return if(r.size==1)r[0] else node(2,r)}
fun exponentCompare(a:Expr,b:Expr):Int {if(a.kind==5&&b.kind!=5)return -1;if(a.kind!=5&&b.kind==5)return 1;return compare(a,b)}
fun termCompare(a:Expr,b:Expr):Int {
    val x=coefficient(a).factors.associate{base(it) to exponent(it)};val y=coefficient(b).factors.associate{base(it) to exponent(it)}
    for(b in (x.keys+y.keys).sortedWith(::compare)){val c=exponentCompare(y[b]?:zero,x[b]?:zero);if(c!=0)return c};return 0
}
fun add(vararg a:Expr)=add(a.toList())
fun add(operands:List<Expr>):Expr {
    val terms=operands.flatMap { f->when {f.kind==1->f.args;f.kind==2&&f.args.size==2&&f.args[0].kind==5&&f.args[1].kind==1->f.args[1].args.map{mul(f.args[0],it)};else->listOf(f)} }
    val groups=linkedMapOf<List<Expr>,Rational>();for(f in terms){val(c,m)=coefficient(f);groups[m]=(groups[m]?:rational(0))+c}
    val built=groups.mapNotNull{(m,c)->if(c.p==0L)null else product(c,m)}.sortedWith(::termCompare)
    return if(built.isEmpty())zero else if(built.size==1)built[0] else node(1,built)
}
fun mul(vararg a:Expr)=mul(a.toList())
fun mul(operands:List<Expr>):Expr {
    var c=rational(1);val groups=linkedMapOf<Expr,MutableList<Expr>>()
    for(f in operands.flatMap{if(it.kind==2)it.args else listOf(it)}){if(f.kind==5)c*=f.q else groups.getOrPut(base(f)){mutableListOf()}.add(f)}
    if(c.p==0L)return zero
    val r=groups.map{(b,g)->if(g.size==1)g[0] else power(b,add(g.map(::exponent)))}
    if(r.any{it.kind==2||it.kind==5}||r.map(::base).distinct().size<r.size)return mul(listOf(number(c))+r)
    return product(c,r.sortedWith{a,b->compare(base(a),base(b))})
}
fun root(v:Long,d:Long):Long? {if(v==1L)return 1;if(d>20)return null;val r=v.toDouble().pow(1.0/d).roundToLong();for(s in max(0,r-1)..r+1){var a=1L;var i=0L;while(i<d&&a<=v){a*=s;i++};if(a==v)return s};return null}
fun rationalPower(value:Rational,exponent:Long):Expr {var b=value;var n=exponent;if(n<0){b=rational(b.q,b.p);n=-n};var r=rational(1);while(n>0){if(n%2!=0L)r*=b;n/=2;if(n>0)b*=b};return number(r)}
fun power(b:Expr,x:Expr):Expr {
    if(x==zero)return one;if(x==one)return b
    if(b.kind==5){if(b==one)return one;if(x.kind!=5)return node(3,listOf(b,x));if(b.q.p==0L){if(x.q.p>0)return zero;error("division by zero")};if(integer(x))return rationalPower(b.q,x.q.p);if(b.q.p>0){val s=root(b.q.p,x.q.q);val t=root(b.q.q,x.q.q);if(s!=null&&t!=null)return rationalPower(rational(s,t),x.q.p)}}
    else if(integer(x)){if(b.kind==3)return power(b.args[0],mul(b.args[1],x));if(b.kind==2)return mul(b.args.map{power(it,x)})}
    return node(3,listOf(b,x))
}
fun fn(s:String,a:Expr):Expr {
    if(s=="sqrt")return power(a,half)
    if(a==zero&&s in setOf("sin","tan"))return zero;if(a==zero&&s in setOf("cos","exp"))return one;if(a==one&&s=="ln")return zero
    if(s in setOf("sin","cos","tan")&&coefficient(a).coefficient.p<0){val r=fn(s,mul(minus,a));return if(s=="cos")r else mul(minus,r)}
    if(a.kind==4&&((s=="exp"&&a.name=="ln")||(s=="ln"&&a.name=="exp")))return a.args[0]
    return node(4,listOf(a),s)
}
fun variables(f:Expr):Set<String> = if(f.kind==0)setOf(f.name) else f.args.flatMap{variables(it)}.toSortedSet()
fun derivative(f:Expr,v:String):Expr {
    if(f.kind==5)return zero;if(f.kind==0)return if(f.name==v)one else zero
    if(f.kind==1)return add(f.args.map{derivative(it,v)})
    if(f.kind==2)return add(f.args.indices.map{i->mul(f.args.mapIndexed{j,t->if(i==j)derivative(t,v) else t})})
    if(f.kind==3){val(b,x)=f.args;if(v !in variables(x))return mul(x,power(b,add(x,minus)),derivative(b,v));if(v !in variables(b))return mul(f,fn("ln",b),derivative(x,v));return mul(f,add(mul(derivative(x,v),fn("ln",b)),mul(x,derivative(b,v),power(b,minus))))}
    val a=f.args[0];val h=when(f.name){"sin"->fn("cos",a);"cos"->mul(minus,fn("sin",a));"tan"->power(fn("cos",a),num(-2));"exp"->f;else->power(a,minus)};return mul(h,derivative(a,v))
}
fun rebuild(f:Expr,a:List<Expr>):Expr =when(f.kind){1->add(a);2->mul(a);3->power(a[0],a[1]);else->fn(f.name,a[0])}
fun substitute(f:Expr,m:Map<String,Expr>):Expr =when(f.kind){0->m[f.name]?:f;5->f;else->rebuild(f,f.args.map{substitute(it,m)})}
fun terms(f:Expr)=if(f.kind==1)f.args else listOf(f)
fun distribute(a:Expr,b:Expr)=add(terms(a).flatMap{x->terms(b).map{y->mul(x,y)}})
fun expand(f:Expr):Expr {if(f.kind==0||f.kind==5)return f;val a=f.args.map(::expand);if(f.kind==2)return a.reduce(::distribute);if(f.kind==3&&a[0].kind==1&&integer(a[1])&&a[1].q.p>0){var r=a[0];for(i in 1 until a[1].q.p)r=distribute(r,a[0]);return r};return rebuild(f,a)}
fun numeric(f:Expr):Double {
    if(f.kind==5)return f.q.p.toDouble()/f.q.q
    if(f.kind==1)return f.args.fold(0.0){r,t->r+numeric(t)};if(f.kind==2)return f.args.fold(1.0){r,t->r*numeric(t)}
    if(f.kind==3){val u=numeric(f.args[0]);val z=numeric(f.args[1]);val integral=if(f.args[1].kind==5)integer(f.args[1]) else z==floor(z);if(u<0&&!integral)error("domain error");return if(f.args[1]==half)sqrt(u) else u.pow(z)}
    val a=numeric(f.args[0]);if(f.name=="ln"&&a<=0)error("domain error");return when(f.name){"sin"->sin(a);"cos"->cos(a);"tan"->tan(a);"exp"->exp(a);else->ln(a)}
}
fun atomic(f:Expr)=f.kind==0||f.kind==4||(integer(f)&&f.q.p>=0)||(f.kind==3&&f.args[1]==half)
fun atom(f:Expr)=if(atomic(f))show(f) else "(${show(f)})"
fun showPower(b:Expr,x:Expr)=if(x==half)"sqrt(${show(b)})" else "${atom(b)}^${atom(x)}"
fun factor(f:Expr)=if(f.kind==1)"(${show(f)})" else if(f.kind==3)showPower(f.args[0],f.args[1]) else show(f)
fun quotient(c:Rational,a:List<Expr>):String {val top=mutableListOf<String>();val bottom=mutableListOf<String>();if(abs(c.p)!=1L)top.add(abs(c.p).toString());if(c.q!=1L)bottom.add(c.q.toString());for(f in a){if(negative(f)){val r=number(-f.args[1].q);bottom.add(if(r==one)factor(f.args[0]) else showPower(f.args[0],r))}else top.add(factor(f))};var s=if(top.isEmpty())"1" else top.joinToString("*");if(bottom.size==1)s+="/"+bottom[0] else if(bottom.isNotEmpty())s+="/("+bottom.joinToString("*")+")";return(if(c.p<0)"-" else "")+s}
fun show(f:Expr):String {if(f.kind==5)return f.q.p.toString()+(if(f.q.q==1L)"" else "/${f.q.q}");if(f.kind==0)return f.name;if(f.kind==4)return "${f.name}(${show(f.args[0])})";if(f.kind==3)return if(negative(f))quotient(rational(1),listOf(f)) else showPower(f.args[0],f.args[1]);if(f.kind==2){val(c,a)=coefficient(f);return quotient(c,a)};return f.args.map(::show).reduce{a,b->a+if(b.startsWith('-'))" - "+b.substring(1) else " + "+b}}
class Parser(text:String,val names:Map<String,Expr>) {
    private val tokens=mutableListOf<String>();private var position=0
    init {for(m in Regex("[0-9]+|[a-z][a-z0-9]*|[A-Z][A-Z0-9]*|[-+*/^()]| +|.").findAll(text)){val t=m.value;if(t.startsWith(' '))continue;if(!Regex("[a-zA-Z0-9+*/^()-]+").matches(t))error("invalid character '$t'");tokens.add(t)}}
    private fun peek()=tokens.getOrElse(position){""}
    private fun unexpected():Nothing=error(if(position==tokens.size)"unexpected end of expression" else "unexpected '${peek()}'")
    private fun accept(s:String):Boolean {if(peek()!=s)return false;position++;return true}
    private fun expect(s:String){if(!accept(s))unexpected()}
    private fun atomTree():Syntax {val t=peek();if(t.isEmpty())unexpected();if(accept("(")){val a=expression();expect(")");return a};if(!t[0].isLetterOrDigit())unexpected();position++;if(t[0].isDigit())return Syntax("",num(t.toLong()));if(t[0].isUpperCase())return Syntax("",names[t]?:error("undefined name '$t'"));if(t !in functions)return Syntax("",node(0,s=t));expect("(");val a=expression();expect(")");return Syntax(t,args=listOf(a))}
    private fun unary():Syntax {if(accept("-"))return Syntax("neg",args=listOf(unary()));val a=atomTree();return if(accept("^"))Syntax("^",args=listOf(a,unary())) else a}
    private fun term():Syntax {var a=unary();while(peek() in setOf("*","/")){val op=tokens[position++];a=Syntax(op,args=listOf(a,unary()))};return a}
    private fun expression():Syntax {var a=term();while(peek() in setOf("+","-")){val op=tokens[position++];a=Syntax(op,args=listOf(a,term()))};return a}
    private fun evaluate(t:Syntax):Expr {t.value?.let{return it};val a=t.args.map(::evaluate);return when(t.op){"+"->add(a);"-"->add(a[0],mul(minus,a[1]));"*"->mul(a);"/"->mul(a[0],power(a[1],minus));"^"->power(a[0],a[1]);"neg"->mul(minus,a[0]);else->fn(t.op,a[0])}}
    fun parse():Expr {val t=expression();if(position<tokens.size)unexpected();return evaluate(t)}
}
fun variable(s:String)=Regex("[a-z][a-z0-9]*").matches(s)&&s !in functions
fun rationalLiteral(s:String)=Regex("-?[0-9]+(?:/[0-9]+)?").matches(s)
fun literal(s:String):Expr {if(!rationalLiteral(s))error("invalid number '$s'");val a=s.split('/');return num(a[0].toLong(),if(a.size==1)1 else a[1].toLong())}
val signatures=mapOf("SIMPLIFY" to "e","EXPAND" to "e","DIFF" to "ev","DIFFN" to "evn","GRAD" to "e","HESSIAN" to "e","IMPLICIT" to "evv","SUBST" to "eve","EVAL" to "ea","TANGENT" to "evc","LIMIT" to "evc","TAYLOR" to "evcn")
fun command(line:String,names:MutableMap<String,Expr>):List<String> {
    val p=line.indexOf(' ');val c=if(p<0)line else line.substring(0,p);val arg=if(p<0)"" else line.substring(p+1)
    if(c=="LET"){val i=arg.indexOf('=');if(i<0)error("wrong number of arguments");val s=arg.substring(0,i).trim(' ');if(!Regex("[A-Z][A-Z0-9]*").matches(s))error("invalid name '$s'");val f=Parser(arg.substring(i+1).trim(' '),names).parse();names[s]=f;return listOf("$s = ${show(f)}")}
    val sig=signatures[c]?:error("unknown command $c");val fields=if(p<0)emptyList() else arg.split(';').map{it.trim(' ')};if(if(c=="EVAL")fields.size !in 1..2 else fields.size!=sig.length)error("wrong number of arguments")
    val forms=MutableList(fields.size){zero};var n=0;for(i in fields.indices){val s=fields[i];when(sig[i]){'e'->forms[i]=Parser(s,names).parse();'v'->if(!variable(s))error("invalid variable '$s'");'n'->{if(!Regex("[1-8]").matches(s))error("invalid order '$s'");n=s.toInt()};'c'->forms[i]=literal(s)}}
    var f=forms[0];val v=fields.getOrElse(1){""};val out=mutableListOf<String>()
    if(c=="SIMPLIFY")return listOf("simplified: ${show(f)}");if(c=="EXPAND")return listOf("expanded: ${show(expand(f))}");if(c=="DIFF")return listOf("d/d$v = ${show(derivative(f,v))}")
    if(c=="DIFFN"){for(k in 1..n){f=derivative(f,v);out.add("d^$k/d$v^$k = ${show(f)}")};return out}
    if(c=="GRAD"||c=="HESSIAN"){val vs=variables(f).sorted();if(vs.isEmpty())return listOf("no variables");for(i in vs.indices){val d=derivative(f,vs[i]);if(c=="GRAD")out.add("d/d${vs[i]} = ${show(d)}") else for(j in i until vs.size)out.add("d2/d${vs[i]}d${vs[j]} = ${show(derivative(d,vs[j]))}")};return out}
    if(c=="IMPLICIT"){val w=fields[2];if(v==w)error("same variable");return listOf("d$w/d$v = ${show(mul(minus,derivative(f,v),power(derivative(f,w),minus)))}")}
    if(c=="SUBST")return listOf("substituted: ${show(substitute(f,mapOf(v to forms[2])))}")
    if(c=="EVAL"){val values=mutableMapOf<String,Expr>();for(word in v.split(' ').filter{it.isNotEmpty()}){val i=word.indexOf('=');val s=if(i<0)word else word.substring(0,i);val t=if(i<0)"" else word.substring(i+1);if(i<0||!variable(s)||!rationalLiteral(t))error("invalid assignment '$word'");val q=literal(t);if(s in values)error("duplicate variable $s");values[s]=q};for(s in variables(f).sorted())if(s !in values)error("no value for $s");val r=substitute(f,values);return listOf(if(r.kind==5)"exact: ${show(r)}" else String.format(Locale.ROOT,"approx: %.6f",numeric(r)))}
    val x=forms[2];val point=mapOf(v to x)
    if(c=="TANGENT"){val m=substitute(derivative(f,v),point);val y=substitute(f,point);val z=node(0,s=v);val t="tangent: y = ${show(add(mul(m,z),y,mul(number(-x.q),m)))}";if(m==zero)return listOf(t,"normal: $v = ${show(x)}");val k=power(m,minus);return listOf(t,"normal: y = ${show(add(mul(minus,k,z),y,mul(x,k)))}")}
    if(c=="LIMIT"){val top=mutableListOf<Expr>();val bottom=mutableListOf<Expr>();for(t in if(f.kind==2)f.args else listOf(f)){if(negative(t))bottom.add(power(t.args[0],number(-t.args[1].q))) else top.add(t)};var g=mul(top);var h=mul(bottom);for(k in 0..5){val u=substitute(g,point);val b=substitute(h,point);if(b!=zero)return listOf("limit: ${show(mul(u,power(b,minus)))}");if(u!=zero)return listOf("limit: unbounded");if(k<5){g=derivative(g,v);h=derivative(h,v)}};return listOf("limit: unknown")}
    val ds=mutableListOf(f);repeat(n){ds.add(derivative(ds.last(),v))};val ps=mutableListOf<Expr>();var fac=1L;for(k in 0..n){if(k>0)fac*=k;val co=mul(substitute(ds[k],point),num(1L,fac));ps.add(mul(co,power(add(node(0,s=v),number(-x.q)),num(k))))};return listOf("taylor: ${show(expand(add(ps)))}")
}
fun main(){val input=System.`in`.bufferedReader();val names=mutableMapOf<String,Expr>();repeat(input.readLine().toInt()){val line=input.readLine();try{for(s in command(line,names))println(s)}catch(e:IllegalStateException){println("error: ${e.message}")}}}
