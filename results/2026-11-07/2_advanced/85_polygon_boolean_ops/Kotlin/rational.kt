import java.math.BigInteger
import java.util.Locale
typealias BI = BigInteger
val ZERO: BI = BI.ZERO
val ONE: BI = BI.ONE
fun bi(n: Long): BI = BI.valueOf(n)
fun bi(n: Int): BI = bi(n.toLong())
class Fraction(numerator: BI, denominator: BI = ONE) : Comparable<Fraction> {
    val n: BI
    val d: BI
    init {
        val g = numerator.gcd(denominator)
        val s = bi(denominator.signum())
        n = numerator / g * s
        d = denominator / g * s
    }
    override fun compareTo(other: Fraction): Int = (n * other.d).compareTo(other.n * d)
    override fun toString(): String = if (d == ONE) "$n" else "$n/$d"
}
class Point(x: BI, y: BI, d: BI = ONE) : Comparable<Point> {
    val x: BI
    val y: BI
    val d: BI
    init {
        val g = x.gcd(y).gcd(d)
        val s = bi(d.signum())
        this.x = x / g * s
        this.y = y / g * s
        this.d = d / g * s
    }
    constructor(x: Long, y: Long) : this(bi(x), bi(y))
    override fun compareTo(other: Point): Int {
        val yOrder = (y * other.d).compareTo(other.y * d)
        return if (yOrder != 0) yOrder else (x * other.d).compareTo(other.x * d)
    }
    override fun equals(other: Any?): Boolean = other is Point && x == other.x && y == other.y && d == other.d
    override fun hashCode(): Int = (31 * x.hashCode() + y.hashCode()) * 31 + d.hashCode()
    override fun toString(): String = "(${Fraction(x, d)},${Fraction(y, d)})"
    fun real(): Pair<Double, Double> = Pair(x.toDouble() / d.toDouble(), y.toDouble() / d.toDouble())
    fun snapped(): Point {
        fun rounded(v: BI): BI {
            val a = bi(2) * v + d
            val b = bi(2) * d
            val q = a / b
            return if (a % b < ZERO) q - ONE else q
        }
        return Point(rounded(x), rounded(y))
    }
}
fun cross(a: Point, b: Point, c: Point): BI =
(b.x * c.y - b.y * c.x) * a.d + (c.x * a.y - c.y * a.x) * b.d + (a.x * b.y - a.y * b.x) * c.d
fun xCompare(a: Point, b: Point): Int = (a.x * b.d).compareTo(b.x * a.d)
fun yCompare(a: Point, b: Point): Int = (a.y * b.d).compareTo(b.y * a.d)
fun realText(value: Double, digits: Int = 3): String = String.format(Locale.ROOT, "%.${digits}f", value)
