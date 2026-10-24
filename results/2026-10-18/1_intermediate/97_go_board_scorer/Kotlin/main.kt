import java.util.Locale

const val columns="ABCDEFGHJKLMNOPQRST"
val handicapPoints=mapOf(9 to "C3 G7 C7 G3 C5 G5 E3 E7 E5".split(' '),13 to "D4 K10 D10 K4 D7 K7 G4 G10 G7".split(' '),19 to "D4 Q16 D16 Q4 D10 Q10 K4 K16 K10".split(' '))
val arity=mapOf("BOARD" to 2,"KOMI" to 1,"SUPERKO" to 1,"HANDICAP" to 1,"PLAY" to 2,"PASS" to 1,"REPLAY" to 1,"UNDO" to 0,"SHOW" to 0,"MAP" to 0,"STATUS" to 0,"CAPTURES" to 0,"HISTORY" to 0,"MOVES" to 0,"GROUP" to 1,"GROUPS" to 0,"ATARI" to 0,"LEGAL" to 1,"EYES" to 1,"SAFE" to 1,"LADDER" to 1,"DEAD" to 1,"REGIONS" to 0,"SCORE" to 1)
fun other(c:Char)=if(c=='B')'W' else 'B'
fun half(x:Int)=(if(x<0)"-" else "")+(kotlin.math.abs(x)/2)+(if(kotlin.math.abs(x)%2==0)".0" else ".5")
fun emit(vararg a:Any)=println(a.joinToString(" "))
fun komi(s:String):Int? {if(!Regex("-?(0|[1-9][0-9]*)(?:\\.[05])?").matches(s))return null;val negative=s.startsWith('-');val a=s.removePrefix("-").split('.');val whole=a[0].toIntOrNull()?:return null;if(whole>100)return null;val x=2*whole+if(a.size==2&&a[1]=="5")1 else 0;return if(negative&&x==0)null else if(negative)-x else x}
fun adjacent(p:Int,n:Int,diagonal:Boolean=false):List<Int> {val r=p/n;val c=p%n;val steps=if(diagonal)listOf(-1 to -1,-1 to 1,1 to -1,1 to 1) else listOf(-1 to 0,1 to 0,0 to -1,0 to 1);return steps.mapNotNull{(dr,dc)->if(r+dr in 0 until n&&c+dc in 0 until n)(r+dr)*n+c+dc else null}}
fun flood(b:String,n:Int,p:Int,allowed:String):Set<Int> {val seen=mutableSetOf(p);val todo=ArrayDeque<Int>();todo.add(p);while(todo.isNotEmpty())for(q in adjacent(todo.removeLast(),n))if(q !in seen&&b[q] in allowed){seen.add(q);todo.add(q)};return seen}
data class Group(val color:Char,val first:Int,val stones:Set<Int>,val liberties:Set<Int>)
fun group(b:String,n:Int,p:Int):Group {val s=flood(b,n,p,b[p].toString());val l=s.flatMap{q->adjacent(q,n).filter{b[it]=='.'}}.toSet();return Group(b[p],s.min(),s,l)}
fun groups(b:String,n:Int,color:Char?=null):List<Group> {val out=mutableListOf<Group>();val seen=mutableSetOf<Int>();for(p in b.indices)if(b[p]!='.'&&p !in seen&&(color==null||b[p]==color)){val g=group(b,n,p);seen.addAll(g.stones);out.add(g)};return out}
data class Placement(val board:String,val captured:Int,val reason:String)
fun placement(b:String,n:Int,c:Char,p:Int):Placement {if(b[p]!='.')return Placement(b,0,"occupied");val next=b.toCharArray();next[p]=c;var captured=0;val seen=mutableSetOf<Int>();for(q in adjacent(p,n))if(next[q]==other(c)&&q !in seen){val g=group(next.concatToString(),n,q);seen.addAll(g.stones);if(g.liberties.isEmpty()){for(t in g.stones)next[t]='.';captured+=g.stones.size}};val value=next.concatToString();return Placement(value,captured,if(group(value,n,p).liberties.isEmpty())"suicide" else "")}
data class Region(val first:Int,val points:Set<Int>,val owner:String)
fun regions(b:String,n:Int):List<Region> {val out=mutableListOf<Region>();val seen=mutableSetOf<Int>();for(p in b.indices)if(b[p]=='.'&&p !in seen){val points=flood(b,n,p,".");seen.addAll(points);val border=points.flatMap{q->adjacent(q,n).map{b[it]}}.filter{it!='.'}.toSet();out.add(Region(p,points,if(border.size==1)border.first().toString() else "neutral"))};return out}
fun safeGroups(b:String,n:Int,c:Char):List<Group> {
    val own=groups(b,n,c);val touch=mutableListOf<Set<Int>>();val vital=mutableListOf<Set<Int>>();val seen=mutableSetOf<Int>()
    for(p in b.indices)if(b[p]!=c&&p !in seen){val area=flood(b,n,p,"."+other(c));seen.addAll(area);val empty=area.filter{b[it]=='.'};touch.add(own.indices.filter{i->area.any{q->adjacent(q,n).any{it in own[i].stones}}}.toSet());vital.add(own.indices.filter{i->own[i].liberties.containsAll(empty)}.toSet())}
    val s=own.indices.toMutableSet();val t=touch.indices.toMutableSet();while(true){val before=s.size+t.size;s.removeAll{s0->t.count{j->s0 in vital[j]}<2};t.removeAll{j->!s.containsAll(touch[j])};if(before==s.size+t.size)break};return s.sorted().map{own[it]}
}
data class Reading(val success:Boolean,val move:Int=-1)
data class ReadKey(val board:String,val depth:Int,val defending:Boolean)
data class LadderResult(val status:String,val move:Int=-1)
fun ladder(b:String,n:Int,p:Int):LadderResult {
    val defender=b[p];val attacker=other(defender);val memo=mutableMapOf<ReadKey,Reading>()
    fun read(current:String,depth:Int,defending:Boolean):Reading {
        if(depth>=40)return Reading(defending);val key=ReadKey(current,depth,defending);memo[key]?.let{return it};val g=group(current,n,p);val candidates=g.liberties.toMutableSet();val seen=mutableSetOf<Int>()
        if(defending)for(q in g.stones)for(t in adjacent(q,n))if(current[t]==attacker&&t !in seen){val e=group(current,n,t);seen.addAll(e.stones);if(e.liberties.size==1)candidates.addAll(e.liberties)}
        for(q in candidates.sorted()){val next=placement(current,n,if(defending)defender else attacker,q);if(next.reason.isNotEmpty())continue;val success=if(defending){val count=group(next.board,n,p).liberties.size;count>=3||(count==2&&!read(next.board,depth+1,false).success)}else !read(next.board,depth+1,true).success;if(success){val r=Reading(true,q);memo[key]=r;return r}}
        val r=Reading(false);memo[key]=r;return r
    }
    val count=group(b,n,p).liberties.size;if(count>=3)return LadderResult("safe");val r=read(b,0,count==1);return LadderResult(if(if(count==1)r.success else !r.success)"escapes" else "captured",r.move)
}
data class Snapshot(val board:String,val turn:Char,val black:Int,val white:Int,val passes:Int,val over:Boolean)
data class Move(val color:Char,val point:Int,val captured:Int,val before:Snapshot)
class Game {
    var n=19;var komi2=13;var board=".".repeat(361);var turn='B';var captures=mutableMapOf('B' to 0,'W' to 0);var passes=0;var over=false;var superko=false
    var handicap=listOf<Int>();val history=mutableListOf<Move>();var positions=mutableListOf(board);val dead=mutableSetOf<Int>()
    fun reset(size:Int,k:Int){n=size;komi2=k;board=".".repeat(n*n);turn='B';captures=mutableMapOf('B' to 0,'W' to 0);passes=0;over=false;handicap=emptyList();history.clear();positions=mutableListOf(board);dead.clear()}
    fun point(s:String):Int {if(!Regex("[A-HJ-T](?:[1-9]|1[0-9])").matches(s))return -1;val c=columns.indexOf(s[0]);val r=s.substring(1).toInt();return if(c<n&&r<=n)(r-1)*n+c else -1}
    fun name(p:Int)=columns[p%n].toString()+(p/n+1)
    fun sgf(p:Int)=""+(97+p%n).toChar()+(97+n-1-p/n).toChar()
    fun check(c:Char,p:Int):Placement {val r=placement(board,n,c,p);var reason=r.reason;if(reason.isEmpty()&&positions.size>=2&&r.board==positions[positions.size-2])reason="ko";if(reason.isEmpty()&&superko&&r.board in positions)reason="superko";return r.copy(reason=reason)}
    fun move(c:Char,p:Int,checked:Placement?=null):Int {val before=Snapshot(board,turn,captures.getValue('B'),captures.getValue('W'),passes,over);var captured=0;if(p<0){passes++;if(passes==2)over=true}else{val r=checked?:check(c,p);board=r.board;captured=r.captured;captures[c]=captures.getValue(c)+captured;passes=0};turn=other(c);history.add(Move(c,p,captured,before));positions.add(board);dead.clear();return captured}
    fun clean()=board.mapIndexed{p,c->if(p in dead)'.' else c}.joinToString("")
    fun show(map:Boolean=false){val b=if(map)clean() else board;val chars=b.toCharArray();val stars=handicapPoints.getValue(n).filterIndexed{i,_->n==19||i<4||i==8}.map(::point).toSet();if(map)for(r in regions(b,n))for(p in r.points)chars[p]=when(r.owner){"B"->'x';"W"->'o';else->'.'};for(p in b.indices)if(b[p]!='.'){val c=if(b[p]=='B')'X' else 'O';chars[p]=if(!map&&p in dead)c.lowercaseChar() else c}else if(!map)chars[p]=if(p in stars)'+' else '.';val header="   "+columns.take(n).toList().joinToString(" ");emit(header);for(r in n downTo 1)emit(r.toString().padStart(2),chars.slice((r-1)*n until r*n).joinToString(" "),r);emit(header)}
    fun score(method:String){val b=clean();val territory=mutableMapOf('B' to 0,'W' to 0);val total=mutableMapOf<Char,Int>();for(r in regions(b,n))if(r.owner!="neutral")territory[r.owner[0]]=territory.getValue(r.owner[0])+r.points.size;for(c in "BW"){val fields=mutableListOf<Any>(c);if(method=="AREA"){val stones=b.count{it==c};total[c]=2*(stones+territory.getValue(c))+(if(c=='W')komi2 else 0);fields.addAll(listOf("stones",stones,"territory",territory.getValue(c)))}else{val prisoners=captures.getValue(c)+dead.count{board[it]==other(c)};total[c]=2*(territory.getValue(c)+prisoners)+(if(c=='W')komi2 else 0);fields.addAll(listOf("territory",territory.getValue(c),"prisoners",prisoners))};if(c=='W')fields.addAll(listOf("komi",half(komi2)));fields.addAll(listOf("total",half(total.getValue(c))));emit(*fields.toTypedArray())};val d=total.getValue('B')-total.getValue('W');emit("result",if(d>0)"B+"+half(d) else if(d<0)"W+"+half(-d) else "Draw")}
    fun execute(line:String){
        val words=line.split(' ');val c=words[0];val a=words.drop(1);if(c !in arity){emit("ERROR unknown command");return};if(a.size!=arity[c]){emit("ERROR bad arguments");return}
        val valid=when(c){"BOARD"->a[0] in setOf("9","13","19")&&komi(a[1])!=null;"KOMI"->komi(a[0])!=null;"SUPERKO"->a[0] in setOf("ON","OFF");"HANDICAP"->Regex("[2-9]").matches(a[0]);"PLAY","PASS","LEGAL","EYES","SAFE"->a[0] in setOf("B","W");"SCORE"->a[0] in setOf("AREA","TERRITORY");else->true};if(!valid){emit("ERROR bad arguments");return}
        var p=-1;if(c in setOf("PLAY","GROUP","LADDER","DEAD")){p=point(a[if(c=="PLAY")1 else 0]);if(p<0){emit("ERROR bad point");return}}
        val records=mutableListOf<Pair<Char,Int>>();if(c=="REPLAY"){if(!Regex("(?:;[BW]\\[[a-z]{0,2}\\])+").matches(a[0])){emit("ERROR bad sequence");return};for(m in Regex(";([BW])\\[([a-z]*)\\]").findAll(a[0])){val text=m.groupValues[2];if(text.isNotEmpty()&&(text.length!=2||text.any{it-'a'>=n})){emit("ERROR bad sequence");return};records.add(m.groupValues[1][0] to if(text.isEmpty())-1 else (n-1-(text[1]-'a'))*n+(text[0]-'a'))}}
        if(c in setOf("PLAY","PASS","REPLAY")&&over){emit("ERROR game over");return}
        when(c){
            "BOARD"->{reset(a[0].toInt(),komi(a[1])!!);emit("board",n,"komi",half(komi2))}
            "KOMI"->{komi2=komi(a[0])!!;emit("komi",half(komi2))}
            "SUPERKO"->{superko=a[0]=="ON";emit("superko",if(superko)"on" else "off")}
            "HANDICAP"->{if(history.isNotEmpty()||board.any{it!='.'}){emit("ERROR handicap not allowed");return};val k=a[0].toInt();val ix=if(k==5)listOf(0,1,2,3,8) else if(k==7)listOf(0,1,2,3,4,5,8) else (0 until k).toList();handicap=ix.map{point(handicapPoints.getValue(n)[it])};val b=board.toCharArray();for(q in handicap)b[q]='B';board=b.concatToString();turn='W';positions=mutableListOf(board);dead.clear();emit("handicap",k,*handicap.map(::name).toTypedArray())}
            "PLAY"->{val color=a[0][0];val r=check(color,p);val reason=if(color!=turn)"turn" else r.reason;if(reason.isNotEmpty())emit("ILLEGAL",color,a[1],reason) else {val count=move(color,p,r);if(count==0)emit(color,a[1]) else emit(color,a[1],"captures",count)}}
            "PASS"->{if(a[0][0]!=turn)emit("ILLEGAL",a[0],"pass turn") else {move(a[0][0],-1);emit(a[0],"pass");if(over)emit("game over")}}
            "REPLAY"->{var played=0;var stop=listOf<Any>();for((color,q) in records){val next=if(q<0)null else check(color,q);val reason=if(over)"game over" else if(color!=turn)"turn" else next?.reason?:"";if(reason.isNotEmpty()){stop=listOf("stopped",color,if(q<0)"pass" else name(q),reason);break};move(color,q,next);played++};emit("replay",played,"moves",*stop.toTypedArray());if(over)emit("game over")}
            "UNDO"->{if(history.isEmpty()){emit("ERROR nothing to undo");return};val m=history.removeLast();val s=m.before;board=s.board;turn=s.turn;captures=mutableMapOf('B' to s.black,'W' to s.white);passes=s.passes;over=s.over;positions.removeLast();dead.clear();emit("undo",m.color,if(m.point<0)"pass" else name(m.point))}
            "SHOW"->show();"MAP"->show(true)
            "STATUS"->{emit("size",n,"komi",half(komi2),"handicap",handicap.size,"superko",if(superko)"on" else "off");if(over)emit("moves",history.size,"game over") else emit("moves",history.size,"next",turn,"passes",passes)}
            "CAPTURES"->emit("captures B",captures.getValue('B'),"W",captures.getValue('W'))
            "HISTORY"->{emit("history",history.size);for((i,m) in history.withIndex()){val row=mutableListOf<Any>(i+1,m.color,if(m.point<0)"pass" else name(m.point));if(m.captured>0)row.addAll(listOf("captures",m.captured));emit(*row.toTypedArray())}}
            "MOVES"->{val s=StringBuilder("(;GM[1]FF[4]SZ[$n]KM[${half(komi2)}]");if(handicap.isNotEmpty()){s.append("HA[${handicap.size}]AB");for(q in handicap)s.append('[').append(sgf(q)).append(']')};for(m in history)s.append(';').append(m.color).append('[').append(if(m.point<0)"" else sgf(m.point)).append(']');emit(s.append(')'))}
            "GROUP","DEAD","LADDER"->{if(board[p]=='.'){emit("ERROR no stone");return};val g=group(board,n,p);when(c){"GROUP"->{emit("group",g.color,name(g.first),"size",g.stones.size,"liberties",g.liberties.size);emit("stones",*g.stones.sorted().map(::name).toTypedArray());emit("liberties",*g.liberties.sorted().map(::name).toTypedArray())};"DEAD"->{val alive=p in dead;if(alive)dead.removeAll(g.stones) else dead.addAll(g.stones);emit(if(alive)"alive" else "dead",g.color,name(g.first),"size",g.stones.size)};else->{val r=ladder(board,n,p);if(r.move<0)emit("ladder",a[0],r.status) else emit("ladder",a[0],r.status,name(r.move))}}}
            "GROUPS"->{val gs=groups(board,n);emit("groups",gs.size);for(g in gs){val row=mutableListOf<Any>(g.color,name(g.first),"size",g.stones.size,"liberties",g.liberties.size);if(g.first in dead)row.add("dead");emit(*row.toTypedArray())}}
            "ATARI"->{val gs=groups(board,n).filter{it.liberties.size==1};if(gs.isEmpty())emit("atari none");for(g in gs)emit("atari",g.color,name(g.first),"size",g.stones.size,"at",name(g.liberties.first()))}
            "LEGAL"->{val rejected=mutableListOf<Pair<String,String>>();var count=0;for(q in board.indices)if(board[q]=='.'){val reason=check(a[0][0],q).reason;if(reason.isEmpty())count++ else rejected.add(name(q) to reason)};emit("legal",a[0],count);for((q,reason) in rejected)emit(q,reason)}
            "EYES"->{val found=mutableListOf<Pair<String,String>>();for(q in board.indices)if(board[q]=='.'){val ns=adjacent(q,n);if(ns.all{board[it]==a[0][0]}){val enemies=adjacent(q,n,true).count{board[it]==other(a[0][0])};found.add(name(q) to if(enemies<=if(ns.size==4)1 else 0)"real" else "false")}};emit("eyes",a[0],found.size);for((q,kind) in found)emit(q,kind)}
            "SAFE"->{val gs=safeGroups(board,n,a[0][0]);emit("safe",a[0],gs.size);for(g in gs)emit(name(g.first),"size",g.stones.size)}
            "REGIONS"->{val rs=regions(clean(),n);emit("regions",rs.size);for(r in rs)emit(name(r.first),"size",r.points.size,r.owner)}
            "SCORE"->score(a[0])
        }
    }
}
fun main(){val input=System.`in`.bufferedReader();val game=Game();repeat(input.readLine().toInt()){game.execute(input.readLine())}}
