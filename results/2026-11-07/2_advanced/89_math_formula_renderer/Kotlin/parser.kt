sealed interface Node {
    data class Atom(val kind: String, val value: String, val column: Int) : Node
    data class Row(val elements: List<Node>) : Node
    data class Binary(val name: String, val first: Node, val second: Node) : Node
    data class Root(val index: Node?, val body: Node) : Node
    data class Script(val base: Node, val sub: Node?, val sup: Node?) : Node
    data class Delimited(val left: String, val right: String, val body: Node, val column: Int) : Node
    data class Matrix(val name: String, val rows: List<List<Node>>) : Node
    data class Accent(val name: String, val body: Node) : Node
}
fun empty(): Node = Node.Row(emptyList())
fun Node.isEmpty(): Boolean = this is Node.Row && elements.isEmpty()
data class Formula(val elements: List<Node>, val tag: Pair<String, Int>?, val label: Pair<String, Int>?)
class Parser(val tokens: List<Token>, end: Int) {
    val eof = Token("eof", "", end)
    var index = 0
    var tag: Pair<String, Int>? = null
    var label: Pair<String, Int>? = null
    val peek: Token get() = tokens.getOrNull(index) ?: eof
    fun take(): Token {
        val token = peek; if (index < tokens.size) index++; return token
    }
    fun unexpected(): FormulaError = FormulaError(peek.column, when (peek.kind) {
        "right" -> "unexpected \\right"; "end" -> "unexpected \\end"; "&" -> "misplaced &"; "newline" -> "misplaced \\\\"; else -> "unexpected end of input"
    })
    fun list(top: Boolean = false, rootIndex: Boolean = false): List<Node> {
        val result = mutableListOf<Node>()
        while (true) {
            val token = peek
            if (token.kind in listOf("}", "&", "newline", "right", "end", "eof") || rootIndex && token.kind == "symbol" && token.value == "]") return result
            if (token.kind in listOf("tag", "label")) {
                if (!top) throw FormulaError(token.column, "misplaced \\${token.kind}")
                if ((if (token.kind == "tag") tag else label) != null) throw FormulaError(token.column, "duplicate \\${token.kind}")
                if (token.kind == "tag") tag = Pair(token.value, token.column) else label = Pair(token.value, token.column)
                take(); continue
            }
            result.add(element())
        }
    }
    fun element(): Node {
        val base = if (peek.kind in listOf("^", "_")) empty() else nucleus()
        var sub: Node? = null
        var sup: Node? = null
        while (peek.kind in listOf("^", "_")) {
            val token = take()
            if ((if (token.kind == "^") sup else sub) != null) throw FormulaError(token.column, if (token.kind == "^") "double superscript" else "double subscript")
            val value = argument(token.kind)
            if (token.kind == "^") sup = value else sub = value
        }
        return if (sub != null || sup != null) Node.Script(base, sub, sup) else base
    }
    fun argument(name: String): Node {
        if (peek.kind in listOf("identifier", "number", "symbol", "command", "text", "eqref", "{", "frac", "binom", "overset", "underset", "sqrt", "accent")) return nucleus()
        throw FormulaError(peek.column, "missing argument for $name")
    }
    fun delimiter(): String {
        val token = take()
        if (token.kind == "symbol" && token.value in listOf("(", ")", "[", "]", "|", ".") || token.kind == "command" && token.value in listOf("\\{", "\\}")) return token.value
        throw FormulaError(token.column, "invalid delimiter")
    }
    fun nucleus(): Node {
        val token = take()
        return when (token.kind) {
            "identifier", "number", "symbol", "command", "text", "eqref" -> Node.Atom(token.kind, token.value, token.column)
            "{" -> {
                val nodes = list(); if (peek.kind != "}") throw unexpected(); take(); collapse(nodes)
            }
            "frac", "binom", "overset", "underset" -> {
                val name = "\\" + token.kind; val first = argument(name); val second = argument(name); Node.Binary(token.kind, first, second)
            }
            "sqrt" -> {
                var rootIndex: Node? = null
                if (peek.kind == "symbol" && peek.value == "[") {
                    val column = take().column
                    val nodes = list(false, true)
                    if (peek.kind != "symbol" || peek.value != "]") throw FormulaError(column, "missing ]")
                    take(); rootIndex = collapse(nodes)
                }
                Node.Root(rootIndex, argument("\\sqrt"))
            }
            "accent" -> Node.Accent(token.value, argument("\\" + token.value))
            "left" -> {
                val left = delimiter()
                val nodes = list()
                if (peek.kind != "right") throw FormulaError(token.column, "missing \\right")
                val column = take().column
                Node.Delimited(left, delimiter(), collapse(nodes), column)
            }
            "begin" -> {
                val rows = mutableListOf(mutableListOf<Node>())
                while (true) {
                    rows.last().add(collapse(list()))
                    val end = take()
                    if (end.kind == "&") continue
                    if (end.kind == "newline") {
                        rows.add(mutableListOf()); continue
                    }
                    if (end.kind == "end") {
                        if (end.value != token.value) throw FormulaError(end.column, "mismatched \\end"); break
                    }
                    throw FormulaError(token.column, "missing \\end")
                }
                if (rows.size > 1 && rows.last().size == 1 && rows.last()[0].isEmpty()) rows.removeAt(rows.lastIndex)
                val width = rows.maxOf {
                    it.size
                }
                for (row in rows) repeat(width - row.size) {
                    row.add(empty())
                }
                Node.Matrix(token.value, rows)
            }
            else -> error("unreachable nucleus")
        }
    }
    companion object {
        fun collapse(nodes: List<Node>): Node = if (nodes.size == 1) nodes[0] else Node.Row(nodes)
        fun parse(tokens: List<Token>, end: Int): Formula {
            val braces = mutableListOf<Int>()
            for (token in tokens) {
                if (token.kind == "{") braces.add(token.column)
                else if (token.kind == "}") {
                    if (braces.isEmpty()) throw FormulaError(token.column, "unmatched }"); braces.removeAt(braces.lastIndex)
                }
            }
            if (braces.isNotEmpty()) throw FormulaError(braces.last(), "unclosed {")
            val parser = Parser(tokens, end)
            val elements = parser.list(true)
            if (parser.peek.kind != "eof") throw parser.unexpected()
            return Formula(elements, parser.tag, parser.label)
        }
    }
}
