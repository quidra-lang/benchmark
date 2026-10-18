import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    for (text in listOf("(a + b) * [c - d]", "{x = [1, 2, (3 + 4)]}", "f(a[i] + g(b)}", "(1 + 2)) * 3", "if (a < b) { c = d[0]; }", "((a + b] * c", "[{(x * y) - z}")) {
        val stack = mutableListOf<Char>(); var error = -1
        for ((i,ch) in text.withIndex()) {
            val close = ")]}".indexOf(ch)
            if (ch in "([{") stack.add(ch)
            else if (close >= 0) { if (stack.isEmpty() || stack.last() != "([{"[close]) { error = i; break }; stack.removeAt(stack.lastIndex) }
        }
        if (error < 0 && stack.isNotEmpty()) error = text.length
        println(text + " -> " + if (error < 0) "balanced" else "error at index $error")
    }
}
