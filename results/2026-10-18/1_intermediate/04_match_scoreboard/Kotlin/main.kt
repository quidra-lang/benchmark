private const val P=0
private const val G=2
private const val W=4
private const val L=6
private const val R=8
private const val GS=10
private const val SERVE=11
private const val LEG=12
private const val DONE=13
private const val WINNER=14
private const val TC=15
private const val TS=16
private const val TV=17
private const val TURN=18
private const val LINEUP=21
private const val SUBS=33
private const val TIMEOUTS=35
private const val POINTS=37
private const val SERVED=39
private const val SERVEWON=41
private const val RUN=43
private const val CURRENT=45
private const val SERVICE=47
private const val HOLDS=49
private const val BREAKS=51
private const val BPO=53
private const val BPW=55
private const val DARTS=57
private const val SCORED=59
private const val BUSTS=61
private const val HIGH=63
private const val TONS=65
private const val MAXIMUMS=67
private const val ATTEMPTS=69
private const val HITS=71
private const val FRAME=73
private const val STANDING=74
private const val ROLLCOUNT=75
private const val ROLLS=76
private const val FRAMEROLLS=97
private const val FIRSTROLL=98
private const val SECONDROLL=99

data class Finished(val a: Int, val b: Int, val type: Int = 0, val loser: Int = 0)
data class Dart(val name: String, val value: Int, val doubleOut: Boolean)
data class BowlingFrame(val marks: String, val cumulative: Int?, val open: Boolean)
class Problem(message: String) : RuntimeException(message)

class Scoreboard {
    private val matches = linkedMapOf<String,Match>()
    private val darts = mutableListOf<Dart>()
    private val doubles = mutableListOf<Dart>()
    private val dartIndex: Map<String,Int>
    private val cache = mutableMapOf<Pair<Int,Int>,List<String>>()
    init {
        for (prefix in listOf("S","T","D")) {
            for (n in 20 downTo 1) {
                val multiplier = when (prefix) {
                    "S" -> 1
                    "T" -> 3
                    else -> 2
                }
                val dart = Dart("$prefix$n",n*multiplier,prefix == "D")
                darts.add(dart)
                if (dart.doubleOut) doubles.add(dart)
            }
        }
        darts.add(Dart("25",25,false))
        val bull = Dart("BULL",50,true)
        darts.add(bull)
        doubles.add(bull)
        darts.add(Dart("MISS",0,false))
        dartIndex = darts.withIndex().associate { it.value.name to it.index }
    }
    private fun fail(message: String): Nothing = throw Problem(message)
    private fun checkout(score: Int, maximum: Int): List<String> = cache.getOrPut(score to maximum) {
        fun search(): List<String> {
            for (a in doubles) {
                if (a.value == score) return listOf(a.name)
            }
            if (maximum >= 2) {
                for (a in darts.take(62)) {
                    for (b in doubles) {
                        if (a.value+b.value == score) return listOf(a.name,b.name)
                    }
                }
            }
            if (maximum >= 3) {
                for (a in darts.take(62)) {
                    for (b in darts.take(62)) {
                        for (c in doubles) {
                            if (a.value+b.value+c.value == score) return listOf(a.name,b.name,c.name)
                        }
                    }
                }
            }
            return emptyList()
        }
        search()
    }
    private inner class Match(t: List<String>) {
        val id = t[1]
        val sport = t[2]
        val names = listOf(t[3],if (sport == "BOWLING") "" else t[4])
        private val options = mutableMapOf<String,String>()
        private val initial = Array(2) { IntArray(6) }
        var s = IntArray(100)
        private val finished = mutableListOf<Finished>()
        private val history = ArrayDeque<IntArray>()
        init {
            val allowed = mutableMapOf<String,Set<String>>()
            if (sport != "BOWLING") {
                allowed["FIRST"] = setOf("A","B")
                options["FIRST"] = "A"
            }
            if (sport == "TENNIS") {
                allowed["SETS"] = setOf("3","5")
                allowed["DEUCE"] = setOf("AD","NOAD")
                allowed["FINAL"] = setOf("TB7","TB10","ADV","SUPER")
                options.putAll(mapOf("SETS" to "3","DEUCE" to "AD","FINAL" to "TB7"))
            }
            if (sport == "TABLETENNIS") {
                allowed["GAMES"] = setOf("5","7")
                options["GAMES"] = "5"
            }
            if (sport == "DARTS") {
                allowed["START"] = setOf("301","501","701")
                allowed["SETS"] = setOf("1","2","3","4","5")
                allowed["LEGS"] = setOf("1","2","3","4","5")
                options.putAll(mapOf("START" to "501","SETS" to "1","LEGS" to "1"))
            }
            val firstOption = if (sport == "BOWLING") 4 else if (sport == "VOLLEYBALL") 7 else 5
            val seen = mutableSetOf<String>()
            for (token in t.drop(firstOption)) {
                val p = token.split('=')
                if (p.size != 2 || p[0] !in allowed || p[1] !in allowed.getValue(p[0]) || !seen.add(p[0])) fail("invalid option")
                options[p[0]] = p[1]
            }
            s[GS] = first()
            s[SERVE] = first()
            s[LEG] = 1
            s[STANDING] = 10
            if (sport == "DARTS") {
                s[R] = option("START")
                s[R+1] = option("START")
                s[TS] = option("START")
            }
            if (sport == "VOLLEYBALL") {
                for (side in 0..1) {
                    val lineup = t[5+side].split(',').map { it.toInt() }
                    for (i in 0 until 6) {
                        initial[side][i] = lineup[i]
                        s[LINEUP+side*6+i] = lineup[i]
                    }
                }
            }
        }
        private fun first() = if (options.getOrDefault("FIRST","A") == "A") 0 else 1
        private fun option(key: String) = options.getValue(key).toInt()
        fun over() = s[DONE] != 0
        private fun tennis() = sport == "TENNIS"
        fun rally() = sport !in setOf("DARTS","BOWLING")
        private fun finalSet() = tennis() && s[W] == option("SETS")/2 && s[W+1] == option("SETS")/2
        private fun superTie() = finalSet() && options["FINAL"] == "SUPER"
        private fun tieBreak() = superTie() || tennis() && s[G] == 6 && s[G+1] == 6 && !(finalSet() && options["FINAL"] == "ADV")
        private fun server(): Int {
            if (tennis()) {
                val alternate = if (tieBreak()) (s[P]+s[P+1]+1)/2%2 else 0
                return s[GS] xor alternate
            }
            if (sport == "TABLETENNIS") {
                val played = s[P]+s[P+1]
                val alternate = if (played < 20) played/2%2 else played%2
                return first() xor (finished.size%2) xor alternate
            }
            return s[SERVE]
        }
        private fun normalWin(x: Int, extra: Int) = s[P+x]+extra >= 4 &&
            (options["DEUCE"] == "NOAD" || s[P+x]+extra-s[P+1-x] >= 2)
        private fun endSet(x: Int, score: Finished) {
            finished.add(score)
            s[W+x]++
            val target = when (sport) {
                "TENNIS" -> option("SETS")/2+1
                "TABLETENNIS" -> option("GAMES")/2+1
                "VOLLEYBALL" -> 3
                else -> 2
            }
            if (s[W+x] == target) {
                s[DONE] = 1
                s[WINNER] = x
            } else {
                s[P] = 0
                s[P+1] = 0
                s[G] = 0
                s[G+1] = 0
                if (sport == "VOLLEYBALL") {
                    for (side in 0..1) {
                        s[SUBS+side] = 0
                        s[TIMEOUTS+side] = 0
                        initial[side].copyInto(s,LINEUP+side*6)
                    }
                    s[SERVE] = first() xor (finished.size%2)
                }
            }
        }
        private fun point(x: Int) {
            val serve = server()
            s[POINTS+x]++
            s[SERVED+serve]++
            if (serve == x) s[SERVEWON+x]++
            s[CURRENT+1-x] = 0
            s[CURRENT+x]++
            s[RUN+x] = maxOf(s[RUN+x],s[CURRENT+x])
            if (tennis()) {
                val tie = tieBreak()
                val superTie = superTie()
                if (!tie && normalWin(1-serve,1)) {
                    s[BPO+1-serve]++
                    if (x != serve) s[BPW+x]++
                }
                s[P+x]++
                if (tie) {
                    val target = if (superTie || finalSet() && options["FINAL"] == "TB10") 10 else 7
                    if (s[P+x] >= target && s[P+x]-s[P+1-x] >= 2) {
                        val score = if (superTie) Finished(s[P],s[P+1],2) else {
                            s[G+x]++
                            Finished(s[G],s[G+1],1,s[P+1-x])
                        }
                        s[GS] = s[GS] xor 1
                        endSet(x,score)
                    }
                } else if (normalWin(x,0)) {
                    s[SERVICE+s[GS]]++
                    if (x == s[GS]) s[HOLDS+x]++ else s[BREAKS+x]++
                    s[G+x]++
                    s[P] = 0
                    s[P+1] = 0
                    s[GS] = s[GS] xor 1
                    if (s[G+x] >= 6 && s[G+x]-s[G+1-x] >= 2) endSet(x,Finished(s[G],s[G+1]))
                }
                return
            }
            s[P+x]++
            if (sport == "BADMINTON") s[SERVE] = x
            if (sport == "VOLLEYBALL" && s[SERVE] != x) {
                val start = LINEUP+x*6
                val old = s[start]
                s.copyInto(s,start,start+1,start+6)
                s[start+5] = old
                s[SERVE] = x
            }
            val target = if (sport == "TABLETENNIS") 11 else if (sport == "BADMINTON") 21 else if (finished.size == 4) 15 else 25
            if (s[P+x] >= target && s[P+x]-s[P+1-x] >= 2 || sport == "BADMINTON" && s[P+x] == 30) endSet(x,Finished(s[P],s[P+1]))
        }
        private fun completeTurn(x: Int) {
            s[HIGH+x] = maxOf(s[HIGH+x],s[TV])
            if (s[TV] >= 100) s[TONS+x]++
            if (s[TV] == 180) s[MAXIMUMS+x]++
        }
        private fun nextTurn() {
            s[SERVE] = s[SERVE] xor 1
            s[TC] = 0
            s[TV] = 0
            s[TS] = s[R+s[SERVE]]
        }
        private fun dart(code: Int) {
            val d = darts[code]
            val x = s[SERVE]
            val before = s[R+x]
            if (s[TC] == 0) s[TS] = before
            if (before == 50 || before <= 40 && before%2 == 0) s[ATTEMPTS+x]++
            s[DARTS+x]++
            s[TURN+s[TC]] = code
            s[TC]++
            s[TV] += d.value
            val remaining = before-d.value
            if (remaining < 0 || remaining == 1 || remaining == 0 && !d.doubleOut) {
                s[SCORED+x] -= s[TV]-d.value
                s[BUSTS+x]++
                s[R+x] = s[TS]
                nextTurn()
            } else {
                s[R+x] = remaining
                s[SCORED+x] += d.value
                if (remaining == 0) {
                    s[HITS+x]++
                    completeTurn(x)
                    s[L+x]++
                    if (s[L+x] == option("LEGS")) {
                        finished.add(Finished(s[L],s[L+1]))
                        s[W+x]++
                        if (s[W+x] == option("SETS")) {
                            s[DONE] = 1
                            s[WINNER] = x
                            return
                        }
                        s[L] = 0
                        s[L+1] = 0
                    }
                    s[LEG]++
                    s[R] = option("START")
                    s[R+1] = option("START")
                    s[SERVE] = first() xor ((s[LEG]-1)%2)
                    s[TC] = 0
                    s[TV] = 0
                    s[TS] = option("START")
                } else if (s[TC] == 3) {
                    completeTurn(x)
                    nextTurn()
                }
            }
        }
        private fun roll(pins: Int) {
            s[ROLLS+s[ROLLCOUNT]] = pins
            s[ROLLCOUNT]++
            val r = s[FRAMEROLLS]
            val frame = s[FRAME]
            if (r == 0) s[FIRSTROLL] = pins
            if (r == 1) s[SECONDROLL] = pins
            s[STANDING] -= pins
            val end = if (frame < 9) r == 1 || r == 0 && pins == 10 else
                r == 2 || r == 1 && s[FIRSTROLL] != 10 && s[FIRSTROLL]+pins < 10
            if (end) {
                if (frame == 9) s[DONE] = 1
                else {
                    s[FRAME]++
                    s[FRAMEROLLS] = 0
                    s[STANDING] = 10
                }
            } else {
                s[FRAMEROLLS]++
                if (frame == 9 && s[STANDING] == 0) s[STANDING] = 10
            }
        }
        private fun bowlingFrames(): List<BowlingFrame> {
            val result = mutableListOf<BowlingFrame>()
            var cursor = 0
            var cumulative = 0
            for (frame in 0 until 10) {
                if (cursor >= s[ROLLCOUNT]) break
                val first = s[ROLLS+cursor]
                val count = if (frame < 9) if (first == 10) 1 else minOf(2,s[ROLLCOUNT]-cursor) else minOf(3,s[ROLLCOUNT]-cursor)
                val marks = StringBuilder()
                var standing = 10
                var sum = 0
                var fresh = true
                for (i in 0 until count) {
                    val pins = s[ROLLS+cursor+i]
                    marks.append(if (pins == 10 && fresh) "X" else if (pins == standing) "/" else if (pins == 0) "-" else pins.toString())
                    sum += pins
                    standing -= pins
                    fresh = frame == 9 && standing == 0
                    if (fresh) standing = 10
                }
                val score = when {
                    frame == 9 -> if (over()) sum else null
                    first == 10 && cursor+2 < s[ROLLCOUNT] -> 10+s[ROLLS+cursor+1]+s[ROLLS+cursor+2]
                    first != 10 && count == 2 -> if (sum < 10) sum else if (cursor+2 < s[ROLLCOUNT]) 10+s[ROLLS+cursor+2] else null
                    else -> null
                }
                val total = score?.let {
                    cumulative += it
                    cumulative
                }
                val open = count >= 2 && first != 10 && first+s[ROLLS+cursor+1] < 10
                result.add(BowlingFrame(marks.toString(),total,open))
                cursor += count
            }
            return result
        }
        fun event(command: String, value: String, tokens: List<String>) {
            if (over()) fail("match over")
            var code = 0
            var side = 0
            var position = -1
            if (command == "ROLL") {
                code = value.toInt()
                if (code > s[STANDING]) fail("too many pins")
            }
            if (command == "THROW") code = dartIndex[value] ?: fail("invalid dart")
            if (command in setOf("SUB","TIMEOUT")) {
                side = if (tokens[2] == "A") 0 else 1
                if (command == "SUB") {
                    val from = tokens[3].toInt()
                    val to = tokens[4].toInt()
                    position = (0 until 6).firstOrNull { s[LINEUP+side*6+it] == from } ?: fail("player not on court")
                    if ((0 until 6).any { s[LINEUP+side*6+it] == to }) fail("player already on court")
                    if (s[SUBS+side] == 6) fail("no substitutions left")
                } else if (s[TIMEOUTS+side] == 2) fail("no timeouts left")
            }
            val before = s.copyOf()
            val count = finished.size
            when (command) {
                "POINT" -> point(if (value == "A") 0 else 1)
                "ROLL" -> roll(code)
                "THROW" -> dart(code)
                "SUB" -> {
                    s[LINEUP+side*6+position] = tokens[4].toInt()
                    s[SUBS+side]++
                }
                "TIMEOUT" -> s[TIMEOUTS+side]++
            }
            val changed = s.indices.filter { before[it] != s[it] }
            val undo = IntArray(1+changed.size*2)
            undo[0] = count
            for ((i,index) in changed.withIndex()) {
                undo[1+i*2] = index
                undo[2+i*2] = before[index]
            }
            history.addLast(undo)
        }
        fun undo() {
            if (history.isEmpty()) fail("nothing to undo")
            val undo = history.removeLast()
            for (i in 1 until undo.size step 2) s[undo[i]] = undo[i+1]
            finished.subList(undo[0],finished.size).clear()
        }
        private fun situation(x: Int): String {
            val old = s.copyOf()
            val count = finished.size
            val games = s[G]+s[G+1]
            val serve = server()
            val normal = tennis() && !tieBreak()
            point(x)
            val result = when {
                over() -> "match point"
                finished.size > count -> if (tennis() || sport == "VOLLEYBALL") "set point" else "game point"
                normal && s[G]+s[G+1] > games -> if (x == serve) "game point" else "break point"
                else -> ""
            }
            s = old
            finished.subList(count,finished.size).clear()
            return result
        }
        private fun finishedScore(f: Finished, first: Int): String {
            val pair = if (first == 0) "${f.a}-${f.b}" else "${f.b}-${f.a}"
            return if (f.type == 2) "[$pair]" else pair+if (f.type == 1) "(${f.loser})" else ""
        }
        private fun pair(offset: Int) = "${s[offset]}-${s[offset+1]}"
        fun score(): String {
            if (sport == "BOWLING") {
                val frames = bowlingFrames().map { it.marks+(it.cumulative?.let { total -> "($total)" } ?: "") }
                return "$id: ${names[0]}"+if (frames.isEmpty()) "" else " ${frames.joinToString(" ")}"
            }
            val serve = if (over()) -1 else server()
            val items = mutableListOf<String>()
            if (sport == "DARTS") {
                items.addAll(listOf("sets",pair(W),"legs",pair(L),"score",pair(R)))
                if (!over()) {
                    if (s[TC] > 0) {
                        items.add("turn")
                        for (i in 0 until s[TC]) items.add(darts[s[TURN+i]].name)
                    }
                    val check = checkout(s[R+s[SERVE]],3-s[TC])
                    if (check.isNotEmpty()) {
                        items.add("checkout")
                        items.addAll(check)
                    }
                }
            } else {
                items.addAll(finished.map { finishedScore(it,0) })
                if (!over()) {
                    if (tennis()) {
                        if (superTie()) items.add("[${pair(P)}]")
                        else {
                            items.add(pair(G))
                            if (tieBreak()) items.add(pair(P))
                            else if (options["DEUCE"] == "AD" && s[P] >= 3 && s[P+1] >= 3) {
                                items.add(if (s[P] == s[P+1]) "40-40" else if (s[P] > s[P+1]) "AD-40" else "40-AD")
                            } else {
                                val points = listOf("0","15","30","40")
                                items.add("${points[s[P]]}-${points[s[P+1]]}")
                            }
                        }
                    } else {
                        items.add(pair(P))
                        if (sport == "VOLLEYBALL") items.addAll(listOf("server",s[LINEUP+s[SERVE]*6].toString()))
                    }
                    for (x in 0..1) {
                        val situation = situation(x)
                        if (situation.isNotEmpty()) items.add("($situation ${names[x]})")
                    }
                }
            }
            return "$id: ${names[0]}${if (serve == 0) "*" else ""} vs ${names[1]}${if (serve == 1) "*" else ""} ${items.joinToString(" ")}"
        }
        fun stats(): List<String> {
            if (sport == "BOWLING") {
                val frames = bowlingFrames()
                val strikes = frames.sumOf { it.marks.count { c -> c == 'X' } }
                val spares = frames.sumOf { it.marks.count { c -> c == '/' } }
                val open = frames.count { it.open }
                val old = s.copyOf()
                while (!over()) roll(s[STANDING])
                val maximum = bowlingFrames().last().cumulative!!
                s = old
                return listOf("$id ${names[0]}: strikes $strikes spares $spares open $open max $maximum")
            }
            return (0..1).map { x ->
                var line = "$id ${names[x]}: "
                if (sport == "DARTS") {
                    val average = if (s[DARTS+x] == 0) 0L else s[SCORED+x].toLong()*300/s[DARTS+x]
                    line += "darts ${s[DARTS+x]} average ${average/100}.${(average%100).toString().padStart(2,'0')}"+
                        " busts ${s[BUSTS+x]} high ${s[HIGH+x]} tons ${s[TONS+x]} 180s ${s[MAXIMUMS+x]} doubles ${s[HITS+x]}/${s[ATTEMPTS+x]}"
                } else {
                    line += "points ${s[POINTS+x]} serve ${s[SERVEWON+x]}/${s[SERVED+x]} run ${s[RUN+x]}"
                    if (tennis()) line += " holds ${s[HOLDS+x]}/${s[SERVICE+x]} breaks ${s[BREAKS+x]} break points ${s[BPW+x]}/${s[BPO+x]}"
                    if (sport == "VOLLEYBALL") line += " subs ${s[SUBS+x]} timeouts ${s[TIMEOUTS+x]} lineup "+
                        (0 until 6).joinToString(",") { s[LINEUP+x*6+it].toString() }
                }
                line
            }
        }
        fun result(): String {
            if (!over()) fail("match not finished")
            if (sport == "BOWLING") return "$id: ${names[0]} ${bowlingFrames().last().cumulative}"
            val winner = s[WINNER]
            return "$id: ${names[winner]} def. ${names[1-winner]} ${finished.joinToString(" ") { finishedScore(it,winner) }}"
        }
    }
    fun execute(line: String): List<String> {
        val t = line.split(' ')
        val command = t[0]
        if (command == "MATCH") {
            if (t[1] in matches) fail("duplicate match")
            val match = Match(t)
            matches[t[1]] = match
            return emptyList()
        }
        if (command == "CHECKOUT") {
            val answer = checkout(t[1].toInt(),3)
            return listOf("checkout ${t[1]}: "+if (answer.isEmpty()) "none" else answer.joinToString(" "))
        }
        if (command == "STANDINGS") {
            val totals = mutableMapOf<String,IntArray>()
            for (m in matches.values) {
                if (m.over() && m.sport != "BOWLING") {
                    val winner = m.s[WINNER]
                    totals.getOrPut(m.names[winner]) { IntArray(2) }[0]++
                    totals.getOrPut(m.names[1-winner]) { IntArray(2) }[1]++
                }
            }
            val names = totals.keys.sortedWith(compareByDescending<String> { totals.getValue(it)[0] }.thenBy { totals.getValue(it)[1] }.thenBy { it })
            val records = names.map { "$it ${totals.getValue(it)[0]}-${totals.getValue(it)[1]}" }
            return listOf("standings: "+if (records.isEmpty()) "none" else records.joinToString(", "))
        }
        val match = matches[t[1]] ?: fail("unknown match")
        when (command) {
            "UNDO" -> match.undo()
            "SCORE" -> return listOf(match.score())
            "STATS" -> return match.stats()
            "RESULT" -> return listOf(match.result())
            else -> {
                val correct = when (command) {
                    "POINT" -> match.rally()
                    "ROLL" -> match.sport == "BOWLING"
                    "THROW" -> match.sport == "DARTS"
                    else -> match.sport == "VOLLEYBALL"
                }
                if (!correct) fail("wrong event")
                when (command) {
                    "POINT" -> {
                        for (c in t[2]) match.event(command,c.toString(),t)
                    }
                    "ROLL", "THROW" -> {
                        for (value in t.drop(2)) match.event(command,value,t)
                    }
                    else -> match.event(command,"",t)
                }
            }
        }
        return emptyList()
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val app = Scoreboard()
    repeat(input.readLine().toInt()) {
        val lines = try {
            app.execute(input.readLine())
        } catch (problem: Problem) {
            listOf("ERROR ${problem.message}")
        }
        for (line in lines) {
            output.write(line)
            output.newLine()
        }
    }
    output.flush()
}
