import java.io.File
import java.util.Locale

fun fixed(value: Double, places: Int = 4): String {
    val text = String.format(Locale.ROOT, "%.${places}f", value)
    return if (text.startsWith('-') && text.drop(1).all { it == '0' || it == '.' }) text.drop(1) else text
}
fun fourDecimal(value: Double) = fixed(value).toDouble()
fun ratio(numerator: Int, denominator: Int) = "$numerator/$denominator ${fixed(numerator.toDouble() / denominator.toDouble())}"
fun fraction(numerator: Int, denominator: Int): String {
    if (denominator == 0) return "- -"
    var first = numerator
    var second = denominator
    while (second != 0) { val remainder = first % second; first = second; second = remainder }
    return "${numerator / first}/${denominator / first} ${fixed(numerator.toDouble() / denominator.toDouble())}"
}
fun joinParts(parts: List<List<String>>) = parts.flatMapIndexed { index, part -> if (index == 0) part else listOf("") + part }
fun writeLines(name: String, lines: List<String>) { File("output").mkdirs(); File("output/$name").writeText(lines.joinToString("\n", postfix = "\n")) }
