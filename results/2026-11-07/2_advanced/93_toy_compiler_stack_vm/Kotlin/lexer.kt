data class Position(val line: Int, val column: Int) : Comparable<Position> {
    override fun compareTo(other: Position): Int = compareValuesBy(this, other, {
        it.line
    }, {
        it.column
    })
    override fun toString(): String = "$line:$column"
}
class CompileError(val kind: String, val position: Position, val reason: String) : Exception(reason)
data class Token(val kind: String, val text: String, val position: Position)
object Lexer {
    fun lex(lines: List<Pair<Int, String>>): List<Token> {
        val text = lines.joinToString("") {
            it.second + "\n"
        }; val positions = mutableListOf<Position>()
        for ((number, line) in lines) for (i in 0..line.length) positions.add(Position(number, i + 1))
        fun letter(c: Char): Boolean = c in 'A'..'Z' || c in 'a'..'z'
        fun digit(c: Char): Boolean = c in '0'..'9'
        val tokens = mutableListOf<Token>(); var i = 0
        while (i < text.length) {
            if (text[i] == ' ' || text[i] == '\n') {
                i++; continue
            }
            val start = i; var kind = "symbol"
            fun failure(reason: String): CompileError = CompileError("lexical", positions[start], reason)
            if (text.startsWith("//", i)) {
                while (i < text.length && text[i] != '\n') i++; continue
            }
            if (text.startsWith("/*", i)) {
                val end = text.indexOf("*/", i + 2); if (end < 0) throw failure("unterminated comment"); i = end + 2; continue
            }
            if (letter(text[i]) || text[i] == '_') {
                i++; while (i < text.length && (letter(text[i]) || digit(text[i]) || text[i] == '_')) i++; kind = if (text.substring(start, i) in listOf("int", "bool", "void", "true", "false", "if", "else", "while", "for", "break", "continue", "return", "print", "read")) "keyword" else "identifier"
            }
            else if (digit(text[i])) {
                i++; while (i < text.length && digit(text[i])) i++; val n = text.substring(start, i).toLong(); if (n > 2147483647L) throw failure("integer literal too large"); kind = "integer"
            }
            else if (i + 1 < text.length && text.substring(i, i + 2) in listOf("<=", ">=", "==", "!=", "&&", "||")) i += 2
            else if (text[i] in "+-*/%<>=!(){}[],;") i++ else throw failure("unexpected character '${text[i]}'")
            tokens.add(Token(kind, text.substring(start, i), positions[start]))
        }
        tokens.add(Token("end", "", Position(lines.last().first, lines.last().second.length + 1))); return tokens
    }
}
