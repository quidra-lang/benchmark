import java.math.BigDecimal
import java.math.RoundingMode

fun decode(text: String): String {
    val result = StringBuilder()
    var i = 0
    while (i < text.length) {
        when (val ch = text[i]) {
            '+' -> result.append(' ')
            '%' -> {
                result.append(text.substring(i + 1,i + 3).toInt(16).toChar())
                i += 2
            }
            else -> result.append(ch)
        }
        i++
    }
    return result.toString()
}
fun main() {
    val queries = listOf("name=Alice+Smith&age=30&city=New%20York",
        "q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
        "msg=50%25+off%21&debug&lang=en&ref=&lang=ja",
        "redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips")
    for ((index,query) in queries.withIndex()) {
        val values = sortedMapOf<String,MutableList<String>>()
        for (item in query.split('&')) {
            val equals = item.indexOf('=')
            val key = decode(if (equals < 0) item else item.substring(0,equals))
            val value = decode(if (equals < 0) "" else item.substring(equals + 1))
            values.getOrPut(key) { mutableListOf() }.add(value)
        }
        println("query ${index + 1}:")
        for ((key,items) in values) println("  $key: ${items.joinToString(", ") { "\"$it\"" }}")
    }
}
