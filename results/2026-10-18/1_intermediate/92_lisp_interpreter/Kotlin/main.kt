import java.io.BufferedReader
import java.io.InputStreamReader

private object Nil
private object VoidValue
private object Uninitialized
private data class Symbol(val name:String)
private class Pair(val car:Any,val cdr:Any)
private class Env(val parent:Env?=null){
    val frame=mutableMapOf<String,Any>()
    fun find(n:String):Env{var e:Env?=this;while(e!=null){if(e.frame.containsKey(n))return e;e=e.parent};error("unbound variable: $n")}
    fun get(n:String):Any{val v=find(n).frame.getValue(n);if(v===Uninitialized)error("uninitialized variable: $n");return v}
}
private class Procedure(var name:String?,val minimum:Int,val variadic:Boolean,val rest:String?=null,val params:List<String> = emptyList(),val body:List<Any> = emptyList(),val env:Env?=null,val builtin:((List<Any>)->Any)?=null){
    fun call(a:List<Any>):Any{
        if(a.size<minimum||(!variadic&&a.size!=minimum))error("${name?:"lambda"}: wrong number of arguments (expected ${if(variadic)"at least " else ""}$minimum, got ${a.size})")
        builtin?.let{return it(a)}
        val e=Env(env);params.forEachIndexed{i,n->e.frame[n]=a[i]};if(rest!=null)e.frame[rest]=makeList(a.drop(minimum));return evalBody(body,e)
    }
}
private fun makeList(a:List<Any>,tail:Any=Nil):Any{var v=tail;for(x in a.asReversed())v=Pair(x,v);return v}
private fun items(value:Any):List<Any>?{var v=value;val a=mutableListOf<Any>();while(v is Pair){a.add(v.car);v=v.cdr};return if(v===Nil)a else null}
private fun truth(v:Any)=v!=false
private fun repr(value:Any,quoted:Boolean=true):String{
    if(value===Nil)return "()";if(value===VoidValue)return "#<void>"
    when(value){is Boolean->return if(value)"#t" else "#f";is Long->return value.toString();is String->return if(quoted)"\""+value.replace("\\","\\\\").replace("\"","\\\"").replace("\n","\\n")+"\"" else value;is Symbol->return value.name;is Procedure->return value.name?.let{"#<procedure $it>"}?:"#<procedure>"}
    var v=value;val a=mutableListOf<String>();while(v is Pair){a.add(repr(v.car,quoted));v=v.cdr};if(v!==Nil){a.add(".");a.add(repr(v,quoted))};return "("+a.joinToString(" ")+")"
}
private fun same(a:Any,b:Any,deep:Boolean=false):Boolean{if(a is Pair&&b is Pair)return if(deep)same(a.car,b.car,true)&&same(a.cdr,b.cdr,true) else a===b;return a==b}
private data class Parameters(val names:List<String>,val rest:String?)
private fun parameters(value:Any):Parameters?{var v=value;val names=mutableListOf<String>();while(v is Pair){val s=v.car as? Symbol?:return null;names.add(s.name);v=v.cdr};val r=(v as? Symbol)?.name;if(v!==Nil&&r==null)return null;val all=names+listOfNotNull(r);return if(all.distinct().size==all.size)Parameters(names,r) else null}
private fun closure(p:Parameters,b:List<Any>,e:Env,n:String?=null)=Procedure(n,p.names.size,p.rest!=null,p.rest,p.names,b,e)
private data class Binding(val name:String,val expression:Any)
private fun bindings(v:Any,unique:Boolean):List<Binding>?{val a=items(v)?:return null;val bs=mutableListOf<Binding>();val seen=mutableSetOf<String>();for(x in a){val b=items(x)?:return null;if(b.size!=2)return null;val s=b[0] as? Symbol?:return null;if(unique&&!seen.add(s.name))return null;bs.add(Binding(s.name,b[1]))};return bs}
private fun shape(ok:Boolean,x:Any){if(!ok)error("bad syntax: "+repr(x))}
private fun evalBody(a:List<Any>,e:Env):Any{var v:Any=VoidValue;for(x in a)v=evaluate(x,e);return v}
private fun evaluate(x:Any,e:Env):Any{
    if(x is Symbol)return e.get(x.name);if(x !is Pair){shape(x!==Nil,x);return x};val parsed=items(x);shape(parsed!=null,x);val a=parsed!!;val n=a.size;val h=(a[0] as? Symbol)?.name?:""
    when(h){
        "quote"->{shape(n==2,x);return a[1]}
        "if"->{shape(n==3||n==4,x);return if(truth(evaluate(a[1],e)))evaluate(a[2],e) else if(n==4)evaluate(a[3],e) else VoidValue}
        "begin"->return evalBody(a.drop(1),e)
        "lambda"->{val p=if(n>=3)parameters(a[1]) else null;shape(p!=null,x);return closure(p!!,a.drop(2),e)}
        "define"->{
            if(n>1&&a[1] is Symbol){shape(n==3,x);val name=(a[1] as Symbol).name;val v=evaluate(a[2],e);if(v is Procedure&&v.builtin==null&&v.name==null)v.name=name;e.frame[name]=v}
            else{val t=a.getOrNull(1) as? Pair;val name=t?.car as? Symbol;val p=if(n>=3&&name!=null)parameters(t!!.cdr) else null;shape(p!=null,x);e.frame[name!!.name]=closure(p!!,a.drop(2),e,name.name)};return VoidValue
        }
        "set!"->{shape(n==3&&a[1] is Symbol,x);val name=(a[1] as Symbol).name;val v=evaluate(a[2],e);e.find(name).frame[name]=v;return VoidValue}
        "let","let*","letrec"->{
            val named=h=="let"&&n>1&&a[1] is Symbol;val at=if(named)2 else 1;val bs=if(n>=at+2)bindings(a[at],h!="let*") else null;shape(bs!=null,x);val bindings=bs!!;var scope=Env(e)
            if(h=="let*"){if(bindings.isNotEmpty())scope=e;for(b in bindings){val v=evaluate(b.expression,scope);scope=Env(scope);scope.frame[b.name]=v}}
            else if(h=="letrec"){for(b in bindings)scope.frame[b.name]=Uninitialized;for(b in bindings)scope.frame[b.name]=evaluate(b.expression,scope)}
            else{val vs=bindings.map{evaluate(it.expression,e)};if(named){val name=(a[1] as Symbol).name;val f=closure(Parameters(bindings.map{it.name},null),a.drop(3),scope,name);scope.frame[name]=f;return f.call(vs)};bindings.forEachIndexed{i,b->scope.frame[b.name]=vs[i]}}
            return evalBody(a.drop(at+1),scope)
        }
        "cond"->{val cs=a.drop(1).map{items(it)};cs.forEachIndexed{i,c->shape(c!=null&&c.isNotEmpty(),x);if(c!![0]==Symbol("else"))shape(c.size>=2&&i==cs.size-1,x)};for(c0 in cs){val c=c0!!;if(c[0]==Symbol("else"))return evalBody(c.drop(1),e);val v=evaluate(c[0],e);if(truth(v))return if(c.size==1)v else evalBody(c.drop(1),e)};return VoidValue}
        "and"->{var v:Any=true;for(z in a.drop(1)){v=evaluate(z,e);if(!truth(v))break};return v}
        "or"->{for(z in a.drop(1)){val v=evaluate(z,e);if(truth(v))return v};return false}
        "when","unless"->{shape(n>=3,x);return if(truth(evaluate(a[1],e))==(h=="when"))evalBody(a.drop(2),e) else VoidValue}
    }
    val f=evaluate(a[0],e);val args=a.drop(1).map{evaluate(it,e)};if(f !is Procedure)error("not a procedure: "+repr(f));return f.call(args)
}
private var mid=false
private fun write(s:String){print(s);if(s.isNotEmpty())mid=!s.endsWith('\n')}
private fun line(s:String){if(mid)write("\n");write(s+"\n")}
private fun expect(n:String,v:Any,k:String):Any{val ok=when(k){"integer"->v is Long;"string"->v is String;"pair"->v is Pair;"procedure"->v is Procedure;else->items(v)!=null};if(!ok)error("$n: expected $k, got "+repr(v));return v}
private fun asList(n:String,v:Any):List<Any>{expect(n,v,"list");return items(v)!!}
private fun global():Env{
    val e=Env();fun add(n:String,m:Int,r:Boolean,fn:(List<Any>)->Any){e.frame[n]=Procedure(n,m,r,builtin=fn)}
    for(name in listOf("+","*","-","quotient","remainder","modulo","abs","min","max","gcd","=","<",">","<=",">=")){
        val fixed=if(name in listOf("quotient","remainder","modulo"))2 else if(name=="abs")1 else -1
        add(name,if(fixed>=0)fixed else if(name in listOf("+","*","gcd"))0 else 1,fixed<0){a->
            val z=a.map{expect(name,it,"integer") as Long};val v=z.firstOrNull()?:0L
            when(name){"+"->z.sum();"*"->z.fold(1L){s,x->s*x};"-"->if(z.size==1)-v else v-z.drop(1).sum();"abs"->kotlin.math.abs(v);"min"->z.min();"max"->z.max();"gcd"->z.fold(0L){g0,x->var g=g0;var b=kotlin.math.abs(x);while(b!=0L){val r=g%b;g=b;b=r};g};
                "quotient","remainder","modulo"->{val b=z[1];if(b==0L)error(name+": division by zero");val r=v%b;if(name=="quotient")v/b else if(name=="modulo"&&r!=0L&&((r<0)!=(b<0)))r+b else r}
                else->z.zipWithNext().all{(l,r)->when(name){"="->l==r;"<"->l<r;">"->l>r;"<="->l<=r;else->l>=r}}
            }
        }
    }
    add("not",1,false){!truth(it[0])};add("eq?",2,false){same(it[0],it[1])};add("equal?",2,false){same(it[0],it[1],true)}
    for(n in listOf("null?","pair?","list?","number?","symbol?","procedure?"))add(n,1,false){a->when(n){"null?"->a[0]===Nil;"pair?"->a[0] is Pair;"list?"->items(a[0])!=null;"number?"->a[0] is Long;"symbol?"->a[0] is Symbol;else->a[0] is Procedure}}
    add("cons",2,false){Pair(it[0],it[1])};add("list",0,true){makeList(it)}
    for(n in listOf("car","cdr","cadr"))add(n,1,false){a->val p=expect(n,a[0],"pair") as Pair;when(n){"car"->p.car;"cdr"->p.cdr;else->(expect(n,p.cdr,"pair") as Pair).car}}
    for(n in listOf("length","reverse","list-ref"))add(n,if(n=="list-ref")2 else 1,false){a->val z=asList(n,a[0]);when(n){"length"->z.size.toLong();"reverse"->makeList(z.asReversed());else->{val k=expect(n,a[1],"integer") as Long;if(k<0||k>=z.size)error("list-ref: index out of range: $k");z[k.toInt()]}}}
    add("append",0,true){a->if(a.isEmpty())Nil else makeList(a.dropLast(1).flatMap{asList("append",it)},a.last())}
    for(n in listOf("map","filter","fold-left","apply"))add(n,if(n=="fold-left")3 else 2,n!="filter"){a->
        val f=expect(n,a[0],"procedure") as Procedure
        if(n=="apply")f.call(a.drop(1).dropLast(1)+asList(n,a.last()))
        else{val ls=a.drop(if(n=="fold-left")2 else 1).map{asList(n,it)};val out=mutableListOf<Any>();var acc=a[1];for(i in 0 until ls.minOf{it.size}){if(n=="filter"){if(truth(f.call(listOf(ls[0][i]))))out.add(ls[0][i])}else{val args=ls.map{it[i]};val v=f.call(if(n=="fold-left")listOf(acc)+args else args);if(n=="map")out.add(v) else acc=v}};if(n=="fold-left")acc else makeList(out)}
    }
    add("string-append",0,true){a->a.joinToString(""){expect("string-append",it,"string") as String}};add("number->string",1,false){expect("number->string",it[0],"integer").toString()}
    add("display",1,false){write(repr(it[0],false));VoidValue};add("newline",0,false){write("\n");VoidValue};add("error",1,true){a->error((expect("error",a[0],"string") as String)+a.drop(1).joinToString(""){" "+repr(it)})};return e
}
private data class Token(val kind:Char,val value:Any?=null)
private class Reader(val lines:List<String>){
    var row=0;var col=0
    fun skip(){row++;col=0}
    fun end():Boolean{while(row<lines.size){val s=lines[row];while(col<s.length&&s[col]==' ')col++;if(col<s.length&&s[col]!=';')return false;skip()};return true}
    fun token():Token{if(end())error("unexpected end of input");val s=lines[row];var c=s[col++];if(c in "()'")return Token(c);if(c=='"'){val v=StringBuilder();while(col<s.length){c=s[col++];if(c=='"')return Token('v',v.toString());if(c=='\\'){if(col==s.length)break;c=s[col++];if(c !in "\"\\n")error("bad escape");if(c=='n')c='\n'};v.append(c)};error("unterminated string")};val start=col-1;while(col<s.length&&s[col] !in " ()'\";")col++;val a=s.substring(start,col);if(a==".")return Token('.');if(a.matches(Regex("[+-]?[0-9]+")))return Token('v',a.toLong());if(a=="#t"||a=="#f")return Token('v',a=="#t");if(a.startsWith('#'))error("bad token: $a");return Token('v',Symbol(a))}
    fun datum(t:Token=token()):Any{if(t.kind=='v')return t.value!!;if(t.kind=='\'')return makeList(listOf(Symbol("quote"),datum()));if(t.kind!='(')error("unexpected ${t.kind}");val a=mutableListOf<Any>();while(true){val next=token();if(next.kind==')')return makeList(a);if(next.kind=='.'&&a.isNotEmpty()){val tail=datum();if(token().kind!=')')error("expected )");return makeList(a,tail)};a.add(datum(next))}}
}
fun main(){val lines=mutableListOf<String>();val input=BufferedReader(InputStreamReader(System.`in`));while(true){val s=input.readLine()?:break;if(s=="(exit)")break;lines.add(s)};val r=Reader(lines);val e=global();while(!r.end()){val x:Any;try{x=r.datum()}catch(err:IllegalStateException){line("Error: read: "+err.message);if(err.message=="unexpected end of input")break;r.skip();continue};try{val v=evaluate(x,e);if(v!==VoidValue)line(repr(v))}catch(err:IllegalStateException){line("Error: "+err.message)}};if(mid)write("\n")}
