private class Problem(val reason: String) : RuntimeException(reason)

private fun fail(reason: String): Nothing = throw Problem(reason)

private class Formula(val op: String, val left: Formula? = null, val right: Formula? = null)

private fun leaf(op: String) = Formula(op)

private fun negation(a: Formula) = Formula("~", a)

private fun binary(op: String, a: Formula, b: Formula) = Formula(op, a, b)

private fun same(a: Formula, b: Formula): Boolean = a === b || a.op == b.op && when {
    a.left == null && b.left == null -> true
    a.left == null || b.left == null -> false
    a.right == null && b.right == null -> same(a.left, b.left)
    a.right == null || b.right == null -> false
    else -> same(a.left, b.left) && same(a.right, b.right)
}
private fun precedence(op: String) = when (op) {
    "<->" -> 1
    "->" -> 2
    "|" -> 3
    "^" -> 4
    "&" -> 5
    "~" -> 6
    else -> 7
}
private fun notation(f: Formula): String {
    val a = f.left ?: return f.op
    if (f.op == "~") return "~" + if (a.right != null) "(${notation(a)})" else notation(a)
    val b = f.right!!
    val left = if (a.right != null && (precedence(a.op) < precedence(f.op) || a.op == "->" && f.op == "->")) "(${notation(a)})" else notation(a)
    val right = if (b.right != null && (precedence(b.op) < precedence(f.op) || b.op == f.op && f.op != "->")) "(${notation(b)})" else notation(b)
    return "$left ${f.op} $right"
}
private fun variables(f: Formula): Set<Char> = if (f.left == null) (if (f.op[0] in 'A'..'Z') setOf(f.op[0]) else emptySet()) else variables(f.left) + (f.right?.let(::variables) ?: emptySet())

private fun evaluate(f: Formula, vars: List<Char>, row: Int): Int {
    val a = f.left ?: return when (f.op) {
        "0" -> 0
        "1" -> 1
        else -> row shr (vars.size - 1 - vars.indexOf(f.op[0])) and 1
    }
    val x = evaluate(a, vars, row)
    if (f.op == "~") return 1 - x
    val y = evaluate(f.right!!, vars, row)
    return when (f.op) {
        "&" -> x and y
        "|" -> x or y
        "^" -> x xor y
        "->" -> (1 - x) or y
        else -> if (x == y) 1 else 0
    }
}
private data class Token(val text: String, val position: Int)

private class Parser(text: String, start: Int, val definitions: Map<String, Formula>) {
    val tokens = mutableListOf<Token>()
    var at = 0
    val end = start + text.length
    init {
        var i = 0
        while (i < text.length) {
            if (text[i] == ' ') {
                i++
                continue
            }
            val begin = i
            when {
                text.startsWith("<->", i) -> i += 3
                text.startsWith("->", i) -> i += 2
                text[i] in 'a'..'z' -> {
                    i++
                    while (i < text.length && (text[i] in 'a'..'z' || text[i] in '0'..'9')) i++
                }
                text[i] in 'A'..'Z' || text[i] in "01~&^|()" -> i++
                else -> fail("invalid character '${text[i]}' at ${start + i}")
            }
            tokens.add(Token(text.substring(begin, i), start + begin))
        }
    }
    fun peek() = tokens.getOrNull(at)?.text ?: ""

    fun error(): Nothing = fail(tokens.getOrNull(at)?.let {
        "unexpected '${it.text}' at ${it.position}"
    } ?: "unexpected end of formula at $end")

    fun unary(): Formula {
        if (peek() == "~") {
            at++
            return negation(unary())
        }
        if (peek() == "(") {
            at++
            val f = expression(1)
            if (peek() != ")") error()
            at++
            return f
        }
        val t = tokens.getOrNull(at) ?: error()
        if (t.text[0] in 'a'..'z') {
            val f = definitions[t.text] ?: fail("undefined name '${t.text}' at ${t.position}")
            at++
            return f
        }
        if (t.text == "0" || t.text == "1" || t.text.length == 1 && t.text[0] in 'A'..'Z') {
            at++
            return leaf(t.text)
        }
        error()
    }
    fun expression(level: Int): Formula {
        if (level == 6) return unary()
        var f = expression(level + 1)
        val op = listOf("", "<->", "->", "|", "^", "&")[level]
        while (peek() == op) {
            at++
            f = binary(op, f, expression(if (op == "->") level else level + 1))
        }
        return f
    }
    fun parse(): Formula {
        val f = expression(1)
        if (at != tokens.size) error()
        return f
    }
}
private fun negate(a: Formula) = when (a.op) {
    "0" -> leaf("1")
    "1" -> leaf("0")
    "~" -> a.left!!
    else -> negation(a)
}
private fun simplifyPair(op: String, a: Formula, b: Formula): Formula {
    val eq = same(a, b)
    val complementary = a.op == "~" && same(a.left!!, b) || b.op == "~" && same(a, b.left!!)
    val result = when (op) {
        "&" -> when {
            a.op == "0" || b.op == "0" -> leaf("0")
            a.op == "1" -> b
            b.op == "1" || eq -> a
            complementary -> leaf("0")
            else -> null
        }
        "|" -> when {
            a.op == "1" || b.op == "1" -> leaf("1")
            a.op == "0" -> b
            b.op == "0" || eq -> a
            complementary -> leaf("1")
            else -> null
        }
        "^" -> when {
            a.op == "0" -> b
            b.op == "0" -> a
            a.op == "1" -> negate(b)
            b.op == "1" -> negate(a)
            eq -> leaf("0")
            complementary -> leaf("1")
            else -> null
        }
        "->" -> when {
            a.op == "0" || b.op == "1" -> leaf("1")
            a.op == "1" -> b
            b.op == "0" -> negate(a)
            eq -> leaf("1")
            complementary -> b
            else -> null
        } else -> when {
            a.op == "1" -> b
            b.op == "1" -> a
            a.op == "0" -> negate(b)
            b.op == "0" -> negate(a)
            eq -> leaf("1")
            complementary -> leaf("0")
            else -> null
        }
    }
    return result ?: binary(op, a, b)
}
private fun simplify(f: Formula, assignments: Map<Char, Int> = emptyMap()): Formula {
    val child = f.left ?: return assignments[f.op[0]]?.let {
        leaf(it.toString())
    } ?: f
    val a = simplify(child, assignments)
    return if (f.op == "~") negate(a) else simplifyPair(f.op, a, simplify(f.right!!, assignments))
}
private fun dual(f: Formula): Formula {
    val child = f.left ?: return when (f.op) {
        "0" -> leaf("1")
        "1" -> leaf("0")
        else -> f
    }
    val a = dual(child)
    if (f.op == "~") return negation(a)
    val b = dual(f.right!!)
    return when (f.op) {
        "&" -> binary("|", a, b)
        "|" -> binary("&", a, b)
        "^" -> binary("<->", a, b)
        "<->" -> binary("^", a, b)
        else -> binary("&", negation(a), b)
    }
}
private fun nnf(f: Formula, positive: Boolean = true, memo: MutableMap<Pair<Formula, Boolean>, Formula> = mutableMapOf()): Formula {
    val key = f to positive
    memo[key]?.let {
        return it
    }
    val result = when {
        f.left == null -> if (positive) f else when (f.op) {
            "0" -> leaf("1")
            "1" -> leaf("0")
            else -> negation(f)
        }
        f.op == "~" -> nnf(f.left, !positive, memo)
        f.op == "&" || f.op == "|" -> binary(if ((f.op == "&") == positive) "&" else "|", nnf(f.left, positive, memo), nnf(f.right!!, positive, memo))
        f.op == "->" -> binary(if (positive) "|" else "&", nnf(f.left, !positive, memo), nnf(f.right!!, positive, memo))
        else -> {
            val equal = (f.op == "<->") == positive
            binary("|", binary("&", nnf(f.left, true, memo), nnf(f.right!!, equal, memo)), binary("&", nnf(f.left, false, memo), nnf(f.right, !equal, memo)))
        }
    }
    memo[key] = result
    return result
}
private fun pattern(row: Int, n: Int) = (0 until n).joinToString("") {
    if (row and (1 shl (n - 1 - it)) == 0) "0" else "1"
}
private fun invert(p: String) = p.map {
    when (it) {
        '0' -> '1'
        '1' -> '0'
        else -> '-'
    }
}.joinToString("")

private fun patternKey(p: String) = p.map {
    when (it) {
        '1' -> '0'
        '0' -> '1'
        else -> '2'
    }
}.joinToString("")

private fun sortedPatterns(ps: Collection<String>) = ps.sortedBy(::patternKey)

private fun literals(p: String) = p.count {
    it != '-'
}
private fun contains(p: String, row: Int) = p.zip(pattern(row, p.length)).all {
    (a, b) -> a == '-' || a == b
}
private fun termText(p: String, vars: List<Char>, clause: Boolean): String {
    val parts = p.zip(vars).mapNotNull {
        (c, v) -> when (c) {
            '1' -> "$v"
            '0' -> "~$v"
            else -> null
        }
    }
    return if (parts.isEmpty()) (if (clause) "0" else "1") else parts.joinToString(if (clause) " | " else " & ")
}
private fun coverText(ps: List<String>, vars: List<Char>, clause: Boolean): String {
    if (ps.isEmpty()) return if (clause) "1" else "0"
    return ps.joinToString(if (clause) " & " else " | ") {
        p -> val text = termText(p, vars, clause)
        if (clause && ps.size >= 2 && literals(p) >= 2) "($text)" else text
    }
}
private fun coefficients(values: List<Int>): List<Int> {
    val c = values.toMutableList()
    var bit = 1
    while (bit < c.size) {
        for (s in c.indices) if (s and bit != 0) c[s] = c[s] xor c[s xor bit]
        bit *= 2
    }
    return c
}
private fun assignment(row: Int, vars: List<Char>) = vars.zip(pattern(row, vars.size).toList()).joinToString(" ", "{", "}") {
    (v, n) -> "$v=$n"
}
private fun minimize(vars: List<Char>, on: List<Int>, dc: List<Int>, pos: Boolean): List<String> {
    var stage = (on + dc).map {
        pattern(it, vars.size)
    }.toSet()
    val primes = mutableListOf<String>()
    val output = mutableListOf<String>()
    var k = 0
    while (true) {
        val list = stage.toList()
        val used = mutableSetOf<Int>()
        val next = mutableSetOf<String>()
        for (i in list.indices) for (j in i + 1 until list.size) {
            val different = list[i].indices.filter {
                list[i][it] != list[j][it]
            }
            if (different.size == 1) {
                val d = different[0]
                if (list[i][d] != '-' && list[j][d] != '-') {
                    val p = list[i].toCharArray()
                    p[d] = '-'
                    next.add(String(p))
                    used.add(i)
                    used.add(j)
                }
            }
        }
        val added = list.filterIndexed {
            i, _ -> i !in used
        }
        if (!pos) output.add("stage $k: implicants ${stage.size} primes ${added.size}")
        primes.addAll(added)
        if (next.isEmpty()) break
        stage = next
        k++
    }
    val targets = sortedPatterns(primes.filter {
        p -> on.any {
            contains(p, it)
        }
    })
    val essential = sortedSetOf<Int>()
    for (r in on) {
        val list = targets.indices.filter {
            contains(targets[it], r)
        }
        if (list.size == 1) essential.add(list[0])
    }
    val optional = targets.indices.filter {
        it !in essential
    }
    var best: List<String>? = null
    var bestLiterals = 0

    fun earlier(a: List<String>, b: List<String>): Boolean {
        for (i in a.indices) {
            val cmp = patternKey(a[i]).compareTo(patternKey(b[i]))
            if (cmp != 0) return cmp < 0
        }
        return false
    }
    for (mask in 0 until (1 shl optional.size)) {
        val chosen = essential.toMutableSet()
        for (i in optional.indices) if (mask and (1 shl i) != 0) chosen.add(optional[i])
        if (best != null && chosen.size > best!!.size) continue
        if (!on.all {
            r -> chosen.any {
                contains(targets[it], r)
            }
        })
        continue
        val ps = sortedPatterns(chosen.map {
            if (pos) invert(targets[it]) else targets[it]
        })
        val count = ps.sumOf(::literals)
        if (best == null || ps.size < best!!.size || ps.size == best!!.size && (count < bestLiterals || count == bestLiterals && earlier(ps, best!!))) {
            best = ps
            bestLiterals = count
        }
    }
    val cover = best!!
    if (!pos) {
        for ((heading, ps) in listOf("primes" to targets, "essential" to essential.map {
            targets[it]
        }))
        output.add("$heading: " + if (ps.isEmpty()) "none" else ps.joinToString(", ") {
            termText(it, vars, false)
        })
    }
    output.add("minimal: ${coverText(cover, vars, pos)}")
    output.add("${if (pos) "clauses" else "terms"} ${cover.size} literals $bestLiterals")
    return output
}
private data class Clause(val positive: Int = 0, val negative: Int = 0)

private fun tidy(cs: Set<Clause>) = cs.filter {
    c -> c.positive and c.negative == 0 && cs.none {
        e -> e != c && e.positive and c.positive == e.positive && e.negative and c.negative == e.negative
    }
}.toSet()

private fun clauses(f: Formula, vars: List<Char>, memo: MutableMap<Formula, Set<Clause>> = mutableMapOf()): Set<Clause> {
    memo[f]?.let {
        return it
    }
    val result = when {
        f.op == "1" -> emptySet()
        f.op == "0" -> setOf(Clause())
        f.op == "~" || f.left == null -> {
            val bit = 1 shl vars.indexOf(if (f.op == "~") f.left!!.op[0] else f.op[0])
            setOf(if (f.op == "~") Clause(negative = bit) else Clause(positive = bit))
        } else -> {
            val a = clauses(f.left, vars, memo)
            val b = clauses(f.right!!, vars, memo)
            tidy(if (f.op == "&") a + b else a.flatMap {
                x -> b.map {
                    y -> Clause(x.positive or y.positive, x.negative or y.negative)
                }
            }.filter {
                it.positive and it.negative == 0
            }.toSet())
        }
    }
    memo[f] = result
    return result
}
private fun clausePatterns(cs: Set<Clause>, n: Int) = sortedPatterns(cs.map {
    c -> (0 until n).joinToString("") {
        i -> when {
            c.positive and (1 shl i) != 0 -> "1"
            c.negative and (1 shl i) != 0 -> "0"
            else -> "-"
        }
    }
})

private fun validName(s: String) = s.matches(Regex("[a-z][a-z0-9]{0,7}"))

private fun words(s: String) = s.split(' ').filter {
    it.isNotEmpty()
}
private class Workbench {
    val definitions = sortedMapOf<String, Formula>()

    fun parse(text: String, start: Int) = Parser(text, start, definitions).parse()

    fun define(name: String, f: Formula): List<String> {
        val heading = if (name in definitions) "redefined" else "defined"
        definitions[name] = f
        return listOf("$heading $name = ${notation(f)}")
    }
    fun command(line: String): List<String> {
        val command = line.substringBefore(' ')
        val argument = if (' ' in line) line.substringAfter(' ') else ""
        val known = setOf("DEF", "DEFSUM", "DEL", "LIST", "PRINT", "TABLE", "MINTERMS", "MAXTERMS", "DNF", "CNF", "NNF", "DUAL", "ANF", "SIMPLIFY", "RESTRICT", "COFACTOR", "MINIMIZE", "MINDC", "MINPOS", "KMAP", "SAT", "TAUT", "COUNT", "EQUIV", "IMPLIES", "PROPS", "BDD", "CLAUSES", "DP")
        if (command !in known) fail("unknown command $command")
        if (command == "LIST") {
            if (' ' in line) fail("unexpected argument")
            return listOf("names: ${definitions.size}") + definitions.map {
                (n, f) -> "$n = ${notation(f)}"
            }
        }
        if (' ' !in line) fail("missing argument")
        if (command == "DEL") {
            if (!validName(argument)) fail("invalid name '$argument'")
            if (definitions.remove(argument) == null) fail("undefined name '$argument'")
            return listOf("deleted $argument")
        }
        if (command == "DEF") {
            val at = argument.indexOf(' ')
            if (at < 0) fail("missing argument")
            val name = argument.substring(0, at)
            if (!validName(name)) fail("invalid name '$name'")
            return define(name, parse(argument.substring(at + 1), name.length + 6))
        }
        if (command == "DEFSUM") {
            val at = argument.indexOf(';')
            if (at < 0) fail("missing ';'")
            val front = words(argument.substring(0, at))
            if (front.isEmpty()) fail("missing argument")
            val name = front[0]
            if (!validName(name)) fail("invalid name '$name'")
            val list = front.drop(1)
            if (list.isEmpty() || list.any {
                it.length != 1 || it[0] !in 'A'..'Z'
            } || list.zipWithNext().any {
                (a, b) -> a >= b
            })
            fail("bad variable list")
            if (list.size >= 9) fail("too many variables: ${list.size}")
            val terms = mutableListOf<Formula>()
            var previous = -1
            for (word in words(argument.substring(at + 1))) {
                if (!word.matches(Regex("0|[1-9][0-9]*"))) fail("bad minterm '$word'")
                val row = word.toInt()
                if (row >= (1 shl list.size) || row <= previous) fail("bad minterm '$word'")
                previous = row
                val nodes = list.zip(pattern(row, list.size).toList()).map {
                    (v, n) -> if (n == '1') leaf(v) else negation(leaf(v))
                }
                terms.add(nodes.reduce {
                    a, b -> binary("&", a, b)
                })
            }
            return define(name, if (terms.isEmpty()) leaf("0") else terms.reduce {
                a, b -> binary("|", a, b)
            })
        }
        val split = command in setOf("RESTRICT", "COFACTOR", "MINDC", "EQUIV", "IMPLIES")
        val at = if (split) argument.indexOf(';') else -1
        if (split && at < 0) fail("missing ';'")
        val front = if (split) argument.substring(0, at) else argument
        val back = if (split) argument.substring(at + 1) else ""
        val f = parse(front, command.length + 2)
        val g = if (command in setOf("MINDC", "EQUIV", "IMPLIES")) parse(back, command.length + at + 3) else null
        if (command == "RESTRICT" || command == "COFACTOR") {
            val list = words(back)
            if (command == "RESTRICT") {
                if (list.isEmpty()) fail("missing assignment")
                val assignments = mutableMapOf<Char, Int>()
                for (word in list) {
                    if (!word.matches(Regex("[A-Z]=[01]"))) fail("bad assignment '$word'")
                    if (word[0] in assignments) fail("duplicate variable ${word[0]}")
                    assignments[word[0]] = word[2] - '0'
                }
                return listOf("restricted: ${notation(simplify(f, assignments))}")
            }
            if (list.size != 1 || list[0].length != 1 || list[0][0] !in 'A'..'Z') fail("bad variable")
            val x = list[0][0]
            val high = simplify(f, mapOf(x to 1))
            val low = simplify(f, mapOf(x to 0))
            return listOf("cofactor $x=1: ${notation(high)}", "cofactor $x=0: ${notation(low)}", "difference: ${notation(simplifyPair("^", high, low))}")
        }
        val vars = (variables(f) + (g?.let(::variables) ?: emptySet())).sorted()
        if (command !in setOf("PRINT", "NNF", "DUAL", "SIMPLIFY", "CLAUSES", "DP") && vars.size >= 9) fail("too many variables: ${vars.size}")
        when (command) {
            "PRINT" -> {
                fun measure(f: Formula): Pair<Int, Int> {
                    val a = f.left?.let(::measure) ?: (0 to 0)
                    val b = f.right?.let(::measure) ?: (0 to 0)
                    return 1 + a.first + b.first to 1 + maxOf(a.second, b.second)
                }
                val (size, depth) = measure(f)
                return listOf("formula: ${notation(f)}", "variables: ${vars.joinToString(" ").ifEmpty { "none" }}", "size $size depth $depth")
            }
            "NNF" -> return listOf("nnf: ${notation(nnf(f))}")
            "DUAL" -> return listOf("dual: ${notation(dual(f))}")
            "SIMPLIFY" -> return listOf("simplified: ${notation(simplify(f))}")
            "CLAUSES", "DP" -> {
                var cs = clauses(nnf(f), vars)
                if (command == "CLAUSES") return listOf("clauses: ${coverText(clausePatterns(cs, vars.size), vars, true)}")
                val output = mutableListOf("start: clauses ${cs.size}")
                for (i in vars.indices) {
                    if (cs.isEmpty() || Clause() in cs) break
                    val bit = 1 shl i
                    val p = cs.filter {
                        it.positive and bit != 0
                    }
                    val q = cs.filter {
                        it.negative and bit != 0
                    }
                    val resolvents = p.flatMap {
                        a -> q.map {
                            b -> Clause((a.positive or b.positive) and bit.inv(), (a.negative or b.negative) and bit.inv())
                        }
                    }.filter {
                        it.positive and it.negative == 0
                    }.toSet()
                    cs = tidy(cs.filter {
                        (it.positive or it.negative) and bit == 0
                    }.toSet() + resolvents)
                    output.add("eliminate ${vars[i]}: resolvents ${resolvents.size} clauses ${cs.size}")
                }
                output.add("result: ${if (Clause() in cs) "unsatisfiable" else "satisfiable"}")
                return output
            }
        }
        val values = (0 until (1 shl vars.size)).map {
            evaluate(f, vars, it)
        }
        val other = g?.let {
            term -> values.indices.map {
                evaluate(term, vars, it)
            }
        } ?: emptyList()
        val models = values.indices.filter {
            values[it] == 1
        }
        val falseRows = values.indices.filter {
            values[it] == 0
        }
        return when (command) {
            "TABLE" -> listOf(vars.joinToString("") {
                "$it "
            } + "| F") + values.indices.map {
                r -> pattern(r, vars.size).map {
                    "$it "
                }.joinToString("") + "| ${values[r]}"
            }
            "MINTERMS", "MAXTERMS" -> listOf("${command.lowercase()}: " + (if (command == "MINTERMS") models else falseRows).joinToString(" ").ifEmpty {
                "none"
            })
            "DNF", "CNF" -> {
                val pos = command == "CNF"
                val ps = (if (pos) falseRows else models).map {
                    r -> pattern(r, vars.size).let {
                        if (pos) invert(it) else it
                    }
                }
                listOf("${command.lowercase()}: ${coverText(ps, vars, pos)}")
            }
            "ANF" -> {
                val c = coefficients(values)
                val ps = c.indices.filter {
                    c[it] == 1
                }.map {
                    pattern(it, vars.size).replace('0', '-')
                }.sortedWith(compareBy<String> {
                    literals(it)
                }.thenBy {
                    patternKey(it)
                })
                listOf("anf: " + ps.joinToString(" ^ ") {
                    termText(it, vars, false)
                }.ifEmpty {
                    "0"
                })
            }
            "SAT" -> listOf(models.firstOrNull()?.let {
                "satisfiable: ${assignment(it, vars)}"
            } ?: "unsatisfiable")
            "TAUT" -> listOf(falseRows.firstOrNull()?.let {
                "not a tautology: ${assignment(it, vars)}"
            } ?: "tautology")
            "COUNT" -> listOf("models: ${models.size} of ${values.size}")
            "EQUIV", "IMPLIES" -> {
                val r = values.indices.firstOrNull {
                    if (command == "EQUIV") values[it] != other[it] else values[it] == 1 && other[it] == 0
                }
                listOf(if (r == null) (if (command == "EQUIV") "equivalent" else "implies") else if (command == "EQUIV") "not equivalent: ${assignment(r, vars)} f=${values[r]} g=${other[r]}" else "does not imply: ${assignment(r, vars)}")
            }
            "MINIMIZE", "MINDC", "MINPOS" -> {
                val on = values.indices.filter {
                    if (command == "MINPOS") values[it] == 0 else values[it] == 1 && (other.isEmpty() || other[it] == 0)
                }
                minimize(vars, on, other.indices.filter {
                    other[it] == 1
                },
                command == "MINPOS")
            }
            "PROPS" -> {
                val depends = vars.indices.filter {
                    i -> values.indices.any {
                        values[it] != values[it xor (1 shl (vars.size - 1 - i))]
                    }
                }.map {
                    vars[it]
                }
                val c = coefficients(values)
                val symmetric = values.indices.groupBy {
                    Integer.bitCount(it)
                }.values.all {
                    rows -> rows.map {
                        values[it]
                    }.distinct().size == 1
                }
                val properties = listOf("zero-preserving" to (values[0] == 0), "one-preserving" to (values.last() == 1), "self-dual" to values.indices.all {
                    values[it] != values[values.lastIndex - it]
                }, "monotone" to values.indices.all {
                    r -> vars.indices.all {
                        i -> r and (1 shl i) != 0 || values[r] <= values[r or (1 shl i)]
                    }
                }, "linear" to c.indices.all {
                    c[it] == 0 || Integer.bitCount(it) <= 1
                }, "symmetric" to symmetric)
                listOf("depends: ${depends.joinToString(" ").ifEmpty { "none" }}") + properties.map {
                    (name, value) -> "$name: ${if (value) "yes" else "no"}"
                }
            }
            "KMAP" -> {
                if (vars.size !in 2..4) fail("kmap needs 2 to 4 variables")
                val p = vars.size / 2
                val q = vars.size - p
                val output = mutableListOf(vars.take(p).joinToString("") + "\\" + vars.drop(p).joinToString("") + (0 until (1 shl q)).joinToString("") {
                    " " + pattern(it xor (it / 2), q)
                })
                for (i in 0 until (1 shl p)) {
                    val r = i xor (i / 2)
                    output.add(pattern(r, p) + " ".repeat(q + 1) + (0 until (1 shl q)).joinToString("") {
                        j -> " ".repeat(q) + values[(r shl q) or (j xor (j / 2))]
                    })
                }
                output
            }
            "BDD" -> {
                val nodes = mutableListOf<Triple<Int, Int, Int>>()

                fun build(level: Int, list: List<Int>): Int {
                    if (list.size == 1) return list[0]
                    val lo = build(level + 1, list.take(list.size / 2))
                    val hi = build(level + 1, list.drop(list.size / 2))
                    if (lo == hi) return lo
                    val triple = Triple(level, lo, hi)
                    val old = nodes.indexOf(triple)
                    if (old >= 0) return old + 2
                    nodes.add(triple)
                    return nodes.size + 1
                }
                val root = build(0, values)
                val paths = mutableListOf(0, 1)
                val output = mutableListOf("nodes: ${nodes.size}")
                for ((i, node) in nodes.withIndex()) {
                    val (v, lo, hi) = node
                    output.add("${i + 2} = ite(${vars[v]}, $hi, $lo)")
                    paths.add(paths[lo] + paths[hi])
                }
                output.add("root: $root")
                output.add("paths: ${paths[root]}")
                output
            } else -> error("unreachable command")
        }
    }
}
fun main() {
    val count = readLine()!!.toInt()
    val workbench = Workbench()
    repeat(count) {
        try {
            workbench.command(readLine()!!).forEach(::println)
        } catch (e: Problem) {
            println("error: ${e.reason}")
        }
    }
}
