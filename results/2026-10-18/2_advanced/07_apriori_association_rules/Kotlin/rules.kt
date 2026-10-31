import kotlin.math.abs

data class Fraction private constructor(val numerator: Long, val denominator: Long, private val normalized: Boolean) : Comparable<Fraction> {
    constructor(numerator: Long, denominator: Long = 1L) : this(numerator / gcd(abs(numerator), denominator), denominator / gcd(abs(numerator), denominator), true)
    constructor(numerator: Int, denominator: Int = 1) : this(numerator.toLong(), denominator.toLong())
    override fun compareTo(other: Fraction) = (numerator * other.denominator).compareTo(other.numerator * denominator)
    operator fun minus(other: Fraction) = Fraction(numerator * other.denominator - other.numerator * denominator, denominator * other.denominator)
    operator fun unaryMinus() = Fraction(-numerator, denominator)
    companion object { fun gcd(first: Long, second: Long): Long { var a = first; var b = second; while (b != 0L) { val remainder = a % b; a = b; b = remainder }; return a } }
}
class Rule(val items: List<String>, val antecedent: List<String>, val consequent: List<String>, val count: Int, total: Int, first: Int, second: Int) {
    val support = Fraction(count, total)
    val confidence = Fraction(count, first)
    val lift = liftOf(total, count, first, second)
    val leverage = Fraction(total.toLong() * count - first.toLong() * second, total.toLong() * total)
    val conviction = if (first == count) null else Fraction((total - second).toLong() * first, total.toLong() * (first - count))
    var improvement = Fraction(0)
    var rank = 0
}
data class RuleSet(val generated: Int, val rules: List<Rule>) { val productive get() = rules.count { it.improvement > Fraction(0) } }
fun liftOf(total: Int, together: Int, first: Int, second: Int) = Fraction(total.toLong() * together, first.toLong() * second)
fun meets(confidence: Fraction, lift: Fraction, params: Params) = confidence >= params.minConfidence && lift >= params.minLift
fun compareRules(first: Rule, second: Rule): Int {
    if (first.confidence != second.confidence) return second.confidence.compareTo(first.confidence)
    if (first.lift != second.lift) return second.lift.compareTo(first.lift)
    if (first.count != second.count) return second.count.compareTo(first.count)
    val order = compareItems(first.antecedent, second.antecedent)
    return if (order != 0) order else compareItems(first.consequent, second.consequent)
}
