private const val FACES = "URFDLB"
private const val COLORS = "WRGYOB"
private const val LETTERS = "URFDLBMESudfblrxyz"
private val corners = listOf("URF", "UFL", "ULB", "UBR", "DFR", "DLF", "DBL", "DRB")
private val edges = listOf("UR", "UF", "UL", "UB", "DR", "DF", "DL", "DB", "FR", "FL", "BL", "BR")
private val cornerStickers = listOf(listOf(8,9,20), listOf(6,18,38), listOf(0,36,47), listOf(2,45,11), listOf(29,26,15), listOf(27,44,24), listOf(33,53,42), listOf(35,17,51))
private val edgeStickers = listOf(listOf(5,10), listOf(7,19), listOf(3,37), listOf(1,46), listOf(32,16), listOf(28,25), listOf(30,43), listOf(34,52), listOf(23,12), listOf(21,41), listOf(50,39), listOf(48,14))
private data class Move(val letter: Char, val amount: Int) {
    fun text() = letter.toString() + when (amount) {
        2 -> "2"
        3 -> "'"
        else -> ""
    }
    fun inverse() = copy(amount = 4-amount)
}
// A permutation maps each source sticker to its destination sticker.
private typealias Permutation = List<Int>
private typealias State = List<Char>
private class Problem(val text: String) : RuntimeException(text)
private fun identity(): Permutation = (0 until 54).toList()
private fun solvedState(): State = List(54) {
    COLORS[it/9]
}
private fun compose(a: Permutation, b: Permutation): Permutation = a.map {
    b[it]
}
private fun inversePermutation(p: Permutation): Permutation = MutableList(54) {
    0
}.also {
    out -> p.forEachIndexed {
        i, target -> out[target] = i
    }
}
private fun apply(state: State, p: Permutation): State = state.toMutableList().also {
    out -> p.forEachIndexed {
        i, target -> out[target] = state[i]
    }
}
private fun inverse(sequence: List<Move>) = sequence.asReversed().map {
    it.inverse()
}
private fun notation(sequence: List<Move>) = if (sequence.isEmpty()) "0" else "${sequence.size} ${sequence.joinToString(" ") { it.text() }}"
private fun axis(m: Char) = when (m) {
    in "RLMrlx" -> 'x'
    in "UDEudy" -> 'y'
    else -> 'z'
}
private fun solved(state: State) = state.indices.all {
    state[it] == state[it/9*9+4]
}
private fun simplify(input: List<Move>): List<Move> {
    var sequence = input
    while (true) {
        val out = mutableListOf<Move>()
        var at = 0
        while (at < sequence.size) {
            val a = axis(sequence[at].letter)
            val run = mutableListOf<Move>()
            while (at < sequence.size && axis(sequence[at].letter) == a) {
                val m = sequence[at++]
                val i = run.indexOfFirst {
                    it.letter == m.letter
                }
                if (i < 0) run.add(m) else run[i] = run[i].copy(amount = (run[i].amount+m.amount)%4)
            }
            out.addAll(run.filter {
                it.amount != 0
            })
        }
        if (out == sequence) return out
        sequence = out
    }
}
private fun number(s: String): Long? = if (s.length in 1..10 && s.all {
    it in '0'..'9'
} && (s.length == 1 || s[0] != '0')) s.toLong() else null
private fun name(s: String) = s.length in 1..8 && s.all {
    it in 'a'..'z'
}
private fun simple(s: String): List<Move> = buildList {
    var at = 0
    while (at < s.length) {
        if (s[at] == ' ') {
            at++
            continue
        }
        val letter = s[at++]
        val amount = when (s.getOrNull(at)) {
            '2' -> {
                at++
                2
            }
            '\'' -> {
                at++
                3
            }
            else -> 1
        }
        add(Move(letter, amount))
    }
}
private class SequenceParser(private val line: String, private var at: Int, private val macros: Map<String, List<Move>>) {
    private fun current() = line.getOrNull(at)
    private fun skip() {
        while (current() == ' ') at++
    }
    private fun syntax(): Nothing = throw Problem("error: syntax at ${minOf(at+1, line.length+1)}")
    private fun power(sequence: List<Move>): List<Move> {
        var count = 1
        if (current()?.let {
            it in '1'..'9'
        } == true) {
            count = line[at++]-'0'
            if (current()?.let {
                it in '0'..'9'
            } == true) count = count*10+(line[at++]-'0')
        }
        val invert = current() == '\''
        if (invert) at++
        val repeated = buildList {
            repeat(count) {
                addAll(sequence)
            }
        }
        return if (invert) inverse(repeated) else repeated
    }
    private fun sequence(): List<Move> {
        val out = mutableListOf<Move>()
        while (true) {
            skip()
            val c = current() ?: break
            val next = when {
                c in LETTERS -> {
                    at++
                    val amount = when (current()) {
                        '2' -> {
                            at++
                            2
                        }
                        '\'' -> {
                            at++
                            3
                        }
                        else -> 1
                    }
                    listOf(Move(c, amount))
                }
                c == '(' -> {
                    at++
                    val sequence = sequence()
                    skip()
                    if (current() != ')') syntax()
                    at++
                    power(sequence)
                }
                c == '[' -> {
                    at++
                    val a = sequence()
                    skip()
                    val separator = current()
                    if (separator != ',' && separator != ':') syntax()
                    at++
                    val b = sequence()
                    skip()
                    if (current() != ']') syntax()
                    at++
                    power(a+b+inverse(a)+(if (separator == ',') inverse(b) else emptyList()))
                }
                c == '{' -> {
                    at++
                    val start = at
                    while (current()?.let {
                        it in 'a'..'z'
                    } == true) at++
                    if (at == start || current() != '}') syntax()
                    val name = line.substring(start, at)
                    val sequence = macros[name] ?: throw Problem("error: undefined $name")
                    at++
                    power(sequence)
                }
                else -> break
            }
            out.addAll(next)
        }
        return out
    }
    fun parse(): List<Move> {
        val sequence = sequence()
        skip()
        if (current() != null) syntax()
        if (sequence.size > 500) throw Problem("error: too long")
        return sequence
    }
}
private class Cube {
    var state = solvedState()
    val history = mutableListOf<Move>()
    val redo = mutableListOf<Move>()
    val macros = sortedMapOf<String, List<Move>>()
    val saves = mutableMapOf<String, Pair<State, List<Move>>>()
    val moves = linkedMapOf<Move, Permutation>()
    val rotations = mutableListOf<Pair<List<Move>, Permutation>>()
    init {
        fun index(face: Char, row: Int, col: Int) = FACES.indexOf(face)*9+row*3+col
        val basics = mutableMapOf<Char, Permutation>()
        for (letter in "URFDLBMES") {
            val p = identity().toMutableList()
            if (letter in FACES) for (i in 0..2) for (j in 0..2) p[index(letter, i, j)] = index(letter, j, 2-i)
            fun link(f: Char, r: Int, c: Int, g: Char, s: Int, d: Int) {
                p[index(f,r,c)] = index(g,s,d)
            }
            for (i in 0..2) when (letter) {
                'U' -> {
                    link('F',0,i,'L',0,i)
                    link('L',0,i,'B',0,i)
                    link('B',0,i,'R',0,i)
                    link('R',0,i,'F',0,i)
                }
                'R' -> {
                    link('F',i,2,'U',i,2)
                    link('U',i,2,'B',2-i,0)
                    link('B',i,0,'D',2-i,2)
                    link('D',i,2,'F',i,2)
                }
                'F' -> {
                    link('U',2,i,'R',i,0)
                    link('R',i,0,'D',0,2-i)
                    link('D',0,i,'L',i,2)
                    link('L',i,2,'U',2,2-i)
                }
                'D' -> {
                    link('F',2,i,'R',2,i)
                    link('R',2,i,'B',2,i)
                    link('B',2,i,'L',2,i)
                    link('L',2,i,'F',2,i)
                }
                'L' -> {
                    link('U',i,0,'F',i,0)
                    link('F',i,0,'D',i,0)
                    link('D',i,0,'B',2-i,2)
                    link('B',i,2,'U',2-i,0)
                }
                'B' -> {
                    link('U',0,i,'L',2-i,0)
                    link('L',i,0,'D',2,i)
                    link('D',2,i,'R',2-i,2)
                    link('R',i,2,'U',0,i)
                }
                'M' -> {
                    link('U',i,1,'F',i,1)
                    link('F',i,1,'D',i,1)
                    link('D',i,1,'B',2-i,1)
                    link('B',i,1,'U',2-i,1)
                }
                'E' -> {
                    link('F',1,i,'R',1,i)
                    link('R',1,i,'B',1,i)
                    link('B',1,i,'L',1,i)
                    link('L',1,i,'F',1,i)
                }
                else -> {
                    link('U',1,i,'R',i,1)
                    link('R',i,1,'D',1,2-i)
                    link('D',1,i,'L',i,1)
                    link('L',i,1,'U',1,2-i)
                }
            }
            basics[letter] = p
        }
        for ((letter, text) in listOf('r' to "RM'", 'l' to "LM", 'u' to "UE'", 'd' to "DE", 'f' to "FS", 'b' to "BS'", 'x' to "RM'L'", 'y' to "UE'D'", 'z' to "FSB'")) {
            var p = identity()
            for (m in simple(text)) repeat(m.amount) {
                p = compose(p, basics.getValue(m.letter))
            }
            basics[letter] = p
        }
        for (letter in LETTERS) {
            var p = identity()
            for (amount in 1..3) {
                p = compose(p, basics.getValue(letter))
                moves[Move(letter,amount)] = p
            }
        }
        for (base in listOf("", "x", "x2", "x'", "z", "z'")) for (y in listOf("", "y", "y2", "y'")) {
            val sequence = simple(base+" "+y)
            rotations.add(sequence to effect(sequence))
        }
    }
    fun permutation(m: Move) = moves.getValue(m)
    fun effect(sequence: List<Move>): Permutation = sequence.fold(identity()) {
        p, m -> compose(p, permutation(m))
    }
    fun applySequence(state: State, sequence: List<Move>) = apply(state, effect(sequence))
    fun conjugate(p: Permutation, m: Move, outer: Boolean): Move {
        val effect = compose(compose(p, permutation(m)), inversePermutation(p))
        return moves.entries.first {
            (!outer || it.key.letter in FACES) && it.value == effect
        }.key
    }
    fun normalized(state: State): Pair<List<Move>, State>? {
        for ((sequence, p) in rotations) {
            val s = apply(state, p)
            if ((0..5).all {
                s[it*9+4] == COLORS[it]
            }) return sequence to s
        }
        return null
    }
    fun pieces(state: State, positions: List<List<Int>>): List<Pair<Int, Int>?> {
        val solved = solvedState()
        return positions.map {
            position ->
            var found: Pair<Int, Int>? = null
            for ((piece, colors) in positions.withIndex()) for (t in colors.indices) {
                if (colors.indices.all {
                    j -> state[position[(t+j)%colors.size]] == solved[colors[j]]
                }) found = piece to t
            }
            found
        }
    }
    fun check(w: String): String? {
        if (w.length != 54) return "length ${w.length}"
        w.indexOfFirst {
            it !in COLORS
        }.takeIf {
            it >= 0
        }?.let {
            return "char ${it+1}"
        }
        for (c in COLORS) {
            val count = w.count {
                it == c
            }
            if (count != 9) return "count $c $count"
        }
        val state = w.toList()
        val normalized = normalized(state)?.second ?: return "centers"
        val cp = pieces(state, cornerStickers)
        val ep = pieces(state, edgeStickers)
        cp.indexOfFirst {
            it == null
        }.takeIf {
            it >= 0
        }?.let {
            return "corner ${corners[it]}"
        }
        ep.indexOfFirst {
            it == null
        }.takeIf {
            it >= 0
        }?.let {
            return "edge ${edges[it]}"
        }
        for ((names, positions) in listOf(corners to cp, edges to ep)) for (i in names.indices) if (positions.none {
            it!!.first == i
        }) return "missing ${names[i]}"
        val c = pieces(normalized, cornerStickers)
        val e = pieces(normalized, edgeStickers)
        if (c.sumOf {
            it!!.second
        }%3 != 0) return "twist"
        if (e.sumOf {
            it!!.second
        }%2 != 0) return "flip"
        fun parity(p: List<Pair<Int, Int>?>): Int {
            var count = 0
            for (i in p.indices) for (j in i+1 until p.size) if (p[i]!!.first > p[j]!!.first) count++
            return count%2
        }
        return if (parity(c) != parity(e)) "parity" else null
    }
    fun cycles(positions: List<Pair<Int, Int>?>, names: List<String>, modulus: Int): String {
        val destination = IntArray(names.size)
        val orientation = IntArray(names.size)
        for ((q, entry) in positions.withIndex()) {
            val (piece, t) = entry!!
            destination[piece] = q
            orientation[piece] = t
        }
        val seen = BooleanArray(names.size)
        val out = mutableListOf<String>()
        for (start in names.indices) {
            if (seen[start]) continue
            val cycle = mutableListOf<String>()
            var sum = 0
            var p = start
            while (!seen[p]) {
                seen[p] = true
                cycle.add(names[p])
                sum += orientation[p]
                p = destination[p]
            }
            val mark = if (modulus == 1 || sum%modulus == 0) "" else if (modulus == 3 && sum%3 == 2) "-" else "+"
            if (cycle.size >= 2 || mark.isNotEmpty()) out.add("(${cycle.joinToString(" ")})$mark")
        }
        return out.ifEmpty {
            listOf("none")
        }.joinToString(" ")
    }
    fun order(sequence: List<Move>): Long {
        fun gcd(a: Long, b: Long): Long {
            var x = a
            var y = b
            while (y != 0L) {
                val t = x%y
                x = y
                y = t
            }
            return x
        }
        val p = effect(sequence)
        val seen = BooleanArray(54)
        var result = 1L
        for (start in 0 until 54) {
            var i = start
            var length = 0L
            while (!seen[i]) {
                seen[i] = true
                length++
                i = p[i]
            }
            if (length != 0L) result = result/gcd(result,length)*length
        }
        return result
    }
    fun search(state: State, left: Int, previous: Char?, path: MutableList<Move>): Boolean {
        if (left == 0) return solved(state)
        for (face in FACES) {
            if (previous == face || (previous == 'D' && face == 'U') || (previous == 'L' && face == 'R') || (previous == 'B' && face == 'F')) continue
            for (amount in 1..3) {
                val m = Move(face,amount)
                path.add(m)
                if (search(apply(state,permutation(m)),left-1,face,path)) return true
                path.removeAt(path.lastIndex)
            }
        }
        return false
    }
    fun command(line: String): List<String> {
        val command = line.substringBefore(' ')
        val arg = if (' ' in line) line.substringAfter(' ') else null
        val noArgs = setOf("RESET", "SHOW", "STATE", "ISSOLVED", "HISTORY", "SOLUTION", "ANALYZE", "STAGE", "MACROS")
        val word = setOf("CHECK", "LOAD", "UNDO", "REDO", "SEARCH", "WHERE", "SAVE", "RESTORE", "SCRAMBLE")
        val sequences = setOf("APPLY", "INVERT", "SIMPLIFY", "METRICS", "ORDER", "CYCLES", "UNROTATE", "UNTIL")
        val heads = setOf("DEFINE", "MIRROR", "ROTATE")
        if (command !in noArgs && command !in word && command !in sequences && command !in heads) throw Problem("error: unknown command $command")
        val words = arg?.split(' ') ?: emptyList()
        val head = words.firstOrNull() ?: ""
        fun bad(): Nothing = throw Problem("error: bad arguments")
        if (command in noArgs && arg != null) bad()
        if (command in word) {
            if (words.size != if (command == "SCRAMBLE") 2 else 1) bad()
            if (command in setOf("UNDO", "REDO", "SEARCH", "SCRAMBLE") && words.any {
                number(it) == null
            }) bad()
            if (command in setOf("SAVE", "RESTORE") && !name(head)) bad()
        }
        if (command in heads && (arg == null || when (command) {
            "DEFINE" -> !name(head)
            "MIRROR" -> head !in setOf("LR", "UD", "FB")
            else -> head !in setOf("x", "x'", "x2", "y", "y'", "y2", "z", "z'", "z2")
        })) bad()
        val sequence = if (command in sequences || command in heads) SequenceParser(line, minOf(line.length, command.length+(if (command in heads) head.length+2 else 1)), macros).parse() else emptyList()
        val n = if (command in setOf("UNDO", "REDO", "SEARCH", "SCRAMBLE")) number(head)!! else 0L
        if ((command in setOf("UNDO", "REDO") && n == 0L) || (command == "SEARCH" && n > 4) || (command == "SCRAMBLE" && (n !in 1L..50L || number(words[1])!! !in 1L..2147483646L))) throw Problem("error: bad value")
        if (command == "WHERE" && head !in corners && head !in edges) throw Problem("error: unknown piece $head")
        val text = when (command) {
            "RESET" -> {
                state = solvedState()
                history.clear()
                redo.clear()
                "reset"
            }
            "SHOW" -> return buildList {
                for (group in listOf(listOf(0),listOf(4,2,1,5),listOf(3))) for (row in 0..2) add((if (group.size == 1) "      " else "")+group.flatMap {
                    face -> (0..2).map {
                        state[face*9+row*3+it]
                    }
                }.joinToString(" "))
            }
            "STATE" -> "state ${state.joinToString("")}"
            "ISSOLVED" -> if (solved(state)) "solved" else "unsolved ${state.indices.count { state[it] != state[it/9*9+4] }}"
            "HISTORY" -> "history ${notation(history)}"
            "SOLUTION" -> "solution ${notation(simplify(inverse(history)))}"
            "MACROS" -> return listOf("macros ${macros.size}")+macros.map {
                (name, sequence) -> "macro $name ${notation(sequence)}"
            }
            "CHECK", "LOAD" -> {
                val reason = check(head)
                if (reason != null) {
                    if (command == "LOAD") throw Problem("error: invalid $reason")
                    "invalid $reason"
                }
                else if (command == "CHECK") "valid" else {
                    state = head.toList()
                    history.clear()
                    redo.clear()
                    "loaded"
                }
            }
            "UNDO", "REDO" -> {
                val undo = command == "UNDO"
                val count = minOf(n, (if (undo) history.size else redo.size).toLong()).toInt()
                if (count == 0) throw Problem("error: nothing to ${command.lowercase()}")
                repeat(count) {
                    val m = if (undo) history.removeAt(history.lastIndex) else redo.removeAt(redo.lastIndex)
                    state = apply(state,permutation(if (undo) m.inverse() else m))
                    if (undo) redo.add(m) else history.add(m)
                }
                "${if (undo) "undone" else "redone"} $count"
            }
            "SAVE" -> {
                saves[head] = state.toList() to history.toList()
                "saved $head"
            }
            "RESTORE" -> {
                val save = saves[head] ?: throw Problem("error: no save $head")
                state = save.first.toList()
                history.clear()
                history.addAll(save.second)
                redo.clear()
                "restored $head"
            }
            "APPLY" -> {
                state = applySequence(state,sequence)
                history.addAll(sequence)
                redo.clear()
                "applied ${sequence.size}"
            }
            "DEFINE" -> {
                macros[head] = sequence.toList()
                "defined $head ${sequence.size}"
            }
            "INVERT" -> "inverse ${notation(inverse(sequence))}"
            "SIMPLIFY" -> "simplified ${notation(simplify(sequence))}"
            "ORDER" -> "order ${order(sequence)}"
            "METRICS" -> {
                var htm = 0
                var qtm = 0
                var stm = 0
                for (m in sequence) {
                    if (m.letter in "xyz") continue
                    val h = if (m.letter in "MES") 2 else 1
                    htm += h
                    qtm += h*if (m.amount == 2) 2 else 1
                    stm++
                }
                "metrics htm $htm qtm $qtm stm $stm etm ${sequence.size}"
            }
            "ROTATE" -> {
                val p = permutation(simple(head)[0])
                "rotated ${notation(sequence.map { conjugate(p,it,false) })}"
            }
            "MIRROR" -> {
                val mirror = when (head) {
                    "LR" -> 'x'
                    "UD" -> 'y'
                    else -> 'z'
                }
                val out = sequence.map {
                    m -> if (axis(m.letter) == mirror) {
                        val i = "RLrlUDudFBfb".indexOf(m.letter)
                        if (i < 0) m else Move("LRlrDUduBFbf"[i],4-m.amount)
                    } else m.inverse()
                }
                "mirror ${notation(out)}"
            }
            "UNROTATE" -> {
                val out = mutableListOf<Move>()
                var rotation = identity()
                for (m in sequence) {
                    val replacement = when (m.letter) {
                        'M' -> "RL'x'"
                        'E' -> "UD'y'"
                        'S' -> "F'Bz"
                        'r' -> "Lx"
                        'l' -> "Rx'"
                        'u' -> "Dy"
                        'd' -> "Uy'"
                        'f' -> "Bz"
                        'b' -> "Fz'"
                        else -> ""
                    }
                    val expanded = if (replacement.isEmpty()) listOf(m) else simple(replacement).map {
                        it.copy(amount = it.amount*m.amount%4)
                    }.filter {
                        it.amount != 0
                    }
                    for (n in expanded) if (n.letter in "xyz") rotation = compose(rotation,permutation(n)) else out.add(conjugate(rotation,n,true))
                }
                out.addAll(rotations.first {
                    it.second == rotation
                }.first)
                "unrotated ${notation(out)}"
            }
            "UNTIL" -> {
                val p = effect(sequence)
                var currentState = this.state
                var found: Long? = null
                for (i in 1L..order(sequence)) {
                    currentState = apply(currentState,p)
                    if (solved(currentState)) {
                        found = i
                        break
                    }
                }
                "until ${found?.toString() ?: "never"}"
            }
            "SEARCH" -> {
                var answer: List<Move>? = null
                for (depth in 0..n.toInt()) {
                    val path = mutableListOf<Move>()
                    if (search(state,depth,null,path)) {
                        answer = path
                        break
                    }
                }
                answer?.let {
                    "found ${notation(it)}"
                } ?: "not found"
            }
            "SCRAMBLE" -> {
                var x = number(words[1])!!
                val out = mutableListOf<Move>()
                repeat(n.toInt()) {
                    val faces = FACES.filter {
                        f -> out.lastOrNull()?.letter != f && (out.size < 2 || axis(out.last().letter) != axis(out[out.lastIndex-1].letter) || axis(f) != axis(out.last().letter))
                    }
                    x = 48271*x%2147483647
                    val letter = faces[(x%faces.length).toInt()]
                    x = 48271*x%2147483647
                    out.add(Move(letter, listOf(1,3,2)[(x%3).toInt()]))
                }
                state = applySequence(state,out)
                history.addAll(out)
                redo.clear()
                "scramble ${out.joinToString(" ") { it.text() }}"
            }
            "ANALYZE", "STAGE", "WHERE" -> {
                val (rotation, state) = normalized(this.state)!!
                val cp = pieces(state,cornerStickers)
                val ep = pieces(state,edgeStickers)
                if (command == "ANALYZE") return listOf("rotation ${if (rotation.isEmpty()) "none" else rotation.joinToString(" ") { it.text() }}", "corners ${cycles(cp,corners,3)}", "edges ${cycles(ep,edges,2)}")
                if (command == "WHERE") {
                    val names = if (head in corners) corners else edges
                    val positions = if (head in corners) cp else ep
                    val piece = names.indexOf(head)
                    val q = positions.indexOfFirst {
                        it!!.first == piece
                    }
                    "$head at ${names[q]} ${if (head in corners) "twist" else "flip"} ${positions[q]!!.second}"
                } else {
                    val cross = (4..7).count {
                        ep[it] == (it to 0)
                    }
                    val slots = (4..7).count {
                        cp[it] == (it to 0) && ep[it+4] == (it+4 to 0)
                    }
                    val top = state.take(9).count {
                        it == 'W'
                    }
                    val stage = when {
                        solved(state) -> "solved"
                        cross == 4 && slots == 4 && top == 9 -> "oll"
                        cross == 4 && slots == 4 -> "f2l"
                        cross == 4 -> "cross"
                        else -> "none"
                    }
                    "stage $stage cross $cross slots $slots top $top"
                }
            }
            else -> {
                val state = applySequence(solvedState(),sequence)
                val centers = (0..5).map {
                    COLORS.indexOf(state[it*9+4]) to 0
                }
                return listOf("corners ${cycles(pieces(state,cornerStickers),corners,3)}", "edges ${cycles(pieces(state,edgeStickers),edges,2)}", "centers ${cycles(centers,FACES.map(Char::toString),1)}")
            }
        }
        return listOf(text)
    }
}
fun main() {
    val cube = Cube()
    repeat(readLine()!!.toInt()) {
        try {
            cube.command(readLine()!!).forEach(::println)
        }
        catch (p: Problem) {
            println(p.text)
        }
    }
}
