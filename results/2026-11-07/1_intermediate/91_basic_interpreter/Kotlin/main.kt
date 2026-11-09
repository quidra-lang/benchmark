import java.io.BufferedReader
import java.io.InputStreamReader
import kotlin.math.abs
import kotlin.math.sqrt

private class SyntaxFault : RuntimeException()
private class RuntimeFault(message: String) : RuntimeException(message)
private fun syntax(): Nothing = throw SyntaxFault()
private fun fault(reason: String): Nothing = throw RuntimeFault(reason)

private data class Token(val type: String, val text: String, val value: Any)
private class Expr(
    var kind: String, val type: String, val value: Any = "",
    val args: MutableList<Expr> = mutableListOf()
)
private class Statement(var kind: String) {
    var line = 0
    var next: Statement? = null
    var expr: Expr? = null
    var target: Expr? = null
    val targets = mutableListOf<Expr>()
    val expressions = mutableListOf<Expr>()
    val values = mutableListOf<Any>()
    val numbers = mutableListOf<Int>()
    val clauses = mutableListOf<Clause>()
    val items = mutableListOf<PrintItem>()
    var name = ""
    var mode = ""
}
private data class Clause(val number: Int?, val body: List<Statement>)
private data class PrintItem(val kind: String, val expr: Expr?)
private data class Address(val name: String, val index: Int?)
private class BasicArray(val bounds: List<Int>, val values: MutableList<Any>)
private data class Frame(
    val kind: String, val position: Statement?, val name: String = "",
    val limit: Int = 0, val step: Int = 0
)

private fun variable(name: String) = Regex("[A-Z][0-9]?[$]?").matches(name)
private fun nameType(name: String) = if (name.endsWith("$")) "S" else "I"
private fun valueType(value: Any) = if (value is String) "S" else "I"
private val signatures = mapOf(
    "ABS" to listOf("I"), "SGN" to listOf("I"), "INT" to listOf("I"),
    "SQR" to listOf("I"), "RND" to listOf("I"), "LEN" to listOf("S"),
    "ASC" to listOf("S"), "VAL" to listOf("S"), "CHR$" to listOf("I"),
    "STR$" to listOf("I"), "LEFT$" to listOf("SI"),
    "RIGHT$" to listOf("SI"), "MID$" to listOf("SI", "SII"),
    "INSTR" to listOf("SS")
)
private val errorCodes = mapOf(
    "NEXT WITHOUT FOR" to 1, "RETURN WITHOUT GOSUB" to 3,
    "OUT OF DATA" to 4, "ILLEGAL FUNCTION CALL" to 5,
    "OVERFLOW" to 6, "OUT OF MEMORY" to 7,
    "UNDEFINED LINE NUMBER" to 8, "SUBSCRIPT OUT OF RANGE" to 9,
    "DUPLICATE DEFINITION" to 10, "DIVISION BY ZERO" to 11,
    "TYPE MISMATCH" to 13, "STRING TOO LONG" to 15,
    "RESUME WITHOUT ERROR" to 20, "FOR WITHOUT NEXT" to 26,
    "WHILE WITHOUT WEND" to 29, "WEND WITHOUT WHILE" to 30,
    "INPUT PAST END" to 62
)

private fun tokenize(source: String): List<Token> {
    val tokens = mutableListOf<Token>()
    var p = 0
    while (p < source.length) {
        val c = source[p]
        if (c == ' ') {
            p++
        } else if (c == '"') {
            val end = source.indexOf('"', p + 1)
            if (end < 0) syntax()
            tokens.add(Token("S", source.substring(p, end + 1), source.substring(p + 1, end)))
            p = end + 1
        } else if (c.isDigit()) {
            val start = p
            while (p < source.length && source[p].isDigit()) p++
            val text = source.substring(start, p)
            val number = text.toLongOrNull() ?: syntax()
            if (number > 32767) syntax()
            tokens.add(Token("I", text, number.toInt()))
        } else if (c in 'A'..'Z') {
            if (source.startsWith("REM", p)) {
                tokens.add(Token("W", "REM", "REM"))
                break
            }
            val start = p
            while (p < source.length && (source[p] in 'A'..'Z' || source[p].isDigit())) p++
            if (p < source.length && source[p] == '$') p++
            val text = source.substring(start, p)
            tokens.add(Token("W", text, text))
        } else {
            var text = source.substring(p, (p + 2).coerceAtMost(source.length))
            if (text !in listOf("<>", "<=", ">=")) text = c.toString()
            if (c !in "+-*/^=<>() ,;:") syntax()
            tokens.add(Token("P", text, text))
            p += text.length
        }
    }
    tokens.add(Token("E", "", ""))
    return tokens
}

private class Parser(private val tokens: List<Token>) {
    private var index = 0
    private fun now() = tokens[index]
    private fun at(text: String) = now().type in listOf("W", "P") && now().text == text
    private fun take(text: String): Boolean {
        if (!at(text)) return false
        index++
        return true
    }
    private fun expect(text: String) {
        if (!take(text)) syntax()
    }
    private fun number(): Int {
        if (now().type != "I") syntax()
        return tokens[index++].value as Int
    }
    private fun integer(level: Int = 0): Expr {
        val e = expression(level)
        if (e.type != "I") syntax()
        return e
    }
    private fun target(): Expr {
        val token = now()
        if (token.type != "W" || !variable(token.text)) syntax()
        index++
        val e = Expr("variable", nameType(token.text), token.text)
        if (take("(")) {
            e.kind = "array"
            e.args.add(integer())
            if (take(",")) e.args.add(integer())
            expect(")")
        }
        return e
    }
    private fun primary(): Expr {
        val token = now()
        if (token.type == "I" || token.type == "S") {
            index++
            return Expr("constant", token.type, token.value)
        }
        if (take("(")) {
            val e = expression()
            expect(")")
            return e
        }
        if (token.type == "W" && variable(token.text)) return target()
        if (take("ERR")) return Expr("builtin", "I", "ERR")
        if (take("ERL")) return Expr("builtin", "I", "ERL")
        if (token.type == "W" && signatures.containsKey(token.text)) {
            index++
            expect("(")
            val args = mutableListOf(expression())
            while (take(",")) args.add(expression())
            expect(")")
            if (args.joinToString("") { it.type } !in signatures.getValue(token.text)) syntax()
            return Expr("call", nameType(token.text), token.text, args)
        }
        syntax()
    }
    private fun expression(level: Int = 0): Expr {
        if (level == 2 && take("NOT")) return Expr("unary", "I", "NOT", mutableListOf(integer(2)))
        if (level == 6 && take("-")) return Expr("unary", "I", "-", mutableListOf(integer(6)))
        if (level == 8) return primary()
        var left = expression(level + 1)
        val operators = listOf(
            listOf("OR"), listOf("AND"), emptyList(),
            listOf("=", "<>", "<", ">", "<=", ">="),
            listOf("+", "-"), listOf("*", "/", "MOD"),
            emptyList(), listOf("^")
        )[level]
        while (operators.any { at(it) }) {
            val op = tokens[index++].text
            val right = expression(if (level == 7) 6 else level + 1)
            if (left.type != right.type ||
                (left.type == "S" && level != 3 && op != "+")) syntax()
            left = Expr("binary", if (level == 3) "I" else left.type, op, mutableListOf(left, right))
            if (level == 7) break
        }
        return left
    }
    private fun clause(): Clause =
        if (now().type == "I") Clause(number(), emptyList()) else Clause(null, list(true))
    private fun list(inClause: Boolean = false): List<Statement> {
        val result = mutableListOf(statement(inClause))
        while (take(":")) result.add(statement(inClause))
        return result
    }
    private fun statement(inClause: Boolean): Statement {
        val word = now().text
        if (inClause && word in listOf("IF", "FOR", "NEXT", "WHILE", "WEND", "DATA")) syntax()
        val s = Statement(word)
        if (take("REM") || take("RETURN") || take("WEND") || take("END") || take("STOP"))
            return s
        if (take("PRINT")) {
            var lastValue = false
            while (now().type != "E" && !at(":") && !at("ELSE")) {
                if (take(";")) {
                    s.items.add(PrintItem(";", null))
                    lastValue = false
                } else if (take(",")) {
                    s.items.add(PrintItem(",", null))
                    lastValue = false
                } else {
                    val mode = if (at("TAB")) "TAB" else if (at("SPC")) "SPC" else "value"
                    if (mode == "value" && lastValue) syntax()
                    val e = if (mode == "value") expression() else {
                        index++
                        expect("(")
                        val value = integer()
                        expect(")")
                        value
                    }
                    s.items.add(PrintItem(mode, e))
                    lastValue = mode == "value"
                }
            }
            return s
        }
        if (take("INPUT") || take("READ") || take("DIM")) {
            do {
                val target = target()
                if (word == "DIM" && target.kind != "array") syntax()
                s.targets.add(target)
            } while (take(","))
            return s
        }
        if (take("DATA")) {
            do {
                val negative = take("-")
                val token = now()
                if (token.type != "I" && (token.type != "S" || negative)) syntax()
                index++
                s.values.add(if (negative) -(token.value as Int) else token.value)
            } while (take(","))
            return s
        }
        if (take("IF")) {
            s.expr = integer()
            expect("THEN")
            s.clauses.add(clause())
            if (take("ELSE")) s.clauses.add(clause())
            if (now().type != "E") syntax()
            return s
        }
        if (take("GOTO") || take("GOSUB")) {
            s.numbers.add(number())
            return s
        }
        if (take("ON")) {
            if (take("ERROR")) {
                s.kind = "handler"
                expect("GOTO")
                s.numbers.add(number())
            } else {
                s.expr = integer()
                s.mode = if (take("GOTO")) "GOTO" else {
                    expect("GOSUB")
                    "GOSUB"
                }
                do { s.numbers.add(number()) } while (take(","))
            }
            return s
        }
        if (take("RESUME")) {
            if (take("NEXT")) s.mode = "NEXT"
            else if (now().type == "I") {
                s.mode = "line"
                s.numbers.add(number())
            }
            return s
        }
        if (take("FOR")) {
            val token = now()
            if (token.type != "W" || !variable(token.text) || nameType(token.text) != "I") syntax()
            s.name = token.text
            index++
            expect("=")
            s.expressions.add(integer())
            expect("TO")
            s.expressions.add(integer())
            s.expressions.add(if (take("STEP")) integer() else Expr("constant", "I", 1))
            return s
        }
        if (take("NEXT")) {
            if (now().type == "W" && variable(now().text) && nameType(now().text) == "I")
                s.name = tokens[index++].text
            return s
        }
        if (take("WHILE") || take("RANDOMIZE")) {
            s.expr = integer()
            return s
        }
        if (take("RESTORE")) {
            if (now().type == "I") s.numbers.add(number())
            return s
        }
        take("LET")
        s.kind = "assign"
        s.target = target()
        expect("=")
        s.expr = expression()
        if (s.expr!!.type != s.target!!.type) syntax()
        return s
    }
    fun parse(): List<Statement> {
        val result = list()
        if (now().type != "E") syntax()
        return result
    }
}

private class Machine(private val inputs: List<String>) {
    private val vars = mutableMapOf<String, Any>()
    private val arrays = mutableMapOf<String, BasicArray>()
    private val stack = mutableListOf<Frame>()
    private val lines = mutableMapOf<Int, Statement>()
    private val sequence = mutableListOf<Statement>()
    private val data = mutableListOf<Pair<Int, Any>>()
    private var dataIndex = 0
    private var inputIndex = 0
    private var random = 1L
    private var handler = 0
    private var handling = false
    private var remembered: Statement? = null
    private var err = 0
    private var erl = 0
    private var buffer = ""
    private val output = mutableListOf<String>()

    private fun endLine() {
        output.add(buffer.trimEnd(' '))
        buffer = ""
    }
    private fun message(s: String) {
        if (buffer.isNotEmpty()) endLine()
        output.add(s)
    }
    private fun checked(n: Long): Int {
        if (n < -32768 || n > 32767) fault("OVERFLOW")
        return n.toInt()
    }
    private fun get(name: String): Any = vars[name] ?: if (nameType(name) == "S") "" else 0
    private fun declare(name: String, bounds: List<Int>) {
        val count = bounds.fold(1) { a, b -> a * (b + 1) }
        val zero: Any = if (nameType(name) == "S") "" else 0
        arrays[name] = BasicArray(bounds, MutableList(count) { zero })
    }
    private fun address(expr: Expr): Address {
        val name = expr.value as String
        if (expr.kind == "variable") return Address(name, null)
        val indices = expr.args.map { evaluate(it) as Int }
        if (!arrays.containsKey(name)) declare(name, indices.map { 10 })
        val array = arrays.getValue(name)
        if (indices.size != array.bounds.size ||
            indices.indices.any { indices[it] < 0 || indices[it] > array.bounds[it] })
            fault("SUBSCRIPT OUT OF RANGE")
        var offset = 0
        indices.forEachIndexed { i, value -> offset = offset * (array.bounds[i] + 1) + value }
        return Address(name, offset)
    }
    private fun load(a: Address): Any =
        if (a.index == null) get(a.name) else arrays.getValue(a.name).values[a.index]
    private fun store(a: Address, value: Any) {
        if (a.index == null) vars[a.name] = value else arrays.getValue(a.name).values[a.index] = value
    }
    private fun power(a: Int, b: Int): Int {
        if (b < 0) fault("ILLEGAL FUNCTION CALL")
        if (b == 0) return 1
        var result = 1L
        var base = a.toLong()
        var exponent = b
        while (exponent > 0) {
            if (exponent % 2 == 1) result = checked(result * base).toLong()
            exponent /= 2
            if (exponent > 0) base = checked(base * base).toLong()
        }
        return result.toInt()
    }
    private fun evaluate(e: Expr): Any {
        val op = e.value
        if (e.kind == "constant") return op
        if (e.kind == "variable" || e.kind == "array") return load(address(e))
        if (e.kind == "builtin") return if (op == "ERR") err else erl
        if (e.kind == "unary") {
            val value = evaluate(e.args[0]) as Int
            return if (op == "NOT") value.inv() else checked(-value.toLong())
        }
        val args = e.args.map { evaluate(it) }
        if (e.kind == "call") return call(op as String, args)
        val a = args[0]
        val b = args[1]
        if (op in listOf("=", "<>", "<", ">", "<=", ">=")) {
            val cmp = if (a == b) 0 else if (a is String) a.compareTo(b as String)
                else (a as Int).compareTo(b as Int)
            return if (when (op) {
                "=" -> cmp == 0; "<>" -> cmp != 0; "<" -> cmp < 0
                ">" -> cmp > 0; "<=" -> cmp <= 0; else -> cmp >= 0
            }) -1 else 0
        }
        if (e.type == "S") {
            val text = (a as String) + (b as String)
            if (text.length > 255) fault("STRING TOO LONG")
            return text
        }
        val x = a as Int
        val y = b as Int
        return when (op) {
            "+" -> checked(x.toLong() + y)
            "-" -> checked(x.toLong() - y)
            "*" -> checked(x.toLong() * y)
            "/" -> if (y == 0) fault("DIVISION BY ZERO") else checked(x.toLong() / y)
            "MOD" -> if (y == 0) fault("DIVISION BY ZERO") else x % y
            "^" -> power(x, y)
            "AND" -> x and y
            "OR" -> x or y
            else -> syntax()
        }
    }
    private fun call(name: String, args: List<Any>): Any {
        val n = args[0] as? Int ?: 0
        val s = args[0] as? String ?: ""
        val k = if (args.size > 1) args[1] as? Int ?: 0 else 0
        return when (name) {
            "ABS" -> checked(abs(n.toLong()))
            "SGN" -> n.compareTo(0)
            "INT" -> n
            "SQR" -> if (n < 0) fault("ILLEGAL FUNCTION CALL") else sqrt(n.toDouble()).toInt()
            "RND" -> {
                if (n < 1) fault("ILLEGAL FUNCTION CALL")
                random = 48271 * random % 2147483647
                (random % n + 1).toInt()
            }
            "LEN" -> s.length
            "ASC" -> if (s.isEmpty()) fault("ILLEGAL FUNCTION CALL") else s[0].code
            "VAL" -> checked(Regex("^ *([+-]?[0-9]+)").find(s)?.groupValues?.get(1)?.toLongOrNull() ?: 0L)
            "CHR$" -> if (n !in 32..126) fault("ILLEGAL FUNCTION CALL") else n.toChar().toString()
            "STR$" -> n.toString()
            "LEFT$" -> if (k < 0) fault("ILLEGAL FUNCTION CALL") else s.take(k)
            "RIGHT$" -> if (k < 0) fault("ILLEGAL FUNCTION CALL") else s.takeLast(k)
            "MID$" -> {
                val length = if (args.size == 3) args[2] as Int else s.length
                if (k < 1 || length < 0) fault("ILLEGAL FUNCTION CALL")
                if (k > s.length) "" else s.substring(k - 1, (k - 1 + length).coerceAtMost(s.length))
            }
            "INSTR" -> s.indexOf(args[1] as String) + 1
            else -> syntax()
        }
    }
    private fun line(n: Int): Statement = lines[n] ?: fault("UNDEFINED LINE NUMBER")
    private fun push(frame: Frame) {
        if (stack.size == 100) fault("OUT OF MEMORY")
        stack.add(frame)
    }
    private fun search(kind: String, name: String = ""): Int {
        for (i in stack.indices.reversed()) {
            val f = stack[i]
            if (f.kind == "GOSUB") break
            if (f.kind == kind && (name.isEmpty() || f.name == name)) return i
        }
        return -1
    }
    private fun matching(s: Statement, open: String, close: String): Statement? {
        var depth = 0
        for (i in (sequence.indexOf(s) + 1) until sequence.size) {
            val t = sequence[i]
            if (t.kind == open) depth++
            else if (t.kind == close) {
                if (depth == 0) return t.next
                depth--
            }
        }
        fault("$open WITHOUT $close")
    }
    private fun subroutine(number: Int, after: Statement?): Statement {
        val destination = line(number)
        push(Frame("GOSUB", after))
        return destination
    }
    private fun execute(s: Statement): Statement? {
        var next = s.next
        when (s.kind) {
            "REM", "DATA" -> Unit
            "assign" -> {
                val place = address(s.target!!)
                store(place, evaluate(s.expr!!))
            }
            "PRINT" -> {
                for (item in s.items) {
                    if (item.kind == ",") buffer += " ".repeat(10 - buffer.length % 10)
                    else if (item.kind != ";") {
                        val value = evaluate(item.expr!!)
                        if (item.kind == "value") buffer += value.toString()
                        else {
                            val count = value as Int
                            if (count < 0) fault("ILLEGAL FUNCTION CALL")
                            buffer += " ".repeat(if (item.kind == "SPC") count else (count - buffer.length).coerceAtLeast(0))
                        }
                    }
                }
                if (s.items.isEmpty() || s.items.last().kind !in listOf(";", ",")) endLine()
            }
            "INPUT", "READ" -> for (target in s.targets) {
                val place = address(target)
                val value: Any
                if (s.kind == "READ") {
                    if (dataIndex == data.size) fault("OUT OF DATA")
                    value = data[dataIndex++].second
                    if (valueType(value) != target.type) fault("TYPE MISMATCH")
                } else {
                    var received: Any
                    while (true) {
                        if (inputIndex == inputs.size) fault("INPUT PAST END")
                        val text = inputs[inputIndex++]
                        if (target.type == "S") {
                            received = text
                            break
                        }
                        val number = if (Regex("-?[0-9]+").matches(text)) text.toIntOrNull() else null
                        if (number != null && number in -32768..32767) {
                            received = number
                            break
                        }
                        message("?REDO FROM START")
                    }
                    value = received
                }
                store(place, value)
            }
            "RESTORE" -> {
                if (s.numbers.isNotEmpty()) {
                    val number = s.numbers[0]
                    line(number)
                    val found = data.indexOfFirst { it.first >= number }
                    dataIndex = if (found < 0) data.size else found
                } else dataIndex = 0
            }
            "IF" -> {
                val clause = s.clauses.getOrNull(if ((evaluate(s.expr!!) as Int) != 0) 0 else 1)
                if (clause != null) next = if (clause.number == null) clause.body[0] else line(clause.number)
            }
            "GOTO" -> next = line(s.numbers[0])
            "GOSUB" -> next = subroutine(s.numbers[0], next)
            "ON" -> {
                val index = evaluate(s.expr!!) as Int
                if (index < 0) fault("ILLEGAL FUNCTION CALL")
                if (index in 1..s.numbers.size) {
                    val target = s.numbers[index - 1]
                    next = if (s.mode == "GOTO") line(target) else subroutine(target, next)
                }
            }
            "RETURN" -> {
                val found = stack.indexOfLast { it.kind == "GOSUB" }
                if (found < 0) fault("RETURN WITHOUT GOSUB")
                next = stack[found].position
                stack.subList(found, stack.size).clear()
            }
            "FOR" -> {
                val values = s.expressions.map { evaluate(it) as Int }
                val start = values[0]
                val limit = values[1]
                val step = values[2]
                if (step == 0) fault("ILLEGAL FUNCTION CALL")
                val found = search("FOR", s.name)
                if (found >= 0) stack.subList(found, stack.size).clear()
                vars[s.name] = start
                if (if (step > 0) start > limit else start < limit) next = matching(s, "FOR", "NEXT")
                else push(Frame("FOR", next, s.name, limit, step))
            }
            "NEXT" -> {
                val found = search("FOR", s.name)
                if (found < 0) fault("NEXT WITHOUT FOR")
                stack.subList(found + 1, stack.size).clear()
                val frame = stack[found]
                val value = checked((get(frame.name) as Int).toLong() + frame.step)
                vars[frame.name] = value
                if (if (frame.step > 0) value > frame.limit else value < frame.limit)
                    stack.removeAt(stack.lastIndex)
                else next = frame.position
            }
            "WHILE" -> {
                if ((evaluate(s.expr!!) as Int) != 0) push(Frame("WHILE", s))
                else next = matching(s, "WHILE", "WEND")
            }
            "WEND" -> {
                val found = search("WHILE")
                if (found < 0) fault("WEND WITHOUT WHILE")
                next = stack[found].position
                stack.subList(found, stack.size).clear()
            }
            "DIM" -> for (target in s.targets) {
                val name = target.value as String
                val bounds = target.args.map { evaluate(it) as Int }
                if (arrays.containsKey(name)) fault("DUPLICATE DEFINITION")
                if (bounds.any { it < 0 }) fault("ILLEGAL FUNCTION CALL")
                if (bounds.fold(1L) { a, b -> a * (b + 1) } > 10000) fault("OUT OF MEMORY")
                declare(name, bounds)
            }
            "RANDOMIZE" -> {
                val value = evaluate(s.expr!!) as Int
                if (value < 1) fault("ILLEGAL FUNCTION CALL")
                random = value.toLong()
            }
            "handler" -> {
                if (s.numbers[0] != 0) line(s.numbers[0])
                handler = s.numbers[0]
            }
            "RESUME" -> {
                if (!handling) fault("RESUME WITHOUT ERROR")
                next = when (s.mode) {
                    "line" -> line(s.numbers[0])
                    "NEXT" -> remembered!!.next
                    else -> remembered
                }
                handling = false
            }
            "STOP" -> {
                message("BREAK IN LINE " + s.line)
                return null
            }
            "END" -> return null
        }
        return next
    }
    private fun connect(body: List<Statement>, after: Statement?, line: Int) {
        var following = after
        for (s in body.asReversed()) {
            s.line = line
            s.next = following
            s.clauses.forEach { connect(it.body, following, line) }
            following = s
        }
    }
    fun run(source: Map<Int, String>): List<String> {
        val parsed = mutableListOf<Pair<Int, List<Statement>>>()
        for (line in source.keys.sorted()) {
            try {
                parsed.add(line to Parser(tokenize(source.getValue(line))).parse())
            } catch (_: SyntaxFault) {
                message("ERROR IN LINE $line: SYNTAX ERROR")
                return finish()
            }
        }
        var following: Statement? = null
        for ((number, statements) in parsed.asReversed()) {
            connect(statements, following, number)
            lines[number] = statements.first()
            following = statements.first()
        }
        sequence.addAll(parsed.flatMap { it.second })
        for (s in sequence) if (s.kind == "DATA")
            for (value in s.values) data.add(s.line to value)
        var position = following
        while (position != null) {
            val statement = position
            try {
                position = execute(statement)
            } catch (problem: RuntimeFault) {
                if (handler != 0 && !handling) {
                    err = errorCodes[problem.message] ?: 0
                    erl = statement.line
                    remembered = statement
                    handling = true
                    position = line(handler)
                } else {
                    message("ERROR IN LINE " + statement.line + ": " + problem.message)
                    position = null
                }
            }
        }
        return finish()
    }
    private fun finish(): List<String> {
        if (buffer.isNotEmpty()) endLine()
        output.add("READY")
        return output
    }
}

fun main() {
    val reader = BufferedReader(InputStreamReader(System.`in`))
    val sessions = reader.readLine()?.toIntOrNull() ?: return
    val output = StringBuilder()
    repeat(sessions) {
        val source = mutableMapOf<Int, String>()
        while (true) {
            val line = reader.readLine() ?: break
            if (line == "RUN") break
            val result = Regex("([0-9]+)(?: +(.*))?").matchEntire(line) ?: continue
            val number = result.groupValues[1].toInt()
            if (result.groups[2] == null) source.remove(number)
            else source[number] = result.groupValues[2]
        }
        val data = mutableListOf<String>()
        while (true) {
            val line = reader.readLine() ?: break
            if (line == "END") break
            data.add(line)
        }
        for (line in Machine(data).run(source)) output.append(line).append('\n')
    }
    print(output.toString())
}
