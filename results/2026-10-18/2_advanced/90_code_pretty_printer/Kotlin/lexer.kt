class SourceError(val line: Int, val column: Int, val reason: String) : Exception(reason)
data class Comment(val text: String, val line: Int, val column: Int, val blank: Int, val lineComment: Boolean, var own: Boolean = false)
data class Token(val text: String, val kind: String, val line: Int, val column: Int, val blank: Int,
val leading: MutableList<Comment> = mutableListOf(), val trailing: MutableList<Comment> = mutableListOf())
data class Occurrence(val token: Boolean, val index: Int)
data class Lexed(val tokens: MutableList<Token> = mutableListOf(), val comments: MutableList<Comment> = mutableListOf(), val order: MutableList<Occurrence> = mutableListOf())
object Lexer {
    fun letter(c: Char): Boolean = c in 'A'..'Z' || c in 'a'..'z'
    fun digit(c: Char): Boolean = c in '0'..'9'
    fun trim(text: String): String = text.trimEnd(' ')
    fun lex(lines: List<String>): Lexed {
        val result = Lexed()
        var previous = 0
        for ((row, line) in lines.withIndex()) {
            var i = 0
            while (i < line.length) {
                if (line[i] == ' ') {
                    i++; continue
                }
                val start = i
                val lineNumber = row + 1
                val blank = maxOf(0, lineNumber - previous - 1)
                fun failure(reason: String): SourceError = SourceError(lineNumber, start + 1, reason)
                if (line.startsWith("//", i)) {
                    result.order.add(Occurrence(false, result.comments.size))
                    result.comments.add(Comment(trim(line.substring(i)), lineNumber, i + 1, blank, true)); previous = lineNumber; break
                }
                if (line.startsWith("/*", i)) {
                    val end = line.indexOf("*/", i + 2)
                    if (end < 0) throw failure("unterminated comment")
                    result.order.add(Occurrence(false, result.comments.size))
                    result.comments.add(Comment(line.substring(i, end + 2), lineNumber, i + 1, blank, false)); previous = lineNumber; i = end + 2; continue
                }
                val kind: String
                if (letter(line[i]) || line[i] == '_') {
                    i++
                    while (i < line.length && (letter(line[i]) || digit(line[i]) || line[i] == '_')) i++
                    kind = if (line.substring(start, i) in listOf("int", "float", "bool", "string", "void", "if", "else", "while", "for", "return", "break", "continue", "true", "false", "switch", "case", "default")) "keyword" else "identifier"
                } else if (digit(line[i])) {
                    i++; while (i < line.length && digit(line[i])) i++
                    if (i + 1 < line.length && line[i] == '.' && digit(line[i + 1])) {
                        i += 2; while (i < line.length && digit(line[i])) i++
                    }
                    kind = "number"
                } else if (line[i] == '"') {
                    i++
                    var closed = false
                    while (i < line.length) {
                        if (line[i] == '\\') i += 2
                        else if (line[i] == '"') {
                            i++; closed = true; break
                        } else i++
                    }
                    if (!closed) throw failure("unterminated string")
                    kind = "string"
                } else if (i + 1 < line.length && line.substring(i, i + 2) in listOf("<=", ">=", "==", "!=", "&&", "||", "+=", "-=", "*=", "/=", "%=")) {
                    i += 2; kind = "symbol"
                }
                else if (line[i] in "+-*/%<>=!()[]{},;.?:") {
                    i++; kind = "symbol"
                }
                else throw failure("unexpected character '${line[i]}'")
                result.order.add(Occurrence(true, result.tokens.size))
                result.tokens.add(Token(line.substring(start, i), kind, lineNumber, start + 1, blank)); previous = lineNumber
            }
        }
        result.tokens.add(Token("", "end", lines.size + 1, 1, 0))
        return result
    }
}
