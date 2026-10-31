import kotlin.math.abs
class F(numerator: Long, denominator: Long = 1) : Comparable<F> {
    val n: Long
    val d: Long
    init {
        require(denominator != 0L); var a = abs(numerator); var b = abs(denominator); while (b != 0L) {
            val r = a % b; a = b; b = r
        }; val gcd = maxOf(1L, a); n = numerator / gcd * if (denominator < 0) -1 else 1; d = abs(denominator) / gcd
    }
    constructor(value: Int) : this(value.toLong())
    operator fun plus(other: F): F = F(n * other.d + other.n * d, d * other.d)
    operator fun minus(other: F): F = F(n * other.d - other.n * d, d * other.d)
    operator fun times(other: F): F = F(n * other.n, d * other.d)
    operator fun div(other: F): F = F(n * other.d, d * other.n)
    operator fun unaryMinus(): F = F(-n, d)
    override fun compareTo(other: F): Int = (n * other.d).compareTo(other.n * d)
    override fun equals(other: Any?): Boolean = other is F && n == other.n && d == other.d
    override fun hashCode(): Int = 31 * n.hashCode() + d.hashCode()
    override fun toString(): String = if (d == 1L) "$n" else "$n/$d"
    val absolute: F get() = F(abs(n), d)
    fun floor(): Long = Math.floorDiv(n, d)
    fun ceil(): Long = -Math.floorDiv(-n, d)
    val approximate: String get() {
        val scaled = (absolute * F(1000000) + F(1, 2)).floor(); return (if (n < 0 && scaled > 0) "-" else "") + (scaled / 1000000).toString() + "." + (scaled % 1000000).toString().padStart(6, '0')
    }
    companion object {
        fun read(word: String, signed: Boolean = false): F? {
            if (!word.matches(Regex(if (signed) "-?[0-9]+(?:\\.[0-9]+|/[0-9]+)?" else "[0-9]+(?:\\.[0-9]+|/[0-9]+)?"))) return null
            val sign = if (word.startsWith("-")) -1L else 1L
            val value = word.removePrefix("-")
            if ('/' in value) {
                val parts = value.split('/'); val denominator = parts[1].toLong(); return if (denominator == 0L) null else F(sign * parts[0].toLong(), denominator)
            }
            if ('.' in value) {
                val parts = value.split('.'); return F(sign * (parts[0] + parts[1]).toLong(), (1..parts[1].length).fold(1L) {
                    a, _ -> a * 10
                })
            }
            return F(sign * value.toLong())
        }
    }
}
fun Iterable<F>.sumF(): F = fold(F(0)) {
    a, b -> a + b
}
