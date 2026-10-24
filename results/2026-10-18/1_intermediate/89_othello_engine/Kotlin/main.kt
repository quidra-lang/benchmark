import kotlin.math.max
val weights=intArrayOf(100,-20,10,5,5,10,-20,100,-20,-50,-2,-2,-2,-2,-50,-20,10,-2,-1,-1,-1,-1,-2,10,5,-2,-1,-1,-1,-1,-2,5,5,-2,-1,-1,-1,-1,-2,5,10,-2,-1,-1,-1,-1,-2,10,-20,-50,-2,-2,-2,-2,-50,-20,100,-20,10,5,5,10,-20,100)
val transforms="rot90 rot180 rot270 mirror flip diag anti".split(" ")
val zero="NEW DUMP SHOW SCORE LEGAL HISTORY SHEET STATS EVAL STABLE SOLVE".split(" ")
val numeric="UNDO REDO HINT PV AI ANALYZE RANDOM PERFT DIVIDE".split(" ")
val active="FLIPS MOVE PLAY HINT PV AI SOLVE AUTOPLAY RANDOM MC DIVIDE".split(" ")
val commands=(zero+numeric+"LOAD TRANSFORM AUTOPLAY MC FLIPS MOVE PLAY RECORD".split(" ")).toSet()
fun other(s:Char)=if(s=='B')'W'else 'B'
fun name(p:Int)="${'a'+p%8}${p/8+1}"
fun square(s:String)=(s[1]-'1')*8+s[0]-'a'
fun inside(r:Int,c:Int)=r in 0..7&&c in 0..7
fun initial():String {val b=CharArray(64){'.'};b[27]='W';b[36]='W';b[28]='B';b[35]='B';return b.concatToString()}
fun flips(b:String,s:Char,p:Int):List<Int>{if(b[p]!='.')return emptyList();val out=mutableListOf<Int>();val row=p/8;val col=p%8;for(dr in -1..1)for(dc in -1..1){if(dr==0&&dc==0)continue;var r=row+dr;var c=col+dc;val line=mutableListOf<Int>();while(inside(r,c)&&b[8*r+c]==other(s)){line+=8*r+c;r+=dr;c+=dc};if(line.isNotEmpty()&&inside(r,c)&&b[8*r+c]==s)out+=line};return out.sorted()}
fun legal(b:String,s:Char)=(0..63).filter{b[it]=='.'&&flips(b,s,it).isNotEmpty()}
fun place(b:String,s:Char,p:Int):String{val a=b.toCharArray();for(q in flips(b,s,p))a[q]=s;a[p]=s;return a.concatToString()}
fun terminal(b:String)=legal(b,'B').isEmpty()&&legal(b,'W').isEmpty()
fun gameOver(b:String):String{val x=b.count{it=='B'};val y=b.count{it=='W'};return "game over B $x W $y ${if(x>y)"winner B"else if(x<y)"winner W"else "draw"}"}
fun evaluate(b:String,s:Char):List<Int>{val w=(0..63).sumOf{if(b[it]==s)weights[it]else if(b[it]==other(s))-weights[it]else 0};val own=legal(b,s).size;val enemy=legal(b,other(s)).size;return listOf(w+10*(own-enemy),w,own,enemy)}
val searchCache=HashMap<Triple<String,Char,Int>,Int>();val perftCache=HashMap<Triple<String,Char,Int>,Int>()
fun search(b:String,s:Char,d:Int):Int{val key=Triple(b,s,d);searchCache[key]?.let{return it};val moves=legal(b,s);val o=other(s);val v=if(moves.isEmpty()&&legal(b,o).isEmpty())(if(d<0)1 else 1000)*(b.count{it==s}-b.count{it==o})else if(d==0)evaluate(b,s)[0]else if(moves.isEmpty())-search(b,o,if(d<0)-1 else d-1)else moves.maxOf{-search(place(b,s,it),o,if(d<0)-1 else d-1)};if(searchCache.size>300000)searchCache.clear();searchCache[key]=v;return v}
fun ranked(b:String,s:Char,d:Int)=legal(b,s).map{-search(place(b,s,it),other(s),if(d<0)-1 else d-1) to it}.sortedWith(compareByDescending<Pair<Int,Int>>{it.first}.thenBy{it.second})
fun variation(start:String,side:Char,depth:Int):Pair<List<String>,String>{var b=start;var s=side;var d=depth;val steps=mutableListOf<String>();while(d!=0&&!terminal(b)){val moves=ranked(b,s,d);if(moves.isEmpty())steps+="pass"else{val p=moves[0].second;steps+=name(p);b=place(b,s,p)};s=other(s);if(d>0)d--};return steps to b}
fun perft(b:String,s:Char,d:Int):Int{if(d==0)return 1;val key=Triple(b,s,d);perftCache[key]?.let{return it};val moves=legal(b,s);val o=other(s);val n=if(moves.isNotEmpty())moves.sumOf{perft(place(b,s,it),o,d-1)}else if(legal(b,o).isEmpty())1 else perft(b,o,d-1);if(perftCache.size>200000)perftCache.clear();perftCache[key]=n;return n}
fun stable(b:String):Pair<Int,Int>{val stable=BooleanArray(64);val axes=listOf(0 to 1,1 to 0,1 to 1,1 to -1);while(true){val found=mutableListOf<Int>();for(p in 0..63){if(b[p]=='.'||stable[p])continue;var ok=true;for((dr,dc) in axes){var full=true;var anchor=false;for(sign in listOf(-1,1)){var r=p/8+dr*sign;var c=p%8+dc*sign;if(!inside(r,c)||(stable[8*r+c]&&b[8*r+c]==b[p]))anchor=true;while(inside(r,c)){if(b[8*r+c]=='.')full=false;r+=dr*sign;c+=dc*sign}};if(!full&&!anchor){ok=false;break}};if(ok)found+=p};if(found.isEmpty())break;for(p in found)stable[p]=true};return (0..63).count{stable[it]&&b[it]=='B'} to (0..63).count{stable[it]&&b[it]=='W'}}
fun transform(p:Int,op:String):Int{val r=p/8;val c=p%8;return when(op){"rot90"->8*c+7-r;"rot180"->63-p;"rot270"->8*(7-c)+r;"mirror"->8*r+7-c;"flip"->8*(7-r)+c;"diag"->8*c+r;else->8*(7-c)+7-r}}
fun transformBoard(b:String,op:String):String{val a=CharArray(64);for(p in 0..63)a[transform(p,op)]=b[p];return a.concatToString()}
class Minstd(var value:Long){fun draw():Long{value=value*48271%2147483647;return value}}
fun randomGame(start:String,side:Char,rng:Minstd):String{var b=start;var s=side;while(true){val moves=legal(b,s);if(moves.isNotEmpty())b=place(b,s,moves[(rng.draw()%moves.size).toInt()])else if(legal(b,other(s)).isEmpty())return b;s=other(s)}}
fun average(f:Int,n:Int):String{val v=100*f/n;return "${v/100}.${(v%100).toString().padStart(2,'0')}"}
data class Position(val board:String,val side:Char,val over:Boolean)
data class Move(val side:Char,val square:Int,val count:Int,val passed:Boolean,val before:Position,val after:Position)
fun emit(vararg xs:Any)=println(xs.joinToString(" "))
class Othello{var board=initial();var side='B';var over=false;var history=mutableListOf<Move>();var redo=mutableListOf<Move>()
    fun reset(){board=initial();side='B';over=false;history.clear();redo.clear()}
    fun snapshot()=Position(board,side,over)
    fun restore(p:Position){board=p.board;side=p.side;over=p.over}
    fun status()=if(over)gameOver(board)else "$side to move"
    fun adjust(quiet:Boolean=false):Boolean{if(legal(board,side).isNotEmpty())return false;if(legal(board,other(side)).isNotEmpty()){if(!quiet)emit(side,"passes");side=other(side);return true};over=true;if(!quiet)emit(gameOver(board));return false}
    fun move(p:Int,quiet:Boolean=false,value:Int?=null):Boolean{val before=snapshot();val s=side;val k=flips(board,s,p).size;board=place(board,s,p);if(!quiet){if(value==null)emit(s,name(p),"flips",k)else emit(s,name(p),"flips",k,"value",value)};side=other(s);val passed=adjust(quiet);history+=Move(s,p,k,passed,before,snapshot());redo.clear();return passed}
    fun reason(p:Int)=if(over)"game over"else if(board[p]!='.')"occupied"else if(flips(board,side,p).isEmpty())"no flips"else ""
    fun record(text:String){val e=Othello();val ps=mutableListOf<Int>();var passes=0;for(i in text.indices step 2){val p=square(text.substring(i,i+2));val why=e.reason(p);if(why.isNotEmpty()){emit("ILLEGAL move",i/2+1,name(p),why);return};ps+=p;if(e.move(p,true))passes++};restore(e.snapshot());history=e.history;redo.clear();val op=when(name(ps[0])){"e6"->"diag";"d3"->"anti";"c4"->"rot180";else->""};emit("record",ps.size,"moves",passes,"passes");emit("normal",ps.joinToString(""){name(if(op.isEmpty())it else transform(it,op))});emit(status())}
    fun sheet(){val fields=(if(history.isEmpty())board else history[0].before.board).map{it.toString()}.toMutableList();history.forEachIndexed{i,r->fields[r.square]=(i+1).toString()};emit(" "+"abcdefgh".map{it.toString().padStart(3)}.joinToString(""));for(r in 0..7)emit((r+1).toString()+fields.subList(8*r,8*r+8).joinToString(""){it.padStart(3)})}
    fun stats(){val total=history.sumOf{it.count};if(history.isEmpty())emit("moves 0")else emit("moves",history.size,"flips",total,"avg",average(total,history.size),"passes",history.count{it.passed});for(s in listOf('B','W')){val rows=history.filter{it.side==s};if(rows.isEmpty()){emit(s,"moves 0");continue};val sum=rows.sumOf{it.count};val maximum=rows.maxOf{it.count};emit(s,"moves",rows.size,"flips",sum,"avg",average(sum,rows.size),"max",maximum,name(rows.first{it.count==maximum}.square),"corners",rows.count{it.square in listOf(0,7,56,63)})}}
    fun auto(black:Int,white:Int,seed:Long=0){val rng=Minstd(seed);val ps=mutableListOf<String>();var passes=0;while(!over){val moves=legal(board,side);val p=if(seed!=0L)moves[(rng.draw()%moves.size).toInt()]else ranked(board,side,if(side=='B')black else white)[0].second;ps+=name(p);if(move(p,true))passes++};emit(if(seed!=0L)"random"else "autoplay",ps.size,"moves",passes,"passes");emit("moves",ps.joinToString(""));emit(gameOver(board))}
    fun monteCarlo(k:Int,seed:Long){val rng=Minstd(seed);var best=-1;var bp=-1;for(p in legal(board,side)){var w=0;var d=0;var l=0;val start=place(board,side,p);repeat(k){val b=randomGame(start,other(side),rng);val diff=b.count{it==side}-b.count{it==other(side)};if(diff>0)w++ else if(diff<0)l++ else d++};emit(name(p),w,d,l);if(2*w+d>best){best=2*w+d;bp=p}};emit("best",name(bp),best)}
    fun execute(text:String){val words=text.split(' ');val cmd=words[0];val a=words.drop(1);var error=""
        if(cmd !in commands)error="unknown command"
        else if(cmd=="LOAD"){if(a.size!=2||!Regex("[.BW]{64}").matches(a[0])||a[1] !in listOf("B","W"))error="bad board"}
        else if(cmd in listOf("MOVE","FLIPS")){error=if(a.size!=1)"bad arguments"else if(!Regex("[a-h][1-8]").matches(a[0]))"bad square"else ""}
        else if(cmd in listOf("PLAY","RECORD")){error=if(a.size!=1)"bad arguments"else if(a[0].length>120||!Regex("([a-h][1-8])+").matches(a[0]))"bad record"else ""}
        else if(cmd in zero){if(a.isNotEmpty())error="bad arguments"}
        else if(cmd=="TRANSFORM"){if(a.size!=1||a[0] !in transforms)error="bad arguments"}
        else{val expected=if(cmd in listOf("AUTOPLAY","MC"))2 else 1;var valid=a.size==expected&&a.all{Regex("[0-9]+").matches(it)};if(valid){val ns=a.map{it.toLong()};val n=ns[0];valid=when(cmd){"AUTOPLAY"->ns.all{it in 1L..4L};"HINT","PV","AI","ANALYZE"->n in 1L..4L;"PERFT","DIVIDE"->n in 1L..8L;"MC"->n in 1L..100L&&ns[1] in 1L..2147483646L;"RANDOM"->n in 1L..2147483646L;else->n>=1}};if(!valid)error="bad arguments"}
        if(error.isNotEmpty()){emit("ERROR",error);return};if(over&&cmd in active){emit("ERROR game over");return};val n=a.firstOrNull()?.toIntOrNull()?:0
        when(cmd){
            "NEW"->{reset();emit("OK")}
            "LOAD"->{board=a[0];side=a[1][0];over=false;history.clear();redo.clear();emit("OK");adjust()}
            "DUMP"->emit("board",board,side)
            "SHOW"->{emit("  a b c d e f g h");val moves=if(over)emptyList()else legal(board,side);for(r in 0..7)emit((r+1).toString()+" "+(0..7).joinToString(" "){c->(if(8*r+c in moves)'*'else board[8*r+c]).toString()});emit(status())}
            "SCORE"->emit("score B",board.count{it=='B'},"W",board.count{it=='W'},"empty",board.count{it=='.'})
            "LEGAL"->{val moves=if(over)emptyList()else legal(board,side);emit((listOf("legal",moves.size.toString())+moves.map(::name)).joinToString(" "))}
            "MOVE","FLIPS"->{val p=square(a[0]);val why=reason(p);if(why.isNotEmpty())emit("ILLEGAL",why)else if(cmd=="MOVE")move(p)else{val f=flips(board,side,p);emit((listOf("flips",a[0],f.size.toString())+f.map(::name)).joinToString(" "))}}
            "PLAY"->{for(i in a[0].indices step 2){val p=square(a[0].substring(i,i+2));val why=reason(p);if(why.isNotEmpty()){emit("ILLEGAL move",i/2+1,name(p),why);break};move(p)}}
            "RECORD"->record(a[0])
            "UNDO"->{if(n>history.size)emit("ERROR cannot undo")else{val removed=history.takeLast(n);restore(removed[0].before);history=history.dropLast(n).toMutableList();redo=(removed+redo).toMutableList();emit(status())}}
            "REDO"->{if(n>redo.size)emit("ERROR cannot redo")else{val added=redo.take(n);redo=redo.drop(n).toMutableList();history.addAll(added);restore(added.last().after);emit(status())}}
            "HISTORY"->{emit("history",history.size);history.forEachIndexed{i,r->emit("${i+1} ${r.side} ${name(r.square)} ${r.count}"+(if(r.passed)" pass"else ""))}}
            "SHEET"->sheet();"STATS"->stats()
            "TRANSFORM"->{val op=a[0];board=transformBoard(board,op);fun tr(r:Move)=r.copy(square=transform(r.square,op),before=r.before.copy(board=transformBoard(r.before.board,op)),after=r.after.copy(board=transformBoard(r.after.board,op)));history=history.map(::tr).toMutableList();redo=redo.map(::tr).toMutableList();emit("OK")}
            "EVAL"->{val(v,w,x,y)=evaluate(board,side);emit("eval",v,"weights",w,"mobility",x,y)}
            "STABLE"->{val(b,w)=stable(board);emit("stable B",b,"W",w)}
            "HINT"->ranked(board,side,n).forEach{(v,p)->emit(name(p),v)}
            "PV"->{val(steps,_)=variation(board,side,n);emit((listOf("pv",search(board,side,n).toString())+steps).joinToString(" "))}
            "AI"->{val(v,p)=ranked(board,side,n)[0];move(p,false,v)}
            "ANALYZE"->{val loss=mutableMapOf('B' to 0,'W' to 0);history.forEachIndexed{i,r->val rows=ranked(r.before.board,r.side,n);val(best,bp)=rows[0];val v=rows.first{it.second==r.square}.first;loss[r.side]=loss.getValue(r.side)+best-v;emit(i+1,r.side,name(r.square),v,"best",name(bp),best)};emit("loss B",loss.getValue('B'),"W",loss.getValue('W'))}
            "SOLVE"->{if(board.count{it=='.'}>=9)emit("ERROR too many empties")else{ranked(board,side,-1).forEach{(v,p)->emit(name(p),v)};val(steps,b)=variation(board,side,-1);emit((listOf("line")+steps).joinToString(" "));emit("final B",b.count{it=='B'},"W",b.count{it=='W'})}}
            "AUTOPLAY"->auto(n,a[1].toInt());"RANDOM"->auto(0,0,n.toLong());"MC"->monteCarlo(n,a[1].toLong())
            "PERFT"->emit("perft",n,perft(board,side,n))
            "DIVIDE"->{var total=0;for(p in legal(board,side)){val v=perft(place(board,side,p),other(side),n-1);emit(name(p),v);total+=v};emit("total",total)}
        }
    }
}
fun main(){val n=readln().toInt();val e=Othello();repeat(n){e.execute(readln())}}
