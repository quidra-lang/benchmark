private data class Token(val text: String, val kind: String, val line: Int)

private class Problem(val line: Int, val reason: String) : RuntimeException(reason)

private fun fail(t: Token, reason: String): Nothing = throw Problem(t.line, reason)
private val signatures = mapOf(
    "FD" to "E", "BK" to "E", "RT" to "E", "LT" to "E", "SETH" to "E",
    "PU" to "", "PD" to "", "PE" to "", "SETPEN" to "E", "SETXY" to "EE", "SETX" to "E", "SETY" to "E",
    "HOME" to "", "CS" to "", "CLEAN" to "", "FILL" to "", "LABEL" to "P", "SNAPSHOT" to "",
    "REPEAT" to "EL", "FOR" to "QEEL", "WHILE" to "EL", "IF" to "EL", "IFELSE" to "ELL",
    "TEST" to "E", "IFTRUE" to "L", "IFFALSE" to "L", "STOP" to "", "OUTPUT" to "E",
    "MAKE" to "QE", "LOCAL" to "Q", "LOCALMAKE" to "QE", "TRACE" to "Q", "UNTRACE" to "Q", "SEED" to "E", "PRINT" to "P"
)
private val aliases = mapOf("FORWARD" to "FD", "BACK" to "BK", "RIGHT" to "RT", "LEFT" to "LT", "SETHEADING" to "SETH", "PENUP" to "PU", "PENDOWN" to "PD", "PENERASE" to "PE", "CLEARSCREEN" to "CS", "IFT" to "IFTRUE", "IFF" to "IFFALSE", "OP" to "OUTPUT", "PR" to "PRINT")
private val functions = mapOf("XCOR" to 0, "YCOR" to 0, "HEADING" to 0, "REPCOUNT" to 0, "RANDOM" to 1, "ABS" to 1, "NOT" to 1, "AND" to 2, "OR" to 2, "MAX" to 2, "MIN" to 2)

private fun canonical(s: String) = aliases[s] ?: s

private fun primitive(s: String) = canonical(s) in signatures || s in functions || s in setOf("TO", "END", "MOD")

private fun name(s: String) = s.isNotEmpty() && s[0] in 'A'..'Z' && s.all {
    it in 'A'..'Z' || it in '0'..'9' || it == '_'
}

private fun lex(text: String, line: Int): List<Token> {
    val s = text.substringBefore(';').uppercase()
    val out = mutableListOf<Token>()
    var i = 0
    while (i < s.length) {
        val c = s[i]
        if (c == ' ') {
            i++
            continue
        }
        if (c in "[]()+-*/=<>") {
            var word = c.toString()
            var kind = "symbol"
            if (c == '-' && (i == 0 || s[i - 1] in " [(") && i + 1 < s.length && s[i + 1] != ' ') kind = "sign"
            if (c == '<' && i + 1 < s.length && s[i + 1] in "=>" || c == '>' && i + 1 < s.length && s[i + 1] == '=') {
                word += s[i + 1]
                i++
            }
            out.add(Token(word, kind, line))
            i++
            continue
        }
        val start = i
        while (i < s.length && s[i] !in " []()+-*/=<>") i++
        val word = s.substring(start, i)
        val kind = when {
            word.all {
                it in '0'..'9'
            } -> "number"
            word.startsWith(':') && name(word.drop(1)) -> "variable"
            word.startsWith('"') && name(word.drop(1)) -> "quote"
            name(word) -> "word"
            else -> throw Problem(line, "bad token '$word'")
        }
        out.add(Token(word, kind, line))
    }
    return out
}

private data class Expr(val token: Token, val op: String, val args: List<Expr> = emptyList())

private data class Item(val word: String? = null, val expr: Expr? = null)

private data class Command(val token: Token, val op: String, val exprs: List<Expr> = emptyList(), val words: List<String> = emptyList(), val lists: List<List<Command>> = emptyList(), val items: List<Item> = emptyList())

private class Procedure(val token: Token, val params: List<String>) {
    val raw = mutableListOf<Token>()
    var body = emptyList<Command>()
}

private class Parser(val tokens: List<Token>, val procedures: Map<String, Procedure>, val inside: Boolean) {
    var at = 0

    fun unknown(t: Token) = t.kind == "word" && !primitive(t.text) && t.text !in procedures

    fun next(owner: Token): Token {
        val t = tokens.getOrNull(at)
        if (t == null || t.text == "]" || t.text == ")") fail(owner, "not enough inputs to ${owner.text}")
        if (unknown(t)) fail(t, "I don't know how to ${t.text}")
        return t
    }

    fun rejected(owner: Token, t: Token): Nothing = fail(t, "${owner.text} doesn't like ${t.text} as input")

    fun expression(owner: Token): Expr = binary(owner, 0)

    fun binary(owner: Token, level: Int): Expr {
        if (level == 3) return term(owner)
        val operators = when (level) {
            0 -> setOf("=", "<>", "<", ">", "<=", ">=")
            1 -> setOf("+", "-")
            else -> setOf("*", "/", "MOD")
        }
        var left = binary(owner, level + 1)
        while (at < tokens.size && tokens[at].text in operators && tokens[at].kind != "sign") {
            val op = tokens[at++]
            val right = binary(op, level + 1)
            left = Expr(op, op.text, listOf(left, right))
        }
        return left
    }

    fun term(owner: Token): Expr {
        val t = next(owner)
        at++
        return when {
            t.kind == "number" -> Expr(t, "NUMBER")
            t.kind == "variable" -> Expr(t, "VARIABLE")
            t.text == "-" -> Expr(t, "NEG", listOf(term(t)))
            t.text == "(" -> {
                val e = expression(t)
                if (tokens.getOrNull(at)?.text != ")") fail(t, "missing )")
                at++
                e
            }
            t.kind == "word" && t.text in functions -> Expr(t, "FUNCTION", List(functions.getValue(t.text)) {
                expression(t)
            })
            t.kind == "word" && t.text in procedures -> Expr(t, "CALL", List(procedures.getValue(t.text).params.size) {
                expression(t)
            })
            else -> rejected(owner, t)
        }
    }

    fun item(owner: Token): Item {
        val t = next(owner)
        return if (t.kind == "quote") {
            at++
            Item(word = t.text.drop(1))
        } else Item(expr = expression(owner))
    }

    fun list(owner: Token): List<Command> {
        val open = next(owner)
        if (open.text != "[") rejected(owner, open)
        at++
        val out = mutableListOf<Command>()
        while (at < tokens.size && tokens[at].text != "]") out.add(command())
        if (at == tokens.size) fail(open, "missing ]")
        at++
        return out
    }

    fun command(): Command {
        val t = tokens[at++]
        if (t.text == "]") fail(t, "unexpected ]")
        if (t.text == "(" && tokens.getOrNull(at)?.let {
            it.kind == "word" && canonical(it.text) == "PRINT"
        } == true) {
            val owner = tokens[at++]
            val items = mutableListOf<Item>()
            while (tokens.getOrNull(at)?.text != ")") {
                if (at == tokens.size || tokens[at].text == "]") fail(t, "missing )")
                items.add(item(owner))
            }
            at++
            return Command(t, "MULTIPRINT", items = items)
        }
        if (t.kind == "word" && t.text in setOf("TO", "END")) fail(t, "misplaced ${t.text}")
        val op = canonical(t.text)
        if (t.kind == "word" && op in signatures) {
            if (!inside && op in setOf("STOP", "OUTPUT", "LOCAL", "LOCALMAKE")) fail(t, "can only use ${t.text} inside a procedure")
            val exprs = mutableListOf<Expr>()
            val words = mutableListOf<String>()
            val lists = mutableListOf<List<Command>>()
            val items = mutableListOf<Item>()
            for (kind in signatures.getValue(op)) when (kind) {
                'E' -> exprs.add(expression(t))
                'P' -> items.add(item(t))
                'L' -> lists.add(list(t))
                'Q' -> {
                    val q = next(t)
                    if (q.kind != "quote") rejected(t, q)
                    at++
                    words.add(q.text.drop(1))
                    if (op in setOf("TRACE", "UNTRACE") && q.text.drop(1) !in procedures) fail(q, "I don't know how to ${q.text.drop(1)}")
                }
            }
            return Command(t, op, exprs, words, lists, items)
        }
        if (t.kind == "word" && t.text in procedures) return Command(t, "CALL", List(procedures.getValue(t.text).params.size) {
            expression(t)
        })
        if (unknown(t)) fail(t, "I don't know how to ${t.text}")
        fail(t, "you don't say what to do with ${t.text}")
    }

    fun sequence(): List<Command> {
        val out = mutableListOf<Command>()
        while (at < tokens.size) out.add(command())
        return out
    }
}

private data class Point(val x: Int, val y: Int)

private class Environment(val values: MutableMap<String, Long> = mutableMapOf(), var test: Boolean? = null)

private class Flow(val value: Long?) : RuntimeException()

private class Runtime(val procedures: Map<String, Procedure>, val output: MutableList<String>) {
    var x = 0
    var y = 0
    var heading = 0
    var pen = "DOWN"
    var character = '*'
    var random = 1L
    val canvas = mutableMapOf<Point, Char>()
    val envs = mutableListOf(Environment())
    val calls = mutableListOf<String>()
    val repetitions = mutableListOf<Long>()
    val traced = mutableSetOf<String>()
    val directions = listOf(0 to 1, 1 to 1, 1 to 0, 1 to -1, 0 to -1, -1 to -1, -1 to 0, -1 to 1)

    fun variable(t: Token): Long {
        val name = t.text.drop(1)
        for (env in envs.asReversed()) env.values[name]?.let {
            return it
        }
        fail(t, "$name has no value")
    }

    fun make(name: String, value: Long) {
        for (i in envs.lastIndex downTo 1) if (name in envs[i].values) {
            envs[i].values[name] = value
            return
        }
        envs[0].values[name] = value
    }

    fun invoke(t: Token, values: List<Long>): Long? {
        if (calls.size == 100) fail(t, "recursion too deep")
        val p = procedures.getValue(t.text)
        val trace = t.text in traced
        val indent = "  ".repeat(calls.size)
        if (trace) output.add(indent + "( " + t.text + values.joinToString("") {
            " $it"
        } + " )")
        envs.add(Environment(p.params.zip(values).toMap().toMutableMap()))
        calls.add(t.text)
        var value: Long? = null
        try {
            execute(p.body)
        } catch (flow: Flow) {
            value = flow.value
        }
        envs.removeAt(envs.lastIndex)
        calls.removeAt(calls.lastIndex)
        if (trace) output.add(indent + t.text + if (value == null) " stops" else " outputs $value")
        return value
    }

    fun evaluate(e: Expr): Long {
        val t = e.token
        if (e.op == "NUMBER") return t.text.toLong()
        if (e.op == "VARIABLE") return variable(t)
        val a = e.args.map(::evaluate)
        if (e.op == "NEG") return -a[0]
        if (e.op == "CALL") return invoke(t, a) ?: fail(t, "${t.text} did not output")
        if (e.op == "FUNCTION") return when (t.text) {
            "XCOR" -> x.toLong()
            "YCOR" -> y.toLong()
            "HEADING" -> heading.toLong()
            "REPCOUNT" -> repetitions.lastOrNull() ?: fail(t, "REPCOUNT outside REPEAT")
            "RANDOM" -> {
                if (a[0] <= 0) fail(t, "RANDOM doesn't like ${a[0]} as input")
                random = 48271 * random % 2147483647
                random % a[0]
            }
            "ABS" -> kotlin.math.abs(a[0])
            "NOT" -> if (a[0] == 0L) 1L else 0L
            "AND" -> if (a[0] != 0L && a[1] != 0L) 1L else 0L
            "OR" -> if (a[0] != 0L || a[1] != 0L) 1L else 0L
            "MAX" -> maxOf(a[0], a[1])
            else -> minOf(a[0], a[1])
        }
        if ((e.op == "/" || e.op == "MOD") && a[1] == 0L) fail(t, "${t.text} doesn't like 0 as input")
        return when (e.op) {
            "+" -> a[0] + a[1]
            "-" -> a[0] - a[1]
            "*" -> a[0] * a[1]
            "/" -> a[0] / a[1]
            "MOD" -> a[0] % a[1]
            "=" -> if (a[0] == a[1]) 1L else 0L
            "<>" -> if (a[0] != a[1]) 1L else 0L
            "<" -> if (a[0] < a[1]) 1L else 0L
            ">" -> if (a[0] > a[1]) 1L else 0L
            "<=" -> if (a[0] <= a[1]) 1L else 0L
            else -> if (a[0] >= a[1]) 1L else 0L
        }
    }

    fun item(p: Item) = p.word ?: evaluate(p.expr!!).toString()

    fun apply(x: Int, y: Int) {
        val p = Point(x, y)
        if (pen == "DOWN") canvas[p] = character else if (pen == "ERASE") canvas.remove(p)
    }

    fun move(n: Long) {
        val d = directions[heading / 45]
        val sign = if (n < 0) -1 else 1
        apply(x, y)
        repeat(kotlin.math.abs(n).toInt()) {
            x += sign * d.first
            y += sign * d.second
            apply(x, y)
        }
    }

    fun floor(n: Long, d: Long): Long {
        val q = n / d
        return if (n < 0 && n % d != 0L) q - 1 else q
    }

    fun straight(xx: Int, yy: Int) {
        val dx = xx - x
        val dy = yy - y
        val size = maxOf(kotlin.math.abs(dx), kotlin.math.abs(dy))
        if (size == 0) apply(x, y) else for (i in 0..size) apply(x + floor(2L * i * dx + size, 2L * size).toInt(), y + floor(2L * i * dy + size, 2L * size).toInt())
        x = xx
        y = yy
    }

    fun fill() {
        if (canvas.isEmpty() || Point(x, y) in canvas) return
        val x1 = canvas.keys.minOf {
            it.x
        }
        val x2 = canvas.keys.maxOf {
            it.x
        }
        val y1 = canvas.keys.minOf {
            it.y
        }
        val y2 = canvas.keys.maxOf {
            it.y
        }
        if (x !in x1..x2 || y !in y1..y2) return
        val queue = ArrayDeque<Point>()
        queue.add(Point(x, y))
        canvas[Point(x, y)] = character
        while (queue.isNotEmpty()) {
            val p = queue.removeFirst()
            for ((dx, dy) in listOf(0 to 1, 1 to 0, 0 to -1, -1 to 0)) {
                val q = Point(p.x + dx, p.y + dy)
                if (q.x in x1..x2 && q.y in y1..y2 && q !in canvas) {
                    canvas[q] = character
                    queue.add(q)
                }
            }
        }
    }

    fun picture() {
        if (canvas.isEmpty()) {
            output.add("CANVAS 0 0 0")
            return
        }
        val x1 = canvas.keys.minOf {
            it.x
        }
        val x2 = canvas.keys.maxOf {
            it.x
        }
        val y1 = canvas.keys.minOf {
            it.y
        }
        val y2 = canvas.keys.maxOf {
            it.y
        }
        output.add("CANVAS ${x2 - x1 + 1} ${y2 - y1 + 1} ${canvas.size}")
        for (yy in y2 downTo y1) output.add((x1..x2).map {
            canvas[Point(it, yy)] ?: ' '
        }.joinToString("").trimEnd(' '))
    }

    fun execute(commands: List<Command>) {
        for (c in commands) command(c)
    }

    fun command(c: Command) {
        val t = c.token
        val op = c.op
        if (op == "WHILE") {
            while (evaluate(c.exprs[0]) != 0L) execute(c.lists[0])
            return
        }
        if (op == "PRINT" || op == "MULTIPRINT") {
            val values = c.items.map(::item)
            output.add(values.joinToString(" "))
            return
        }
        if (op == "LABEL") {
            val text = item(c.items[0])
            val d = directions[heading / 45]
            for ((i, ch) in text.withIndex()) canvas[Point(x + i * d.first, y + i * d.second)] = ch
            return
        }
        val a = c.exprs.map(::evaluate)
        when (op) {
            "CALL" -> invoke(t, a)?.let {
                fail(t, "you don't say what to do with $it")
            }
            "FD" -> move(a[0])
            "BK" -> move(-a[0])
            "RT", "LT", "SETH" -> {
                val angle = a[0]
                if (angle % 45 != 0L) fail(t, "${t.text} doesn't like $angle as input")
                val h = if (op == "SETH") angle else heading + if (op == "RT") angle else -angle
                heading = ((h % 360 + 360) % 360).toInt()
            }
            "PU" -> pen = "UP"
            "PD" -> pen = "DOWN"
            "PE" -> pen = "ERASE"
            "SETPEN" -> {
                if (a[0] !in 33L..126L) fail(t, "SETPEN doesn't like ${a[0]} as input")
                character = a[0].toInt().toChar()
            }
            "SETXY" -> straight(a[0].toInt(), a[1].toInt())
            "SETX" -> straight(a[0].toInt(), y)
            "SETY" -> straight(x, a[0].toInt())
            "HOME" -> {
                straight(0, 0)
                heading = 0
            }
            "CS" -> {
                canvas.clear()
                x = 0
                y = 0
                heading = 0
            }
            "CLEAN" -> canvas.clear()
            "FILL" -> fill()
            "SNAPSHOT" -> picture()
            "MAKE" -> make(c.words[0], a[0])
            "LOCAL" -> envs.last().values[c.words[0]] = 0
            "LOCALMAKE" -> envs.last().values[c.words[0]] = a[0]
            "TRACE" -> traced.add(c.words[0])
            "UNTRACE" -> traced.remove(c.words[0])
            "SEED" -> {
                if (a[0] <= 0) fail(t, "SEED doesn't like ${a[0]} as input")
                random = a[0]
            }
            "STOP" -> throw Flow(null)
            "OUTPUT" -> throw Flow(a[0])
            "REPEAT" -> {
                if (c.lists[0].isEmpty()) return
                var i = 1L
                while (i <= a[0]) {
                    repetitions.add(i)
                    try {
                        execute(c.lists[0])
                    } finally {
                        repetitions.removeAt(repetitions.lastIndex)
                    }
                    i++
                }
            }
            "FOR" -> {
                if (c.lists[0].isEmpty()) {
                    make(c.words[0], a[1])
                    return
                }
                val step = if (a[0] <= a[1]) 1L else -1L
                var i = a[0]
                while (true) {
                    make(c.words[0], i)
                    execute(c.lists[0])
                    if (i == a[1]) break
                    i += step
                }
            }
            "IF" -> if (a[0] != 0L) execute(c.lists[0])
            "IFELSE" -> execute(c.lists[if (a[0] != 0L) 0 else 1])
            "TEST" -> envs.last().test = a[0] != 0L
            "IFTRUE", "IFFALSE" -> {
                val test = envs.last().test ?: fail(t, "${t.text} without TEST")
                if (test == (op == "IFTRUE")) execute(c.lists[0])
            }
        }
    }

    fun errors() {
        var i = calls.lastIndex
        while (i >= 0) {
            val p = calls[i]
            var count = 0
            while (i >= 0 && calls[i] == p) {
                count++
                i--
            }
            output.add("  in $p" + if (count == 1) "" else " x$count")
        }
    }
}

private fun process(source: List<Pair<Int, String>>, output: MutableList<String>) {
    val procedures = linkedMapOf<String, Procedure>()
    val top = mutableListOf<Token>()
    var current: Procedure? = null
    try {
        for ((line, text) in source) {
            val tokens = lex(text, line)
            if (tokens.isEmpty()) continue
            if (tokens[0].kind == "word" && tokens[0].text == "TO") {
                val start = tokens[0]
                current?.let {
                    fail(start, "TO inside definition of ${it.token.text}")
                }
                if (tokens.size < 2 || tokens[1].kind != "word") fail(start, "bad procedure header")
                val name = tokens[1]
                if (primitive(name.text)) fail(start, "${name.text} is a primitive")
                if (name.text in procedures) fail(start, "${name.text} is already defined")
                val params = mutableListOf<String>()
                for (t in tokens.drop(2)) {
                    if (t.kind != "variable") fail(start, "bad procedure header")
                    if (t.text.drop(1) in params) fail(start, "duplicate input ${t.text}")
                    params.add(t.text.drop(1))
                }
                current = Procedure(Token(name.text, "word", line), params)
                procedures[name.text] = current!!
            } else if (tokens.size == 1 && tokens[0].kind == "word" && tokens[0].text == "END") {
                if (current == null) fail(tokens[0], "END without TO")
                current = null
            } else if (current != null) current!!.raw.addAll(tokens) else top.addAll(tokens)
        }
        current?.let {
            fail(it.token, "missing END for ${it.token.text}")
        }
        for (p in procedures.values) p.body = Parser(p.raw, procedures, true).sequence()
        val body = Parser(top, procedures, false).sequence()
        val runtime = Runtime(procedures, output)
        try {
            runtime.execute(body)
            output.add("TURTLE ${runtime.x} ${runtime.y} ${runtime.heading} ${runtime.pen} ${runtime.character}")
            runtime.picture()
        } catch (e: Problem) {
            output.add("ERROR line ${e.line}: ${e.reason}")
            runtime.errors()
        }
    } catch (e: Problem) {
        output.add("ERROR line ${e.line}: ${e.reason}")
    }
}

fun main() {
    val lines = generateSequence(::readLine).toList()
    val output = mutableListOf<String>()
    var at = 0
    while (at < lines.size && lines[at] != "#EOF") {
        output.add("PROGRAM ${lines[at].drop(9)}")
        at++
        val source = mutableListOf<Pair<Int, String>>()
        while (at < lines.size && lines[at] != "#EOF" && !lines[at].startsWith("#PROGRAM ")) {
            source.add(at + 1 to lines[at])
            at++
        }
        process(source, output)
    }
    for (line in output) println(line)
}
