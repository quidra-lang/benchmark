val backslash = 92.toChar().toString()
data class Token(val kind: String, val spelling: String, val name: String, val line: Int, val column: Int, val space: Boolean)
class ReadError(val line: Int, val column: Int, val reason: String, val index: Int, val eof: Boolean) : Exception(reason)
data class Variable(val name: String, val term: Term, var count: Int)
data class Parsed(val term: Term, val variables: List<Variable>, val next: Int)
fun symbol(c: Char): Boolean = c in "+-*/^<>=~:.?@#&$" || c.code == 92
fun digit(c: Char): Boolean = c in '0'..'9'
fun lower(c: Char): Boolean = c in 'a'..'z'
fun alpha(c: Char): Boolean = lower(c) || c in 'A'..'Z'
data class Operator(val priority: Int, val left: Int, val right: Int)
fun operatorInfo(name: String): Operator? {
    val pair = when (name) {
        ":-" -> 1200 to "xfx"
        ";" -> 1100 to "xfy"
        "->" -> 1050 to "xfy"
        "," -> 1000 to "xfy"
        "=", backslash + "=", "==", backslash + "==", "is", "=:=", "=" + backslash + "=", "<", ">", "=<", ">=", "=.." -> 700 to "xfx"
        "+", "-" -> 500 to "yfx"
        "*", "/", "//", "mod", "rem" -> 400 to "yfx"
        else -> return null
    }
    val (p, kind) = pair
    return Operator(p, if (kind == "yfx") p else p - 1, if (kind == "xfy") p else p - 1)
}
fun prefixPriority(name: String): Int? = if (name == backslash + "+") 900 else if (name == "-") 200 else null
fun isOperator(name: String): Boolean = operatorInfo(name) != null || prefixPriority(name) != null
fun lex(text: String, firstColumn: Int): List<Token> {
    val tokens = mutableListOf<Token>()
    var i = 0
    var line = 1
    var column = firstColumn
    var space = true
    while (i < text.length) {
        if (text[i] == ' ') {
            i++
            column++
            space = true
            continue
        }
        if (text[i].code == 10) {
            i++
            line++
            column = 1
            space = true
            continue
        }
        if (text[i] == '%') {
            while (i < text.length && text[i].code != 10) {
                i++
                column++
            }
            space = true
            continue
        }
        val start = i
        val at = column
        var kind: String
        var name = ""
        if (digit(text[i])) {
            while (i < text.length && digit(text[i])) i++
            val value = text.substring(start, i).toLongOrNull()
            if (value != null && value <= 2147483647L) kind = "integer" else {
                kind = "invalid"
                name = "integer too large"
            }
        }
        else if (alpha(text[i]) || text[i] == '_') {
            while (i < text.length && (alpha(text[i]) || digit(text[i]) || text[i] == '_')) i++
            kind = if (lower(text[start])) "name" else "variable"
        }
        else if (symbol(text[i])) {
            while (i < text.length && symbol(text[i])) i++
            kind = if (i - start == 1 && text[start] == '.' && (i == text.length || text[i].code in listOf(32, 10, 37))) "end" else "name"
        }
        else if (text[i] == '!' || text[i] == ';') {
            i++
            kind = "name"
        }
        else if (text[i] in ",|()[]") {
            i++
            kind = "punctuation"
        }
        else if (text[i].code == 39) {
            i++
            var invalid = false
            var closed = false
            val value = StringBuilder()
            while (i < text.length && text[i].code != 10) {
                if (text[i].code == 39) {
                    if (text.getOrNull(i + 1)?.code == 39) {
                        value.append(39.toChar())
                        i += 2
                    } else {
                        i++
                        closed = true
                        break
                    }
                }
                else if (text[i].code == 92) {
                    i++
                    if (i < text.length && text[i].code != 10) {
                        when (text[i].code) {
                            110 -> value.append(10.toChar())
                            116 -> value.append(9.toChar())
                            92, 39 -> value.append(text[i])
                            else -> invalid = true
                        }
                        i++
                    }
                }
                else value.append(text[i++])
            }
            if (!closed) {
                kind = "invalid"
                name = "unterminated quoted atom"
            } else if (invalid) {
                kind = "invalid"
                name = "undefined escape sequence"
            } else {
                kind = "quoted"
                name = value.toString()
            }
        } else {
            i++
            kind = "invalid"
            name = "illegal character '${text[start]}'"
        }
        val spelling = text.substring(start, i)
        if (name.isEmpty() && kind != "quoted") name = spelling
        tokens.add(Token(kind, spelling, name, line, at, space))
        column += i - start
        space = false
    }
    tokens.add(Token("eof", "", "", line, column, space))
    return tokens
}
class Reader(val tokens: List<Token>, var index: Int, val store: Store) {
    val variables = mutableListOf<Variable>()
    val names = mutableMapOf<String, Int>()
    val peek: Token get() = tokens[index]
    fun error(i: Int): ReadError {
        val token = tokens[i]
        val reason = when {
            token.kind == "invalid" -> token.name
            token.kind == "eof" -> "unexpected end of file"
            token.kind == "end" -> "unexpected end of clause"
            token.kind == "name" && operatorInfo(token.name) != null -> "operator priority clash"
            else -> "unexpected " + 34.toChar() + token.spelling + 34.toChar()
        }
        return ReadError(token.line, token.column, reason, i, token.kind == "eof")
    }
    fun take(): Pair<Int, Token> {
        val result = index to peek
        if (peek.kind != "eof") index++
        return result
    }
    fun expect(name: String) {
        val (at, token) = take()
        if (token.kind != "punctuation" || token.name != name) throw error(at)
    }
    fun term(limit: Int): Pair<Term, Int> {
        var (term, priority) = primary(limit)
        while (peek.kind == "name" || peek.kind == "punctuation" && peek.name == ",") {
            val info = operatorInfo(peek.name) ?: break
            if (info.priority > limit || priority > info.left) break
            val name = take().second.name
            val argument = this.term(info.right).first
            term = Term.Compound(name, listOf(term, argument))
            priority = info.priority
        }
        return term to priority
    }
    fun starts(token: Token): Boolean = token.kind in listOf("integer", "variable", "quoted") || token.kind == "punctuation" && token.name in listOf("(", "[") || token.kind == "name" && (operatorInfo(token.name) == null || prefixPriority(token.name) != null)
    fun primary(limit: Int): Pair<Term, Int> {
        val (at, token) = take()
        when (token.kind) {
            "integer" -> return Term.Integer(token.name.toLong()) to 0
            "variable" -> {
                if (token.name == "_") return store.fresh() to 0
                val i = names[token.name]
                if (i != null) {
                    variables[i].count++
                    return variables[i].term to 0
                }
                val value = store.fresh()
                names[token.name] = variables.size
                variables.add(Variable(token.name, value, 1))
                return value to 0
            }
            "punctuation" -> {
                if (token.name == "(") {
                    val result = term(1200).first
                    expect(")")
                    return result to 0
                }
                if (token.name != "[") throw error(at)
                if (peek.kind == "punctuation" && peek.name == "]") {
                    take()
                    return Term.Atom("[]") to 0
                }
                val elements = mutableListOf(term(999).first)
                while (peek.kind == "punctuation" && peek.name == ",") {
                    take()
                    elements.add(term(999).first)
                }
                val tail = if (peek.kind == "punctuation" && peek.name == "|") {
                    take()
                    term(999).first
                } else Term.Atom("[]")
                expect("]")
                return list(elements, tail) to 0
            }
            "name", "quoted" -> {
                if (peek.kind == "punctuation" && peek.name == "(" && !peek.space) {
                    take()
                    val args = mutableListOf(term(999).first)
                    while (peek.kind == "punctuation" && peek.name == ",") {
                        take()
                        args.add(term(999).first)
                    }
                    expect(")")
                    return Term.Compound(token.name, args) to 0
                }
                if (token.kind == "name" && token.name == "-" && peek.kind == "integer" && !peek.space) return Term.Integer(-take().second.name.toLong()) to 0
                val p = if (token.kind == "name") prefixPriority(token.name) else null
                if (p != null && starts(peek)) {
                    if (p > limit) throw ReadError(token.line, token.column, "operator priority clash", at, false)
                    return Term.Compound(token.name, listOf(term(p).first)) to p
                }
                return Term.Atom(token.name) to 0
            }
            else -> throw error(at)
        }
    }
    fun clause(query: Boolean = false): Parsed {
        val value = term(1200).first
        val (at, token) = take()
        if (token.kind != "end") throw error(at)
        if (query && peek.kind != "eof") throw error(index)
        return Parsed(value, variables.toList(), index)
    }
}
