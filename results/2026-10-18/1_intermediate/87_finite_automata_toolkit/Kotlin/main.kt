private class Problem(val reason: String) : RuntimeException(reason)

private fun fail(reason: String): Nothing = throw Problem(reason)

private fun displayWord(word: String) = word.ifEmpty {
    "e"
}
private data class Transition(val from: Int, val symbol: Char, val to: Int)

private data class Automaton(val dfa: Boolean, val states: List<String>, val alphabet: List<Char>, val start: Int, val accepting: Set<Int>, val transitions: Set<Transition>) {
    private val adjacency = transitions.groupBy {
        it.from to it.symbol
    }.mapValues {
        (_, ts) -> ts.map {
            it.to
        }.toSet()
    }
    fun direct(p: Int, c: Char) = adjacency[p to c] ?: emptySet()

    fun delta(p: Int, c: Char) = direct(p, c).first()

    fun summary(name: String) = "${if (dfa) "DFA" else "NFA"} $name: alphabet=${alphabet.joinToString("")} states=${states.size} accepting=${accepting.size} transitions=${transitions.size}"

    fun closure(set: Set<Int>): Set<Int> {
        val result = set.toMutableSet()
        val queue = ArrayDeque<Int>()
        queue.addAll(set)
        while (queue.isNotEmpty()) for (q in direct(queue.removeFirst(), 'e')) if (result.add(q)) queue.add(q)
        return result
    }
    fun initial() = closure(setOf(start))

    fun destination(set: Set<Int>, c: Char) = closure(set.flatMap {
        direct(it, c)
    }.toSet())

    fun accepted(set: Set<Int>) = set.any {
        it in accepting
    }
    fun setText(set: Set<Int>) = set.sorted().joinToString(",", "{", "}") {
        states[it]
    }
    fun listText(set: Set<Int>) = set.sorted().joinToString(",") {
        states[it]
    }.ifEmpty {
        "none"
    }
    fun determinize(): Pair<Automaton, List<String>> {
        val sets = mutableListOf(initial())
        val index = mutableMapOf(sets[0] to 0)
        val transitions = mutableSetOf<Transition>()
        var i = 0
        while (i < sets.size) {
            for (c in alphabet) {
                val next = destination(sets[i], c)
                val j = index[next] ?: sets.size.also {
                    index[next] = it
                    sets.add(next)
                }
                transitions.add(Transition(i, c, j))
            }
            i++
        }
        val result = generated(true, "D", sets.size, alphabet, 0, sets.indices.filter {
            accepted(sets[it])
        }.toSet(), transitions)
        return result to sets.indices.map {
            "  D$it = ${setText(sets[it])}"
        }
    }
    fun reachable(reverse: Boolean): Set<Int> {
        val result = (if (reverse) accepting else setOf(start)).toMutableSet()
        val queue = ArrayDeque<Int>()
        queue.addAll(result)
        while (queue.isNotEmpty()) {
            val s = queue.removeFirst()
            for (t in transitions) if ((if (reverse) t.to else t.from) == s) {
                val next = if (reverse) t.from else t.to
                if (result.add(next)) queue.add(next)
            }
        }
        return result
    }
    fun minimize(): Pair<Automaton, List<String>> {
        val reachable = reachable(false)
        val details = mutableListOf("  unreachable: ${listText(states.indices.filter { it !in reachable }.toSet())}")
        var blocks = listOf(true, false).map {
            accept -> reachable.filter {
                (it in accepting) == accept
            }.toSet()
        }.filter {
            it.isNotEmpty()
        }.sortedBy {
            it.min()
        }
        fun partition(bs: List<Set<Int>>) = bs.joinToString(" ") {
            setText(it)
        }
        details.add("  round 0: ${partition(blocks)}")
        var round = 1
        while (true) {
            val group = IntArray(states.size)
            for ((i, block) in blocks.withIndex()) for (s in block) group[s] = i
            val split = reachable.sorted().groupBy {
                s -> listOf(group[s]) + alphabet.map {
                    group[delta(s, it)]
                }
            }
            val next = split.values.map {
                it.toSet()
            }.sortedBy {
                it.min()
            }
            if (next.size == blocks.size) break
            blocks = next
            details.add("  round $round: ${partition(blocks)}")
            round++
        }
        val group = IntArray(states.size)
        for ((i, block) in blocks.withIndex()) for (s in block) group[s] = i
        val sequence = mutableListOf(group[start])
        val names = mutableMapOf(sequence[0] to 0)
        val transitions = mutableSetOf<Transition>()
        var i = 0
        while (i < sequence.size) {
            val s = blocks[sequence[i]].min()
            for (c in alphabet) {
                val b = group[delta(s, c)]
                val j = names[b] ?: sequence.size.also {
                    names[b] = it
                    sequence.add(b)
                }
                transitions.add(Transition(i, c, j))
            }
            i++
        }
        val accepting = sequence.indices.filter {
            accepted(blocks[sequence[it]])
        }.toSet()
        for (j in sequence.indices) details.add("  M$j = ${setText(blocks[sequence[j]])}")
        return generated(true, "M", sequence.size, alphabet, 0, accepting, transitions) to details
    }
    fun product(other: Automaton, command: String): Pair<Automaton, List<String>> {
        val pairs = mutableListOf(start to other.start)
        val index = mutableMapOf(pairs[0] to 0)
        val transitions = mutableSetOf<Transition>()
        var i = 0
        while (i < pairs.size) {
            for (c in alphabet) {
                val pair = delta(pairs[i].first, c) to other.delta(pairs[i].second, c)
                val j = index[pair] ?: pairs.size.also {
                    index[pair] = it
                    pairs.add(pair)
                }
                transitions.add(Transition(i, c, j))
            }
            i++
        }
        val accepting = pairs.indices.filter {
            j ->
            val (p, q) = pairs[j]
            val a = p in this.accepting
            val b = q in other.accepting
            when (command) {
                "UNION" -> a || b
                "INTERSECT" -> a && b
                else -> a && !b
            }
        }.toSet()
        return generated(true, "P", pairs.size, alphabet, 0, accepting, transitions) to pairs.indices.map {
            j -> "  P$j = (${states[pairs[j].first]},${other.states[pairs[j].second]})"
        }
    }
    fun smallest(): String? {
        val seen = mutableSetOf(start)
        val queue = ArrayDeque<Pair<Int, String>>()
        queue.add(start to "")
        while (queue.isNotEmpty()) {
            val (s, word) = queue.removeFirst()
            if (s in accepting) return word
            for (c in alphabet) {
                val q = delta(s, c)
                if (seen.add(q)) queue.add(q to (word + c))
            }
        }
        return null
    }
    fun language(counting: Boolean = true): Long? {
        val live = reachable(true)
        val color = IntArray(states.size)
        val counts = LongArray(states.size)

        fun visit(s: Int): Long? {
            if (s !in live) return 0
            if (color[s] == 1) return null
            if (color[s] == 2) return counts[s]
            color[s] = 1
            var count = if (s in accepting) 1L else 0L
            for (c in alphabet) {
                val n = visit(delta(s, c)) ?: return null
                if (counting) count += n
            }
            color[s] = 2
            counts[s] = if (counting) count else 1L
            return counts[s]
        }
        return visit(start)
    }
    fun count(n: Int): Long {
        var counts = LongArray(states.size)
        counts[start] = 1
        repeat(n) {
            val next = LongArray(states.size)
            for (s in states.indices) for (c in alphabet) next[delta(s, c)] += counts[s]
            counts = next
        }
        return accepting.sumOf {
            counts[it]
        }
    }
    fun enumerate(limit: Int): String {
        val queue = ArrayDeque<Pair<Int, String>>()
        queue.add(start to "")
        var count = 0
        val first = mutableListOf<String>()
        while (queue.isNotEmpty()) {
            val (s, word) = queue.removeFirst()
            if (s in accepting) {
                count++
                if (first.size < 50) first.add(displayWord(word))
            }
            if (word.length < limit) for (c in alphabet) queue.add(delta(s, c) to (word + c))
        }
        return "$count" + (if (first.isEmpty()) "" else " " + first.joinToString(" ")) + if (count > 50) " ..." else ""
    }
    fun synchronize(): String {
        val initial = states.indices.toSet()
        val seen = mutableSetOf(initial)
        val queue = ArrayDeque<Pair<Set<Int>, String>>()
        queue.add(initial to "")
        while (queue.isNotEmpty()) {
            val (set, word) = queue.removeFirst()
            if (set.size == 1) return "SYNCHRONIZING ${displayWord(word)} -> ${states[set.first()]}"
            for (c in alphabet) {
                val next = set.map {
                    delta(it, c)
                }.toSet()
                if (seen.add(next)) queue.add(next to (word + c))
            }
        }
        return "NOT SYNCHRONIZING"
    }
    fun table(): List<String> {
        val symbols = alphabet + if (!dfa && transitions.any {
            it.symbol == 'e'
        })
        listOf('e') else emptyList()
        val rows = mutableListOf(listOf("") + symbols.map {
            it.toString()
        })
        for (p in states.indices) {
            val label = (if (p == start) "->" else "  ") + (if (p in accepting) "*" else " ") + states[p]
            rows.add(listOf(label) + symbols.map {
                c -> val set = direct(p, c)
                if (dfa) states[set.first()] else if (set.isEmpty()) "-" else setText(set)
            })
        }
        val widths = rows[0].indices.map {
            i -> rows.maxOf {
                it[i].length
            }
        }
        return rows.map {
            row -> row.indices.joinToString("  ") {
                row[it].padEnd(widths[it])
            }.trimEnd()
        }
    }
    fun show(name: String): String {
        val words = mutableListOf(if (dfa) "DFA" else "NFA", name, states.joinToString(","), alphabet.joinToString(""), states[start], if (accepting.isEmpty()) "-" else listText(accepting))
        for (p in states.indices) for (c in alphabet + 'e') for (q in direct(p, c).sorted()) words.add("${states[p]}:$c:${states[q]}")
        return words.joinToString(" ")
    }
}
private fun generated(dfa: Boolean, prefix: String, size: Int, alphabet: List<Char>, start: Int, accepting: Set<Int>, transitions: Set<Transition>) = Automaton(dfa, (0 until size).map {
    "$prefix$it"
},
alphabet, start, accepting, transitions)

private class Regular(val kind: Char, val children: List<Regular> = emptyList(), val symbol: Char = 'e')

private class RegexParser(val text: String) {
    var at = 0

    fun peek() = text.getOrNull(at) ?: '\u0000'

    fun error(): Nothing = fail("syntax error at ${at + 1}")

    fun atom(): Regular {
        val c = peek()
        if (c in 'a'..'z' || c in '0'..'9') {
            at++
            return Regular('s', symbol = c)
        }
        if (c == '(') {
            at++
            val r = alternation()
            if (peek() != ')') error()
            at++
            return r
        }
        error()
    }
    fun factor(): Regular {
        var r = atom()
        while (peek() in "*+?") {
            val c = peek()
            at++
            r = Regular(c, listOf(r))
        }
        return r
    }
    fun sequence(): Regular {
        val list = mutableListOf(factor())
        while (peek() in 'a'..'z' || peek() in '0'..'9' || peek() == '(') list.add(factor())
        return if (list.size == 1) list[0] else Regular('.', list)
    }
    fun alternation(): Regular {
        val list = mutableListOf(sequence())
        while (peek() == '|') {
            at++
            list.add(sequence())
        }
        return if (list.size == 1) list[0] else Regular('|', list)
    }
}
private fun regexAutomaton(alphabet: List<Char>, text: String): Automaton {
    for (c in text) if ((c in 'a'..'z' || c in '0'..'9') && c != 'e' && c !in alphabet) fail("unknown symbol $c")
    val parser = RegexParser(text)
    val tree = parser.alternation()
    if (parser.at != text.length) parser.error()
    var size = 0
    val transitions = mutableSetOf<Transition>()

    fun state() = size++

    fun build(r: Regular): Pair<Int, Int> {
        if (r.kind == 's') {
            val s = state()
            val f = state()
            transitions.add(Transition(s, r.symbol, f))
            return s to f
        }
        if (r.kind == '.') {
            val parts = r.children.map(::build)
            for ((a, b) in parts.zipWithNext()) transitions.add(Transition(a.second, 'e', b.first))
            return parts.first().first to parts.last().second
        }
        val s = state()
        if (r.kind == '|') {
            val parts = r.children.map(::build)
            val f = state()
            for ((a, b) in parts) {
                transitions.add(Transition(s, 'e', a))
                transitions.add(Transition(b, 'e', f))
            }
            return s to f
        }
        val (a, b) = build(r.children[0])
        val f = state()
        transitions.add(Transition(s, 'e', a))
        transitions.add(Transition(b, 'e', f))
        if (r.kind != '?') transitions.add(Transition(b, 'e', a))
        if (r.kind != '+') transitions.add(Transition(s, 'e', f))
        return s to f
    }
    val (s, f) = build(tree)
    return generated(false, "N", size, alphabet, s, setOf(f), transitions)
}
private class Toolkit {
    val automata = linkedMapOf<String, Automaton>()

    fun get(name: String) = automata[name] ?: fail("unknown automaton $name")

    fun fresh(name: String) {
        if (name in automata) fail("$name already exists")
    }
    fun register(name: String, a: Automaton, details: List<String> = emptyList()): List<String> {
        automata[name] = a
        return listOf(a.summary(name)) + details
    }
    fun define(dfa: Boolean, args: List<String>): List<String> {
        if (args.size < 5) fail("wrong number of arguments")
        fresh(args[0])
        val states = mutableListOf<String>()
        for (name in args[1].split(',')) {
            if (name in states) fail("duplicate state $name")
            states.add(name)
        }
        fun state(name: String): Int {
            val s = states.indexOf(name)
            if (s < 0) fail("unknown state $name")
            return s
        }
        val start = state(args[3])
        val accepting = mutableSetOf<Int>()
        if (args[4] != "-") for (name in args[4].split(',')) {
            val s = state(name)
            if (!accepting.add(s)) fail("duplicate state $name")
        }
        val alphabet = args[2].toList().sorted()
        val transitions = mutableSetOf<Transition>()
        for (word in args.drop(5)) {
            val fields = word.split(':')
            val p = state(fields[0])
            val c = fields[1][0]
            if (c == 'e' && dfa) fail("epsilon transition in DFA")
            if (c != 'e' && c !in alphabet) fail("unknown symbol $c")
            val q = state(fields[2])
            val t = Transition(p, c, q)
            if (t in transitions) fail("duplicate transition $word")
            if (dfa && transitions.any {
                it.from == p && it.symbol == c
            })
            fail("conflicting transition $word")
            transitions.add(t)
        }
        if (dfa) for (p in states.indices) for (c in alphabet) if (transitions.none {
            it.from == p && it.symbol == c
        })
        fail("missing transition ${states[p]}:$c")
        return register(args[0], Automaton(dfa, states, alphabet, start, accepting, transitions))
    }
    fun command(line: String): List<String> {
        val fields = line.split(' ')
        val c = fields[0]
        val args = fields.drop(1)
        val count = when (c) {
            "DFA", "NFA" -> return define(c == "DFA", args)
            "REGEX" -> {
                if (args.size != 3) fail("wrong number of arguments")
                fresh(args[0])
                return register(args[0], regexAutomaton(args[1].toList().sorted(), args[2]))
            }
            "ACCEPT", "CLOSURE", "TODFA", "EPSFREE", "MINIMIZE", "EQUIV", "COMPLEMENT", "REVERSE", "STAR", "ENUM", "COUNT" -> 2
            "UNION", "INTERSECT", "DIFF", "CONCAT" -> 3
            "EMPTY", "FINITE", "INFO", "TABLE", "SHOW", "SYNC", "DELETE" -> 1
            "LIST" -> 0
            else -> fail("unknown command $c")
        }
        if (args.size != count) fail("wrong number of arguments")
        if (c == "LIST") return automata.map {
            (name, a) -> a.summary(name)
        }.ifEmpty {
            listOf("(none)")
        }
        val a = get(args[0])
        val two = c in setOf("EQUIV", "UNION", "INTERSECT", "DIFF", "CONCAT")
        val b = if (two) get(args[1]) else null
        val creates = c in setOf("TODFA", "EPSFREE", "MINIMIZE", "UNION", "INTERSECT", "DIFF", "COMPLEMENT", "REVERSE", "CONCAT", "STAR")
        if (creates) fresh(args.last())
        if (c in setOf("MINIMIZE", "COMPLEMENT", "UNION", "INTERSECT", "DIFF", "SYNC")) {
            if (!a.dfa) fail("${args[0]} is not a DFA")
            if (two && !b!!.dfa) fail("${args[1]} is not a DFA")
        }
        if (two && a.alphabet != b!!.alphabet) fail("alphabets differ")
        when (c) {
            "DELETE" -> {
                automata.remove(args[0])
                return listOf("deleted ${args[0]}")
            }
            "ACCEPT" -> {
                val word = if (args[1] == "e") "" else args[1]
                for (ch in word) if (ch !in a.alphabet) fail("unknown symbol $ch")
                var set = a.initial()

                fun text(s: Set<Int>) = if (a.dfa) a.states[s.first()] else a.setText(s)
                var path = text(set)
                for (ch in word) {
                    set = a.destination(set, ch)
                    path += " -$ch-> ${text(set)}"
                }
                return listOf("${if (a.accepted(set)) "ACCEPT" else "REJECT"} $path")
            }
            "CLOSURE" -> {
                val set = mutableSetOf<Int>()
                for (name in args[1].split(',')) {
                    val s = a.states.indexOf(name)
                    if (s < 0) fail("unknown state $name")
                    set.add(s)
                }
                return listOf(a.setText(a.closure(set)))
            }
            "TABLE" -> return a.table()
            "SHOW" -> return listOf(a.show(args[0]))
            "SYNC" -> return listOf(a.synchronize())
            "EQUIV" -> {
                val x = a.determinize().first
                val z = b!!.determinize().first
                val first = x.start to z.start
                val seen = mutableSetOf(first)
                val queue = ArrayDeque<Pair<Pair<Int, Int>, String>>()
                queue.add(first to "")
                while (queue.isNotEmpty()) {
                    val (pair, word) = queue.removeFirst()
                    val (p, q) = pair
                    val xp = p in x.accepting
                    val zq = q in z.accepting
                    if (xp != zq) return listOf("NOT EQUIVALENT: ${displayWord(word)} is accepted only by ${if (xp) args[0] else args[1]}")
                    for (ch in x.alphabet) {
                        val next = x.delta(p, ch) to z.delta(q, ch)
                        if (seen.add(next)) queue.add(next to (word + ch))
                    }
                }
                return listOf("EQUIVALENT")
            }
        }
        if (c in setOf("ENUM", "COUNT", "EMPTY", "FINITE", "INFO")) {
            val d = a.determinize().first
            return when (c) {
                "ENUM" -> listOf(d.enumerate(args[1].toInt()))
                "COUNT" -> listOf(d.count(args[1].toInt()).toString())
                "EMPTY" -> listOf(d.smallest()?.let {
                    "NOT EMPTY ${displayWord(it)}"
                } ?: "EMPTY")
                "FINITE" -> listOf(d.language()?.let {
                    "FINITE $it"
                } ?: "INFINITE")
                else -> {
                    val deterministic = a.transitions.none {
                        it.symbol == 'e'
                    } && a.states.indices.all {
                        s -> a.alphabet.all {
                            a.direct(s, it).size <= 1
                        }
                    }
                    val complete = a.states.indices.all {
                        s -> a.alphabet.all {
                            a.direct(s, it).isNotEmpty()
                        }
                    }
                    val language = when (d.language(false)) {
                        null -> "infinite"
                        0L -> "empty"
                        else -> "finite"
                    }
                    listOf(a.summary(args[0]), "  epsilon transitions: ${a.transitions.count { it.symbol == 'e' }}", "  reachable: ${a.listText(a.reachable(false))}", "  live: ${a.listText(a.reachable(true))}", "  deterministic: ${if (deterministic) "yes" else "no"}", "  complete: ${if (complete) "yes" else "no"}", "  language: $language", "  minimal DFA states: ${d.minimize().first.states.size}")
                }
            }
        }
        val result: Automaton
        var details = emptyList<String>()
        when (c) {
            "TODFA" -> {
                val pair = a.determinize()
                result = pair.first
                details = pair.second
            }
            "MINIMIZE" -> {
                val pair = a.minimize()
                result = pair.first
                details = pair.second
            }
            "UNION", "INTERSECT", "DIFF" -> {
                val pair = a.product(b!!, c)
                result = pair.first
                details = pair.second
            }
            "COMPLEMENT" -> result = a.copy(accepting = a.states.indices.filter {
                it !in a.accepting
            }.toSet())
            "EPSFREE" -> {
                val accepting = mutableSetOf<Int>()
                val transitions = mutableSetOf<Transition>()
                for (p in a.states.indices) {
                    val closure = a.closure(setOf(p))
                    if (a.accepted(closure)) accepting.add(p)
                    for (ch in a.alphabet) for (q in a.destination(closure, ch)) transitions.add(Transition(p, ch, q))
                }
                result = a.copy(dfa = false, accepting = accepting, transitions = transitions)
            }
            "REVERSE", "STAR" -> {
                val transitions = mutableSetOf<Transition>()
                val accepting = mutableSetOf<Int>()
                if (c == "REVERSE") {
                    for (t in a.transitions) transitions.add(Transition(t.to + 1, t.symbol, t.from + 1))
                    for (p in a.accepting) transitions.add(Transition(0, 'e', p + 1))
                    accepting.add(a.start + 1)
                } else {
                    for (t in a.transitions) transitions.add(Transition(t.from + 1, t.symbol, t.to + 1))
                    transitions.add(Transition(0, 'e', a.start + 1))
                    accepting.add(0)
                    for (p in a.accepting) {
                        transitions.add(Transition(p + 1, 'e', a.start + 1))
                        accepting.add(p + 1)
                    }
                }
                result = generated(false, "N", a.states.size + 1, a.alphabet, 0, accepting, transitions)
            }
            "CONCAT" -> {
                val z = b!!
                val offset = a.states.size
                val transitions = a.transitions.toMutableSet()
                for (t in z.transitions) transitions.add(Transition(t.from + offset, t.symbol, t.to + offset))
                for (p in a.accepting) transitions.add(Transition(p, 'e', z.start + offset))
                result = generated(false, "N", offset + z.states.size, a.alphabet, a.start, z.accepting.map {
                    it + offset
                }.toSet(), transitions)
            } else -> error("unreachable command")
        }
        return register(args.last(), result, details)
    }
}
fun main() {
    val count = readLine()!!.toInt()
    val toolkit = Toolkit()
    repeat(count) {
        val line = readLine()!!
        if (!line.startsWith('#')) {
            try {
                toolkit.command(line).forEach(::println)
            } catch (e: Problem) {
                println("error: ${e.reason}")
            }
        }
    }
}
