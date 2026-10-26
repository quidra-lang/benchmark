import java.net.URLDecoder
import java.nio.charset.StandardCharsets

fun main() {
    val queries = listOf("name=Alice+Smith&age=30&city=New%20York",
        "q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
        "msg=50%25+off%21&debug&lang=en&ref=&lang=ja",
        "redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips")
    for ((index, query) in queries.withIndex()) {
        val values = sortedMapOf<String, MutableList<String>>()
        for (item in query.split('&')) {
            val equals = item.indexOf('=')
            val key = URLDecoder.decode(if (equals < 0) item else item.substring(0, equals), StandardCharsets.UTF_8)
            val value = URLDecoder.decode(if (equals < 0) "" else item.substring(equals + 1), StandardCharsets.UTF_8)
            values.getOrPut(key) { mutableListOf() }.add(value)
        }
        println("query ${index + 1}:")
        for ((key, items) in values) println("  $key: ${items.joinToString(", ") { "\"$it\"" }}")
    }
}
