import java.util.Locale

private class SqlError(message:String):RuntimeException(message)
private fun fail(s:String):Nothing=throw SqlError(s)
private val reserved="SELECT DISTINCT FROM AS JOIN INNER LEFT OUTER ON WHERE GROUP BY HAVING ORDER ASC DESC LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY NOT NULL INT TEXT AND OR IS IN BETWEEN LIKE COUNT SUM MIN MAX AVG EXIT".split(' ').toSet()
private val aggregates=setOf("COUNT","SUM","MIN","MAX","AVG")
private val comparisons=setOf("=","<>","!=","<","<=",">",">=")
private data class Token(val kind:String,val text:String,val value:Any)
private fun tokenize(s:String):List<Token>{
    val a=mutableListOf<Token>();var i=0
    while(i<s.length){val c=s[i];val start=i;if(c==' '||c=='\n'){i++;continue};if(s.startsWith("--",i)){i=s.indexOf('\n',i).let{if(it<0)s.length else it};continue}
        if(c=='\''){i=s.indexOf('\'',i+1)+1;a.add(Token("string",s.substring(start,i),s.substring(start+1,i-1)))}
        else if(c in '0'..'9'){while(i<s.length&&s[i] in '0'..'9')i++;val t=s.substring(start,i);a.add(Token("integer",t,t.toLong()))}
        else if(c.isLetter()||c=='_'){while(i<s.length&&(s[i].isLetterOrDigit()||s[i]=='_'))i++;val t=s.substring(start,i);val up=t.uppercase(Locale.ROOT);a.add(Token(if(up in reserved)"keyword" else "name",t,if(up in reserved)up else t))}
        else{var t=s.substring(i,minOf(i+2,s.length));if(t !in setOf("<>","!=","<=",">=","||"))t=c.toString();if(t.length==1&&c !in "(),.;*/%+-=<>")fail("unexpected character '$c'");a.add(Token("symbol",t,t));i+=t.length}
    };return a
}
private class Expr(val kind:String,val op:String="",val args:List<Expr> = emptyList(),val value:Any?=null){var table:String?=null;var column="";var text="";var index=-1;var distinct=false;var negated=false}
private data class Column(val name:String,val type:String,val primary:Int,val notNull:Boolean)
private data class TableRef(val name:String,val alias:String)
private data class Item(val expr:Expr,val alias:String?,val heading:String)
private data class Order(val expr:Expr,val descending:Boolean,val ordinal:Long?,val alias:String?)
private data class Join(val table:TableRef,val left:Boolean,val condition:Expr)
private class Query{
    var distinct=false;var star=false;val items=mutableListOf<Item>();lateinit var source:TableRef;val joins=mutableListOf<Join>();var where:Expr?=null;var having:Expr?=null;var group:List<Expr>?=null;val order=mutableListOf<Order>();var limit:Long?=null;var offset=0L
}
private class Command{
    var kind="";var name="";var columns=emptyList<Column>();var names:List<String>?=null;var tuples=emptyList<List<Expr>>();var assignments=emptyList<Pair<String,Expr>>();var where:Expr?=null;var query:Query?=null
}
private class Parser(val tokens:List<Token>){
    var position=0
    fun peek()=tokens[position]
    fun take()=tokens[position++]
    fun at(w:String):Boolean{val t=peek();return t.kind in setOf("keyword","symbol")&&t.value==w}
    fun accept(w:String):Boolean{if(!at(w))return false;position++;return true}
    fun syntax():Nothing=fail("syntax error at '${peek().text}'")
    fun expect(w:String){if(!accept(w))syntax()}
    fun name():String{if(peek().kind!="name")syntax();return take().value as String}
    fun integer():Long{if(peek().kind!="integer")syntax();return take().value as Long}
    fun <T> comma(read:()->T):List<T>{val a=mutableListOf(read());while(accept(","))a.add(read());return a}
    fun <T> parens(read:()->T):List<T>{expect("(");val a=comma(read);expect(")");return a}
    fun alias():String?=if(accept("AS"))name() else if(peek().kind=="name")name() else null
    fun table():TableRef{val n=name();return TableRef(n,alias()?:n)}
    fun reference():Expr{val n=name();val e=Expr("ref");if(accept(".")){e.table=n;e.column=name();e.text=n+"."+e.column}else{e.column=n;e.text=n};return e}
    fun expr(level:Int=0):Expr{
        if(level==2&&accept("NOT"))return Expr("unary","NOT",listOf(expr(2)));if(level==6&&accept("-"))return Expr("unary","-",listOf(expr(6)));if(level==7)return primary();var left=expr(level+1)
        if(level==3){if(peek().kind=="symbol"&&(peek().value as String) in comparisons){val op=take().value as String;return Expr("binary",op,listOf(left,expr(4)))};if(accept("IS")){val neg=accept("NOT");expect("NULL");return Expr("isnull",args=listOf(left)).also{it.negated=neg}};val neg=accept("NOT");var e:Expr?=null
            if(accept("IN"))e=Expr("in",args=listOf(left)+parens{expr()}) else if(accept("BETWEEN")){val low=expr(4);expect("AND");e=Expr("between",args=listOf(left,low,expr(4)))}else if(accept("LIKE"))e=Expr("like",args=listOf(left,expr(4)))else if(neg)syntax();if(e!=null){e.negated=neg;return e};return left
        }
        val ops=listOf(listOf("OR"),listOf("AND"),emptyList(),emptyList(),listOf("+","-","||"),listOf("*","/","%"),emptyList())
        while(ops[level].any{at(it)}){val op=take().value as String;left=Expr("binary",op,listOf(left,expr(level+1)))};return left
    }
    fun primary():Expr{val t=peek();if(t.kind=="integer"||t.kind=="string"){take();return Expr("literal",value=t.value)};if(accept("NULL"))return Expr("literal");if(t.kind=="name")return reference();if(t.kind=="keyword"&&(t.value as String) in aggregates){val n=take().value as String;expect("(");var distinct=false;val args=if(n=="COUNT"&&accept("*"))emptyList()else{distinct=accept("DISTINCT");listOf(expr())};expect(")");return Expr("aggregate",n,args).also{it.distinct=distinct}};if(accept("(")){val e=expr();expect(")");return Expr("group",args=listOf(e))};syntax()}
    fun clause(w:String):Expr?=if(accept(w))expr()else null
    fun item():Item{val start=position;val e=expr();val stop=position;val alias=alias();val heading=alias?:if(e.kind=="ref")e.column else buildString{for(i in start until stop){if(i>start&&tokens[i].kind!="symbol"&&tokens[i-1].kind!="symbol")append(' ');append(tokens[i].text)}};return Item(e,alias,heading)}
    fun orderItem():Order{val start=position;val e=expr();val single=position==start+1;val t=tokens[start];val desc=accept("DESC");if(!desc)accept("ASC");return Order(e,desc,if(single&&t.kind=="integer")t.value as Long else null,if(single&&t.kind=="name")t.value as String else null)}
    fun query():Query{val q=Query();q.distinct=accept("DISTINCT");q.star=accept("*");if(!q.star)q.items.addAll(comma{item()});expect("FROM");q.source=table();while(at("JOIN")||at("INNER")||at("LEFT")){val left=accept("LEFT");if(left)accept("OUTER")else accept("INNER");expect("JOIN");val t=table();expect("ON");q.joins.add(Join(t,left,expr()))};q.where=clause("WHERE");if(accept("GROUP")){expect("BY");q.group=comma{reference()}};q.having=clause("HAVING");if(accept("ORDER")){expect("BY");q.order.addAll(comma{orderItem()})};if(accept("LIMIT")){q.limit=integer();if(accept("OFFSET"))q.offset=integer()};return q}
    fun column():Column{val n=name();if(!at("INT")&&!at("TEXT"))syntax();val type=take().value as String;var pk=0;var nn=false;while(true){if(accept("PRIMARY")){expect("KEY");pk++;nn=true}else if(accept("NOT")){expect("NULL");nn=true}else break};return Column(n,type,pk,nn)}
    fun statement():Command{val c=Command();if(accept("CREATE")){c.kind="create";expect("TABLE");c.name=name();c.columns=parens{column()}}else if(accept("DROP")){c.kind="drop";expect("TABLE");c.name=name()}else if(accept("INSERT")){c.kind="insert";expect("INTO");c.name=name();if(at("("))c.names=parens{name()};expect("VALUES");c.tuples=comma{parens{expr()}}}else if(accept("UPDATE")){c.kind="update";c.name=name();expect("SET");c.assignments=comma{val n=name();expect("=");n to expr()};c.where=clause("WHERE")}else if(accept("DELETE")){c.kind="delete";expect("FROM");c.name=name();c.where=clause("WHERE")}else if(accept("SELECT")){c.kind="select";c.query=query()}else if(accept("EXIT"))c.kind="exit";expect(";");return c}
}
private typealias Row=List<Any?>
private class Table(val name:String,val columns:List<Column>,val key:Int){var rows=emptyList<Row>();fun column(n:String)=columns.indexOfFirst{it.name==n}}
private data class Entry(val name:String,val table:Table,val offset:Int)
private class Scope{
    val entries=mutableListOf<Entry>();var width=0
    fun add(n:String,t:Table){if(entries.any{it.name==n})fail("duplicate table name $n");entries.add(Entry(n,t,width));width+=t.columns.size}
    fun resolve(e:Expr):String{val found=mutableListOf<Pair<Int,String>>();var seen=false;for(p in entries)if(e.table==null||e.table==p.name){seen=true;val i=p.table.column(e.column);if(i>=0)found.add(p.offset+i to p.table.columns[i].type)};if(e.table!=null&&!seen)fail("unknown table ${e.table}");if(found.isEmpty())fail("unknown column ${e.text}");if(found.size>1)fail("ambiguous column ${e.column}");e.index=found[0].first;return found[0].second}
}
private fun compatible(a:String,b:String)=a==b||a=="NULL"||b=="NULL"
private fun requireType(a:String,b:String,op:String){if(!compatible(a,b))fail("type mismatch for $op")}
private fun check(e:Expr,s:Scope,allow:Boolean=false,grouped:List<Int>?=null,inside:Boolean=false):String{
    if(e.kind=="literal")return if(e.value==null)"NULL" else if(e.value is Long)"INT" else "TEXT";if(e.kind=="ref"){val t=s.resolve(e);if(grouped!=null&&!inside&&e.index !in grouped)fail("column ${e.text} is not grouped");return t}
    if(e.kind=="aggregate"){if(!allow||inside)fail("misuse of aggregate ${e.op}");if(e.args.isEmpty())return "INT";val t=check(e.args[0],s,allow,grouped,true);if(e.op=="SUM"||e.op=="AVG")requireType(t,"INT",e.op);return if(e.op=="MIN"||e.op=="MAX")t else "INT"}
    val ts=e.args.map{check(it,s,allow,grouped,inside)};if(e.kind=="group")return ts[0];if(e.kind=="isnull")return "INT";if(e.kind=="binary"&&e.op in comparisons){requireType(ts[0],ts[1],e.op);return "INT"};if(e.kind=="in"||e.kind=="between"){for(t in ts.drop(1))requireType(t,ts[0],if(e.kind=="in")"IN" else "BETWEEN");return "INT"};val op=if(e.kind=="like")"LIKE" else e.op;val t=if(op=="LIKE"||op=="||")"TEXT" else "INT";for(actual in ts)requireType(actual,t,op);return if(op=="||")"TEXT" else "INT"
}
private fun condition(e:Expr?,s:Scope,name:String,allow:Boolean=false,grouped:List<Int>?=null){if(e!=null)requireType(check(e,s,allow,grouped),"INT",name)}
private fun hasAggregate(e:Expr):Boolean=e.kind=="aggregate"||e.args.any{hasAggregate(it)}
private fun truth(v:Any?)=v!=null&&(v as Long)!=0L
private fun flag(b:Boolean)=if(b)1L else 0L
private fun inverse(v:Any?):Long?=if(v==null)null else flag(v==0L)
private fun compare(a:Any?,b:Any?):Int{if(a==b)return 0;if(a==null)return -1;if(b==null)return 1;return if(a is Long)a.compareTo(b as Long)else(a as String).compareTo(b as String)}
private fun operate(op:String,a:Any?,b:Any?):Any?{
    if(op=="AND")return if(a==0L||b==0L)0L else if(a==null||b==null)null else 1L;if(op=="OR")return if(truth(a)||truth(b))1L else if(a==null||b==null)null else 0L;if(a==null||b==null)return null;if(op in comparisons){val c=compare(a,b);return flag(when(op){"="->c==0;"<>","!="->c!=0;"<"->c<0;"<="->c<=0;">"->c>0;else->c>=0})};if(op=="||")return (a as String)+(b as String);val x=a as Long;val y=b as Long;return when(op){"+"->x+y;"-"->x-y;"*"->x*y;"/"->if(y==0L)null else x/y;"%"->if(y==0L)null else x%y;else->error("operator")}
}
private fun like(text:String,pattern:String):Boolean{val dp=BooleanArray(text.length+1);dp[0]=true;for(c in pattern){if(c=='%'){for(i in 1..text.length)dp[i]=dp[i]||dp[i-1]}else{for(i in text.length downTo 1)dp[i]=dp[i-1]&&(c=='_'||c==text[i-1]);dp[0]=false}};return dp[text.length]}
private fun evaluate(e:Expr,row:Row,group:List<Row>?=null):Any?{
    if(e.kind=="literal")return e.value;if(e.kind=="ref")return row[e.index];if(e.kind=="aggregate"){if(e.args.isEmpty())return group!!.size.toLong();var values=group!!.map{evaluate(e.args[0],it)}.filterNotNull();if(e.distinct)values=values.distinct();if(e.op=="COUNT")return values.size.toLong();if(values.isEmpty())return null;if(e.op=="MIN"||e.op=="MAX")return values.reduce{a,b->if((compare(a,b)<=0)==(e.op=="MIN"))a else b};val sum=values.sumOf{it as Long};return if(e.op=="AVG")sum/values.size else sum}
    val a=e.args.map{evaluate(it,row,group)};if(e.kind=="group")return a[0];if(e.kind=="unary")return if(e.op=="NOT")inverse(a[0])else if(a[0]==null)null else -(a[0] as Long);if(e.kind=="binary")return operate(e.op,a[0],a[1]);if(e.kind=="isnull")return flag((a[0]==null)!=e.negated)
    val result=when(e.kind){"in"->if(a[0]==null)null else if(a.drop(1).contains(a[0]))1L else if(a.drop(1).contains(null))null else 0L;"between"->operate("AND",operate(">=",a[0],a[1]),operate("<=",a[0],a[2]));else->if(a[0]==null||a[1]==null)null else flag(like(a[0] as String,a[1] as String))};return if(e.negated)inverse(result)else result
}
private fun satisfies(e:Expr?,r:Row,g:List<Row>?=null)=e==null||truth(evaluate(e,r,g))
private fun countRows(n:Int)="$n ${if(n==1)"row" else "rows"}"
private fun written(v:Any?)=v?.toString()?:"NULL"
private fun printTable(items:List<Item>,types:List<String>,rows:List<Row>){
    val widths=items.map{it.heading.length}.toIntArray();val cells=rows.map{r->r.map{written(it)}};for(r in cells)for(i in r.indices)widths[i]=maxOf(widths[i],r[i].length);val sep="+"+widths.joinToString(""){"-".repeat(it+2)+"+"}
    fun format(r:List<String>,header:Boolean)="|"+r.mapIndexed{i,v->" "+(if(!header&&types[i]=="INT")v.padStart(widths[i])else v.padEnd(widths[i]))+" |"}.joinToString("")
    println(sep);println(format(items.map{it.heading},true));println(sep);for(r in cells)println(format(r,false));println(sep);println("(${countRows(rows.size)})")
}
private class Database{
    val tables=mutableMapOf<String,Table>()
    fun table(n:String)=tables[n]?:fail("unknown table $n")
    fun targets(t:Table,names:List<String>):List<Int>{val a=mutableListOf<Int>();for(n in names){val i=t.column(n);if(i<0)fail("unknown column $n");if(i in a)fail("duplicate column $n");a.add(i)};return a}
    fun constraints(t:Table,rows:List<Row>,checked:List<Int>){for(i in checked){for((j,c)in t.columns.withIndex())if(c.notNull&&rows[i][j]==null)fail("NULL value in column ${c.name}");if(t.key>=0)for(j in rows.indices)if(i!=j&&rows[i][t.key]==rows[j][t.key])fail("duplicate primary key ${written(rows[i][t.key])}")}}
    fun execute(c:Command){
        if(c.kind=="select"){select(c.query!!);return};if(c.kind=="create"){if(tables.containsKey(c.name))fail("table ${c.name} already exists");val seen=mutableSetOf<String>();var primary=0;var key=-1;for((i,col)in c.columns.withIndex()){if(!seen.add(col.name))fail("duplicate column ${col.name}");primary+=col.primary;if(primary>=2)fail("multiple primary keys");if(col.primary>0)key=i};tables[c.name]=Table(c.name,c.columns,key);println("Table ${c.name} created.");return}
        val t=table(c.name);if(c.kind=="drop"){tables.remove(c.name);println("Table ${c.name} dropped.");return};val rows=mutableListOf<Row>();val checked=mutableListOf<Int>();var count=0
        if(c.kind=="insert"){
            val target=c.names?.let{targets(t,it)}?:t.columns.indices.toList();val empty=Scope();for(tuple in c.tuples){if(tuple.size!=target.size)fail("expected ${target.size} values, got ${tuple.size}");for((i,e)in tuple.withIndex()){val col=t.columns[target[i]];requireType(check(e,empty),col.type,"column ${col.name}")}};rows.addAll(t.rows)
            for(tuple in c.tuples){val r=MutableList<Any?>(t.columns.size){null};for((i,e)in tuple.withIndex())r[target[i]]=evaluate(e,emptyList());checked.add(rows.size);rows.add(r)};constraints(t,rows,checked);count=c.tuples.size
        }else if(c.kind=="update"){
            val target=targets(t,c.assignments.map{it.first});val scope=Scope();scope.add(t.name,t);for((i,a)in c.assignments.withIndex()){val col=t.columns[target[i]];requireType(check(a.second,scope),col.type,"column ${col.name}")};condition(c.where,scope,"WHERE")
            for((i,r)in t.rows.withIndex()){var next=r;if(satisfies(c.where,r)){val replacement=r.toMutableList();for((j,a)in c.assignments.withIndex())replacement[target[j]]=evaluate(a.second,r);next=replacement;checked.add(i);count++};rows.add(next)};constraints(t,rows,checked)
        }else{val scope=Scope();scope.add(t.name,t);condition(c.where,scope,"WHERE");for(r in t.rows)if(satisfies(c.where,r))count++ else rows.add(r)}
        t.rows=rows;println(countRows(count)+when(c.kind){"insert"->" inserted.";"update"->" updated.";else->" deleted."})
    }
    private data class Result(val values:Row,val keys:Row,val position:Int)
    fun select(q:Query){
        val scope=Scope();scope.add(q.source.alias,table(q.source.name));for(j in q.joins){scope.add(j.table.alias,table(j.table.name));condition(j.condition,scope,"ON")};condition(q.where,scope,"WHERE");val grouping=q.group?.map{scope.resolve(it);it.index}?:emptyList()
        if(q.star)for(p in scope.entries)for(c in p.table.columns){val e=Expr("ref");e.table=p.name;e.column=c.name;e.text=c.name;q.items.add(Item(e,null,c.name))};val aggregate=q.group!=null||q.having!=null||q.items.any{hasAggregate(it.expr)}||q.order.any{hasAggregate(it.expr)};val grouped=if(aggregate)grouping else null;val types=q.items.map{check(it.expr,scope,true,grouped)};condition(q.having,scope,"HAVING",true,grouped)
        val keys=q.order.map{o->var key:Expr?=null;if(o.ordinal!=null){val k=o.ordinal;if(k<1||k>q.items.size)fail("ORDER BY position $k is out of range");key=q.items[k.toInt()-1].expr}else if(o.alias!=null)key=q.items.firstOrNull{it.alias==o.alias}?.expr;if(key==null){check(o.expr,scope,true,grouped);key=o.expr};key}
        var rows=scope.entries[0].table.rows;for((ji,j)in q.joins.withIndex()){val t=scope.entries[ji+1].table;val next=mutableListOf<Row>();for(left in rows){var found=false;for(right in t.rows){val combined=left+right;if(satisfies(j.condition,combined)){next.add(combined);found=true}};if(j.left&&!found)next.add(left+List(t.columns.size){null})};rows=next};rows=rows.filter{satisfies(q.where,it)}
        val groups=if(!aggregate)rows.map{listOf(it)}else if(q.group==null)listOf(rows)else rows.groupBy{r->grouping.map{r[it]}}.values.toList();val results=mutableListOf<Result>()
        for(g in groups){val row=g.firstOrNull()?:emptyList();val context=if(aggregate)g else null;if(!satisfies(q.having,row,context))continue;results.add(Result(q.items.map{evaluate(it.expr,row,context)},keys.map{evaluate(it!!,row,context)},results.size))}
        results.sortWith{a,b->var result=0;for(i in keys.indices){result=compare(a.keys[i],b.keys[i]);if(result!=0){if(q.order[i].descending)result=-result;break}};if(result==0)a.position.compareTo(b.position)else result};val unique=if(q.distinct)results.distinctBy{it.values}else results;val first=minOf(q.offset,unique.size.toLong()).toInt();val end=q.limit?.let{minOf(unique.size.toLong(),first+it).toInt()}?:unique.size;printTable(q.items,types,unique.subList(first,end).map{it.values})
    }
}
fun main(){val source=System.`in`.bufferedReader().readText();val statements=mutableListOf<String>();var start=0;var i=0;while(i<source.length){if(source[i]=='\'')i=source.indexOf('\'',i+1)else if(source.startsWith("--",i)){val end=source.indexOf('\n',i);if(end<0)break;i=end}else if(source[i]==';'){statements.add(source.substring(start,i+1));start=i+1};i++};val db=Database();for(text in statements){try{val c=Parser(tokenize(text)).statement();if(c.kind=="exit")break;if(c.kind.isNotEmpty())db.execute(c)}catch(err:SqlError){println("ERROR: ${err.message}")}}}
