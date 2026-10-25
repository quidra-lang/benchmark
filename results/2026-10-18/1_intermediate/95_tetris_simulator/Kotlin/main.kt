import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

private val kinds = "IOTSZJL"
private val operationNames = listOf("L", "R", "LL", "RR", "SD", "DD", "CW", "CCW", "HD", "LOCK", "HOLD")
private val commandNames = setOf("NEW", "PRINT", "NEXT", "PREVIEW", "STATUS", "ANALYZE", "ROW", "GARBAGE", "ATTACK", "TICK", "UNDO", "SAVE", "LOAD", "SPINS", "HINT", "AUTO")
private val afterEnd = setOf("PRINT", "NEXT", "PREVIEW", "STATUS", "ANALYZE", "LOAD")
private val states = "0R2L"
private val clearNames = listOf("SINGLE", "DOUBLE", "TRIPLE", "TETRIS", "TSPIN_MINI", "TSPIN_MINI_SINGLE", "TSPIN_MINI_DOUBLE", "TSPIN", "TSPIN_SINGLE", "TSPIN_DOUBLE", "TSPIN_TRIPLE")
private val frames = listOf(
    listOf("....", "####", "....", "...."), listOf("##", "##"), listOf(".#.", "###", "..."),
    listOf(".##", "##.", "..."), listOf("##.", ".##", "..."), listOf("#..", "###", "..."), listOf("..#", "###", "...")
)
private val ordinaryKicks = arrayOf(
    arrayOf(0 to 0,-1 to 0,-1 to 1,0 to -2,-1 to -2),
    arrayOf(0 to 0,1 to 0,1 to -1,0 to 2,1 to 2),
    arrayOf(0 to 0,1 to 0,1 to -1,0 to 2,1 to 2),
    arrayOf(0 to 0,-1 to 0,-1 to 1,0 to -2,-1 to -2),
    arrayOf(0 to 0,1 to 0,1 to 1,0 to -2,1 to -2),
    arrayOf(0 to 0,-1 to 0,-1 to -1,0 to 2,-1 to 2),
    arrayOf(0 to 0,-1 to 0,-1 to -1,0 to 2,-1 to 2),
    arrayOf(0 to 0,1 to 0,1 to 1,0 to -2,1 to -2)
)
private val iKicks = arrayOf(
    arrayOf(0 to 0,-2 to 0,1 to 0,-2 to -1,1 to 2),
    arrayOf(0 to 0,2 to 0,-1 to 0,2 to 1,-1 to -2),
    arrayOf(0 to 0,-1 to 0,2 to 0,-1 to 2,2 to -1),
    arrayOf(0 to 0,1 to 0,-2 to 0,1 to -2,-2 to 1),
    arrayOf(0 to 0,2 to 0,-1 to 0,2 to 1,-1 to -2),
    arrayOf(0 to 0,-2 to 0,1 to 0,-2 to -1,1 to 2),
    arrayOf(0 to 0,1 to 0,-2 to 0,1 to -2,-2 to 1),
    arrayOf(0 to 0,-1 to 0,2 to 0,-1 to 2,2 to -1)
)
private val kickStates = arrayOf(0 to 1,1 to 0,1 to 2,2 to 1,2 to 3,3 to 2,3 to 0,0 to 3)
private val shapes: List<List<List<Pair<Int, Int>>>> = frames.map { frame ->
    val size = frame.size
    var cells = frame.flatMapIndexed { row, line -> line.mapIndexedNotNull { col, ch -> if (ch == '#') col to row else null } }
    buildList {
        add(cells)
        repeat(3) {
            cells = cells.map { (x,y) -> (size - 1 - y) to x }
            add(cells)
        }
    }
}
private val output = mutableListOf<String>()
private fun emit(text: String) {output.add(text)}
private data class Pos(val s: Int, val x: Int, val y: Int)
private data class Movement(val pos: Pos, val test: Int)
private data class Metrics(val heights: IntArray,val holes: Int,val bump: Int,val value: Int)
private data class ClearInfo(val name: Int,val points: Int,val sent: Int)
private data class Stats(
    var drops: Int=0,var holds: Int=0,var operations: Int=0,var faults: Int=0,var perfect: Int=0,
    var sent: Int=0,var cancelled: Int=0,var received: Int=0,var combo: Int=0,var chain: Int=0,
    val kinds: IntArray=IntArray(7),val clears: IntArray=IntArray(11)
) {
    fun snapshot() = copy(kinds=kinds.clone(),clears=clears.clone())
}
private data class State(
    var board: IntArray=IntArray(22),var random: Long,var queue: MutableList<Int> = mutableListOf(),
    var hold: Int?=null,var usedHold: Boolean=false,var kind: Int=0,var pos: Pos=Pos(0,4,22),
    var last: Int=0,var test: Int=0,var keys: Int=0,var drop: Int=0,var fall: Int=0,
    var ground: Int=0,var resets: Int=0,var lowest: Int=0,var initialLevel: Int,var level: Int,
    var score: Int=0,var lines: Int=0,var pieces: Int=0,var streak: Int=0,var chain: Int=0,
    var pending: MutableList<Int> = mutableListOf(),var ended: Boolean=false,var stats: Stats=Stats()
) {
    fun snapshot() = copy(board=board.clone(),queue=queue.toMutableList(),pending=pending.toMutableList(),stats=stats.snapshot())
}
private data class Save(val state: State,val history: List<State>,val start: State)
private data class Route(val pos: Pos,val parent: Int,val op: Int)
private data class Candidate(val kind: Int,val value: Int,val ops: List<Int>,val occupied: List<Int>,var order: Int=0)
private data class SpinCandidate(val pos: Pos,val spin: Int)
private class GameOver : RuntimeException()
private fun seedStep(x: Long): Long = x*48271L%2147483647L
private fun spawn(kind: Int) = Pos(0,if(kind==1)5 else 4,22)
private fun cells(kind: Int,p: Pos) = shapes[kind][p.s].map { (x,y) -> (p.x+x) to (p.y-y) }
private fun lowest(kind: Int,p: Pos) = cells(kind,p).minOf {it.second}
private fun bag(seed: Long): Pair<Long,List<Int>> {
    var random=seed
    val pieces=(0..6).toMutableList()
    for(i in 6 downTo 1) {
        random=seedStep(random)
        val j=(random%(i+1)).toInt()
        val temp=pieces[i];pieces[i]=pieces[j];pieces[j]=temp
    }
    return random to pieces
}
private fun fits(board: IntArray,kind: Int,p: Pos): Boolean = cells(kind,p).all { (x,y) ->
    x in 1..10 && y in 1..22 && (board[y-1] and (1 shl (x-1)))==0
}
private fun move(board: IntArray,kind: Int,p: Pos,op: Int): Movement? {
    if(op==6||op==7) {
        val b=(p.s+if(op==6)1 else 3)%4
        val row=kickStates.indexOfFirst {it.first==p.s&&it.second==b}
        val offsets=if(kind==1)arrayOf(0 to 0)else(if(kind==0)iKicks else ordinaryKicks)[row]
        for((index,d) in offsets.withIndex()) {
            val q=Pos(b,p.x+d.first,p.y+d.second)
            if(fits(board,kind,q))return Movement(q,index+1)
        }
        return null
    }
    val dx=when(op){0,2->-1;1,3->1;else->0}
    val dy=if(dx==0)-1 else 0
    val repeated=op==2||op==3||op==5
    var q=p
    var changed=false
    do {
        val next=Pos(p.s,q.x+dx,q.y+dy)
        if(!fits(board,kind,next))break
        q=next
        changed=true
    }while(repeated)
    return if(changed)Movement(q,0)else null
}
private fun landing(board: IntArray,kind: Int,p: Pos) = move(board,kind,p,5)?.pos?:p
private fun placed(board: IntArray,kind: Int,p: Pos):Pair<IntArray,Int> {
    val result=board.clone()
    for((x,y) in cells(kind,p))result[y-1]=result[y-1] or (1 shl (x-1))
    val rest=result.filter{it!=1023}
    val cleared=22-rest.size
    return (rest+List(cleared){0}).toIntArray() to cleared
}
private fun evaluate(board: IntArray,n: Int):Metrics {
    val heights=IntArray(10)
    var holes=0
    for(c in 0..9) {
        for(r in 21 downTo 0)if((board[r] and (1 shl c))!=0){heights[c]=r+1;break}
        for(r in 0 until heights[c])if((board[r] and (1 shl c))==0)holes++
    }
    var bump=0
    for(c in 0..8)bump+=abs(heights[c]-heights[c+1])
    return Metrics(heights,holes,bump,76*n-51*heights.sum()-36*holes-18*bump)
}
private fun routes(board: IntArray,kind: Int,start: Pos,target:Pos?=null):Pair<List<Route>,Int?> {
    if(!fits(board,kind,start))return emptyList<Route>() to null
    val entries=mutableListOf(Route(start,-1,-1))
    val seen=hashSetOf(start)
    var i=0
    while(i<entries.size) {
        val entry=entries[i]
        if(target!=null&&landing(board,kind,entry.pos)==target)return entries to i
        for(op in 0..7) {
            val result=move(board,kind,entry.pos,op)?:continue
            if(seen.add(result.pos))entries.add(Route(result.pos,i,op))
        }
        i++
    }
    return (if(target==null)entries else emptyList<Route>()) to null
}
private fun shortest(nodes:List<Route>,index:Int):List<Int> {
    val ops=mutableListOf<Int>()
    var i=index
    while(nodes[i].parent>=0) {
        ops.add(nodes[i].op)
        i=nodes[i].parent
    }
    ops.reverse()
    return ops
}
private fun tSpin(board: IntArray,p: Pos,test: Int):Int {
    val corners=listOf(p.x to p.y,(p.x+2) to p.y,(p.x+2) to (p.y-2),p.x to (p.y-2))
    val blocked=corners.map { (x,y) -> x<1||x>10||y<1||y>22||(board[y-1] and (1 shl (x-1)))!=0 }
    if(blocked.count{it}<3)return 0
    return if((blocked[p.s]&&blocked[(p.s+1)%4])||test==5)2 else 1
}
private fun clearInfo(spin:Int,lines:Int):ClearInfo = when(spin) {
    2->ClearInfo(7+lines,intArrayOf(400,800,1200,1600)[lines],intArrayOf(0,2,4,6)[lines])
    1->ClearInfo(4+lines,intArrayOf(100,200,400)[lines],intArrayOf(0,0,1)[lines])
    else->ClearInfo(if(lines==0)-1 else lines-1,intArrayOf(0,100,300,500,800)[lines],intArrayOf(0,0,1,2,4)[lines])
}
private fun operationsText(ops:List<Int>)=ops.joinToString(" "){operationNames[it]}
private class Game(val number:Int,seed:Int,level:Int){
    var s=State(random=seed.toLong(),initialLevel=level,level=level)
    var history=mutableListOf<State>()
    var start:State
    val saves=mutableMapOf<String,Save>()
    init { addBag(); spawnPiece(takeNext());start=s.snapshot() }
    private fun addBag() {
        val (random,pieces)=bag(s.random)
        s.random=random
        s.queue.addAll(pieces)
    }
    private fun takeNext():Int {
        val kind=s.queue.removeAt(0)
        if(s.queue.size<5)addBag()
        return kind
    }
    private fun spawnPiece(kind:Int) {
        s.kind=kind;s.pos=spawn(kind);s.last=0;s.test=0;s.keys=0;s.drop=0;s.fall=0;s.ground=0;s.resets=0;s.lowest=lowest(kind,s.pos)
        if(!fits(s.board,kind,s.pos))gameOver("block out")
    }
    private fun gameOver(reason:String):Nothing { emit("game over $reason");summary();s.ended=true;throw GameOver() }
    private fun update(p:Pos,last:Int,test:Int=0) {
        s.pos=p;s.last=last;s.test=test
        val row=lowest(s.kind,p)
        if(row<s.lowest){s.lowest=row;s.resets=0}
    }
    private fun grounded()=move(s.board,s.kind,s.pos,4)==null
    private fun drops(points:Int){s.score+=points;s.drop+=points;s.stats.drops+=points}
    private fun insertGarbage(count:Int,hole:Int) {
        if(s.board.takeLast(count).any{it!=0})gameOver("top out")
        s.board=(List(count){1023 xor (1 shl (hole-1))}+s.board.take(22-count)).toIntArray()
    }
    fun operation(op:Int) {
        if(op in 0..7) {
            s.keys++
            val next=move(s.board,s.kind,s.pos,op)
            if(next==null){emit("fail ${operationNames[op]}");return}
            if(op==4||op==5){drops(s.pos.y-next.pos.y);update(next.pos,1);s.fall=0;s.ground=0}
            else{update(next.pos,if(op>=6)2 else 1,next.test);if(s.ground>0&&s.resets<15){s.ground=0;s.resets++}}
        }else if(op==8){
            val landed=landing(s.board,s.kind,s.pos)
            val rows=s.pos.y-landed.y
            drops(2*rows)
            if(rows>0)update(landed,1)
            lock()
        }else if(op==9){if(grounded())lock()else emit("fail LOCK")}
        else{
            if(s.usedHold){emit("fail HOLD");return}
            s.usedHold=true;s.stats.holds++
            val previous=s.hold;s.hold=s.kind
            spawnPiece(previous?:takeNext())
        }
    }
    private fun tick() {
        if(!grounded()) {
            s.ground=0;s.fall++
            val interval=if(s.level>=13)1 else intArrayOf(60,48,37,28,21,16,11,8,6,4,3,2)[s.level-1]
            if(s.fall>=interval){update(s.pos.copy(y=s.pos.y-1),1);s.fall=0}
        }else{s.ground++;if(s.ground>=30)lock()}
    }
    private fun lock() {
        val kind=s.kind;val position=s.pos;val oldCells=cells(kind,position)
        val route=routes(s.board,kind,spawn(kind),position)
        val shortestOps=route.second?.let{shortest(route.first,it)}
        val spin=if(kind==2&&s.last==2)tSpin(s.board,position,s.test)else 0
        val (board,n)=placed(s.board,kind,position)
        s.board=board
        history.add(start.snapshot())
        s.pieces++;s.stats.kinds[kind]++;s.stats.operations+=s.keys
        val info=clearInfo(spin,n)
        val level=s.level
        var points=info.points*level
        var sent=info.sent
        var back=false
        if(n>0){s.streak++;if(n==4||spin!=0){s.chain++;back=s.chain>=2}else s.chain=0}else s.streak=0
        if(back){points=points*3/2;sent++}
        val combo=s.streak-1
        val comboPoints=if(combo>=1)50*combo*level else 0
        if(combo>=0)sent+=intArrayOf(0,1,1,2,2,3,3,4,4,4,5)[min(combo,10)]
        val perfect=n>0&&s.board.all{it==0}
        val perfectPoints=if(perfect)(if(n==4&&back)3200 else intArrayOf(800,1200,1800,2000)[n-1])*level else 0
        if(perfect){sent+=10;s.stats.perfect++}
        val gained=points+comboPoints+perfectPoints
        s.score+=gained;s.lines+=n;s.stats.sent+=sent
        s.stats.combo=max(s.stats.combo,combo);s.stats.chain=max(s.stats.chain,s.chain)
        emit("lock ${s.pieces} ${kinds[kind]} ${states[position.s]} ${position.x} ${position.y} keys ${s.keys} ${shortestOps?.size?:"-"} drop ${s.drop} lines $n sent $sent +$gained total ${s.score}")
        if(shortestOps!=null&&s.keys>shortestOps.size){s.stats.faults++;emit("finesse ${if (shortestOps.isEmpty()) "none" else operationsText(shortestOps)}")}
        if(info.name>=0) {
            s.stats.clears[info.name]++
            val line=buildString {
                append("clear ${clearNames[info.name]} $points")
                if(back)append(" b2b")
                if(combo>=1)append(" combo $combo $comboPoints")
                if(perfect)append(" perfect $perfectPoints")
            }
            emit(line)
        }
        val nextLevel=s.initialLevel+s.lines/10
        if(nextLevel>level){s.level=nextLevel;emit("level ${s.level}")}
        if(oldCells.all{it.second>=21})gameOver("lock out")
        val cancelled=min(sent,s.pending.sum())
        var remaining=cancelled
        while(remaining>0) {
            val used=min(remaining,s.pending[0]);remaining-=used;s.pending[0]-=used
            if(s.pending[0]==0)s.pending.removeAt(0)
        }
        if(cancelled>0){s.stats.cancelled+=cancelled;emit("cancel $cancelled pending ${s.pending.sum()}")}
        if(n==0){
            var risen=0
            while(s.pending.isNotEmpty()&&risen<8){
                val count=min(s.pending[0],8-risen)
                s.random=seedStep(s.random)
                val hole=(s.random%10).toInt()+1
                insertGarbage(count,hole)
                s.stats.received+=count;risen+=count;s.pending[0]-=count
                if(s.pending[0]==0)s.pending.removeAt(0)
                emit("rise $count hole $hole pending ${s.pending.sum()}")
            }
        }
        s.usedHold=false
        spawnPiece(takeNext())
        start=s.snapshot()
    }
    private fun candidates(kind:Int,start:Pos,prefix:List<Int>):List<Candidate>{
        val result=mutableListOf<Candidate>()
        val seen=mutableSetOf<List<Int>>()
        for(turns in listOf(emptyList(),listOf(6),listOf(6,6),listOf(7))) {
            var p=start
            var valid=true
            for(op in turns){val next=move(s.board,kind,p,op);if(next==null){valid=false;break};p=next.pos}
            if(!valid)continue
            fun add(q:Pos,shifts:List<Int>){
                val landed=landing(s.board,kind,q)
                val occupied=cells(kind,landed).map{(it.second-1)*10+it.first-1}.sorted()
                if(!seen.add(occupied))return
                val (board,lines)=placed(s.board,kind,landed)
                result.add(Candidate(kind,evaluate(board,lines).value,prefix+turns+shifts+8,occupied))
            }
            add(p,emptyList())
            for(direction in 0..1){
                var q=p
                val shifts=mutableListOf<Int>()
                while(true){
                    val next=move(s.board,kind,q,direction)?:break
                    q=next.pos;shifts.add(direction);add(q,shifts)
                }
            }
        }
        return result
    }
    private fun ranked():List<Candidate>{
        val result=candidates(s.kind,s.pos,emptyList()).toMutableList()
        val held=s.hold?:s.queue[0]
        if(!s.usedHold&&fits(s.board,held,spawn(held)))result.addAll(candidates(held,spawn(held),listOf(10)))
        for((i,c)in result.withIndex())c.order=i
        return result.sortedWith(compareByDescending<Candidate>{it.value}.thenBy{it.order})
    }
    private fun spins(){
        if(s.kind!=2){emit("spins 0");return}
        val found=mutableMapOf<Pos,Int>()
        for(entry in routes(s.board,2,s.pos).first)for(op in 6..7){
            val next=move(s.board,2,entry.pos,op)?:continue
            if(move(s.board,2,next.pos,4)!=null)continue
            val spin=tSpin(s.board,next.pos,next.test)
            if(spin!=0)found[next.pos]=max(found[next.pos]?:0,spin)
        }
        val rows=found.map{SpinCandidate(it.key,it.value)}.sortedWith(compareBy<SpinCandidate>{it.pos.y}.thenBy{it.pos.x}.thenBy{it.pos.s})
        for(c in rows){val lines=placed(s.board,2,c.pos).second;val info=clearInfo(c.spin,lines);emit("spin ${states[c.pos.s]} ${c.pos.x} ${c.pos.y} ${clearNames[info.name]}")}
        emit("spins ${rows.size}")
    }
    fun summary(){
        val a=s.stats;val c=a.clears
        fun ratio(x:Int,y:Int):String {val q=if(y==0)0 else 100*x/y;return "%d.%02d".format(Locale.US,q/100,q%100)}
        emit("summary game $number score ${s.score} level ${s.level} lines ${s.lines} pieces ${s.pieces}")
        emit("clears single ${c[0]} double ${c[1]} triple ${c[2]} tetris ${c[3]} perfect ${a.perfect}")
        emit("tspins mini ${c[4]} mini_single ${c[5]} mini_double ${c[6]} zero ${c[7]} single ${c[8]} double ${c[9]} triple ${c[10]}")
        emit("pieces "+kinds.indices.joinToString(" "){"${kinds[it]} ${a.kinds[it]}"})
        emit("best combo ${a.combo} chain ${a.chain} holds ${a.holds} drops ${a.drops} faults ${a.faults}")
        emit("garbage sent ${a.sent} cancelled ${a.cancelled} received ${a.received}")
        emit("rates app ${ratio(a.sent,s.pieces)} apl ${ratio(a.sent,s.lines)} kpp ${ratio(a.operations,s.pieces)}")
    }
    fun command(name:String,args:List<String>){
        when(name){
            "PRINT"->{
                val current=if(s.ended)emptySet()else cells(s.kind,s.pos).toSet()
                val ghost=if(s.ended)emptySet()else cells(s.kind,landing(s.board,s.kind,s.pos)).toSet()
                for(r in 22 downTo 1){
                    val line=buildString {
                        append("%2d ".format(Locale.US,r))
                        for(c in 1..10){
                            val p=c to r
                            append(when{
                                (s.board[r-1] and (1 shl (c-1)))!=0->'#'
                                p in current->'@'
                                p in ghost->'+'
                                else->'.'
                            })
                        }
                    }
                    emit(line)
                }
            }
            "NEXT"->emit("hold ${s.hold?.let{kinds[it]}?:'-'} next "+s.queue.take(5).joinToString(""){kinds[it].toString()})
            "PREVIEW"->{
                val n=args[0].toInt();val queue=s.queue.toMutableList();var random=s.random
                while(queue.size<n){val next=bag(random);random=next.first;queue.addAll(next.second)}
                emit("preview "+queue.take(n).joinToString(""){kinds[it].toString()})
            }
            "STATUS"->{
                emit("score ${s.score} level ${s.level} lines ${s.lines} pieces ${s.pieces}")
                val piece=if (s.ended) "-" else "${kinds[s.kind]} ${states[s.pos.s]} ${s.pos.x} ${s.pos.y}"
                emit("piece $piece streak ${s.streak} chain ${s.chain} pending ${s.pending.sum()}")
            }
            "ANALYZE"->{
                val e=evaluate(s.board,0)
                emit("heights "+e.heights.joinToString(" "))
                emit("holes ${e.holes} bumpiness ${e.bump} value ${e.value}")
            }
            "ROW"->{
                val row=args[0].toInt();val pattern=args[1]
                if(cells(s.kind,s.pos).any{it.second==row&&pattern[it.first-1]=='#'}){emit("ERROR overlap");return}
                var mask=0
                for(i in 0..9)if(pattern[i]=='#')mask=mask or (1 shl i)
                s.board[row-1]=mask
                emit("OK")
            }
            "GARBAGE"->{
                val count=args[0].toInt();val hole=args[1].toInt();insertGarbage(count,hole)
                for(j in 0..count){val p=s.pos.copy(y=s.pos.y+j);if(fits(s.board,s.kind,p)){s.pos=p;emit("OK");return}}
                gameOver("top out")
            }
            "ATTACK"->{s.pending.add(args[0].toInt());emit("pending ${s.pending.sum()}")}
            "TICK"->repeat(args[0].toInt()){tick()}
            "UNDO"->{
                if(history.isEmpty())emit("ERROR nothing to undo")
                else{s=history.removeAt(history.lastIndex);start=s.snapshot();emit("undo ${s.pieces} ${kinds[s.kind]}")}
            }
            "SAVE"->{saves[args[0]]=Save(s.snapshot(),history.map{it.snapshot()},start.snapshot());emit("OK")}
            "LOAD"->{
                val saved=saves[args[0]]
                if(saved==null)emit("ERROR unknown save")
                else{s=saved.state.snapshot();history=saved.history.map{it.snapshot()}.toMutableList();start=saved.start.snapshot();emit("load ${s.pieces} ${kinds[s.kind]}")}
            }
            "SPINS"->spins()
            "HINT"->{
                for((i,c)in ranked().take(args[0].toInt()).withIndex())emit("hint ${i+1} ${kinds[c.kind]} ${operationsText(c.ops)} value ${c.value}")
            }
            "AUTO"->{
                repeat(args[0].toInt()){
                    val c=ranked()[0]
                    emit("auto ${kinds[c.kind]} ${operationsText(c.ops)}")
                    for(op in c.ops)operation(op)
                }
            }
        }
    }
}
private fun validNumber(text:String,minValue:Int,maxValue:Int):Boolean {
    if(text.isEmpty()||(text.length>1&&text[0]=='0')||text.any{it !in '0'..'9'})return false
    val n=text.toLongOrNull()?:return false
    return n in minValue.toLong()..maxValue.toLong()
}
private fun validArgs(name:String,args:List<String>):Boolean {
    if(name=="NEW")return args.size==2&&validNumber(args[0],1,2147483646)&&validNumber(args[1],1,15)
    if(name=="ROW")return args.size==2&&validNumber(args[0],1,22)&&args[1].length==10&&args[1].all{it=='#'||it=='.'}&&'.' in args[1]
    if(name=="GARBAGE")return args.size==2&&validNumber(args[0],1,10)&&validNumber(args[1],1,10)
    if(name=="SAVE"||name=="LOAD")return args.size==1&&args[0].length in 1..8&&args[0].all{it in 'a'..'z'}
    val limits=mapOf("PREVIEW" to 14,"ATTACK" to 20,"TICK" to 1000,"HINT" to 10,"AUTO" to 50)
    if(name in limits)return args.size==1&&validNumber(args[0],1,limits.getValue(name))
    return args.isEmpty()
}
fun main(){
    val reader=BufferedReader(InputStreamReader(System.`in`))
    val count=reader.readLine().toInt()
    var game:Game?=null
    var serial=0
    repeat(count){
        val words=reader.readLine().split(' ')
        val name=words[0]
        val args=words.drop(1)
        try {
            if(name in commandNames){
                if(!validArgs(name,args))emit("ERROR bad arguments")
                else if(name=="NEW"){
                    if(game!=null&&!game!!.s.ended){emit("game stopped");game!!.summary()}
                    serial++
                    emit("game $serial seed ${args[0].toInt()} level ${args[1].toInt()}")
                    game=Game(serial,args[0].toInt(),args[1].toInt())
                }else if(game==null)emit("ERROR no game")
                else if(game!!.s.ended&&name !in afterEnd)emit("ERROR game over")
                else game!!.command(name,args)
            }else{
                val bad=words.firstOrNull{it !in operationNames}
                if(bad!=null)emit("ERROR unknown $bad")
                else if(game==null)emit("ERROR no game")
                else if(game!!.s.ended)emit("ERROR game over")
                else for(word in words)game!!.operation(operationNames.indexOf(word))
            }
        }catch(_:GameOver){}
    }
    if(game!=null&&!game!!.s.ended){emit("game stopped");game!!.summary()}
    print(output.joinToString("\n",postfix="\n"))
}
