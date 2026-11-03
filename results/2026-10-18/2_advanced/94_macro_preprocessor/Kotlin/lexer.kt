data class Token(val kind: String, val text: String, val line: Int, val space: Boolean, val hide: Set<String> = emptySet())
data class LogicalLine(val tokens: List<Token>, val start: Int, val end: Int)
object Lexer {
    fun letter(c: Char): Boolean = c in 'A'..'Z' || c in 'a'..'z'
    fun digit(c: Char): Boolean = c in '0'..'9'
    fun one(text: String, start: Int = 0, header: Boolean = false): Pair<String, Int> {
        if (start == text.length) return Pair("other", 0)
        val c = text[start]
        if (header && c == '<') {
            var end = start + 1; while (end < text.length && text[end] != '\n' && text[end] != '>') end++; if (end < text.length && text[end] == '>') return Pair("header", end - start + 1)
        }
        if (letter(c) || c == '_') {
            var n = start + 1; while (n < text.length && (letter(text[n]) || digit(text[n]) || text[n] == '_')) n++; return Pair("identifier", n - start)
        }
        if (digit(c) || c == '.' && start + 1 < text.length && digit(text[start + 1])) {
            var n = start + 1
            while (n < text.length) {
                if (text[n] in "eEpP" && n + 1 < text.length && text[n + 1] in "+-") n += 2 else if (letter(text[n]) || digit(text[n]) || text[n] in "_.") n++ else break
            }; return Pair("number", n - start)
        }
        if (c.code == 39 || c == '"') {
            var n = start + 1; while (n < text.length && text[n] != '\n') {
                if (text[n] == c) return Pair(if (c.code == 39) "character" else "string", n - start + 1); if (text[n].code == 92 && n + 1 < text.length && text[n + 1] != '\n') n += 2 else n++
            }
        }
        for (punctuator in listOf("...", "<<=", ">>=", "->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||", "*=", "/=", "%=", "+=", "-=", "&=", "^=", "|=", "##")) if (text.startsWith(punctuator, start)) return Pair("punctuator", punctuator.length)
        return Pair(if (c in "[](){}.&*+-~!/%<>^|?:;=,#") "punctuator" else "other", 1)
    }
    fun single(text: String): String? {
        if (text.isEmpty() || text.startsWith("//") || text.startsWith("/*")) return null; val (kind, n) = one(text); return if (n == text.length) kind else null
    }
    fun separator(left: String, right: String): Boolean = left == "/" && (right.startsWith("/") || right.startsWith("*")) || one(left + right).second != left.length
    fun render(tokens: List<Token>, output: Boolean = false): String = buildString {
        for ((i, token) in tokens.withIndex()) {
            if (i > 0 && (token.space || output && separator(tokens[i - 1].text, token.text))) append(' '); append(token.text)
        }
    }
    fun lex(source: String): List<LogicalLine> {
        val text = StringBuilder(); val physical = mutableListOf<Int>(); var i = 0; var line = 1
        while (i < source.length) {
            if (source[i].code == 92 && i + 1 < source.length && source[i + 1] == '\n') {
                i += 2; line++; continue
            }; text.append(source[i]); physical.add(line); if (source[i] == '\n') line++; i++
        }
        val spliced = text.toString(); val result = mutableListOf<LogicalLine>(); var tokens = mutableListOf<Token>(); var start = 1; var space = true; i = 0
        while (i < spliced.length) {
            if (spliced[i] == ' ') {
                i++; space = true; continue
            }
            if (spliced[i] == '\n') {
                val end = physical[i]; result.add(LogicalLine(tokens.toList(), start, end)); tokens = mutableListOf(); start = end + 1; i++; space = true; continue
            }
            if (spliced.startsWith("//", i)) {
                while (i < spliced.length && spliced[i] != '\n') i++; space = true; continue
            }
            if (spliced.startsWith("/*", i)) {
                i = spliced.indexOf("*/", i + 2) + 2; space = true; continue
            }
            val header = tokens.size == 2 && tokens[0].text == "#" && tokens[1].text == "include"; val (kind, n) = one(spliced, i, header); tokens.add(Token(kind, spliced.substring(i, i + n), physical[i], space)); i += n; space = false
        }
        if (tokens.isNotEmpty()) result.add(LogicalLine(tokens, start, line)); return result
    }
}
