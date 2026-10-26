import java.util.TreeMap
import kotlin.math.abs

private class CommandError(message: String) : RuntimeException("ERROR $message")

private class Fraction(numerator: Long, denominator: Long = 1) : Comparable<Fraction> {
    val n: Long
    val d: Long

    init {
        var a = abs(numerator)
        var b = abs(denominator)
        while (b != 0L) {
            val remainder = a % b
            a = b
            b = remainder
        }
        val divisor = if (denominator < 0) -a else a
        n = numerator / divisor
        d = denominator / divisor
    }

    companion object {
        val ONE = Fraction(1)
    }

    operator fun plus(b: Fraction) = Fraction(n * b.d + b.n * d, d * b.d)

    operator fun minus(b: Fraction) = Fraction(n * b.d - b.n * d, d * b.d)

    operator fun times(b: Fraction) = Fraction(n * b.n, d * b.d)

    operator fun div(b: Fraction) = Fraction(n * b.d, d * b.n)

    operator fun unaryMinus() = Fraction(-n, d)

    fun absolute() = Fraction(abs(n), d)

    fun power(exponent: Int): Fraction {
        val factor = if (exponent < 0) Fraction(d, n) else this
        var result = ONE
        repeat(abs(exponent)) { result *= factor }
        return result
    }

    override fun compareTo(other: Fraction) = (n * other.d).compareTo(other.n * d)

    override fun equals(other: Any?) = other is Fraction && n == other.n && d == other.d

    override fun hashCode() = 31 * n.hashCode() + d.hashCode()

    override fun toString() = if (d == 1L) "$n" else "$n/$d"

    fun decimal(): String {
        val magnitude = abs(n)
        val places = (magnitude % d * 1_000_000 / d).toString().padStart(6, '0')
        return "${if (n < 0) "-" else ""}${magnitude / d}.$places"
    }

    fun notation(unit: String) = "$this $unit (${decimal()})"
}

private data class Dimension(
    val kg: Long = 0,
    val m: Long = 0,
    val s: Long = 0,
    val a: Long = 0,
    val k: Long = 0,
    val mol: Long = 0,
    val cd: Long = 0,
) {
    operator fun plus(b: Dimension) =
        Dimension(kg + b.kg, m + b.m, s + b.s, a + b.a, k + b.k, mol + b.mol, cd + b.cd)

    operator fun minus(b: Dimension) =
        Dimension(kg - b.kg, m - b.m, s - b.s, a - b.a, k - b.k, mol - b.mol, cd - b.cd)

    fun scale(factor: Int) =
        Dimension(
            kg * factor,
            m * factor,
            s * factor,
            a * factor,
            k * factor,
            mol * factor,
            cd * factor,
        )

    fun half() = Dimension(kg / 2, m / 2, s / 2, a / 2, k / 2, mol / 2, cd / 2)

    fun even() = listOf(kg, m, s, a, k, mol, cd).all { it % 2 == 0L }

    fun match(other: Dimension) {
        if (this != other) throw CommandError("DIMENSION MISMATCH $this vs $other")
    }

    override fun toString(): String {
        val names = listOf("kg", "m", "s", "A", "K", "mol", "cd")
        val terms =
            listOf(kg, m, s, a, k, mol, cd).mapIndexedNotNull { i, exponent ->
                when (exponent) {
                    0L -> null
                    1L -> names[i]
                    else -> "${names[i]}^$exponent"
                }
            }
        return if (terms.isEmpty()) "1" else terms.joinToString(" ")
    }
}

private data class Quantity(val value: Fraction, val dim: Dimension)

private val kinds =
    linkedMapOf(
        "dimensionless" to Dimension(),
        "length" to Dimension(m = 1),
        "mass" to Dimension(kg = 1),
        "time" to Dimension(s = 1),
        "current" to Dimension(a = 1),
        "temperature" to Dimension(k = 1),
        "amount" to Dimension(mol = 1),
        "luminous_intensity" to Dimension(cd = 1),
        "area" to Dimension(m = 2),
        "volume" to Dimension(m = 3),
        "speed" to Dimension(m = 1, s = -1),
        "acceleration" to Dimension(m = 1, s = -2),
        "density" to Dimension(kg = 1, m = -3),
        "momentum" to Dimension(kg = 1, m = 1, s = -1),
        "force" to Dimension(kg = 1, m = 1, s = -2),
        "energy" to Dimension(kg = 1, m = 2, s = -2),
        "power" to Dimension(kg = 1, m = 2, s = -3),
        "pressure" to Dimension(kg = 1, m = -1, s = -2),
        "frequency" to Dimension(s = -1),
        "charge" to Dimension(s = 1, a = 1),
        "voltage" to Dimension(kg = 1, m = 2, s = -3, a = -1),
        "resistance" to Dimension(kg = 1, m = 2, s = -3, a = -2),
        "conductance" to Dimension(kg = -1, m = -2, s = 3, a = 2),
        "capacitance" to Dimension(kg = -1, m = -2, s = 4, a = 2),
        "magnetic_flux" to Dimension(kg = 1, m = 2, s = -2, a = -1),
        "flux_density" to Dimension(kg = 1, s = -2, a = -1),
        "inductance" to Dimension(kg = 1, m = 2, s = -2, a = -2),
        "illuminance" to Dimension(m = -2, cd = 1),
        "catalytic_activity" to Dimension(s = -1, mol = 1),
    )

private fun kindName(dim: Dimension) = kinds.entries.firstOrNull { it.value == dim }?.key ?: "-"

private fun letter(c: Char) = c in 'A'..'Z' || c in 'a'..'z'

private fun digits(text: String) = text.isNotEmpty() && text.all { it in '0'..'9' }

private fun number(text: String): Fraction {
    val body = text.removePrefix("-")
    val value =
        when {
            digits(body) -> Fraction(body.toLong())
            '.' in body -> {
                val parts = body.split('.', limit = 2)
                if (!digits(parts[0]) || !digits(parts[1])) throw CommandError("BAD NUMBER $text")
                var scale = 1L
                repeat(parts[1].length) { scale *= 10 }
                Fraction(parts[0].toLong() * scale + parts[1].toLong(), scale)
            }
            '/' in body -> {
                val parts = body.split('/', limit = 2)
                if (!digits(parts[0]) || !digits(parts[1]) || parts[1].toLong() == 0L)
                    throw CommandError("BAD NUMBER $text")
                Fraction(parts[0].toLong(), parts[1].toLong())
            }
            else -> throw CommandError("BAD NUMBER $text")
        }
    return if (text.startsWith('-')) -value else value
}

private fun exponent(text: String): Int {
    val value = text.toLong()
    if (value == 0L || value !in -3L..3L) throw CommandError("BAD EXPONENT $text")
    return value.toInt()
}

private fun checkName(name: String, variable: Boolean) {
    if (
        name.length !in 1..12 ||
            !name.all(::letter) ||
            variable && name in listOf("abs", "sqrt", "min", "max")
    )
        throw CommandError("BAD NAME $name")
}

private fun integerRoot(n: Long): Long {
    if (n < 2) return n
    var x = n
    var next = (n + 1) / 2
    while (next < x) {
        x = next
        next = (x + n / x) / 2
    }
    return x
}

private enum class TokenKind {
    NUMBER,
    IDENTIFIER,
    UNIT,
    SYMBOL,
    INVALID,
    END,
}

private data class Token(val kind: TokenKind, val text: String, val position: Int)

private sealed interface UnitNode

private data class UnitName(val name: String) : UnitNode

private data class UnitNumber(val text: String) : UnitNode

private data class UnitPower(val child: UnitNode, val exponent: String) : UnitNode

private data class UnitTerm(val op: Char, val node: UnitNode)

private data class UnitProduct(val terms: List<UnitTerm>) : UnitNode

private sealed interface Expr

private data class Literal(val number: String, val unit: String?) : Expr

private data class Variable(val name: String) : Expr

private data class Power(val child: Expr, val exponent: String) : Expr

private data class Negative(val child: Expr) : Expr

private data class Binary(val op: Char, val left: Expr, val right: Expr) : Expr

private data class Call(val name: String, val args: List<Expr>) : Expr

private class Parser(private val source: String, quantity: Boolean) {
    private val tokens = mutableListOf<Token>()
    private var position = 0
    private val current
        get() = tokens[position]

    init {
        var i = 0
        while (i < source.length) {
            val start = i
            val c = source[i]
            val kind =
                when {
                    letter(c) -> {
                        while (i < source.length && letter(source[i])) i++
                        TokenKind.IDENTIFIER
                    }
                    c in '0'..'9' -> {
                        while (i < source.length && source[i] in '0'..'9') i++
                        if (
                            quantity &&
                                i + 1 < source.length &&
                                source[i] == '.' &&
                                source[i + 1] in '0'..'9'
                        ) {
                            i++
                            while (i < source.length && source[i] in '0'..'9') i++
                        }
                        TokenKind.NUMBER
                    }
                    quantity && c == '[' && source.indexOf(']', i + 1) > i + 1 -> {
                        i = source.indexOf(']', i + 1) + 1
                        TokenKind.UNIT
                    }
                    else -> {
                        i++
                        if (c in (if (quantity) "+-*/^()," else "*/^()-")) TokenKind.SYMBOL
                        else TokenKind.INVALID
                    }
                }
            tokens += Token(kind, source.substring(start, i), start)
        }
        tokens += Token(TokenKind.END, "", source.length)
    }

    private fun take(text: String): Boolean {
        if (current.text != text) return false
        position++
        return true
    }

    private fun advance() = tokens[position++]

    private fun syntax() =
        CommandError(
            "SYNTAX $source AT ${if (current.kind == TokenKind.END) "END" else current.position+1}",
        )

    private fun expect(text: String) {
        if (!take(text)) throw syntax()
    }

    private fun readExponent(): String {
        val start = current.position
        take("-")
        if (current.kind != TokenKind.NUMBER || '.' in current.text) throw syntax()
        val token = advance()
        return source.substring(start, token.position + token.text.length)
    }

    private fun unitTerm(): UnitNode {
        val atom =
            when {
                current.kind == TokenKind.IDENTIFIER -> UnitName(advance().text)
                current.kind == TokenKind.NUMBER && current.text[0] != '0' ->
                    UnitNumber(advance().text)
                take("(") -> unitExpression().also { expect(")") }
                else -> throw syntax()
            }
        return if (take("^")) UnitPower(atom, readExponent()) else atom
    }

    private fun unitExpression(): UnitNode {
        val terms = mutableListOf(UnitTerm('*', unitTerm()))
        while (current.text == "*" || current.text == "/") {
            val op = advance().text[0]
            terms += UnitTerm(op, unitTerm())
        }
        return UnitProduct(terms)
    }

    fun completeUnit(): UnitNode {
        val result = unitExpression()
        if (current.kind != TokenKind.END) throw syntax()
        return result
    }

    private fun unitString(): String = advance().text.let { it.substring(1, it.length - 1) }

    private fun primary(): Expr {
        val result =
            when {
                current.kind == TokenKind.NUMBER -> {
                    val text = advance().text
                    Literal(text, if (current.kind == TokenKind.UNIT) unitString() else null)
                }
                current.kind == TokenKind.UNIT -> Literal("1", unitString())
                current.kind == TokenKind.IDENTIFIER -> {
                    val name = advance().text
                    if (take("(")) {
                        val args = mutableListOf(expression())
                        while (take(",")) args += expression()
                        expect(")")
                        Call(name, args)
                    } else Variable(name)
                }
                take("(") -> expression().also { expect(")") }
                else -> throw syntax()
            }
        return if (take("^")) Power(result, readExponent()) else result
    }

    private fun unary(): Expr = if (take("-")) Negative(unary()) else primary()

    private fun product(): Expr {
        var result = unary()
        while (current.text == "*" || current.text == "/") {
            val op = advance().text[0]
            result = Binary(op, result, unary())
        }
        return result
    }

    private fun expression(): Expr {
        var result = product()
        while (current.text == "+" || current.text == "-") {
            val op = advance().text[0]
            result = Binary(op, result, product())
        }
        return result
    }

    fun complete(): Expr {
        val result = expression()
        if (current.kind != TokenKind.END) throw syntax()
        return result
    }
}

private data class Reduced(val coefficient: Fraction, val names: LinkedHashMap<String, Long>)

private fun reduce(node: UnitNode): Reduced =
    when (node) {
        is UnitName -> Reduced(Fraction.ONE, linkedMapOf(node.name to 1L))
        is UnitNumber -> Reduced(Fraction(node.text.toLong()), linkedMapOf())
        is UnitPower -> {
            val result = reduce(node.child)
            val k = node.exponent.toInt()
            val coefficient = result.coefficient.power(k)
            result.names.replaceAll { _, value -> value * k }
            Reduced(coefficient, result.names)
        }
        is UnitProduct -> {
            var coefficient = Fraction.ONE
            val names = linkedMapOf<String, Long>()
            for (term in node.terms) {
                val right = reduce(term.node)
                coefficient =
                    if (term.op == '*') coefficient * right.coefficient
                    else coefficient / right.coefficient
                for ((name, count) in right.names) names[name] =
                    (names[name] ?: 0L) + if (term.op == '*') count else -count
            }
            Reduced(coefficient, names)
        }
    }

private fun reducedText(tree: UnitNode): String {
    val result = reduce(tree)
    val parts = mutableListOf<String>()
    if (result.coefficient != Fraction.ONE) parts += result.coefficient.toString()
    for ((name, count) in result.names) if (count != 0L)
        parts += if (count == 1L) name else "$name^$count"
    return if (parts.isEmpty()) "1" else parts.joinToString(" ")
}

private data class Definition(val value: Fraction, val expression: String)

private data class Unit(
    val symbol: String,
    val quantity: Quantity,
    val prefix: Boolean,
    val definition: Definition? = null,
)

private data class ParsedUnit(val tree: UnitNode, val quantity: Quantity)

private class Database {
    private val units = mutableListOf<Unit>()
    private val variables = TreeMap<String, Quantity>()
    private val prefixes =
        listOf(
            "G" to Fraction(1_000_000_000),
            "M" to Fraction(1_000_000),
            "k" to Fraction(1000),
            "h" to Fraction(100),
            "da" to Fraction(10),
            "d" to Fraction(1, 10),
            "c" to Fraction(1, 100),
            "m" to Fraction(1, 1000),
            "u" to Fraction(1, 1_000_000),
            "n" to Fraction(1, 1_000_000_000),
        )

    init {
        fun add(symbol: String, n: Long, d: Long, kind: String, prefix: Boolean) {
            units += Unit(symbol, Quantity(Fraction(n, d), kinds.getValue(kind)), prefix)
        }
        add("m", 1, 1, "length", true)
        add("g", 1, 1000, "mass", true)
        add("s", 1, 1, "time", true)
        add("A", 1, 1, "current", true)
        add("K", 1, 1, "temperature", true)
        add("mol", 1, 1, "amount", true)
        add("cd", 1, 1, "luminous_intensity", true)
        add("N", 1, 1, "force", true)
        add("J", 1, 1, "energy", true)
        add("W", 1, 1, "power", true)
        add("Pa", 1, 1, "pressure", true)
        add("Hz", 1, 1, "frequency", true)
        add("C", 1, 1, "charge", true)
        add("V", 1, 1, "voltage", true)
        add("ohm", 1, 1, "resistance", true)
        add("S", 1, 1, "conductance", true)
        add("F", 1, 1, "capacitance", true)
        add("Wb", 1, 1, "magnetic_flux", true)
        add("T", 1, 1, "flux_density", true)
        add("H", 1, 1, "inductance", true)
        add("lx", 1, 1, "illuminance", true)
        add("kat", 1, 1, "catalytic_activity", true)
        add("L", 1, 1000, "volume", true)
        add("t", 1000, 1, "mass", false)
        add("min", 60, 1, "time", false)
        add("h", 3600, 1, "time", false)
        add("day", 86400, 1, "time", false)
        add("in", 127, 5000, "length", false)
        add("ft", 381, 1250, "length", false)
        add("yd", 1143, 1250, "length", false)
        add("mi", 201168, 125, "length", false)
        add("nmi", 1852, 1, "length", false)
        add("ha", 10000, 1, "area", false)
        add("kn", 463, 900, "speed", false)
        add("bar", 100000, 1, "pressure", true)
        add("atm", 101325, 1, "pressure", false)
        add("Torr", 20265, 152, "pressure", false)
        add("cal", 523, 125, "energy", true)
        add("Wh", 3600, 1, "energy", true)
        add("Ah", 3600, 1, "charge", true)
        add("dC", 1, 1, "temperature", false)
        add("dF", 5, 9, "temperature", false)
    }

    private fun resolve(name: String): Quantity? {
        units
            .firstOrNull { it.symbol == name }
            ?.let {
                return it.quantity
            }
        for ((prefix, factor) in prefixes) {
            if (!name.startsWith(prefix)) continue
            val symbol = name.substring(prefix.length)
            units
                .take(42)
                .firstOrNull { it.prefix && it.symbol == symbol }
                ?.let {
                    return Quantity(factor * it.quantity.value, it.quantity.dim)
                }
        }
        return null
    }

    private fun validateUnit(node: UnitNode) {
        when (node) {
            is UnitName ->
                if (resolve(node.name) == null) throw CommandError("UNKNOWN UNIT ${node.name}")
            is UnitNumber -> {}
            is UnitPower -> {
                validateUnit(node.child)
                exponent(node.exponent)
            }
            is UnitProduct -> node.terms.forEach { validateUnit(it.node) }
        }
    }

    private fun unitValue(node: UnitNode): Quantity =
        when (node) {
            is UnitName -> resolve(node.name)!!
            is UnitNumber -> Quantity(Fraction(node.text.toLong()), Dimension())
            is UnitPower -> {
                val value = unitValue(node.child)
                val k = node.exponent.toInt()
                Quantity(value.value.power(k), value.dim.scale(k))
            }
            is UnitProduct -> {
                var result = Quantity(Fraction.ONE, Dimension())
                for (term in node.terms) {
                    val right = unitValue(term.node)
                    result =
                        if (term.op == '*')
                            Quantity(result.value * right.value, result.dim + right.dim)
                        else Quantity(result.value / right.value, result.dim - right.dim)
                }
                result
            }
        }

    private fun parseUnit(text: String): ParsedUnit {
        val tree = Parser(text, false).completeUnit()
        validateUnit(tree)
        return ParsedUnit(tree, unitValue(tree))
    }

    private fun unit(text: String) = parseUnit(text).quantity

    private fun quantity(text: String) = evaluate(Parser(text, true).complete())

    private fun evaluate(expression: Expr): Quantity =
        when (expression) {
            is Literal -> {
                val text = expression.unit
                if (text == null) Quantity(number(expression.number), Dimension())
                else {
                    val parsed = unit(text)
                    Quantity(number(expression.number) * parsed.value, parsed.dim)
                }
            }
            is Variable ->
                variables[expression.name]
                    ?: throw CommandError("UNKNOWN VARIABLE ${expression.name}")
            is Negative -> evaluate(expression.child).let { Quantity(-it.value, it.dim) }
            is Power -> {
                val value = evaluate(expression.child)
                val k = exponent(expression.exponent)
                if (value.value.n == 0L && k < 0) throw CommandError("DIVISION BY ZERO")
                Quantity(value.value.power(k), value.dim.scale(k))
            }
            is Binary -> {
                val a = evaluate(expression.left)
                val b = evaluate(expression.right)
                when (expression.op) {
                    '+',
                    '-' -> {
                        a.dim.match(b.dim)
                        Quantity(
                            if (expression.op == '+') a.value + b.value else a.value - b.value,
                            a.dim,
                        )
                    }
                    '*' -> Quantity(a.value * b.value, a.dim + b.dim)
                    else -> {
                        if (b.value.n == 0L) throw CommandError("DIVISION BY ZERO")
                        Quantity(a.value / b.value, a.dim - b.dim)
                    }
                }
            }
            is Call -> {
                val arity =
                    when (expression.name) {
                        "abs",
                        "sqrt" -> 1
                        "min",
                        "max" -> 2
                        else -> throw CommandError("UNKNOWN FUNCTION ${expression.name}")
                    }
                if (expression.args.size != arity)
                    throw CommandError("BAD ARGUMENTS ${expression.name}")
                val a = evaluate(expression.args[0])
                when (expression.name) {
                    "abs" -> Quantity(a.value.absolute(), a.dim)
                    "sqrt" -> {
                        if (a.value.n < 0) throw CommandError("NEGATIVE ROOT")
                        if (!a.dim.even()) throw CommandError("ODD DIMENSION ${a.dim}")
                        val n = integerRoot(a.value.n)
                        val d = integerRoot(a.value.d)
                        if (n * n != a.value.n || d * d != a.value.d)
                            throw CommandError("NOT EXACT")
                        Quantity(Fraction(n, d), a.dim.half())
                    }
                    else -> {
                        val b = evaluate(expression.args[1])
                        a.dim.match(b.dim)
                        if (expression.name == "min") {
                            if (a.value <= b.value) a else b
                        } else {
                            if (a.value >= b.value) a else b
                        }
                    }
                }
            }
        }

    private fun simplified(dim: Dimension) =
        units.firstOrNull { it.quantity.value == Fraction.ONE && it.quantity.dim == dim }?.symbol
            ?: dim.toString()

    private fun notation(value: Quantity) = value.value.notation(simplified(value.dim))

    private fun selected(dim: Dimension) =
        units
            .filter { it.quantity.dim == dim }
            .sortedWith(compareBy<Unit> { it.quantity.value }.thenBy { it.symbol })

    fun command(line: String): List<String> {
        val w = line.split(' ')
        return when (w[0]) {
            "DEFINE" -> {
                checkName(w[1], false)
                val value = number(w[3])
                val from = unit(w[4])
                if (w[1] in kinds || resolve(w[1]) != null) throw CommandError("NAME TAKEN ${w[1]}")
                if (value.n <= 0) throw CommandError("NOT POSITIVE ${w[3]}")
                val factor = value * from.value
                units += Unit(w[1], Quantity(factor, from.dim), false, Definition(value, w[4]))
                listOf("DEFINE ${w[1]} factor=$factor dim=${from.dim} kind=${kindName(from.dim)}")
            }
            "UNDEF" -> {
                val index = units.indexOfFirst { it.symbol == w[1] }
                if (index < 0) throw CommandError("NOT DEFINED ${w[1]}")
                if (index < 42) throw CommandError("BUILTIN UNIT ${w[1]}")
                units.removeAt(index)
                listOf("UNDEF ${w[1]}")
            }
            "DEFS" ->
                listOf("DEFS count=${units.size-42}") +
                    units.drop(42).map {
                        val definition = it.definition!!
                        "DEF ${it.symbol} = ${definition.value} ${definition.expression} factor=${it.quantity.value} dim=${it.quantity.dim}"
                    }
            "CONVERT",
            "INVERT" -> {
                val value = number(w[1])
                val from = unit(w[2])
                val to = unit(w[4])
                val inverse = w[0] == "INVERT"
                if (inverse) {
                    if (from.dim == Dimension() || from.dim + to.dim != Dimension())
                        throw CommandError("NOT RECIPROCAL ${from.dim} vs ${to.dim}")
                    if (value.n == 0L) throw CommandError("DIVISION BY ZERO")
                } else from.dim.match(to.dim)
                var result = value * from.value
                if (inverse) result = Fraction.ONE / result
                result /= to.value
                listOf("${w[0]} $value ${w[2]} = ${result.notation(w[4])}")
            }
            "DIM",
            "REDUCE",
            "SIMPLIFY" -> {
                val parsed = parseUnit(w[1])
                val from = parsed.quantity
                val result =
                    when (w[0]) {
                        "DIM" -> "${from.dim} factor=${from.value} kind=${kindName(from.dim)}"
                        "REDUCE" -> reducedText(parsed.tree)
                        else -> notation(from)
                    }
                listOf("${w[0]} ${w[1]} = $result")
            }
            "ADD",
            "SUB",
            "MUL",
            "DIV",
            "COMPARE" -> {
                val a = number(w[1])
                val first = unit(w[2])
                val b = number(w[3])
                val second = unit(w[4])
                val target = w.size == 7
                val destination = if (target) unit(w[6]) else first
                if (w[0] in listOf("ADD", "SUB", "COMPARE")) {
                    first.dim.match(second.dim)
                    if (target) first.dim.match(destination.dim)
                    val left = a * first.value
                    val right = b * second.value
                    if (w[0] == "COMPARE") {
                        val relation = listOf("<", "=", ">")[left.compareTo(right) + 1]
                        val ratio = if (right.n == 0L) "undefined" else (left / right).toString()
                        listOf("COMPARE $a ${w[2]} $relation $b ${w[4]} ratio=$ratio")
                    } else {
                        val add = w[0] == "ADD"
                        val result = (if (add) left + right else left - right) / destination.value
                        listOf(
                            "${w[0]} $a ${w[2]} ${if (add) "+" else "-"} $b ${w[4]} = ${result.notation(if (target) w[6] else w[2])}",
                        )
                    }
                } else {
                    val multiply = w[0] == "MUL"
                    val dim = if (multiply) first.dim + second.dim else first.dim - second.dim
                    if (!multiply && b.n == 0L) throw CommandError("DIVISION BY ZERO")
                    if (target) dim.match(destination.dim)
                    val raw = if (multiply) a * b else a / b
                    val left = a * first.value
                    val right = b * second.value
                    val coherent = if (multiply) left * right else left / right
                    val op = if (multiply) "*" else "/"
                    val prefix = "${w[0]} $a ${w[2]} $op $b ${w[4]} = "
                    if (target) listOf(prefix + (coherent / destination.value).notation(w[6]))
                    else {
                        val rightUnit =
                            if (!multiply && ('*' in w[4] || '/' in w[4])) "(${w[4]})" else w[4]
                        listOf(
                            "$prefix$raw ${w[2]}$op$rightUnit = ${coherent.notation(simplified(dim))}",
                        )
                    }
                }
            }
            "TEMP" -> {
                val value = number(w[1])
                for (scale in listOf(w[2], w[4])) if (scale !in listOf("C", "F", "K", "R"))
                    throw CommandError("UNKNOWN SCALE $scale")
                val kelvin =
                    when (w[2]) {
                        "C" -> value + Fraction(5463, 20)
                        "F" -> (value + Fraction(45967, 100)) * Fraction(5) / Fraction(9)
                        "R" -> value * Fraction(5) / Fraction(9)
                        else -> value
                    }
                if (kelvin.n < 0) throw CommandError("BELOW ABSOLUTE ZERO")
                val result =
                    when (w[4]) {
                        "C" -> kelvin - Fraction(5463, 20)
                        "F" -> kelvin * Fraction(9) / Fraction(5) - Fraction(45967, 100)
                        "R" -> kelvin * Fraction(9) / Fraction(5)
                        else -> kelvin
                    }
                listOf("TEMP $value ${w[2]} = ${result.notation(w[4])}")
            }
            "LIST" -> {
                val dim = kinds[w[1]] ?: unit(w[1]).dim
                val matching = selected(dim)
                listOf("LIST ${w[1]} dim=$dim kind=${kindName(dim)} count=${matching.size}") +
                    matching.map {
                        "UNIT ${it.symbol} factor=${it.quantity.value} origin=${if (it.definition == null) "builtin" else "user"} prefix=${if (it.prefix) "yes" else "no"}"
                    }
            }
            "TABLE" -> {
                val value = number(w[1])
                val from = unit(w[2])
                val matching = selected(from.dim)
                listOf("TABLE $value ${w[2]} dim=${from.dim} count=${matching.size}") +
                    matching.map {
                        "ROW ${(value * from.value / it.quantity.value).notation(it.symbol)}"
                    }
            }
            "AUTO" -> {
                val value = number(w[1])
                val from = unit(w[2])
                val reference =
                    units.take(42).firstOrNull { it.prefix && it.quantity.dim == from.dim }
                        ?: throw CommandError("NO PREFIXABLE UNIT ${from.dim}")
                val scaled = value * from.value / reference.quantity.value
                val magnitude = scaled.absolute()
                var k = 0
                if (magnitude.n != 0L) {
                    if (magnitude >= Fraction.ONE) {
                        while (k < 9 && magnitude >= Fraction(10).power(k + 3)) k += 3
                    } else {
                        while (k > -9 && magnitude < Fraction(10).power(k)) k -= 3
                    }
                }
                val prefix = listOf("n", "u", "m", "", "k", "M", "G")[(k + 9) / 3]
                listOf(
                    "AUTO $value ${w[2]} = ${(scaled / Fraction(10).power(k)).notation(prefix+reference.symbol)}",
                )
            }
            "SPLIT" -> {
                val value = number(w[1])
                val from = unit(w[2])
                val parts = w[4].split(',')
                val destinations = parts.map(::unit)
                if (value.n < 0) throw CommandError("NEGATIVE VALUE")
                destinations.forEach { from.dim.match(it.dim) }
                if (destinations.zipWithNext().any { (a, b) -> a.value <= b.value })
                    throw CommandError("UNIT ORDER")
                var remaining = value * from.value
                val pieces = mutableListOf<String>()
                for (i in 0 until parts.lastIndex) {
                    val quotient = remaining / destinations[i].value
                    val count = quotient.n / quotient.d
                    remaining -= Fraction(count) * destinations[i].value
                    pieces += "$count ${parts[i]}"
                }
                pieces += (remaining / destinations.last().value).notation(parts.last())
                listOf("SPLIT $value ${w[2]} = ${pieces.joinToString(" ")}")
            }
            "LET" -> {
                checkName(w[1], true)
                val value = quantity(w[3])
                variables[w[1]] = value
                listOf("LET ${w[1]} = ${notation(value)}")
            }
            "EVAL" -> {
                val value = quantity(w[1])
                val result =
                    if (w.size == 4) {
                        val destination = unit(w[3])
                        value.dim.match(destination.dim)
                        (value.value / destination.value).notation(w[3])
                    } else notation(value)
                listOf("EVAL ${w[1]} = $result")
            }
            "VARS" ->
                listOf("VARS count=${variables.size}") +
                    variables.map { (name, value) -> "VAR $name = ${notation(value)}" }
            else -> throw CommandError("UNKNOWN COMMAND ${w[0]}")
        }
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val database = Database()
    repeat(input.readLine().toInt()) {
        val line = input.readLine()
        try {
            for (result in database.command(line)) output.write("$result\n")
        } catch (error: CommandError) {
            output.write("${error.message}\n")
        }
    }
    output.flush()
}
