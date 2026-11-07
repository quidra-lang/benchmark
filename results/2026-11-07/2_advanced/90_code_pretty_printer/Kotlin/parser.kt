data class SyntaxNode(val kind: String, val tokens: List<Int>, val children: List<SyntaxNode>, val start: Int, val end: Int, var trailing: Int? = null)
class Parser(val tokens: List<Token>) {
    var index = 0
    val peek: Token get() = tokens[index]
    val text: String get() = peek.text
    fun take(): Int = index++
    fun failure(expected: String): SourceError = SourceError(peek.line, peek.column, "expected $expected, found ${if (peek.kind == "end") "end of file" else "'$text'"}")
    fun symbol(value: String): Int {
        if (text != value) throw failure("'$value'"); return take()
    }
    fun identifier(): Int {
        if (peek.kind != "identifier") throw failure("identifier"); return take()
    }
    fun readType(): Int {
        if (!isType(text)) throw failure("type"); return take()
    }
    fun node(kind: String, tokens: List<Int>, children: List<SyntaxNode>, start: Int): SyntaxNode = SyntaxNode(kind, tokens, children, start, maxOf(0, index - 1))
    fun empty(): SyntaxNode = SyntaxNode("empty", emptyList(), emptyList(), index, index)
    fun list(kind: String, open: String, close: String, trailing: Boolean): SyntaxNode {
        val start = index
        val tokens = mutableListOf(symbol(open))
        val children = mutableListOf<SyntaxNode>()
        var tail: Int? = null
        if (text != close) {
            children.add(listElement(kind))
            while (text == ",") {
                val comma = take()
                if (trailing && text == close) {
                    tail = comma; break
                }
                tokens.add(comma); children.add(listElement(kind))
            }
        }
        tokens.add(symbol(close))
        return node(kind, tokens, children, start).copy(trailing = tail)
    }
    fun listElement(kind: String): SyntaxNode {
        if (kind == "params") {
            val start = index
            val tokens = listOf(readType(), identifier())
            val children = mutableListOf<SyntaxNode>()
            while (text == "[") {
                val s = index; val pair = listOf(take(), symbol("]")); children.add(node("dimension", pair, emptyList(), s))
            }
            return node("parameter", tokens, children, start)
        }
        return if (kind == "initlist") initializer() else expression()
    }
    fun initializer(): SyntaxNode = if (text == "{") list("initlist", "{", "}", true) else expression()
    fun declaration(semicolon: Boolean): SyntaxNode {
        val start = index; return declarationRest(start, listOf(readType(), identifier()), semicolon)
    }
    fun declarationRest(start: Int, original: List<Int>, semicolon: Boolean): SyntaxNode {
        val tokens = original.toMutableList()
        val children = mutableListOf<SyntaxNode>()
        while (text == "[") {
            val s = index
            val open = take()
            val content = if (text == "]") emptyList() else listOf(expression())
            val close = symbol("]")
            children.add(node("dimension", listOf(open, close), content, s))
        }
        if (text == "=") {
            tokens.add(take()); children.add(initializer())
        }
        if (semicolon) tokens.add(symbol(";"))
        return node("decl", tokens, children, start)
    }
    fun item(): SyntaxNode {
        val start = index
        val tokens = listOf(readType(), identifier())
        return if (text == "(") {
            val parameters = list("params", "(", ")", false); val block = this.block(); node("function", tokens, listOf(parameters, block), start)
        } else declarationRest(start, tokens, true)
    }
    fun block(): SyntaxNode {
        val start = index
        val open = symbol("{")
        val statements = mutableListOf<SyntaxNode>()
        while (text != "}" && peek.kind != "end") statements.add(statement())
        val close = symbol("}")
        return node("block", listOf(open, close), statements, start)
    }
    fun statement(): SyntaxNode {
        val start = index
        if (text == "{") return block()
        if (isType(text)) return declaration(true)
        return when (text) {
            "if", "while" -> {
                val kind = text
                val keyword = take(); val open = symbol("("); val condition = expression(); val close = symbol(")"); val body = statement()
                val tokens = mutableListOf(keyword, open, close)
                val children = mutableListOf(condition, body)
                if (kind == "if" && text == "else") {
                    tokens.add(take()); children.add(statement())
                }
                node(kind, tokens, children, start)
            }
            "for" -> {
                val keyword = take(); val open = symbol("(")
                val initial = if (text == ";") empty() else if (isType(text)) declaration(false) else simple()
                val first = symbol(";"); val condition = if (text == ";") empty() else expression(); val second = symbol(";")
                val update = if (text == ")") empty() else simple(); val close = symbol(")"); val body = statement()
                node("for", listOf(keyword, open, first, second, close), listOf(initial, condition, update, body), start)
            }
            "switch" -> {
                val keyword = take(); val open = symbol("("); val condition = expression(); val close = symbol(")"); val left = symbol("{")
                val children = mutableListOf(condition)
                while (text in listOf("case", "default")) {
                    val s = index; val label = take(); val kind = tokens[label].text
                    val body = mutableListOf<SyntaxNode>()
                    if (kind == "case") body.add(expression())
                    val colon = symbol(":")
                    while (text !in listOf("case", "default", "}") && peek.kind != "end") body.add(statement())
                    children.add(node(kind, listOf(label, colon), body, s))
                }
                val right = symbol("}")
                node("switch", listOf(keyword, open, close, left, right), children, start)
            }
            "return" -> {
                val keyword = take(); val children = if (text == ";") emptyList() else listOf(expression()); val semi = symbol(";"); node("return", listOf(keyword, semi), children, start)
            }
            "break", "continue" -> {
                val keyword = take(); val kind = tokens[keyword].text; val semi = symbol(";"); node(kind, listOf(keyword, semi), emptyList(), start)
            }
            else -> {
                val expression = simple(); val semi = symbol(";"); node("statement", listOf(semi), listOf(expression), start)
            }
        }
    }
    fun simple(): SyntaxNode {
        val start = index
        val left = expression()
        return if (text in listOf("=", "+=", "-=", "*=", "/=", "%=")) {
            val op = take(); val right = expression(); node("assign", listOf(op), listOf(left, right), start)
        } else node("exprstmt", emptyList(), listOf(left), start)
    }
    fun expression(): SyntaxNode {
        val start = index
        val condition = binary(1)
        return if (text == "?") {
            val question = take(); val yes = expression(); val colon = symbol(":"); val no = expression(); node("conditional", listOf(question, colon), listOf(condition, yes, no), start)
        } else condition
    }
    fun binary(precedence: Int): SyntaxNode {
        val start = index
        var left = if (precedence == 6) unary() else binary(precedence + 1)
        while (Parser.precedence(text) == precedence) {
            val op = take()
            val right = if (precedence == 6) unary() else binary(precedence + 1)
            left = node("binary", listOf(op), listOf(left, right), start)
        }
        return left
    }
    fun unary(): SyntaxNode {
        val start = index
        if (text in listOf("-", "!")) {
            val op = take(); val child = unary(); return node("unary", listOf(op), listOf(child), start)
        }
        var target = primary()
        while (true) {
            target = when (text) {
                "(" -> {
                    val args = list("args", "(", ")", false); node("call", emptyList(), listOf(target, args), start)
                }
                "[" -> {
                    val open = take(); val expression = expression(); val close = symbol("]"); node("index", listOf(open, close), listOf(target, expression), start)
                }
                "." -> {
                    val dot = take(); val name = identifier(); node("member", listOf(dot, name), listOf(target), start)
                }
                else -> return target
            }
        }
    }
    fun primary(): SyntaxNode {
        val start = index
        if (peek.kind in listOf("identifier", "number", "string") || text in listOf("true", "false")) return node("atom", listOf(take()), emptyList(), start)
        if (text == "(") {
            val open = take(); val child = expression(); val close = symbol(")"); return node("paren", listOf(open, close), listOf(child), start)
        }
        throw failure("expression")
    }
    companion object {
        fun isType(text: String): Boolean = text in listOf("int", "float", "bool", "string", "void")
        fun precedence(text: String): Int = when (text) {
            "||" -> 1; "&&" -> 2; "==", "!=" -> 3; "<", "<=", ">", ">=" -> 4; "+", "-" -> 5; "*", "/", "%" -> 6; else -> 0
        }
        fun parse(tokens: List<Token>): List<SyntaxNode> {
            val parser = Parser(tokens)
            val items = mutableListOf<SyntaxNode>()
            while (parser.peek.kind != "end") items.add(parser.item())
            return items
        }
    }
}
