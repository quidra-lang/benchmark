import java.util.Locale

private const val INVALID = 1
private const val DIVBYZERO = 2
private const val OVERFLOW = 4
private const val UNDERFLOW = 8
private const val INEXACT = 16

private enum class Mode { RNE, RNA, RTZ, RUP, RDN }
private enum class Kind(val text: String) {
    ZERO("zero"), SUBNORMAL("subnormal"), NORMAL("normal"), INFINITY("infinity"), QNAN("qnan"), SNAN("snan");
    override fun toString() = text
}
private enum class Operation { ADD, SUB, MUL, DIV, SQRT, FMA }
private class CommandError(message: String) : RuntimeException(message)
private fun fail(message: String): Nothing = throw CommandError(message)

private data class Term(val negative: Boolean, val magnitude: Long, val exponent: Int) {
    fun product(other: Term) = Term(negative != other.negative, magnitude * other.magnitude, exponent + other.exponent)
    fun negated() = copy(negative = !negative)
    fun exact() = Exact.of(negative, magnitude, exponent, 1)
    fun decimal(): String {
        if (magnitude == 0L) return "0"
        val (numerator, denominator) = exact().scaled(0)
        val out = StringBuilder(if (negative) "-" else "")
        out.append(numerator / denominator)
        var remainder = numerator % denominator
        if (remainder != 0L) out.append('.')
        while (remainder != 0L) {
            remainder *= 10
            out.append(('0'.code + remainder / denominator).toInt().toChar())
            remainder %= denominator
        }
        return out.toString()
    }
}

private fun sumTerms(terms: List<Term>, mode: Mode): Term {
    val exponent = terms.filter { it.magnitude != 0L }.minOfOrNull { it.exponent } ?: 0
    var sum = 0L
    for (term in terms) {
        if (term.magnitude == 0L) continue
        val magnitude = term.magnitude shl (term.exponent - exponent)
        sum += if (term.negative) -magnitude else magnitude
    }
    if (sum == 0L) {
        val sameZero = terms.all { it.magnitude == 0L && it.negative == terms.first().negative }
        return Term(if (sameZero) terms.first().negative else mode == Mode.RDN, 0, 0)
    }
    return Term(sum < 0, if (sum < 0) -sum else sum, exponent)
}

private class Exact private constructor(val negative: Boolean, val numerator: Long, val exponent: Int, val denominator: Long) {
    companion object {
        fun of(negative: Boolean, numerator: Long, exponent: Int, denominator: Long): Exact {
            if (numerator == 0L) return Exact(negative, 0, 0, 1)
            var a = numerator
            var b = denominator
            while (b != 0L) {
                val remainder = a % b
                a = b
                b = remainder
            }
            var n = numerator / a
            var d = denominator / a
            var q = exponent
            var shift = n.countTrailingZeroBits()
            n = n shr shift
            q += shift
            shift = d.countTrailingZeroBits()
            d = d shr shift
            q -= shift
            return Exact(negative, n, q, d)
        }
    }

    fun scaled(quantum: Int): Pair<Long, Long> {
        val shift = exponent - quantum
        return if (shift >= 0) (numerator shl shift) to denominator else numerator to (denominator shl -shift)
    }
    fun floorLog(): Int {
        val power = denominator.countLeadingZeroBits() - numerator.countLeadingZeroBits()
        val below = if (power >= 0) numerator < (denominator shl power) else (numerator shl -power) < denominator
        return exponent + power - if (below) 1 else 0
    }
    fun fraction(): String {
        if (numerator == 0L) return "0"
        val (n, d) = scaled(0)
        return (if (negative) "-" else "") + n + if (d == 1L) "" else "/$d"
    }
}

private fun integerSqrt(value: Long): Long {
    if (value == 0L) return 0
    var root = value
    var next = (value + 1) / 2
    while (next < root) {
        root = next
        next = (root + value / root) / 2
    }
    return root
}

private data class Quantized(val whole: Long, val inexact: Boolean, val half: Int) {
    companion object {
        fun of(value: Exact, quantum: Int, squareRoot: Boolean): Quantized {
            val (numerator, denominator) = value.scaled(if (squareRoot) 2 * quantum else quantum)
            if (!squareRoot) {
                val remainder = numerator % denominator
                return Quantized(numerator / denominator, remainder != 0L, remainder.compareTo(denominator - remainder))
            }
            val whole = integerSqrt(numerator / denominator)
            val midpoint = 2 * whole + 1
            return Quantized(whole, whole * whole * denominator != numerator,
                (4 * numerator).compareTo(midpoint * midpoint * denominator))
        }
    }
    fun rounded(mode: Mode, negative: Boolean): Long {
        val increment = when (mode) {
            Mode.RNE -> half > 0 || half == 0 && (whole and 1L) != 0L
            Mode.RNA -> half >= 0
            Mode.RTZ -> false
            Mode.RUP -> inexact && !negative
            Mode.RDN -> inexact && negative
        }
        return whole + if (increment) 1 else 0
    }
}

private data class Rounded(val pattern: Int, val flags: Int = 0)
private data class Operand(val pattern: Int = 0, val number: Exact? = null)
private data class Bounds(val minimum: Long, val maximum: Long)

private class Format(val name: String, val e: Int, val m: Int) {
    val w = 1 + e + m
    val bias = (1 shl (e - 1)) - 1
    val emin = 1 - bias
    val emax = bias
    val sign = 1 shl (e + m)
    val base = 1 shl m
    val infinity = ((1 shl e) - 1) shl m
    val nan = infinity or (base / 2)

    fun negative(p: Int) = (p and sign) != 0
    fun zero(p: Int) = (p and (sign - 1)) == 0
    fun signed(p: Int, negative: Boolean) = p or if (negative) sign else 0
    fun kind(p: Int): Kind {
        val magnitude = p and (sign - 1)
        val fraction = p and (base - 1)
        return when {
            magnitude >= infinity -> when {
                fraction == 0 -> Kind.INFINITY
                fraction >= base / 2 -> Kind.QNAN
                else -> Kind.SNAN
            }
            magnitude == 0 -> Kind.ZERO
            magnitude < base -> Kind.SUBNORMAL
            else -> Kind.NORMAL
        }
    }
    fun finite(p: Int) = kind(p) in setOf(Kind.ZERO, Kind.SUBNORMAL, Kind.NORMAL)
    fun isNaN(p: Int) = kind(p) == Kind.QNAN || kind(p) == Kind.SNAN
    fun term(p: Int): Term {
        val field = (p and (sign - 1)) shr m
        val fraction = p and (base - 1)
        return Term(negative(p), (if (field == 0) fraction else base + fraction).toLong(),
            if (field == 0) emin - m else field - bias - m)
    }
    fun overflow(mode: Mode, negative: Boolean): Rounded {
        val toInfinity = mode == Mode.RNE || mode == Mode.RNA || mode == Mode.RUP && !negative || mode == Mode.RDN && negative
        return Rounded(signed(if (toInfinity) infinity else infinity - 1, negative), OVERFLOW or INEXACT)
    }
    fun round(value: Exact, mode: Mode, squareRoot: Boolean = false): Rounded {
        if (value.numerator == 0L) return Rounded(signed(0, value.negative))
        var t = value.floorLog()
        if (squareRoot) t = t.floorDiv(2)
        if (t > emax) return overflow(mode, value.negative)
        var quantum = maxOf(t, emin) - m
        val divided = Quantized.of(value, quantum, squareRoot)
        var significand = divided.rounded(mode, value.negative)
        if (significand == 2L * base) {
            significand = base.toLong()
            quantum++
        }
        if (quantum > emax - m) return overflow(mode, value.negative)
        var flags = if (divided.inexact) INEXACT else 0
        if (divided.inexact && t < emin) {
            val tiny = t < emin - 1 || Quantized.of(value, t - m, squareRoot).rounded(mode, value.negative) < 2L * base
            if (tiny) flags = flags or UNDERFLOW
        }
        val magnitude = if (significand < base) significand.toInt()
            else ((quantum + m + bias) shl m) or (significand - base).toInt()
        return Rounded(signed(magnitude, value.negative), flags)
    }
    fun roundTerm(term: Term, mode: Mode) = round(term.exact(), mode)
    fun roundSum(terms: List<Term>, mode: Mode) = roundTerm(sumTerms(terms, mode), mode)

    fun arithmetic(operation: Operation, a: Int, bInput: Int, c: Int, mode: Mode): Rounded {
        val b = if (operation == Operation.SUB) bInput xor sign else bInput
        val op = if (operation == Operation.SUB) Operation.ADD else operation
        val inputs = when (op) {
            Operation.SQRT -> listOf(a)
            Operation.FMA -> listOf(a, b, c)
            else -> listOf(a, b)
        }
        if (inputs.any(::isNaN)) return Rounded(nan, if (inputs.any { kind(it) == Kind.SNAN }) INVALID else 0)
        val ai = kind(a) == Kind.INFINITY
        val bi = kind(b) == Kind.INFINITY
        val sigma = negative(a) != negative(b)
        val invalid = Rounded(nan, INVALID)
        return when (op) {
            Operation.ADD -> when {
                ai && bi && sigma -> invalid
                ai -> Rounded(a)
                bi -> Rounded(b)
                else -> roundSum(listOf(term(a), term(b)), mode)
            }
            Operation.MUL -> if (ai || bi) {
                if (zero(a) || zero(b)) invalid else Rounded(signed(infinity, sigma))
            } else roundTerm(term(a).product(term(b)), mode)
            Operation.DIV -> when {
                ai -> if (bi) invalid else Rounded(signed(infinity, sigma))
                bi -> Rounded(signed(0, sigma))
                zero(b) -> if (zero(a)) invalid else Rounded(signed(infinity, sigma), DIVBYZERO)
                zero(a) -> Rounded(signed(0, sigma))
                else -> {
                    val x = term(a)
                    val y = term(b)
                    round(Exact.of(sigma, x.magnitude, x.exponent - y.exponent, y.magnitude), mode)
                }
            }
            Operation.SQRT -> when {
                zero(a) -> Rounded(a)
                negative(a) -> invalid
                ai -> Rounded(a)
                else -> round(term(a).exact(), mode, true)
            }
            Operation.FMA -> when {
                ai || bi -> if (zero(a) || zero(b) || kind(c) == Kind.INFINITY && negative(c) != sigma) invalid
                    else Rounded(signed(infinity, sigma))
                kind(c) == Kind.INFINITY -> Rounded(c)
                else -> roundSum(listOf(term(a).product(term(b)), term(c)), mode)
            }
            Operation.SUB -> error("unreachable operation")
        }
    }

    fun rawOperand(word: String, encoding: Boolean): Operand {
        if (word.startsWith("0b") || word.startsWith("0x")) {
            val binary = word.startsWith("0b")
            val width = if (binary) w else (w + 3) / 4
            if (encoding || word.length - 2 != width) fail("ERROR BAD OPERAND $word")
            val p = word.substring(2).toInt(if (binary) 2 else 16)
            if (p >= 2 * sign) fail("ERROR BAD OPERAND $word")
            return Operand(pattern = p)
        }
        when (word) {
            "nan" -> return Operand(pattern = nan)
            "inf" -> return Operand(pattern = infinity)
            "-inf" -> return Operand(pattern = infinity or sign)
        }
        val negative = word.startsWith('-')
        val digits = word.removePrefix("-")
        val slash = digits.indexOf('/')
        val dot = digits.indexOf('.')
        var denominator = 1L
        val numerator = when {
            slash >= 0 -> {
                denominator = digits.substring(slash + 1).toLong()
                if (denominator == 0L) fail("ERROR BAD OPERAND $word")
                digits.substring(0, slash).toLong()
            }
            dot >= 0 -> {
                repeat(digits.length - dot - 1) { denominator *= 10 }
                (digits.substring(0, dot) + digits.substring(dot + 1)).toLong()
            }
            else -> digits.toLong()
        }
        return Operand(number = Exact.of(negative, numerator, 0, denominator))
    }
    fun operand(word: String): Int {
        val value = rawOperand(word, false)
        return value.number?.let { round(it, Mode.RNE).pattern } ?: value.pattern
    }
    fun bits(p: Int) = "${if (negative(p)) 1 else 0}|${binary((p and (sign - 1)) shr m, e)}|${binary(p and (base - 1), m)}"
    fun hex(p: Int) = "0x" + p.toString(16).uppercase(Locale.ROOT).padStart((w + 3) / 4, '0')
    fun value(p: Int): String = when (kind(p)) {
        Kind.QNAN, Kind.SNAN -> "nan"
        Kind.INFINITY -> if (negative(p)) "-inf" else "inf"
        Kind.ZERO -> if (negative(p)) "-0" else "0"
        else -> term(p).decimal()
    }
    fun pattern(p: Int) = "${bits(p)} ${hex(p)} ${value(p)}"
    fun result(result: Rounded) = "${pattern(result.pattern)} ${flagText(result.flags)}"
    fun difference(p: Int, exactSum: Term) = if (finite(p)) sumTerms(listOf(term(p), exactSum.negated()), Mode.RNE).exact().fraction() else value(p)
    fun orderKey(p: Int) = if (negative(p)) -(p - sign) - 1 else p
    fun nextUp(p: Int) = when {
        p == infinity -> p
        zero(p) -> 1
        negative(p) -> p - 1
        else -> p + 1
    }
}

private fun binary(value: Int, width: Int) = value.toString(2).padStart(width, '0')
private fun flagText(flags: Int): String {
    val names = listOf("invalid", "divbyzero", "overflow", "underflow", "inexact")
    val raised = names.filterIndexed { i, _ -> (flags and (1 shl i)) != 0 }
    return "flags=" + if (raised.isEmpty()) "none" else raised.joinToString(",")
}
private fun parseMode(word: String) = Mode.entries.find { it.name == word } ?: fail("ERROR BAD MODE $word")
private fun modeAt(words: List<String>, index: Int) = words.getOrNull(index)?.let(::parseMode) ?: Mode.RNE
private fun integerRange(word: String) = when (word) {
    "I8" -> Bounds(-128, 127)
    "U8" -> Bounds(0, 255)
    "I16" -> Bounds(-32768, 32767)
    "U16" -> Bounds(0, 65535)
    "I32" -> Bounds(-2147483648, 2147483647)
    "U32" -> Bounds(0, 4294967295)
    else -> fail("ERROR BAD TYPE $word")
}
private fun relation(a: Int, b: Int) = if (a < b) "LT" else if (a == b) "EQ" else "GT"

private fun summation(f: Format, words: List<String>): String {
    val command = words[0]
    val mode = parseMode(words[2])
    val values = mutableListOf<Int>()
    var leftCount = 0
    for (word in words.drop(3)) {
        if (word == "|") leftCount = values.size else values.add(f.operand(word))
    }
    if (command == "DOT" && leftCount != values.size - leftCount) fail("ERROR LENGTH MISMATCH")
    if (values.any { !f.finite(it) }) fail("ERROR NOT FINITE")
    val out = StringBuilder()
    if (command == "DOT") {
        val terms = List(leftCount) { i -> f.term(values[i]).product(f.term(values[leftCount + i])) }
        val exactSum = sumTerms(terms, mode)
        val first = f.arithmetic(Operation.MUL, values.first(), values[leftCount], 0, mode)
        var naive = first
        var chained = first
        for (i in 1 until leftCount) {
            val multiplied = f.arithmetic(Operation.MUL, values[i], values[leftCount + i], 0, mode)
            val added = f.arithmetic(Operation.ADD, naive.pattern, multiplied.pattern, 0, mode)
            naive = Rounded(added.pattern, naive.flags or multiplied.flags or added.flags)
        }
        for (i in 1 until leftCount) {
            val fused = f.arithmetic(Operation.FMA, values[i], values[leftCount + i], chained.pattern, mode)
            chained = Rounded(fused.pattern, chained.flags or fused.flags)
        }
        out.appendLine("DOT ${f.name} $mode n=$leftCount")
        out.appendLine("NAIVE ${f.result(naive)}")
        out.appendLine("CHAINED ${f.result(chained)}")
        out.appendLine("EXACT ${exactSum.decimal()}")
        out.appendLine("FUSED ${f.result(f.roundTerm(exactSum, mode))}")
        out.appendLine("DIFF naive=${f.difference(naive.pattern, exactSum)} chained=${f.difference(chained.pattern, exactSum)}")
        return out.toString()
    }
    val exactSum = sumTerms(values.map(f::term), mode)
    var result = Rounded(values.first())
    var compensation = 0
    out.appendLine("$command ${f.name} $mode count=${values.size}")
    for (i in 1 until values.size) {
        if (command == "SUM") {
            val next = f.arithmetic(Operation.ADD, result.pattern, values[i], 0, mode)
            result = Rounded(next.pattern, result.flags or next.flags)
            out.appendLine("PARTIAL ${i + 1} ${f.result(next)}")
        } else {
            val y = f.arithmetic(Operation.SUB, values[i], compensation, 0, mode)
            val t = f.arithmetic(Operation.ADD, result.pattern, y.pattern, 0, mode)
            val d = f.arithmetic(Operation.SUB, t.pattern, result.pattern, 0, mode)
            val c = f.arithmetic(Operation.SUB, d.pattern, y.pattern, 0, mode)
            val flags = y.flags or t.flags or d.flags or c.flags
            result = Rounded(t.pattern, result.flags or flags)
            compensation = c.pattern
            out.appendLine("KSTEP ${i + 1} sum=${f.value(result.pattern)} comp=${f.value(compensation)} ${flagText(flags)}")
        }
    }
    out.appendLine("RESULT ${f.result(result)}")
    out.appendLine("EXACT ${exactSum.decimal()}")
    out.appendLine("ROUNDED ${f.result(f.roundTerm(exactSum, mode))}")
    out.appendLine("DIFF ${f.difference(result.pattern, exactSum)}")
    return out.toString()
}

private fun table(f: Format): String {
    if (f.w > 8) fail("ERROR TABLE TOO LARGE")
    return buildString {
        appendLine("TABLE ${f.name} count=${f.infinity}")
        for (p in 0 until f.infinity) {
            val gap = if (p + 1 == f.infinity) "-" else sumTerms(listOf(f.term(p + 1), f.term(p).negated()), Mode.RNE).decimal()
            appendLine("ENTRY $p ${f.pattern(p)} gap=$gap")
        }
        appendLine("MAX ${f.pattern(f.infinity - 1)}")
        appendLine("MINNORMAL ${f.pattern(f.base)}")
        appendLine("MINSUBNORMAL ${f.pattern(1)}")
        appendLine("EPSILON ${Term(false, 1, -f.m).decimal()}")
        appendLine("PATTERNS finite=${2 * f.infinity} infinite=2 nan=${2 * (f.base - 1)} total=${2 * f.sign}")
    }
}

private class Laboratory {
    private val formats = mutableMapOf(
        "HALF" to Format("HALF", 5, 10), "E5M2" to Format("E5M2", 5, 2), "E4M3" to Format("E4M3", 4, 3)
    )
    private fun format(name: String) = formats[name] ?: fail("ERROR UNKNOWN FORMAT $name")

    fun execute(words: List<String>): String {
        val command = words[0]
        if (command == "FORMAT") {
            if (words[1] in formats) fail("ERROR FORMAT EXISTS ${words[1]}")
            val e = words[2].toInt()
            val m = words[3].toInt()
            if (e !in 2..5 || m !in 1..10) fail("ERROR BAD FORMAT")
            val f = Format(words[1], e, m)
            formats[f.name] = f
            return "FORMAT ${f.name} e=$e m=$m bits=${f.w} bias=${f.bias} emin=${f.emin} emax=${f.emax}\n"
        }
        val f = format(words[1])
        if (command == "TABLE") return table(f)
        if (command in listOf("SUM", "KAHAN", "DOT")) return summation(f, words)
        if (command == "CONVERT") {
            val g = format(words[2])
            val a = f.operand(words[3])
            val mode = modeAt(words, 4)
            val result = when (f.kind(a)) {
                Kind.QNAN -> Rounded(g.nan)
                Kind.SNAN -> Rounded(g.nan, INVALID)
                Kind.INFINITY -> Rounded(g.signed(g.infinity, f.negative(a)))
                Kind.ZERO -> Rounded(g.signed(0, f.negative(a)))
                else -> g.roundTerm(f.term(a), mode)
            }
            return "CONVERT ${f.name} ${g.name} $mode ${g.result(result)}\n"
        }
        if (command == "ENCODE") {
            val value = f.rawOperand(words[2], true)
            val mode = modeAt(words, 3)
            val result = value.number?.let { f.round(it, mode) } ?: Rounded(value.pattern)
            val source = value.number?.fraction() ?: f.value(value.pattern)
            return "ENCODE ${f.name} $mode $source ${f.result(result)}\n"
        }
        val a = f.operand(words[2])
        val out = StringBuilder()
        when (command) {
            "DECODE" -> {
                val kind = f.kind(a)
                val exponent = (a and (f.sign - 1)) shr f.m
                val fraction = a and (f.base - 1)
                out.appendLine("DECODE ${f.name} ${f.bits(a)} ${f.hex(a)} $kind sign=${if (f.negative(a)) 1 else 0}")
                if (f.finite(a)) {
                    val term = f.term(a)
                    out.appendLine("FIELDS exponent=$exponent fraction=$fraction unbiased=${term.exponent + f.m} significand=${if (kind == Kind.NORMAL) 1 else 0}.${binary(fraction, f.m)}")
                    out.appendLine("VALUE ${term.exact().fraction()} ${f.value(a)}")
                } else if (kind == Kind.INFINITY) out.appendLine("FIELDS exponent=$exponent fraction=$fraction")
                else out.appendLine("FIELDS exponent=$exponent fraction=$fraction payload=${fraction % (f.base / 2)}")
            }
            "COMPARE" -> {
                val b = f.operand(words[3])
                val ak = f.orderKey(a)
                val bk = f.orderKey(b)
                val numeric = when {
                    f.isNaN(a) || f.isNaN(b) -> "UN"
                    f.zero(a) && f.zero(b) -> "EQ"
                    else -> relation(ak, bk)
                }
                val flags = if (f.kind(a) == Kind.SNAN || f.kind(b) == Kind.SNAN) INVALID else 0
                out.appendLine("COMPARE ${f.name} ${f.hex(a)} ${f.hex(b)} $numeric total=${relation(ak, bk)} ${flagText(flags)}")
            }
            "TOINT" -> {
                val bounds = integerRange(words[3])
                val mode = modeAt(words, 4)
                val prefix = "TOINT ${f.name} ${words[3]} $mode"
                if (!f.finite(a)) out.appendLine("$prefix invalid flags=invalid")
                else {
                    val value = f.term(a).exact()
                    val divided = Quantized.of(value, 0, false)
                    val magnitude = divided.rounded(mode, value.negative)
                    val result = if (value.negative) -magnitude else magnitude
                    if (result < bounds.minimum || result > bounds.maximum) out.appendLine("$prefix invalid flags=invalid")
                    else out.appendLine("$prefix $result ${flagText(if (divided.inexact) INEXACT else 0)}")
                }
            }
            "NEXTUP", "NEXTDOWN", "ULP" -> {
                val result = if (f.isNaN(a)) Rounded(f.nan, if (f.kind(a) == Kind.SNAN) INVALID else 0)
                else Rounded(when (command) {
                    "NEXTUP" -> f.nextUp(a)
                    "NEXTDOWN" -> f.nextUp(a xor f.sign) xor f.sign
                    else -> if (f.kind(a) == Kind.INFINITY) f.infinity
                        else f.roundTerm(Term(false, 1, f.term(a).exponent), Mode.RNE).pattern
                })
                out.appendLine("$command ${f.name} ${f.result(result)}")
            }
            else -> {
                val operation = Operation.valueOf(command)
                val arity = when (operation) { Operation.SQRT -> 1; Operation.FMA -> 3; else -> 2 }
                val b = if (arity >= 2) f.operand(words[3]) else 0
                val c = if (arity == 3) f.operand(words[4]) else 0
                val mode = modeAt(words, arity + 2)
                out.appendLine("$command ${f.name} $mode ${f.result(f.arithmetic(operation, a, b, c, mode))}")
            }
        }
        return out.toString()
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val count = input.readLine().toInt()
    val laboratory = Laboratory()
    repeat(count) {
        val response = try { laboratory.execute(input.readLine().split(' ')) }
            catch (error: CommandError) { "${error.message}\n" }
        output.write(response)
    }
    output.flush()
}
