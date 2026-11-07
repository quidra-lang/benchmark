data class Position(val file: Int, val line: Int, val column: Int) : Comparable<Position> {
    override fun compareTo(other: Position): Int = compareValuesBy(this, other, {
        it.file
    }, {
        it.line
    }, {
        it.column
    })
}
data class Token(val kind: String, val spelling: String, val value: String, val position: Position)
object Lexer {
    fun letter(c: Char): Boolean = c in 'A'..'Z' || c in 'a'..'z'
    fun digit(c: Char): Boolean = c in '0'..'9'
    fun lex(text: String, file: Int): List<Token> {
        val positions = mutableListOf<Position>(); var row = 1; var column = 1
        for (c in text) {
            positions.add(Position(file, row, column)); if (c == '\n') {
                row++; column = 1
            } else column++
        }
        positions.add(Position(file, row, column))
        val tokens = mutableListOf<Token>(); var i = 0
        while (i < text.length) {
            if (text[i] == ' ' || text[i] == '\n') {
                i++; continue
            }
            val start = i; val kind: String; var value = ""
            if (text.startsWith("(*", i)) {
                val end = text.indexOf("*)", i + 2)
                if (end >= 0) {
                    i = end + 2; continue
                }
                tokens.add(Token("invalid", text.substring(start), "unterminated comment", positions[start])); break
            } else if (digit(text[i])) {
                i++; while (i < text.length && digit(text[i])) i++
                val n = text.substring(start, i).trimStart('0').ifEmpty {
                    "0"
                }.toLongOrNull()
                if (n != null && n <= 2147483647L) {
                    kind = "integer"; value = n.toString()
                } else {
                    kind = "invalid"; value = "integer literal too large"
                }
            } else if (letter(text[i]) || text[i] == '_') {
                i++; while (i < text.length && (letter(text[i]) || digit(text[i]) || text[i] in "_'")) i++
                value = text.substring(start, i); kind = if (value in listOf("let", "rec", "and", "in", "fun", "if", "then", "else", "match", "with", "true", "false", "mod", "val")) "keyword" else "identifier"
            } else if (text[i].code == 39 && i + 1 < text.length && text[i + 1] in 'a'..'z') {
                i += 2; while (i < text.length && (letter(text[i]) || digit(text[i]) || text[i] == '_')) i++
                kind = "type_variable"; value = text.substring(start, i)
            } else if (text[i] == '"') {
                i++; var closed = false; var valid = true; val decoded = StringBuilder()
                while (i < text.length && text[i] != '\n') {
                    if (text[i] == '"') {
                        i++; closed = true; break
                    }
                    if (text[i] == '\\' && i + 1 < text.length && text[i + 1] != '\n') {
                        when (text[i + 1]) {
                            'n' -> decoded.append('\n'); 't' -> decoded.append('\t'); '\\' -> decoded.append('\\'); '"' -> decoded.append('"'); else -> valid = false
                        }; i += 2
                    } else if (text[i] == '\\') i++ else decoded.append(text[i++])
                }
                if (!closed) {
                    kind = "invalid"; value = "unterminated string"
                } else if (!valid) {
                    kind = "invalid"; value = "invalid escape sequence"
                } else {
                    kind = "string"; value = decoded.toString()
                }
            } else {
                if (i + 1 < text.length && text.substring(i, i + 2) in listOf(";;", "->", "::", "||", "&&", "<=", ">=", "<>")) {
                    i += 2; kind = "symbol"; value = text.substring(start, i)
                }
                else if (text[i] in ":;=<>+-*/^()[],|") {
                    i++; kind = "symbol"; value = text.substring(start, i)
                }
                else {
                    kind = "invalid"; value = "illegal character '${text[i++]}'"
                }
            }
            tokens.add(Token(kind, text.substring(start, i), value, positions[start]))
        }
        tokens.add(Token("eof", "", "", positions.last())); return tokens
    }
}
