import java.util.TreeMap
import kotlin.math.abs

enum class Command(val types: String, val minimum: Int, val maximum: Int = minimum) {
    GEN("NV", 2, 25), PCHECK("NV", 2, 25), HAMMING("NI", 2), SIMPLEX("NI", 2),
    REPETITION("NI", 2), PARITY("NI", 2), RM("NII", 3), CYCLIC("NIV", 3),
    DUAL("NA", 2), EXTEND("NA", 2), PUNCTURE("NAI", 3), SHORTEN("NAI", 3),
    AUGMENT("NA", 2), EXPURGATE("NA", 2), PERMUTE("NAI", 3, 26),
    DIRECTSUM("NAB", 3), UUV("NAB", 3), PRODUCT("NAB", 3),
    LIST("", 0), DELETE("A", 1), SHOW("A", 1), INFO("A", 1), SYSTEMATIC("A", 1),
    WEIGHTS("A", 1), COVERING("A", 1), BURST("A", 1), TRELLIS("A", 1), STDARRAY("A", 1),
    EQUAL("AB", 2), ENCODE("AV", 2), SYNDROME("AV", 2), DECODE("AV", 2),
    BOUNDED("AIV", 3), COSET("AV", 2), ERASURE("AX", 2), INTERLEAVE("AIIV", 4, 11),
    CRC("VV", 2), CRCCHECK("VV", 2), FACTOR("I", 1), MACWILLIAMS("II", 2, 26), BOUNDS("II", 2);

    val defining get() = ordinal <= PRODUCT.ordinal
}

class CommandError(message: String) : RuntimeException(message)
data class Division(val quotient: Int, val remainder: Int)
data class Echelon(val rows: List<Int>, val columns: List<Int>)
data class Decoded(val word: Int, val message: Int, val error: Int)

fun ensure(condition: Boolean, message: String) {
    if (!condition) throw CommandError(message)
}

fun letter(c: Char) = c in 'A'..'Z' || c in 'a'..'z'
fun digit(c: Char) = c in '0'..'9'
fun validWord(text: String, kind: Char): Boolean {
    if (text.isEmpty()) return false
    return when (kind) {
        'N', 'A', 'B' -> text.length <= 8 && letter(text[0]) && text.all { letter(it) || digit(it) }
        'I' -> text.length <= 4 && (text.length == 1 || text[0] != '0') && text.all(::digit)
        else -> text.length <= 30 && text.all { it == '0' || it == '1' || kind == 'X' && it == '?' }
    }
}

fun mask(n: Int) = (1 shl n) - 1
fun bit(n: Int, column: Int) = 1 shl (n - column - 1)
fun weight(value: Int) = Integer.bitCount(value)
fun length(value: Int) = 32 - Integer.numberOfLeadingZeros(value)
fun bits(value: Int, n: Int) = value.toString(2).padStart(n, '0')
fun yes(value: Boolean) = if (value) "yes" else "no"
fun StringBuilder.line(text: String) { append(text).append('\n') }

fun divide(original: Int, divisor: Int): Division {
    var value = original
    var quotient = 0
    while (value != 0 && length(value) >= length(divisor)) {
        val shift = length(value) - length(divisor)
        quotient = quotient xor (1 shl shift)
        value = value xor (divisor shl shift)
    }
    return Division(quotient, value)
}

fun basis(rows: List<Int>, n: Int): List<Int> {
    val pivots = IntArray(32)
    val result = mutableListOf<Int>()
    for (original in rows) {
        var row = original
        for (column in n - 1 downTo 0) {
            if ((row and (1 shl column)) == 0) continue
            if (pivots[column] != 0) row = row xor pivots[column]
            else { pivots[column] = row; result.add(original); break }
        }
    }
    return result
}

fun rref(source: List<Int>, n: Int): Echelon {
    val rows = source.toMutableList()
    val columns = mutableListOf<Int>()
    for (column in 0 until n) {
        val rank = columns.size
        val found = (rank until rows.size).firstOrNull { (rows[it] and bit(n, column)) != 0 } ?: continue
        val temporary = rows[rank]; rows[rank] = rows[found]; rows[found] = temporary
        for (i in rows.indices)
            if (i != rank && (rows[i] and bit(n, column)) != 0) rows[i] = rows[i] xor rows[rank]
        columns.add(column)
    }
    return Echelon(rows.take(columns.size), columns)
}

fun nullSpace(source: List<Int>, n: Int): List<Int> {
    val reduced = rref(source, n)
    return (0 until n).filter { it !in reduced.columns }.map { column ->
        var row = bit(n, column)
        for (i in reduced.rows.indices)
            if ((reduced.rows[i] and bit(n, column)) != 0) row = row or bit(n, reduced.columns[i])
        row
    }
}

fun span(rows: List<Int>): List<Int> {
    val words = mutableListOf(0)
    for (row in rows) {
        val count = words.size
        for (i in 0 until count) words.add(words[i] xor row)
    }
    return words
}

fun reedMuller(r: Int, m: Int): List<Int> {
    if (r == 0) return listOf(mask(1 shl m))
    val half = 1 shl (m - 1)
    return reedMuller(minOf(r, m - 1), m - 1).map { (it shl half) or it } + reedMuller(r - 1, m - 1)
}

fun checkDimension(n: Int, k: Int) {
    ensure(k in 1..12 && n - k in 1..12, "bad dimension $n $k")
}

class Code(val n: Int, generator: List<Int>, check: List<Int>? = null, val polynomial: Int? = null) {
    val g: List<Int>
    val h: List<Int>
    val k get() = g.size
    val encoder get() = if (polynomial == null) "matrix" else "polynomial"

    init {
        checkDimension(n, generator.size)
        g = generator.toList()
        h = (check ?: nullSpace(g, n)).toList()
    }

    fun encode(message: Int): Int {
        if (polynomial != null) {
            val shifted = message shl h.size
            return shifted or divide(shifted, polynomial).remainder
        }
        var word = 0
        for (i in g.indices) if ((message and bit(k, i)) != 0) word = word xor g[i]
        return word
    }

    fun syndrome(word: Int): Int {
        var result = 0
        for (row in h) result = (result shl 1) or (weight(row and word) and 1)
        return result
    }

    fun messageFor(word: Int): Int = (0 until (1 shl k)).first { encode(it) == word }

    fun leaders(): IntArray {
        val result = IntArray(1 shl h.size) { -1 }
        result[0] = 0
        var found = 1
        for (w in 1..n) {
            var word = mask(w)
            while (word < (1 shl n)) {
                val syndrome = syndrome(word)
                if (result[syndrome] == -1) {
                    result[syndrome] = word
                    if (++found == result.size) return result
                }
                val lowest = word and -word
                val next = word + lowest
                word = next or (((next xor word) shr 2) / lowest)
            }
        }
        return result
    }

    fun decode(received: Int, leaders: IntArray): Decoded {
        val error = leaders[syndrome(received)]
        val word = received xor error
        return Decoded(word, messageFor(word), error)
    }

    fun decodedText(decoded: Decoded) = "codeword ${bits(decoded.word, n)} message ${bits(decoded.message, k)} " +
        "error ${bits(decoded.error, n)} weight ${weight(decoded.error)}"

    fun burstCorrection(): Int {
        val seen = BooleanArray(1 shl h.size)
        seen[0] = true
        for (size in 1..n) {
            val variants = if (size == 1) 1 else 1 shl (size - 2)
            for (offset in 0..n - size) for (middle in 0 until variants) {
                val word = if (size == 1) 1 else (1 shl (size - 1)) or (middle shl 1) or 1
                val syndrome = syndrome(word shl offset)
                if (seen[syndrome]) return size - 1
                seen[syndrome] = true
            }
        }
        error("No colliding burst")
    }
}

fun construct(command: Command, args: List<String>, a: Code?, b: Code?): Code = when (command) {
    Command.GEN, Command.PCHECK -> {
        val n = args[1].length
        ensure(args.drop(1).all { it.length == n }, "bad length")
        val rows = basis(args.drop(1).map { it.toInt(2) }, n)
        if (command == Command.GEN) Code(n, rows) else Code(n, nullSpace(rows, n), rows)
    }
    Command.HAMMING, Command.SIMPLEX -> {
        val r = args[1].toInt()
        ensure(r in 2..4, "bad parameter")
        val n = (1 shl r) - 1
        val rows = (0 until r).map { i ->
            var row = 0
            for (j in 1..n) row = (row shl 1) or ((j shr (r - i - 1)) and 1)
            row
        }
        if (command == Command.SIMPLEX) Code(n, rows) else Code(n, nullSpace(rows, n), rows)
    }
    Command.REPETITION, Command.PARITY -> {
        val n = args[1].toInt()
        ensure(n in 2..24, "bad parameter")
        Code(n, if (command == Command.REPETITION) listOf(mask(n)) else (0 until n - 1).map { bit(n, it) or 1 })
    }
    Command.RM -> {
        val r = args[1].toInt(); val m = args[2].toInt()
        ensure(m in 1..4 && r <= m, "bad parameter")
        Code(1 shl m, reedMuller(r, m))
    }
    Command.CYCLIC -> {
        val n = args[1].toInt(); val d = args[2].length - 1
        ensure(n in 2..24 && args[2][0] == '1' && d in 1 until n, "bad parameter")
        val divisor = args[2].toInt(2)
        ensure(divide((1 shl n) or 1, divisor).remainder == 0, "not a divisor")
        val k = n - d
        val rows = (0 until k).map { divisor shl (k - it - 1) }
        val checks = IntArray(d)
        for (j in 0 until n) {
            val remainder = divide(bit(n, j), divisor).remainder
            for (i in 0 until d) checks[i] = (checks[i] shl 1) or ((remainder shr (d - i - 1)) and 1)
        }
        Code(n, rows, checks.toList(), divisor)
    }
    Command.DUAL -> Code(a!!.n, a.h, a.g)
    Command.EXTEND -> Code(a!!.n + 1, a.g.map { (it shl 1) or (weight(it) and 1) })
    Command.PUNCTURE, Command.SHORTEN, Command.EXPURGATE -> {
        val source = a!!
        val expurgating = command == Command.EXPURGATE
        val position = if (expurgating) 0 else args[2].toInt()
        if (!expurgating) ensure(position in 1..source.n, "bad position")
        val n = source.n - if (expurgating) 0 else 1
        fun selected(row: Int) = if (expurgating) (weight(row) and 1) != 0 else (row and bit(source.n, position - 1)) != 0
        val removed = if (command == Command.PUNCTURE) -1 else source.g.indexOfFirst(::selected)
        val rows = mutableListOf<Int>()
        for (i in source.g.indices) {
            if (i == removed) continue
            var row = source.g[i]
            if (removed >= 0 && selected(row)) row = row xor source.g[removed]
            if (!expurgating) {
                val low = source.n - position
                row = ((row shr (low + 1)) shl low) or (row and mask(low))
            }
            rows.add(row)
        }
        Code(n, if (command == Command.PUNCTURE) basis(rows, n) else rows)
    }
    Command.AUGMENT -> Code(a!!.n, basis(a.g + mask(a.n), a.n))
    Command.PERMUTE -> {
        val source = a!!
        val positions = args.drop(2).map(String::toInt)
        ensure(positions.size == source.n && positions.sorted() == (1..source.n).toList(), "bad permutation")
        Code(source.n, source.g.map { original ->
            var row = 0
            for (position in positions) row = (row shl 1) or if ((original and bit(source.n, position - 1)) != 0) 1 else 0
            row
        })
    }
    Command.DIRECTSUM, Command.UUV, Command.PRODUCT -> {
        val left = a!!; val right = b!!
        if (command == Command.UUV) ensure(left.n == right.n, "bad length")
        val product = command == Command.PRODUCT
        val n = if (product) left.n * right.n else left.n + right.n
        checkDimension(n, if (product) left.k * right.k else left.k + right.k)
        val rows = if (product) left.g.flatMap { x -> right.g.map { y ->
            var row = 0
            for (i in 0 until left.n) row = (row shl right.n) or if ((x and bit(left.n, i)) != 0) y else 0
            row
        } } else left.g.map { (it shl right.n) or if (command == Command.UUV) it else 0 } + right.g
        Code(n, rows)
    }
    else -> error("Not a defining command")
}

fun distribution(words: List<Int>, offset: Int, n: Int): IntArray {
    val counts = IntArray(n + 1)
    for (word in words) ++counts[weight(word xor offset)]
    return counts
}

fun weightList(counts: IntArray) = counts.indices.filter { counts[it] != 0 }.joinToString(" ") { "$it:${counts[it]}" }
fun gcd(first: Long, second: Long): Long {
    var a = abs(first); var b = second
    while (b != 0L) { val remainder = a % b; a = b; b = remainder }
    return a
}

val combinations = Array(25) { LongArray(25) }.also { table ->
    for (n in 0..24) {
        table[n][0] = 1; table[n][n] = 1
        for (k in 1 until n) table[n][k] = table[n - 1][k - 1] + table[n - 1][k]
    }
}
fun choose(n: Int, k: Int) = if (k < 0 || k > n) 0L else combinations[n][k]
fun volume(n: Int, radius: Int) = (0..radius).sumOf { choose(n, it) }
fun krawtchouk(n: Int, j: Int, x: Int): Long = (0..j).sumOf { y ->
    val term = choose(x, y) * choose(n - x, j - y)
    if (y % 2 == 0) term else -term
}
fun StringBuilder.matrixText(label: String, rows: List<Int>, n: Int) {
    for (row in rows) line("$label ${bits(row, n)}")
}

fun systematic(name: String, code: Code): String {
    val rows = code.g.toMutableList()
    val permutation = IntArray(code.n) { it + 1 }
    for (r in 0 until code.k) {
        var column = r
        var found: Int
        while (true) {
            found = (r until rows.size).firstOrNull { (rows[it] and bit(code.n, column)) != 0 } ?: rows.size
            if (found < rows.size) break
            ++column
        }
        if (column != r) {
            val left = bit(code.n, r); val right = bit(code.n, column)
            for (i in rows.indices)
                if (((rows[i] and left) != 0) != ((rows[i] and right) != 0)) rows[i] = rows[i] xor left xor right
            val temporary = permutation[r]; permutation[r] = permutation[column]; permutation[column] = temporary
        }
        val temporary = rows[r]; rows[r] = rows[found]; rows[found] = temporary
        for (i in rows.indices)
            if (i != r && (rows[i] and bit(code.n, r)) != 0) rows[i] = rows[i] xor rows[r]
    }
    return buildString {
        line("systematic $name perm ${permutation.joinToString(" ")}")
        matrixText("G", rows, code.n)
        for (j in code.h.indices) {
            var row = 0
            for (value in rows) row = (row shl 1) or if ((value and bit(code.n, code.k + j)) != 0) 1 else 0
            line("H ${bits((row shl code.h.size) or bit(code.h.size, j), code.n)}")
        }
    }
}

fun independent(command: Command, args: List<String>): String {
    if (command == Command.CRC || command == Command.CRCCHECK) {
        val d = args[0].length - 1
        ensure(args[0][0] == '1' && d in 1..16, "bad parameter")
        if (command == Command.CRC) ensure(args[1].length + d <= 30, "bad length")
        val value = args[1].toInt(2) shl if (command == Command.CRC) d else 0
        val remainder = divide(value, args[0].toInt(2)).remainder
        val suffix = bits(remainder, d)
        return if (command == Command.CRC) "crc remainder $suffix frame ${args[1]}$suffix\n"
            else "crccheck ${if (remainder == 0) "ok" else "error"} remainder $suffix\n"
    }
    val n = args[0].toInt()
    if (command == Command.BOUNDS) {
        val d = args[1].toInt()
        ensure(d >= 1 && d <= n && n <= 24, "bad parameter")
        val ball = volume(n, (d - 1) / 2)
        val hamming = (0..n).last { (1L shl it) * ball <= (1L shl n) }
        var sum = 0L; var griesmer = 0
        for (k in 1..n) {
            val denominator = 1L shl (k - 1)
            sum += (d + denominator - 1) / denominator
            if (sum <= n) griesmer = k
        }
        return "bounds n $n d $d singleton ${n - d + 1} hamming $hamming griesmer $griesmer\n"
    }
    ensure(n in 1..24, "bad parameter")
    if (command == Command.FACTOR) return buildString {
        var remaining = (1 shl n) or 1
        var divisors = 1; var factor = 3
        append("factor $n")
        while (2 * (length(factor) - 1) <= length(remaining) - 1) {
            var exponent = 0
            while (true) {
                val result = divide(remaining, factor)
                if (result.remainder != 0) break
                remaining = result.quotient; ++exponent
            }
            if (exponent != 0) { append(" ${bits(factor, length(factor))}^$exponent"); divisors *= exponent + 1 }
            factor += 2
        }
        if (remaining != 1) { append(" ${bits(remaining, length(remaining))}^1"); divisors *= 2 }
        line(" divisors $divisors")
    }
    ensure(args.size == n + 2, "bad length")
    ensure(args[1].toInt() == 1, "bad parameter")
    val coefficients = args.drop(1).map(String::toLong)
    val size = coefficients.sum()
    var feasible = (size and (size - 1)) == 0L
    return buildString {
        line("macwilliams n $n size $size")
        append("dual")
        for (j in 0..n) {
            var numerator = 0L
            for (x in 0..n) numerator += coefficients[x] * krawtchouk(n, j, x)
            if (numerator < 0 || numerator % size != 0L) feasible = false
            val divisor = gcd(numerator, size)
            val denominator = size / divisor
            append(' ').append(numerator / divisor)
            if (denominator != 1L) append('/').append(denominator)
        }
        append('\n'); line("feasible ${yes(feasible)}")
    }
}

class Laboratory {
    private val codes = TreeMap<String, Code>()
    private val commands = Command.entries.associateBy { it.name }

    fun process(input: String): String {
        val words = input.split(' ')
        val command = commands[words[0]] ?: throw CommandError("unknown command ${words[0]}")
        val args = words.drop(1)
        ensure(args.size in command.minimum..command.maximum, "bad arguments")
        for (i in args.indices) ensure(validWord(args[i], command.types[minOf(i, command.types.lastIndex)]), "bad arguments")
        var a: Code? = null; var b: Code? = null
        for (i in command.types.indices) {
            val kind = command.types[i]
            if (kind != 'A' && kind != 'B') continue
            val code = codes[args[i]] ?: throw CommandError("no code ${args[i]}")
            if (kind == 'A') a = code else b = code
        }
        if (command.defining) {
            val code = construct(command, args, a, b)
            val status = if (codes.containsKey(args[0])) "redefined" else "defined"
            codes[args[0]] = code
            return "$status ${args[0]} n ${code.n} k ${code.k}\n"
        }
        if (command in listOf(Command.CRC, Command.CRCCHECK, Command.FACTOR, Command.MACWILLIAMS, Command.BOUNDS))
            return independent(command, args)
        if (command == Command.LIST) return buildString {
            line("codes ${codes.size}")
            for ((name, code) in codes) line("$name n ${code.n} k ${code.k} encoder ${code.encoder}")
        }
        val name = args[0]
        if (command == Command.DELETE) { codes.remove(name); return "deleted $name\n" }
        val code = a!!
        val n = code.n; val k = code.k
        return buildString {
            when (command) {
                Command.SHOW -> {
                    line("code $name n $n k $k encoder ${code.encoder}")
                    if (code.polynomial != null) line("poly g ${bits(code.polynomial, n - k + 1)} h ${bits(divide((1 shl n) or 1, code.polynomial).quotient, k + 1)}")
                    matrixText("G", code.g, n); matrixText("H", code.h, n)
                }
                Command.INFO -> {
                    val nonzero = span(code.g).drop(1)
                    val distance = nonzero.minOf(::weight)
                    val generator = nonzero.min()
                    val t = (distance - 1) / 2; val divisor = gcd(k.toLong(), n.toLong())
                    val cyclic = code.g.all { code.syndrome(((it shl 1) and mask(n)) or (it shr (n - 1))) == 0 }
                    line("info $name n $n k $k rate ${k / divisor}/${n / divisor} d $distance t $t " +
                        "perfect ${yes(volume(n, t) == (1L shl (n - k)))} mds ${yes(distance == n - k + 1)} " +
                        "cyclic ${if (cyclic) bits(generator, length(generator)) else "no"}")
                }
                Command.SYSTEMATIC -> append(systematic(name, code))
                Command.WEIGHTS -> {
                    val primary = distribution(span(code.g), 0, n); val dual = distribution(span(code.h), 0, n)
                    val orthogonal = code.g.all { x -> code.g.all { y -> (weight(x and y) and 1) == 0 } }
                    line("weights $name ${weightList(primary)}"); line("dual $name ${weightList(dual)}")
                    line("duality $name self-orthogonal ${yes(orthogonal)} self-dual ${yes(orthogonal && n == 2 * k)} " +
                        "formally-self-dual ${yes(primary.contentEquals(dual))}")
                }
                Command.COVERING -> {
                    val counts = distribution(code.leaders().toList(), 0, n)
                    val radius = counts.indexOfLast { it != 0 }
                    append("covering $name radius $radius leaders")
                    for (i in 0..radius) append(" $i:${counts[i]}")
                    append('\n')
                }
                Command.BURST -> {
                    val detect = span(code.g).drop(1).minOf { length(it) - Integer.numberOfTrailingZeros(it) - 1 }
                    line("burst $name detect $detect correct ${code.burstCorrection()}")
                }
                Command.TRELLIS -> {
                    val profile = (0..n).map { cut ->
                        basis(code.g.map { it shr (n - cut) }, cut).size +
                            basis(code.g.map { it and mask(n - cut) }, n - cut).size - k
                    }
                    line("trellis $name profile ${profile.joinToString(" ")} max ${profile.max()}")
                }
                Command.STDARRAY -> {
                    ensure(n - k <= 6 && k <= 4, "too large")
                    val leaders = code.leaders()
                    val syndromes = leaders.indices.sortedWith(compareBy<Int> { weight(leaders[it]) }.thenBy { leaders[it] })
                    val codewords = span(code.g).sorted()
                    line("stdarray $name rows ${leaders.size} columns ${codewords.size}")
                    for (s in syndromes) {
                        append(bits(s, n - k)).append(':')
                        for (word in codewords) append(' ').append(bits(leaders[s] xor word, n))
                        append('\n')
                    }
                }
                Command.EQUAL -> {
                    val other = b!!
                    if (n != other.n) line("equal $name ${args[1]} no lengths $n ${other.n}")
                    else {
                        val common = k + other.k - basis(code.g + other.g, n).size
                        line("equal $name ${args[1]} ${yes(k == common && other.k == common)} intersection $common")
                    }
                }
                Command.ENCODE -> {
                    ensure(args[1].length == k, "bad length")
                    line("encode $name message ${args[1]} codeword ${bits(code.encode(args[1].toInt(2)), n)}")
                }
                Command.SYNDROME, Command.DECODE, Command.BOUNDED, Command.COSET -> {
                    val text = args[if (command == Command.BOUNDED) 2 else 1]
                    ensure(text.length == n, "bad length")
                    val word = text.toInt(2); val syndrome = code.syndrome(word)
                    if (command == Command.SYNDROME) line("syndrome $name ${bits(syndrome, n - k)} codeword ${yes(syndrome == 0)}")
                    else {
                        val decoded = code.decode(word, code.leaders())
                        if (command == Command.COSET) line("coset $name syndrome ${bits(syndrome, n - k)} " +
                            "leader ${bits(decoded.error, n)} weights ${weightList(distribution(span(code.g), word, n))}")
                        else if (command == Command.BOUNDED && weight(decoded.error) > args[1].toInt())
                            line("bounded $name fail weight ${weight(decoded.error)}")
                        else line("${if (command == Command.BOUNDED) "bounded" else "decode"} $name ${code.decodedText(decoded)}")
                    }
                }
                Command.ERASURE -> {
                    ensure(args[1].length == n, "bad length")
                    var known = 0; var value = 0; var erased = 0
                    for (i in 0 until n) {
                        val c = args[1][i]
                        if (c == '?') ++erased else { known = known or bit(n, i); if (c == '1') value = value or bit(n, i) }
                    }
                    val candidates = span(code.g).filter { (it and known) == value }
                    append("erasure $name erased $erased candidates ${candidates.size}")
                    if (candidates.size == 1) append(" codeword ${bits(candidates[0], n)} message ${bits(code.messageFor(candidates[0]), k)}")
                    append('\n')
                }
                Command.INTERLEAVE -> {
                    val depth = args.size - 3; val start = args[1].toInt(); val size = args[2].toInt()
                    ensure(args.drop(3).all { it.length == k }, "bad length")
                    ensure(start >= 1 && size >= 1 && start + size - 1 <= depth * n, "bad burst")
                    val sentRows = IntArray(depth) { code.encode(args[it + 3].toInt(2)) }
                    val receivedRows = IntArray(depth)
                    val sent = StringBuilder(); val received = StringBuilder()
                    for (column in 0 until n) for (i in 0 until depth) {
                        val position = column * depth + i + 1
                        var value = (sentRows[i] and bit(n, column)) != 0
                        sent.append(if (value) '1' else '0')
                        if (position >= start && position < start + size) value = !value
                        received.append(if (value) '1' else '0')
                        receivedRows[i] = (receivedRows[i] shl 1) or if (value) 1 else 0
                    }
                    line("interleave $name depth $depth burst $start $size"); line("sent $sent"); line("recv $received")
                    val leaders = code.leaders()
                    var correct = 0
                    for (i in 0 until depth) {
                        val decoded = code.decode(receivedRows[i], leaders)
                        val ok = decoded.message == args[i + 3].toInt(2)
                        if (ok) ++correct
                        line("row ${i + 1} errors ${weight(receivedRows[i] xor sentRows[i])} corrected ${weight(decoded.error)} " +
                            "message ${bits(decoded.message, k)} ${if (ok) "ok" else "wrong"}")
                    }
                    line("result ok $correct wrong ${depth - correct}")
                }
                else -> error("Unhandled command")
            }
        }
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val laboratory = Laboratory()
    repeat(input.readLine().toInt()) {
        try { output.write(laboratory.process(input.readLine())) }
        catch (error: CommandError) { output.write("error: ${error.message}\n") }
    }
    output.flush()
}
