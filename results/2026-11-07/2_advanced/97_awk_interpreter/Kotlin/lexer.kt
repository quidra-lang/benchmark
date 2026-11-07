data class Position(val line: Int, val column: Int) : Comparable<Position> {
    override fun compareTo(other: Position): Int = compareValuesBy(this, other, Position::line, Position::column)
    override fun toString(): String = "$line:$column"
}
class SyntaxError(val position: Position) : Exception()
data class Token(val kind: String, val text: String, val value: String, val position: Position)
object Lexer {
    fun letter(c: Char): Boolean = c in 'A'..'Z' || c in 'a'..'z'
    fun digit(c: Char): Boolean = c in '0'..'9'
    fun lex(text: String): List<Token> {
        val positions = mutableListOf<Position>();
        var line = 1;
        var column = 1
        for (c in text) {
            positions.add(Position(line, column));
            if (c.code == 10) {
                line++;
                column = 1
            } else column++
        }
        positions.add(Position(line, column))
        val result = mutableListOf<Token>();
        var i = 0
        val keywords = setOf("BEGIN", "END", "function", "if", "else", "while", "for", "do", "break", "continue", "next", "exit", "return", "delete", "in", "getline", "print", "printf")
        val builtins = setOf("length", "substr", "index", "split", "sprintf", "toupper", "tolower", "close", "int")
        val symbols = setOf("+=", "-=", "*=", "/=", "%=", "^=", "==", "<=", ">=", "!=", "++", "--", "&&", "||", ">>")
        while (i < text.length) {
            if (text[i] == ' ') {
                i++;
                continue
            }
            if (text[i].code == 92 && text.getOrNull(i + 1)?.code == 10) {
                i += 2;
                continue
            }
            if (text[i] == '#') {
                while (i < text.length && text[i].code != 10) i++;
                continue
            }
            val start = i;
            var kind = "symbol";
            var value = ""
            if (text[i].code == 10) {
                i++;
                kind = "newline"
            }
            else if (digit(text[i])) {
                while (i < text.length && digit(text[i])) i++;
                kind = "number"
            }
            else if (letter(text[i]) || text[i] == '_') {
                while (i < text.length && (letter(text[i]) || digit(text[i]) || text[i] == '_')) i++
                val name = text.substring(start, i)
                kind = if (name in keywords) "keyword" else if (name in builtins) "builtin" else if (text.getOrNull(i) == '(') "function" else "name"
            } else if (text[i].code == 34) {
                i++;
                var closed = false;
                val decoded = StringBuilder()
                while (i < text.length) {
                    if (text[i].code == 10) throw SyntaxError(positions[start])
                    if (text[i].code == 34) {
                        i++;
                        closed = true;
                        break
                    }
                    if (text[i].code == 92) {
                        val slash = i++
                        if (i == text.length) throw SyntaxError(positions[start])
                        decoded.append(when (text[i].code) {
                            110 -> 10.toChar();
                            116 -> 9.toChar();
                            92, 34, 47 -> text[i];
                            else -> throw SyntaxError(positions[slash])
                        });
                        i++
                    } else decoded.append(text[i++])
                }
                if (!closed) throw SyntaxError(positions[start]);
                kind = "string";
                value = decoded.toString()
            } else if (i + 1 < text.length && text.substring(i, i + 2) in symbols) i += 2
            else if (text[i] in "+-*/%^!><?:=()[]{},;$") i++
            else throw SyntaxError(positions[i])
            result.add(Token(kind, text.substring(start, i), value, positions[start]))
        }
        result.add(Token("end", "", "", positions.last()));
        return result
    }
}
