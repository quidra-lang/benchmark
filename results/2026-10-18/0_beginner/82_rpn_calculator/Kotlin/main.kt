import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    val expressions = listOf("3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3",
        "15 7 1 1 + - / 3 * 2 1 1 + + -", "4 2 5 * + 1 3 2 * - 5 + /",
        "2 3 4 + 5", "46341 46339 * -2 /")
    for (expression in expressions) {
        val stack = mutableListOf<Int>()
        var error: String? = null
        for (token in expression.split(' ')) {
            if (token.length == 1 && token[0] in "+-*/") {
                if (stack.size < 2) {
                    error = "stack underflow"
                    break
                }
                val b = stack.removeAt(stack.lastIndex)
                val a = stack.removeAt(stack.lastIndex)
                if (token == "/" && b == 0) {
                    error = "division by zero"
                    break
                }
                stack.add(when (token) {
                    "+" -> a + b
                    "-" -> a - b
                    "*" -> a * b
                    else -> a / b
                })
            } else stack.add(token.toInt())
        }
        if (error == null && stack.size != 1) error = "leftover operands"
        println(expression + " => " + (if (error == null) stack.single().toString() else "error: $error"))
    }
}
