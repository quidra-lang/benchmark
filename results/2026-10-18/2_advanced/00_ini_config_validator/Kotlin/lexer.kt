const val LITERAL_DOLLAR: Char = '\u0001'

data class LogicalLine(val number: Int, val segments: List<String>, val code: String, val message: String)

fun logicalLines(physical: List<String>): List<LogicalLine> {
    val result = mutableListOf<LogicalLine>()
    var index = 0
    while (index < physical.size) {
        val number = index + 1
        var source = physical[index++]
        val segments = mutableListOf<String>()
        val current = StringBuilder()
        var quoted = false
        var code = ""
        var message = ""
        var position = 0
        while (position < source.length) {
            val c = source[position]
            when {
                c == '\\' && position == source.lastIndex -> {
                    source = physical[index++].trimStart(' ')
                    position = 0
                }
                quoted && c == '\\' -> {
                    val follower = source[position + 1]
                    when (follower) {
                        '\\', '"' -> current.append(follower)
                        'n' -> current.append('\n')
                        't' -> current.append('\t')
                        '$' -> current.append(LITERAL_DOLLAR)
                        else -> if (code.isEmpty()) {
                            code = "E_ESCAPE"
                            message = "invalid escape sequence \\" + follower
                        }
                    }
                    position += 2
                }
                c == '"' -> {
                    segments += current.toString()
                    current.setLength(0)
                    quoted = !quoted
                    position++
                }
                !quoted && (c == ';' || c == '#') -> break
                else -> { current.append(c); position++ }
            }
        }
        if (quoted && code.isEmpty()) {
            code = "E_UNTERMINATED"
            message = "unterminated string"
        }
        segments += current.toString()
        result += LogicalLine(number, segments, code, message)
    }
    return result
}
