import java.math.BigDecimal
import java.math.RoundingMode

class Parser(private val tokens: List<String>, private var position: Int, private val variables: Map<String,Int>) {
    private fun take(token: String): Boolean {
        if (position >= tokens.size || tokens[position] != token) return false
        position++
        return true
    }
    fun expression(): Int {
        var result = term()
        while (position < tokens.size && tokens[position] in listOf("+","-")) {
            val operation = tokens[position++]
            val right = term()
            result = if (operation == "+") result + right else result - right
        }
        return result
    }
    private fun term(): Int {
        var result = unary()
        while (position < tokens.size && tokens[position] in listOf("*","/")) {
            val operation = tokens[position++]
            val right = unary()
            if (operation == "/" && right == 0) throw IllegalStateException("division by zero")
            result = if (operation == "*") result * right else result / right
        }
        return result
    }
    private fun unary(): Int {
        if (take("-")) return -unary()
        if (take("(")) {
            val result = expression()
            take(")")
            return result
        }
        val token = tokens[position++]
        if (token[0] in '0'..'9') return token.toInt()
        return variables[token] ?: throw IllegalStateException("undefined variable $token")
    }
}
fun main() {
    val lines = listOf("width = 12", "height = width - 5", "area = width * height", "(area + 6) / 4",
        "shift = -area / 8 + 3", "height = 100 / (height - 7) + bonus", "volume = area * depth",
        "width = (width+3)*-(2-4)", "width * shift - height")
    val variables = mutableMapOf<String,Int>()
    for (line in lines) {
        val tokens = Regex("[0-9]+|[a-z]+|[^ ]").findAll(line).map { it.value }.toList()
        val assignment = tokens.size > 1 && tokens[1] == "="
        val name = if (assignment) tokens[0] else null
        try {
            val result = Parser(tokens,if (assignment) 2 else 0,variables).expression()
            if (name != null) {
                variables[name] = result
                println("$name = $result")
            } else println(result)
        } catch (error: IllegalStateException) {
            println("error: ${error.message}")
        }
    }
}
