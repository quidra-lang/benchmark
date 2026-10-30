data class Token(val kind: String, val value: String, val column: Int)
class FormulaError(val column: Int, val reason: String) : Exception(reason)
object Lexer {
    val greek = listOf("alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu", "nu", "xi", "pi", "rho", "sigma", "tau", "upsilon", "phi", "chi", "psi", "omega", "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Upsilon", "Phi", "Psi", "Omega")
    fun symbol(name: String): Pair<String, Int>? {
        if (name in greek) return Pair(name, 0)
        return when (name) {
            "cdot" -> Pair("*", 2); "times" -> Pair("x", 2); "pm" -> Pair("+-", 2); "mp" -> Pair("-+", 2)
            "leq" -> Pair("<=", 3); "geq" -> Pair(">=", 3); "neq" -> Pair("!=", 3); "approx" -> Pair("~=", 3); "to" -> Pair("->", 3)
            "infty" -> Pair("oo", 0); "ldots", "cdots" -> Pair("...", 0); "quad" -> Pair("  ", 0)
            "," -> Pair(" ", 0); "{" -> Pair("{", 4); "}" -> Pair("}", 5)
            "sin", "cos", "tan", "log", "ln", "exp", "det", "lim", "max", "min", "sum", "prod", "int" -> Pair(name, 1)
            else -> null
        }
    }
    fun letter(c: Char): Boolean = c in 'A'..'Z' || c in 'a'..'z'
    fun commandName(text: String): Boolean = symbol(text) != null && text.isNotEmpty() && text.all(::letter)
    fun lex(text: String): List<Token> {
        val result = mutableListOf<Token>()
        var i = 0
        while (i < text.length) {
            val c = text[i]
            val column = i + 1
            val kind: String
            val value: String
            when {
                c == ' ' -> {
                    i++; continue
                }
                letter(c) -> {
                    val start = i++; while (i < text.length && letter(text[i])) i++; kind = "identifier"; value = text.substring(start, i)
                }
                c in '0'..'9' -> {
                    val start = i++
                    while (i < text.length && text[i] in '0'..'9') i++
                    if (i + 1 < text.length && text[i] == '.' && text[i + 1] in '0'..'9') {
                        i += 2; while (i < text.length && text[i] in '0'..'9') i++
                    }
                    kind = "number"; value = text.substring(start, i)
                }
                c in "+-*/=<>:()[],;.!|'" -> {
                    kind = "symbol"; value = c.toString(); i++
                }
                c in "{}^_&" -> {
                    kind = c.toString(); value = kind; i++
                }
                c == '\\' -> {
                    i++
                    if (i < text.length && text[i] == '\\') {
                        i++; kind = "newline"; value = ""
                    }
                    else if (i < text.length && text[i] in "{},") {
                        kind = "command"; value = "\\" + text[i++]
                    }
                    else {
                        val start = i
                        while (i < text.length && letter(text[i])) i++
                        val name = text.substring(start, i)
                        if (name.isEmpty()) throw FormulaError(column, "invalid command")
                        if (name in listOf("text", "begin", "end", "tag", "label", "eqref")) {
                            while (i < text.length && text[i] == ' ') i++
                            if (i == text.length || text[i] != '{') throw FormulaError(i + 1, "expected {")
                            val end = text.indexOf('}', i + 1)
                            if (end < 0) throw FormulaError(column, "unterminated argument")
                            value = text.substring(i + 1, end); i = end + 1; kind = name
                            if (name in listOf("begin", "end") && value !in listOf("matrix", "pmatrix", "bmatrix", "vmatrix", "cases")) throw FormulaError(column, "unknown environment \"$value\"")
                        } else if (symbol(name) != null) {
                            kind = "command"; value = "\\$name"
                        }
                        else if (name in listOf("overline", "hat", "vec", "dot", "tilde", "overbrace", "underbrace")) {
                            kind = "accent"; value = name
                        }
                        else if (name in listOf("frac", "binom", "overset", "underset", "sqrt", "left", "right")) {
                            kind = name; value = ""
                        }
                        else throw FormulaError(column, "unknown command \\$name")
                    }
                }
                else -> throw FormulaError(column, "invalid character $c")
            }
            result.add(Token(kind, value, column))
        }
        return result
    }
}
