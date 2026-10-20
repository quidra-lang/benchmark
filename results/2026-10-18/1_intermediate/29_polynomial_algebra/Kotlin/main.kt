import java.util.TreeMap
import kotlin.math.abs

private class CommandError(message: String) : RuntimeException("ERROR $message")
private fun integerGcd(a: Long, b: Long): Long {
    var x = abs(a)
    var y = abs(b)
    while (y != 0L) { val remainder = x % y; x = y; y = remainder }
    return x
}
private class Fraction(numerator: Long, denominator: Long = 1) : Comparable<Fraction> {
    val n: Long
    val d: Long
    init {
        val divisor = integerGcd(numerator, denominator) * if (denominator < 0) -1 else 1
        n = numerator / divisor
        d = denominator / divisor
    }
    companion object {
        val ZERO = Fraction(0)
        val ONE = Fraction(1)
        fun parse(text: String): Fraction {
            val parts = text.split('/')
            val n = parts[0].toLong()
            val d = if (parts.size == 1) 1L else parts[1].toLong()
            if (d == 0L) throw CommandError("ZERO DENOMINATOR")
            return Fraction(n, d)
        }
    }
    operator fun plus(b: Fraction) = Fraction(n * b.d + b.n * d, d * b.d)
    operator fun minus(b: Fraction) = Fraction(n * b.d - b.n * d, d * b.d)
    operator fun times(b: Fraction) = Fraction(n * b.n, d * b.d)
    operator fun div(b: Fraction) = Fraction(n * b.d, d * b.n)
    operator fun unaryMinus() = Fraction(-n, d)
    fun abs() = Fraction(abs(n), d)
    fun sign() = n.compareTo(0L)
    fun power(exponent: Int): Fraction {
        var result = ONE
        repeat(exponent) { result *= this }
        return result
    }
    override fun compareTo(other: Fraction) = (n * other.d).compareTo(other.n * d)
    override fun equals(other: Any?) = other is Fraction && n == other.n && d == other.d
    override fun hashCode() = 31 * n.hashCode() + d.hashCode()
    override fun toString() = if (d == 1L) "$n" else "$n/$d"
}
private fun whole(n: Int) = Fraction(n.toLong())

private class Polynomial(values: List<Fraction>) {
    private val coefficients = values.dropLastWhile { it.n == 0L }
    val degree get() = coefficients.lastIndex
    val isZero get() = coefficients.isEmpty()
    val leading get() = coefficients.last()
    val isOne get() = degree == 0 && this[0] == Fraction.ONE
    companion object {
        val ZERO = Polynomial(emptyList())
        val ONE = Polynomial(listOf(Fraction.ONE))
        fun constant(value: Fraction) = Polynomial(listOf(value))
        fun linear(value: Fraction, slope: Fraction) = Polynomial(listOf(value, slope))
    }
    operator fun get(i: Int) = coefficients.getOrElse(i) { Fraction.ZERO }
    operator fun plus(b: Polynomial) = Polynomial((0..maxOf(degree, b.degree)).map { this[it] + b[it] })
    operator fun minus(b: Polynomial) = Polynomial((0..maxOf(degree, b.degree)).map { this[it] - b[it] })
    operator fun unaryMinus() = Polynomial(coefficients.map { -it })
    fun scale(factor: Fraction) = Polynomial(coefficients.map { it * factor })
    fun divideScalar(divisor: Fraction) = Polynomial(coefficients.map { it / divisor })
    operator fun times(b: Polynomial): Polynomial {
        if (isZero || b.isZero) return ZERO
        val result = MutableList(degree + b.degree + 1) { Fraction.ZERO }
        for (i in 0..degree) for (j in 0..b.degree) result[i + j] = result[i + j] + this[i] * b[j]
        return Polynomial(result)
    }
    fun power(exponent: Int): Polynomial {
        if (exponent != 0 && isZero) return ZERO
        if (degree == 0 && this[0].d == 1L && abs(this[0].n) == 1L)
            return constant(whole(if (this[0].n < 0 && exponent % 2 == 1) -1 else 1))
        var result = ONE
        repeat(exponent) { result *= this }
        return result
    }
    fun divide(b: Polynomial): Division {
        val q = MutableList(maxOf(0, degree - b.degree + 1)) { Fraction.ZERO }
        val r = coefficients.toMutableList()
        var currentDegree = degree
        while (currentDegree >= 0 && currentDegree >= b.degree) {
            val factor = r[currentDegree] / b.leading
            val shift = currentDegree - b.degree
            q[shift] = factor
            for (j in 0..b.degree) r[shift + j] = r[shift + j] - factor * b[j]
            while (currentDegree >= 0 && r[currentDegree].n == 0L) currentDegree--
        }
        return Division(Polynomial(q), Polynomial(r))
    }
    fun quotient(b: Polynomial) = divide(b).quotient
    fun remainder(b: Polynomial) = divide(b).remainder
    fun monic() = if (isZero) ZERO else divideScalar(leading)
    fun derivative() = Polynomial((1..degree).map { whole(it) * this[it] })
    fun differentiate(order: Int): Polynomial {
        var result = this
        repeat(order) { if (result.isZero) return result; result = result.derivative() }
        return result
    }
    fun integral() = Polynomial(listOf(Fraction.ZERO) + coefficients.mapIndexed { i, c -> c / whole(i + 1) })
    fun evaluate(point: Fraction): Fraction {
        var result = Fraction.ZERO
        for (i in degree downTo 0) result = result * point + this[i]
        return result
    }
    fun compose(inner: Polynomial): Polynomial {
        var result = ZERO
        for (i in degree downTo 0) result = result * inner + constant(this[i])
        return result
    }
    fun gcd(other: Polynomial): Polynomial {
        var a = this
        var b = other
        while (!b.isZero) { val remainder = a.remainder(b); a = b; b = remainder }
        return a.monic()
    }
    fun extendedGcd(other: Polynomial): Bezout {
        var r0 = this
        var r1 = other
        var s0 = ONE
        var s1 = ZERO
        var t0 = ZERO
        var t1 = ONE
        while (!r1.isZero) {
            val division = r0.divide(r1)
            val s = s0 - division.quotient * s1
            val t = t0 - division.quotient * t1
            r0 = r1; r1 = division.remainder
            s0 = s1; s1 = s
            t0 = t1; t1 = t
        }
        return if (r0.isZero) Bezout(r0, s0, t0)
            else Bezout(r0.monic(), s0.divideScalar(r0.leading), t0.divideScalar(r0.leading))
    }
    fun content(): Fraction {
        var denominator = 1L
        var numerator = 0L
        for (c in coefficients) {
            denominator = denominator * c.d / integerGcd(denominator, c.d)
            numerator = integerGcd(numerator, c.n)
        }
        return Fraction(if (leading.n < 0) -numerator else numerator, denominator)
    }
    fun primitive() = divideScalar(content())
    fun squareFreePart() = if (degree < 1) this else quotient(gcd(derivative()))
    fun withoutConstant() = Polynomial(coefficients.drop(1))
    fun checkProduct(b: Polynomial) {
        if (!isZero && !b.isZero && degree + b.degree > 30) throw CommandError("DEGREE LIMIT")
    }
    fun checkPower(exponent: Int) {
        if (!isZero && degree.toLong() * exponent > 30) throw CommandError("DEGREE LIMIT")
    }
    fun checkComposition(b: Polynomial) {
        if (degree >= 1 && b.degree >= 1 && degree * b.degree > 30) throw CommandError("DEGREE LIMIT")
    }
    fun requireNonzero() { if (isZero) throw CommandError("ZERO POLYNOMIAL") }
    fun requireDivisor() { if (isZero) throw CommandError("DIVISION BY ZERO") }
    fun requirePositiveDegree() { if (degree == 0) throw CommandError("DEGREE TOO LOW") }
    fun format(variable: String = "x"): String {
        val text = StringBuilder()
        for (i in degree downTo 0) {
            val c = this[i]
            if (c.n == 0L) continue
            if (text.isEmpty()) { if (c.n < 0) text.append('-') }
            else text.append(if (c.n < 0) " - " else " + ")
            if (i == 0 || c.abs() != Fraction.ONE) text.append(c.abs())
            if (i > 0) text.append(variable)
            if (i > 1) text.append('^').append(i)
        }
        return if (text.isEmpty()) "0" else text.toString()
    }
}
private data class Division(val quotient: Polynomial, val remainder: Polynomial)
private data class Bezout(val g: Polynomial, val s: Polynomial, val t: Polynomial)

private sealed interface Expression { fun evaluate(storage: Map<String, Polynomial>): Polynomial }
private data class Literal(val value: Int) : Expression {
    override fun evaluate(storage: Map<String, Polynomial>) = Polynomial.constant(whole(value))
}
private data object Variable : Expression {
    override fun evaluate(storage: Map<String, Polynomial>) = Polynomial.linear(Fraction.ZERO, Fraction.ONE)
}
private data class Reference(val name: String, val order: Int) : Expression {
    override fun evaluate(storage: Map<String, Polynomial>) =
        (storage[name] ?: throw CommandError("UNKNOWN $name")).differentiate(order)
}
private data class Negative(val operand: Expression) : Expression {
    override fun evaluate(storage: Map<String, Polynomial>) = -operand.evaluate(storage)
}
private data class Binary(val operation: Char, val left: Expression, val right: Expression) : Expression {
    override fun evaluate(storage: Map<String, Polynomial>): Polynomial {
        val a = left.evaluate(storage)
        val b = right.evaluate(storage)
        return when (operation) {
            '+' -> a + b
            '-' -> a - b
            '*' -> { a.checkProduct(b); a * b }
            else -> {
                b.requireDivisor()
                if (b.degree >= 1) throw CommandError("NONCONSTANT DIVISOR")
                a.divideScalar(b[0])
            }
        }
    }
}
private data class Power(val operand: Expression, val exponent: Int) : Expression {
    override fun evaluate(storage: Map<String, Polynomial>): Polynomial {
        val value = operand.evaluate(storage)
        value.checkPower(exponent)
        return value.power(exponent)
    }
}
private data class Call(val function: Expression, val argument: Expression) : Expression {
    override fun evaluate(storage: Map<String, Polynomial>): Polynomial {
        val a = function.evaluate(storage)
        val b = argument.evaluate(storage)
        a.checkComposition(b)
        return a.compose(b)
    }
}
private enum class TokenKind { NUMBER, NAME, SYMBOL, END }
private data class Token(val kind: TokenKind, val text: String, val position: Int)
private class Parser(source: String) {
    private val tokens = mutableListOf<Token>()
    private var position = 0
    private val current get() = tokens[position]
    init {
        var i = 0
        while (i < source.length) {
            if (source[i] == ' ') { i++; continue }
            val start = i++
            val kind = when (source[start]) { in '0'..'9' -> TokenKind.NUMBER; in 'A'..'Z' -> TokenKind.NAME; else -> TokenKind.SYMBOL }
            if (kind == TokenKind.NUMBER) while (i < source.length && source[i] in '0'..'9') i++
            else if (kind == TokenKind.NAME) while (i < source.length && (source[i] in 'A'..'Z' || source[i] in '0'..'9')) i++
            tokens += Token(kind, source.substring(start, i), start + 1)
        }
        tokens += Token(TokenKind.END, "", source.length + 1)
    }
    private fun syntax(): Nothing = throw CommandError("SYNTAX AT ${if (current.kind == TokenKind.END) "END" else current.position}")
    private fun accept(symbol: String): Boolean {
        if (current.kind == TokenKind.SYMBOL && current.text == symbol) { position++; return true }
        return false
    }
    private fun expect(symbol: String) { if (!accept(symbol)) syntax() }
    fun parse(): Expression {
        val result = expression()
        if (current.kind != TokenKind.END) syntax()
        return result
    }
    private fun expression(): Expression {
        val negative = accept("-")
        var result = term()
        if (negative) result = Negative(result)
        while (true) {
            val operation = if (accept("+")) '+' else if (accept("-")) '-' else break
            result = Binary(operation, result, term())
        }
        return result
    }
    private fun term(): Expression {
        var result = factor()
        while (true) {
            val operation = if (accept("*")) '*' else if (accept("/")) '/'
                else if (current.kind == TokenKind.NAME || current.text == "x" || current.text == "(") '*' else break
            result = Binary(operation, result, factor())
        }
        return result
    }
    private fun factor(): Expression {
        var result = primary()
        if (accept("^")) {
            if (current.kind != TokenKind.NUMBER) syntax()
            val exponent = current.text.toInt()
            position++
            result = Power(result, exponent)
        }
        return result
    }
    private fun primary(): Expression {
        if (current.kind == TokenKind.NUMBER) { val value = current.text.toInt(); position++; return Literal(value) }
        if (accept("x")) return Variable
        if (current.kind == TokenKind.NAME) {
            val name = current.text
            position++
            var order = 0
            while (accept("'")) order++
            val reference = Reference(name, order)
            if (!accept("(")) return reference
            val argument = expression()
            expect(")")
            return Call(reference, argument)
        }
        if (accept("(")) { val result = expression(); expect(")"); return result }
        syntax()
    }
}

private data class Root(val value: Fraction, val multiplicity: Int)
private data class Factor(val value: Polynomial, val multiplicity: Int)
private data class RootResult(val content: Fraction, val remaining: Polynomial, val roots: List<Root>)
private fun divisors(n: Long) = (1L..n).filter { n % it == 0L }
private fun rationalRoots(a: Polynomial): RootResult {
    val content = a.content()
    var p = a.divideScalar(content)
    var zeros = 0
    while (p[0].n == 0L) { p = p.withoutConstant(); zeros++ }
    val numerators = divisors(abs(p[0].n))
    val denominators = divisors(p.leading.n)
    val candidates = mutableListOf<Fraction>()
    for (s in numerators) for (t in denominators) {
        if (integerGcd(s, t) == 1L) { candidates += Fraction(-s, t); candidates += Fraction(s, t) }
    }
    candidates.sort()
    val roots = mutableListOf<Root>()
    for (r in candidates) {
        var multiplicity = 0
        while (p.degree >= 1 && p.evaluate(r).n == 0L) {
            p = p.quotient(Polynomial.linear(Fraction(-r.n), Fraction(r.d)))
            multiplicity++
        }
        if (multiplicity > 0) roots += Root(r, multiplicity)
    }
    if (zeros > 0) roots += Root(Fraction.ZERO, zeros)
    roots.sortBy { it.value }
    return RootResult(content, p, roots)
}
private fun squareFreeFactors(a: Polynomial): List<Factor> {
    if (a.degree < 1) return emptyList()
    val w0 = a.monic()
    var c = w0.gcd(w0.derivative())
    var w = w0.quotient(c)
    val result = mutableListOf<Factor>()
    var multiplicity = 1
    while (w.degree >= 1) {
        val y = w.gcd(c)
        val f = w.quotient(y)
        if (f.degree >= 1) result += Factor(f.primitive(), multiplicity)
        c = c.quotient(y)
        w = y
        multiplicity++
    }
    return result
}
private fun appendFactor(text: StringBuilder, p: Polynomial, multiplicity: Int, simpleX: Boolean) {
    text.append(" * ")
    if (simpleX) text.append('x') else text.append('(').append(p.format()).append(')')
    if (multiplicity > 1) text.append('^').append(multiplicity)
}
private data class Bound(val infinity: Int = 0, val value: Fraction = Fraction.ZERO) : Comparable<Bound> {
    companion object {
        fun finite(value: Fraction) = Bound(value = value)
        fun parse(text: String) = when (text) { "-inf" -> Bound(-1); "inf" -> Bound(1); else -> finite(Fraction.parse(text)) }
    }
    override fun compareTo(other: Bound) = if (infinity != 0 || other.infinity != 0) infinity.compareTo(other.infinity) else value.compareTo(other.value)
    override fun toString() = if (infinity == 0) value.toString() else if (infinity < 0) "-inf" else "inf"
}
private data class Interval(val low: Fraction, val high: Fraction)
private fun sturmSequence(a: Polynomial): List<Polynomial> {
    var p = a.squareFreePart()
    var q = p.derivative()
    val sequence = mutableListOf(p)
    while (!q.isZero) {
        sequence += q
        val next = -p.remainder(q)
        p = q
        q = next
    }
    return sequence
}
private fun variations(sequence: List<Polynomial>, point: Bound): Int {
    var previous = 0
    var count = 0
    for (p in sequence) {
        var sign = if (point.infinity == 0) p.evaluate(point.value).sign() else p.leading.sign()
        if (point.infinity < 0 && p.degree % 2 == 1) sign = -sign
        if (sign == 0) continue
        if (previous != 0 && previous != sign) count++
        previous = sign
    }
    return count
}
private fun rootCount(sequence: List<Polynomial>, low: Bound, high: Bound): Int {
    val left = variations(sequence, low)
    val right = variations(sequence, high)
    return left - right
}
private fun examine(sequence: List<Polynomial>, low: Fraction, high: Fraction, width: Fraction, result: MutableList<Interval>) {
    val count = rootCount(sequence, Bound.finite(low), Bound.finite(high))
    if (count >= 2) {
        val middle = (low + high) / whole(2)
        examine(sequence, low, middle, width, result)
        examine(sequence, middle, high, width, result)
    } else if (count == 1) {
        var left = low
        var right = high
        while (right - left > width) {
            val middle = (left + right) / whole(2)
            if (rootCount(sequence, Bound.finite(left), Bound.finite(middle)) >= 1) right = middle else left = middle
        }
        result += Interval(left, right)
    }
}
private fun isolate(a: Polynomial, precision: Int): List<Interval> {
    val sequence = sturmSequence(a)
    val first = sequence.first()
    var maximum = Fraction.ZERO
    for (i in 0 until first.degree) maximum = maxOf(maximum, (first[i] / first.leading).abs())
    val beta = Fraction.ONE + maximum
    val width = Fraction(1, 1L shl precision)
    val result = mutableListOf<Interval>()
    examine(sequence, -beta, beta, width, result)
    return result
}
private fun resultant(a: Polynomial, b: Polynomial): Fraction {
    var p = a
    var q = b
    var result = Fraction.ONE
    while (q.degree >= 1) {
        val t = p.remainder(q)
        if (t.isZero) return Fraction.ZERO
        result *= q.leading.power(p.degree - t.degree)
        if (p.degree * q.degree % 2 == 1) result = -result
        p = q
        q = t
    }
    return result * q[0].power(p.degree)
}
private fun descartes(a: Polynomial, negative: Boolean): Int {
    var previous = 0
    var count = 0
    for (i in a.degree downTo 0) {
        var sign = a[i].sign()
        if (negative && i % 2 == 1) sign = -sign
        if (sign == 0) continue
        if (previous != 0 && previous != sign) count++
        previous = sign
    }
    return count
}
private fun interpolate(values: List<Fraction>): Polynomial {
    val m = values.size / 2
    val x = List(m) { values[2 * it] }
    val d = MutableList(m) { values[2 * it + 1] }
    for (j in 1 until m) for (i in 0 until j) if (x[j] == x[i]) throw CommandError("DUPLICATE X ${x[j]}")
    for (j in 1 until m) for (i in m - 1 downTo j) d[i] = (d[i] - d[i - 1]) / (x[i] - x[i - j])
    var result = Polynomial.ZERO
    for (i in m - 1 downTo 0) result = result * Polynomial.linear(-x[i], Fraction.ONE) + Polynomial.constant(d[i])
    return result
}
private fun special(kind: String, n: Int): Polynomial {
    if (kind !in setOf("chebyshev", "chebyshev2", "legendre", "hermite", "laguerre")) throw CommandError("UNKNOWN KIND $kind")
    if (n > 30) throw CommandError("DEGREE LIMIT")
    var a = Polynomial.ONE
    if (n == 0) return a
    var b = when (kind) {
        "chebyshev2", "hermite" -> Polynomial.linear(Fraction.ZERO, whole(2))
        "laguerre" -> Polynomial.linear(Fraction.ONE, whole(-1))
        else -> Polynomial.linear(Fraction.ZERO, Fraction.ONE)
    }
    for (j in 1 until n) {
        val factor = when (kind) {
            "legendre" -> Polynomial.linear(Fraction.ZERO, whole(2 * j + 1))
            "laguerre" -> Polynomial.linear(whole(2 * j + 1), whole(-1))
            else -> Polynomial.linear(Fraction.ZERO, whole(2))
        }
        val multiplier = when (kind) { "legendre", "laguerre" -> j; "hermite" -> 2 * j; else -> 1 }
        var next = factor * b - a.scale(whole(multiplier))
        if (kind == "legendre" || kind == "laguerre") next = next.scale(Fraction(1, (j + 1).toLong()))
        a = b
        b = next
    }
    return b
}

private data class Named(val name: String, val value: Polynomial)
private class Response {
    val stores = mutableListOf<Named>()
    val lines = mutableListOf<String>()
    var deletion: String? = null
    fun save(name: String, value: Polynomial) {
        stores += Named(name, value)
        lines += "$name = ${value.format()}"
    }
}
private class Calculator {
    private val storage = TreeMap<String, Polynomial>()
    private fun lookup(name: String) = storage[name] ?: throw CommandError("UNKNOWN $name")
    private fun sourcePositions(command: String) = when (command) {
        "ADD", "SUB", "MUL", "GCD", "LCM", "INVMOD", "COMPOSE" -> listOf(2, 3)
        "POW", "DERIV", "INTEG", "TANGENT" -> listOf(2)
        "MODPOW" -> listOf(2, 4)
        "DIV" -> listOf(3, 4)
        "XGCD" -> listOf(4, 5)
        "CRT" -> listOf(2, 3, 4, 5)
        "RESULTANT" -> listOf(1, 2)
        "LIST", "INTERP", "SPECIAL" -> emptyList()
        else -> listOf(1)
    }
    fun execute(line: String): List<String> {
        val response = Response()
        if (line.startsWith("DEF ")) {
            val parts = line.split(' ', limit = 3)
            val expression = Parser(parts[2]).parse()
            response.save(parts[1], expression.evaluate(storage))
        } else {
            val w = line.split(' ')
            val command = w[0]
            if (command == "DIV" && w[1] == w[2] || command == "XGCD" &&
                (w[1] == w[2] || w[1] == w[3] || w[2] == w[3])) throw CommandError("SAME NAME")
            val operands = sourcePositions(command).map { lookup(w[it]) }
            val start = when (command) { "AREA", "TAYLOR", "EVAL", "INTERP" -> 2; "TANGENT" -> 3; else -> w.size }
            val values = w.drop(start).map { Fraction.parse(it) }
            val bounds = if (command == "STURM") Bound.parse(w[2]) to Bound.parse(w[3]) else null
            val a = operands.getOrElse(0) { Polynomial.ZERO }
            val b = operands.getOrElse(1) { Polynomial.ZERO }
            when (command) {
                "PRINT" -> response.lines.add("${w[1]} = ${a.format()}")
                "DELETE" -> { response.deletion = w[1]; response.lines += "deleted ${w[1]}" }
                "LIST" -> {
                    for ((name, value) in storage) response.lines += "$name = ${value.format()}"
                    if (storage.isEmpty()) response.lines += "no polynomials"
                }
                "DEGREE" -> response.lines.add("deg(${w[1]}) = ${if (a.isZero) "-inf" else a.degree}")
                "ADD" -> response.save(w[1], a + b)
                "SUB" -> response.save(w[1], a - b)
                "MUL" -> { a.checkProduct(b); response.save(w[1], a * b) }
                "POW" -> { val n = w[3].toInt(); a.checkPower(n); response.save(w[1], a.power(n)) }
                "DIV" -> {
                    b.requireDivisor()
                    val division = a.divide(b)
                    response.save(w[1], division.quotient)
                    response.save(w[2], division.remainder)
                }
                "GCD" -> response.save(w[1], a.gcd(b))
                "XGCD" -> {
                    val e = a.extendedGcd(b)
                    response.save(w[1], e.g); response.save(w[2], e.s); response.save(w[3], e.t)
                }
                "LCM" -> {
                    val value = if (a.isZero || b.isZero) Polynomial.ZERO else {
                        val g = a.gcd(b)
                        if (a.degree + b.degree - g.degree > 30) throw CommandError("DEGREE LIMIT")
                        (a.quotient(g) * b).monic()
                    }
                    response.save(w[1], value)
                }
                "INVMOD" -> {
                    b.requireDivisor(); b.requirePositiveDegree()
                    val e = a.extendedGcd(b)
                    if (!e.g.isOne) throw CommandError("NOT COPRIME")
                    response.save(w[1], e.s.remainder(b))
                }
                "CRT" -> {
                    val a2 = operands[2]
                    val m2 = operands[3]
                    b.requireDivisor(); m2.requireDivisor()
                    if (b.degree + m2.degree > 30) throw CommandError("DEGREE LIMIT")
                    val e = b.extendedGcd(m2)
                    if (!e.g.isOne) throw CommandError("NOT COPRIME")
                    val r1 = a.remainder(b)
                    val r2 = a2.remainder(m2)
                    val u = ((r2 - r1) * e.s).remainder(m2)
                    response.save(w[1], r1 + b * u)
                }
                "MODPOW" -> {
                    b.requireDivisor()
                    if (2 * b.degree - 2 > 30) throw CommandError("DEGREE LIMIT")
                    var x = Polynomial.ONE.remainder(b)
                    var y = a.remainder(b)
                    var exponent = w[3].toInt()
                    while (exponent > 0) {
                        if (exponent % 2 == 1) x = (x * y).remainder(b)
                        exponent /= 2
                        if (exponent != 0) y = (y * y).remainder(b)
                    }
                    response.save(w[1], x)
                }
                "DERIV" -> response.save(w[1], a.differentiate(w[3].toInt()))
                "INTEG" -> {
                    if (!a.isZero && a.degree + 1 > 30) throw CommandError("DEGREE LIMIT")
                    response.save(w[1], a.integral())
                }
                "AREA" -> {
                    val integral = a.integral()
                    val value = integral.evaluate(values[1]) - integral.evaluate(values[0])
                    response.lines += "integral(${w[1]}, ${values[0]}, ${values[1]}) = $value"
                }
                "TANGENT" -> {
                    val point = values[0]
                    val y = a.evaluate(point)
                    val slope = a.derivative().evaluate(point)
                    response.save(w[1], Polynomial.linear(y - slope * point, slope))
                }
                "TAYLOR" -> {
                    val point = values[0]
                    val shifted = a.compose(Polynomial.linear(point, Fraction.ONE))
                    val variable = if (point.n == 0L) "x" else if (point.n > 0) "(x - $point)" else "(x + ${-point})"
                    response.lines += "taylor(${w[1]}, $point) = ${shifted.format(variable)}"
                }
                "COMPOSE" -> { a.checkComposition(b); response.save(w[1], a.compose(b)) }
                "EVAL" -> for (point in values) response.lines += "${w[1]}($point) = ${a.evaluate(point)}"
                "ROOTS", "FACTOR" -> {
                    a.requireNonzero()
                    val roots = rationalRoots(a)
                    if (command == "ROOTS") {
                        val entries = roots.roots.joinToString(", ") { "${it.value} (${it.multiplicity})" }.ifEmpty { "none" }
                        response.lines += "roots(${w[1]}) = $entries"
                    } else {
                        val text = StringBuilder("factor(${w[1]}) = ${roots.content}")
                        for ((value, multiplicity) in roots.roots)
                            appendFactor(text, Polynomial.linear(Fraction(-value.n), Fraction(value.d)), multiplicity, value.n == 0L)
                        if (roots.remaining.degree >= 1) appendFactor(text, roots.remaining, 1, false)
                        response.lines += text.toString()
                    }
                }
                "SQFREE" -> {
                    a.requireNonzero()
                    val text = StringBuilder("sqfree(${w[1]}) = ${a.content()}")
                    for ((p, multiplicity) in squareFreeFactors(a))
                        appendFactor(text, p, multiplicity, p.degree == 1 && p[0].n == 0L && p[1] == Fraction.ONE)
                    response.lines += text.toString()
                }
                "DESCARTES" -> {
                    a.requireNonzero()
                    response.lines += "descartes(${w[1]}) = positive ${descartes(a, false)}, negative ${descartes(a, true)}"
                }
                "STURM" -> {
                    a.requireNonzero()
                    val (low, high) = bounds!!
                    if (low >= high) throw CommandError("BAD INTERVAL")
                    val sequence = sturmSequence(a)
                    response.lines += "sturm(${w[1]}, $low, $high) = ${rootCount(sequence, low, high)}"
                }
                "ISOLATE" -> {
                    a.requireNonzero()
                    val precision = w[2].toInt()
                    val entries = isolate(a, precision).joinToString(", ") { "(${it.low}, ${it.high}]" }.ifEmpty { "none" }
                    response.lines += "isolate(${w[1]}, $precision) = $entries"
                }
                "RESULTANT" -> {
                    a.requireNonzero(); b.requireNonzero()
                    response.lines += "res(${w[1]}, ${w[2]}) = ${resultant(a, b)}"
                }
                "DISCRIM", "POWERSUM" -> {
                    a.requireNonzero(); a.requirePositiveDegree()
                    val degree = a.degree
                    if (command == "DISCRIM") {
                        var value = resultant(a, a.derivative()) / a.leading
                        if (degree * (degree - 1) / 2 % 2 == 1) value = -value
                        response.lines += "disc(${w[1]}) = $value"
                    } else {
                        val n = w[2].toInt()
                        val monic = a.monic()
                        val sums = MutableList(n + 1) { Fraction.ZERO }
                        for (j in 1..n) {
                            var value = if (j <= degree) whole(j) * monic[degree - j] else Fraction.ZERO
                            for (i in 1..minOf(j - 1, degree)) value += monic[degree - i] * sums[j - i]
                            sums[j] = -value
                        }
                        response.lines += "powersum(${w[1]}) = ${sums.drop(1).joinToString(", ")}"
                    }
                }
                "INTERP" -> response.save(w[1], interpolate(values))
                "SPECIAL" -> response.save(w[1], special(w[2], w[3].toInt()))
                else -> error("Unknown command")
            }
        }
        response.deletion?.let { storage.remove(it) }
        for ((name, value) in response.stores) storage[name] = value
        return response.lines
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val count = input.readLine()?.toInt() ?: return
    val calculator = Calculator()
    repeat(count) {
        val line = input.readLine()
        try { for (text in calculator.execute(line)) { output.write(text); output.write("\n") } }
        catch (error: CommandError) { output.write(error.message!!); output.write("\n") }
    }
    output.flush()
}
