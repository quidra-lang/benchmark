class Problem(message: String) : RuntimeException(message)
data class Node(val kind: Char, val n: Int = 0, val row: Int = 0, val flags: Int = 0,
                val text: String = "", val a: Node? = null, val b: Node? = null, val args: List<Node> = emptyList())
fun num(n: Int) = Node('N', n)
fun text(s: String) = Node('S', text=s)
fun errorValue(s: String) = Node('E', text=s)
fun ref(c: Int, r: Int, f: Int = 0) = Node('R', c, r, f)
val invalid = Node('X')
fun id(r: Node) = r.row * 26 + r.n
fun label(i: Int) = "${('A'.code+i%26).toChar()}${i/26+1}"
fun inside(r: Node) = r.n in 0..25 && r.row in 0..98
fun range(a: Node, b: Node): Node {
    var c=a.n; var d=b.n; var r=a.row; var t=b.row
    var ac=a.flags and 1; var bc=b.flags and 1; var ar=a.flags and 2; var br=b.flags and 2
    if(c>d){val z=c;c=d;d=z;val f=ac;ac=bc;bc=f}
    if(r>t){val z=r;r=t;t=z;val f=ar;ar=br;br=f}
    return Node('G',a=ref(c,r,ac or ar),b=ref(d,t,bc or br))
}
fun address(s: String): Node {
    if(!Regex("[A-Z][1-9][0-9]?").matches(s))throw Problem("bad address")
    return ref(s[0]-'A',s.substring(1).toInt()-1)
}
fun area(s: String): Node {
    val p=s.indexOf(':');if(p<0){val a=address(s);return range(a,a)}
    val a=address(s.substring(0,p));val b=address(s.substring(p+1));return range(a,b)
}
fun cells(g: Node) = (g.a!!.row..g.b!!.row).flatMap { r -> (g.a.n..g.b.n).map { c -> r*26+c } }
fun contains(g: Node,r: Node) = r.n in g.a!!.n..g.b!!.n && r.row in g.a.row..g.b.row
val levels = listOf(setOf("=","<>","<","<=",">",">="),setOf("&"),setOf("+","-"),setOf("*","/"))
fun precedence(op: String) = levels.indexOfFirst { op in it }
data class Token(val value: Node,val position: Int)
class Parser(s: String) {
    private val tokens=mutableListOf<Token>()
    private var at=0
    private fun syntax(p: Int): Nothing = throw Problem("syntax error at $p")
    init {
        var i=1
        while(i<s.length){
            val p=i+1;val ch=s[i];if(ch==' '){i++;continue}
            val x: Node
            if(ch in '0'..'9'){
                var j=i;while(j<s.length&&s[j] in '0'..'9')j++
                if(j-i>=10)syntax(p);x=num(s.substring(i,j).toInt());i=j
            }else if(ch=='"'){
                val j=s.indexOf('"',i+1);if(j<0)syntax(p);x=text(s.substring(i+1,j));i=j+1
            }else if(ch.isLetter()||ch=='$'){
                var j=i;while(j<s.length&&(s[j].isLetterOrDigit()||s[j]=='$'))j++
                val w=s.substring(i,j).uppercase();i=j
                val m=Regex("(\\$?)([A-Z])(\\$?)([1-9][0-9]?)").matchEntire(w)
                x=if(m!=null)ref(m.groupValues[2][0]-'A',m.groupValues[4].toInt()-1,(if(m.groupValues[1].isEmpty())0 else 1) or (if(m.groupValues[3].isEmpty())0 else 2))
                else if(Regex("[A-Z][A-Z0-9]*").matches(w))Node(if(s.substring(j).trimStart().startsWith("("))'C' else 'W',text=w)
                else syntax(p)
            }else{
                var op=s.substring(i,minOf(i+2,s.length));if(op !in setOf("<>","<=",">="))op=ch.toString()
                if(ch !in "+-*/&(),:=<>")syntax(p);x=Node('T',text=op);i+=op.length
            }
            tokens+=Token(x,p)
        }
        tokens+=Token(Node('Z'),s.length+1)
    }
    private fun take(op: String): Boolean {val x=tokens[at].value;if(x.kind=='T'&&x.text==op){at++;return true};return false}
    private fun expect(op: String){if(!take(op))syntax(tokens[at].position)}
    private fun expression(level: Int=0): Node {
        if(level==4)return primary();var a=expression(level+1)
        while(tokens[at].value.kind=='T'&&tokens[at].value.text in levels[level]){val op=tokens[at++].value.text;a=Node('B',text=op,a=a,b=expression(level+1))};return a
    }
    private fun primary(): Node {
        if(take("-"))return Node('U',a=primary());val t=tokens[at++];val x=t.value
        if(x.kind in "NSW")return x
        if(x.kind=='R'){if(!take(":"))return x;if(tokens[at].value.kind!='R')syntax(tokens[at].position);return range(x,tokens[at++].value)}
        if(x.kind=='C'){
            expect("(");val args=mutableListOf<Node>()
            if(!take(")")){args+=expression();while(take(","))args+=expression();expect(")")}
            return Node('F',text=x.text,args=args.toList())
        }
        if(x.kind=='T'&&x.text=="("){val a=expression();expect(")");return a};syntax(t.position)
    }
    fun parse(): Node {val x=expression();if(tokens[at].value.kind!='Z')syntax(tokens[at].position);return x}
}
fun canonical(x: Node): String = when(x.kind){
    'N' -> x.n.toString()
    'S' -> "\"${x.text}\""
    'W' -> x.text
    'X' -> "#REF!"
    'R' -> (if(x.flags and 1 !=0)"$" else "")+('A'.code+x.n).toChar()+(if(x.flags and 2 !=0)"$" else "")+(x.row+1)
    'G' -> canonical(x.a!!)+":"+canonical(x.b!!)
    'F' -> x.text+"("+x.args.joinToString(",",transform=::canonical)+")"
    'U' -> "-"+(if(x.a!!.kind=='B')"("+canonical(x.a)+")" else canonical(x.a))
    else -> {
        var a=canonical(x.a!!);var b=canonical(x.b!!)
        if(x.a.kind=='B'&&precedence(x.a.text)<precedence(x.text))a="($a)"
        if(x.b.kind=='B'&&precedence(x.b.text)<=precedence(x.text))b="($b)"
        a+x.text+b
    }
}
fun display(x: Node?) = if(x==null)"" else if(x.kind=='N')x.n.toString() else x.text
fun notation(x: Node?) = if(x==null)"(empty)" else if(x.kind=='=')"="+canonical(x.a!!) else if(x.kind=='S')"\"${x.text}\"" else display(x)
fun number(x: Node?) = if(x==null)num(0) else if(x.kind in "SG")errorValue("#VALUE!") else x
fun stringValue(x: Node?) = if(x==null)text("") else if(x.kind=='N')text(x.n.toString()) else if(x.kind=='G')errorValue("#VALUE!") else x
fun rewrite(x: Node?,f: (Node)->Node): Node? {
    if(x==null)return null;if(x.kind in "RG")return f(x)
    return x.copy(a=rewrite(x.a,f),b=rewrite(x.b,f),args=x.args.map { rewrite(it,f)!! })
}
fun dependencies(x: Node?,out: MutableSet<Int> = mutableSetOf()): Set<Int> {
    if(x==null)return out
    when(x.kind){'R'->out.add(id(x));'G'->out.addAll(cells(x));else->{dependencies(x.a,out);dependencies(x.b,out);x.args.forEach { dependencies(it,out) }}}
    return out
}
class Sheet {
    private var contents=arrayOfNulls<Node>(2574)
    private var values=arrayOfNulls<Node>(2574)
    private var deps=List<Set<Int>>(2574){emptySet()}
    private val history=mutableListOf<Pair<String,Array<Node?>>>()
    private fun evaluate(x: Node): Node? {
        if(x.kind in "NSG")return x
        if(x.kind=='R')return values[id(x)]
        if(x.kind=='W')return errorValue("#NAME?")
        if(x.kind=='X')return errorValue("#REF!")
        if(x.kind=='U'){val a=number(evaluate(x.a!!));return if(a.kind=='E')a else num(-a.n)}
        if(x.kind=='B'){
            var a=evaluate(x.a!!);var b=evaluate(x.b!!);val op=x.text
            if(a?.kind=='E')return a;if(b?.kind=='E')return b
            if(precedence(op)==0){
                if(a?.kind=='G'||b?.kind=='G')return errorValue("#VALUE!")
                val blank=if(a?.kind=='S'||b?.kind=='S')text("") else num(0);a=a?:blank;b=b?:blank
                val c=if(a.kind!=b.kind){if(a.kind=='N')-1 else 1}else if(a.kind=='N')a.n.compareTo(b.n) else a.text.compareTo(b.text)
                val yes=when(op){"="->c==0;"<>"->c!=0;"<"->c<0;"<="->c<=0;">"->c>0;else->c>=0};return num(if(yes)1 else 0)
            }
            val u=if(op=="&")stringValue(a) else number(a);val v=if(op=="&")stringValue(b) else number(b)
            if(u.kind=='E')return u;if(v.kind=='E')return v
            return when(op){"&"->text(u.text+v.text);"+"->num(u.n+v.n);"-"->num(u.n-v.n);"*"->num(u.n*v.n);else->if(v.n==0)errorValue("#DIV/0!") else num(u.n/v.n)}
        }
        val name=x.text;val args=x.args
        if(name in setOf("SUM","MIN","MAX","COUNT","AVERAGE","AND","OR","CONCAT")){
            if(args.isEmpty())return errorValue("#VALUE!")
            val items=args.flatMap { val v=evaluate(it);if(v?.kind=='G')cells(v).map { i->values[i] } else listOf(v) }
            val ns=items.filterNotNull().filter { it.kind=='N' }.map { it.n }
            if(name=="COUNT")return num(ns.size);items.firstOrNull { it?.kind=='E' }?.let { return it }
            return when(name){
                "SUM"->num(ns.sum());"MIN"->num(ns.minOrNull()?:0);"MAX"->num(ns.maxOrNull()?:0)
                "AVERAGE"->if(ns.isEmpty())errorValue("#DIV/0!") else num(ns.sum()/ns.size)
                "AND"->if(ns.isEmpty())errorValue("#VALUE!") else num(if(ns.all { it!=0 })1 else 0)
                "OR"->if(ns.isEmpty())errorValue("#VALUE!") else num(if(ns.any { it!=0 })1 else 0)
                else->text(items.joinToString(""){stringValue(it).text})
            }
        }
        if(name=="IF"){
            if(args.size !in 2..3)return errorValue("#VALUE!");val c=number(evaluate(args[0]));if(c.kind=='E')return c
            return if(c.n!=0)evaluate(args[1]) else if(args.size==3)evaluate(args[2]) else num(0)
        }
        if(name !in setOf("ABS","NOT","LEN"))return errorValue("#NAME?")
        if(args.size!=1)return errorValue("#VALUE!")
        val v=if(name=="LEN")stringValue(evaluate(args[0])) else number(evaluate(args[0]))
        return if(v.kind=='E')v else num(if(name=="LEN")v.text.length else if(name=="ABS")kotlin.math.abs(v.n) else if(v.n==0)1 else 0)
    }
    private fun recalculate(){
        deps=contents.map { if(it?.kind=='=')dependencies(it.a) else emptySet() }
        values=contents.map { if(it?.kind=='=')null else it }.toTypedArray()
        val indices=IntArray(2574){-1};val low=IntArray(2574);val on=BooleanArray(2574);val cyclic=BooleanArray(2574);val done=BooleanArray(2574);val stack=mutableListOf<Int>();var serial=0
        fun visit(i: Int){
            indices[i]=serial;low[i]=serial++;stack.add(i);on[i]=true
            for(j in deps[i])if(contents[j]?.kind=='='){
                if(indices[j]<0){visit(j);low[i]=minOf(low[i],low[j])}else if(on[j])low[i]=minOf(low[i],indices[j])
            }
            if(low[i]==indices[i]){
                val part=mutableListOf<Int>();var j: Int
                do{j=stack.removeAt(stack.lastIndex);on[j]=false;part.add(j)}while(j!=i)
                if(part.size>1||i in deps[i])for(k in part)cyclic[k]=true
            }
        }
        for(i in 0 until 2574)if(contents[i]?.kind=='='&&indices[i]<0)visit(i)
        fun calculate(i: Int){
            if(contents[i]?.kind!='='||done[i])return;done[i]=true
            if(cyclic[i]){values[i]=errorValue("#CYCLE!");return}
            deps[i].forEach(::calculate);val v=evaluate(contents[i]!!.a!!);values[i]=if(v==null)num(0) else if(v.kind=='G')errorValue("#VALUE!") else v
        }
        for(i in 0 until 2574)calculate(i)
    }
    private fun replace(next: Array<Node?>): Int {val old=values;contents=next;recalculate();return old.indices.count { old[it]!=values[it] }}
    private fun describe(i: Int)="${label(i)}: ${notation(contents[i])} -> ${notation(values[i])}"
    private fun formatted(xs: Collection<Int>)=if(xs.isEmpty())"none" else xs.sorted().joinToString(",",transform=::label)
    fun execute(line: String): List<String> {
        val p=line.indexOf(' ');val name=if(p<0)line else line.substring(0,p);val rest=if(p<0)"" else line.substring(p+1)
        when(name){
            "SHOW"->return listOf(describe(id(address(rest))))
            "LIST"->{val out=contents.indices.filter { contents[it]!=null }.map(::describe);return if(out.isEmpty())listOf("(no cells)") else out}
            "DEPS"->{val i=id(address(rest));return listOf("$rest: precedents=${formatted(deps[i])} dependents=${formatted(deps.indices.filter { i in deps[it] })}")}
            "PRINT"->{
                val g=area(rest);val rw=(g.b!!.row+1).toString().length;val cs=g.a!!.n..g.b.n;val rs=g.a.row..g.b.row
                val ws=cs.map { c->maxOf(1,rs.maxOf { r->display(values[r*26+c]).length }) }
                val sep="+"+"-".repeat(rw)+"+"+ws.joinToString(""){"-".repeat(it)+"+"}
                val head="|"+" ".repeat(rw)+"|"+cs.zip(ws).joinToString(""){(c,w)->('A'.code+c).toChar().toString().padEnd(w)+"|"}
                val out=mutableListOf(sep,head,sep)
                for(r in rs){var row="|"+(r+1).toString().padStart(rw)+"|";for((c,w) in cs.zip(ws)){val v=values[r*26+c];row+=(if(v?.kind=='N')display(v).padStart(w) else display(v).padEnd(w))+"|"};out+=row};out+=sep;return out
            }
            "UNDO"->{if(history.isEmpty())throw Problem("nothing to undo");val (command,old)=history.removeAt(history.lastIndex);return listOf("UNDO $command changed=${replace(old)}")}
        }
        var next=contents.copyOf();var target=-1
        when(name){
            "SET"->{
                val p=rest.indexOf(' ');target=id(address(rest.substring(0,p)));val s=rest.substring(p+1)
                next[target]=if(s.startsWith("="))Node('=',a=Parser(s).parse())
                else if(Regex("\"[^\"]*\"").matches(s))text(s.substring(1,s.length-1))
                else if(Regex("0|-?[1-9][0-9]{0,8}").matches(s))num(s.toInt()) else throw Problem("bad value")
            }
            "CLEAR"->for(i in cells(area(rest)))next[i]=null
            "COPY","MOVE"->{
                val p=rest.indexOf(' ');val source=area(rest.substring(0,p));val dest=address(rest.substring(p+1));val dc=dest.n-source.a!!.n;val dr=dest.row-source.a.row
                fun shift(r: Node,relative: Boolean)=ref(r.n+(if(relative&&r.flags and 1!=0)0 else dc),r.row+(if(relative&&r.flags and 2!=0)0 else dr),r.flags)
                val destination=range(shift(source.a,false),shift(source.b!!,false));if(!inside(destination.a!!)||!inside(destination.b!!))throw Problem("out of grid")
                val transform: (Node)->Node = {x->
                    if(x.kind=='R'){
                        if(name=="COPY"){val a=shift(x,true);if(inside(a))a else invalid}
                        else if(contains(source,x))shift(x,false) else if(contains(destination,x))invalid else x
                    }else if(name=="MOVE"&&!(contains(source,x.a!!)&&contains(source,x.b!!)))x
                    else{val a=shift(x.a!!,name=="COPY");val b=shift(x.b!!,name=="COPY");if(inside(a)&&inside(b))range(a,b) else invalid}
                }
                if(name=="MOVE")next=next.map { rewrite(it,transform) }.toTypedArray()
                val ids=cells(source);val moving=ids.map { if(name=="COPY")rewrite(contents[it],transform) else next[it] }
                if(name=="MOVE")for(i in ids)next[i]=null
                for(j in ids.indices)next[ids[j]+dr*26+dc]=moving[j]
            }
            "INSERTROW","DELETEROW","INSERTCOL","DELETECOL"->{
                val row=name.endsWith("ROW");val insert=name.startsWith("INSERT")
                if(!Regex(if(row)"[1-9][0-9]?" else "[A-Z]").matches(rest))throw Problem("bad address")
                val at=if(row)rest.toInt()-1 else rest[0]-'A';val limit=if(row)99 else 26
                fun axis(x: Node)=if(row)x.row else x.n
                fun change(x: Node,v: Int)=ref(if(row)x.n else v,if(row)v else x.row,x.flags)
                if(insert&&contents.indices.any { contents[it]!=null&&(if(row)it/26 else it%26)==limit-1 })throw Problem("last ${if(row)"row" else "column"} not empty")
                val transform: (Node)->Node = {x->
                    if(x.kind=='R'){
                        val v=axis(x);val n=v+(if(insert){if(v>=at)1 else 0}else if(v>at)-1 else 0)
                        if(!insert&&v==at||n>=limit)invalid else change(x,n)
                    }else{
                        val a=axis(x.a!!);val b=axis(x.b!!)
                        val u=a+(if(insert){if(a>=at)1 else 0}else if(a>at)-1 else 0)
                        val v=b+(if(insert){if(b>=at)1 else 0}else if(b>=at)-1 else 0)
                        if(!insert&&a==at&&b==at||v>=limit)invalid else range(change(x.a,u),change(x.b,v))
                    }
                }
                next=arrayOfNulls(2574)
                for(i in contents.indices)if(contents[i]!=null){val r=ref(i%26,i/26);val v=axis(r);if(!insert&&v==at)continue;val t=change(r,v+(if(insert){if(v>=at)1 else 0}else if(v>at)-1 else 0));next[id(t)]=rewrite(contents[i],transform)}
            }
            else->throw Problem("unknown command")
        }
        history+=name to contents;val changed=replace(next)
        return listOf(name+(if(name=="SET")" ${label(target)}=${notation(values[target])}" else "")+" changed=$changed")
    }
}
fun main(){
    val input=System.`in`.bufferedReader();val n=input.readLine().toInt();val sheet=Sheet();val out=StringBuilder()
    repeat(n){val line=input.readLine();try{for(s in sheet.execute(line))out.append(s).append('\n')}catch(e: Problem){out.append("ERROR ").append(e.message).append('\n')}}
    print(out)
}
