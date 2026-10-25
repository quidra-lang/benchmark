import java.io.File
import kotlin.math.abs

fun fractionText(value: Fraction): String {
    val numerator = abs(value.numerator)
    val scaled = 10000L * numerator / value.denominator
    val decimal = "${scaled / 10000L}.${(scaled % 10000L).toString().padStart(4, '0')}"
    val sign = if (value.numerator < 0L) "-" else ""
    return "$sign$numerator/${value.denominator}=${if (scaled > 0L) sign else ""}$decimal"
}
fun percentText(part: Long, whole: Long): String { val scaled = 10000L * part / whole; return "${scaled / 100L}.${(scaled % 100L).toString().padStart(2, '0')}%" }
fun money(cents: Long) = "${cents / 100L}.${(cents % 100L).toString().padStart(2, '0')}"
fun itemsetText(items: List<String>) = items.joinToString("+")
fun ruleArrow(rule: Rule) = "${itemsetText(rule.antecedent)} -> ${itemsetText(rule.consequent)}"
fun rulesCsv(rules: List<Rule>) = listOf("rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement") + rules.map { rule -> listOf(rule.rank.toString(), itemsetText(rule.antecedent), itemsetText(rule.consequent), rule.count.toString(), fractionText(rule.support), fractionText(rule.confidence), fractionText(rule.lift), fractionText(rule.leverage), rule.conviction?.let(::fractionText) ?: "INF", fractionText(rule.improvement)).joinToString(",") }
fun writeReport(name: String, lines: List<String>) { File("output").mkdirs(); File("output/$name").writeText(lines.joinToString("\n", postfix = if (lines.isEmpty()) "" else "\n")) }
