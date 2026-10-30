import java.io.File
data class Profile(val values: MutableMap<String, String> = mutableMapOf()) {
    fun yes(key: String): Boolean = values[key] == "yes"
    fun number(key: String): Int = values.getValue(key).toInt()
    val kr: Boolean get() = values["brace_style"] == "kr"
}
fun attach(lexed: Lexed): Pair<List<Token>, Int> {
    val tokens = lexed.tokens
    for ((k, entry) in lexed.order.withIndex()) {
        if (entry.token) continue
        val comment = lexed.comments[entry.index]
        val previous = lexed.order.take(k).lastOrNull {
            it.token
        }?.index
        val next = lexed.order.drop(k + 1).firstOrNull {
            it.token
        }?.index
        val following = lexed.order.getOrNull(k + 1)
        val nextLine = following?.let {
            if (it.token) tokens[it.index].line else lexed.comments[it.index].line
        }
        comment.own = comment.lineComment || nextLine == null || nextLine > comment.line
        val trailing = previous != null && tokens[previous].line == comment.line && (next == null || tokens[next].line > comment.line)
        if (trailing) tokens[previous!!].trailing.add(comment) else tokens[next ?: tokens.lastIndex].leading.add(comment)
    }
    return Pair(tokens, lexed.comments.size)
}
fun checkComments(items: List<SyntaxNode>, tokens: List<Token>) {
    val allowed = mutableSetOf(tokens.lastIndex)
    val tails = mutableSetOf<Int>()
    fun walk(node: SyntaxNode) {
        when (node.kind) {
            "block" -> {
                allowed.add(node.tokens[1]); node.children.forEach {
                    allowed.add(it.start)
                }
            }
            "switch" -> {
                allowed.add(node.tokens[4])
                for (clause in node.children.drop(1)) {
                    allowed.add(clause.tokens[0])
                    clause.children.drop(if (clause.kind == "case") 1 else 0).forEach {
                        allowed.add(it.start)
                    }
                }
            }
            "if" -> {
                if (node.children[1].kind != "block") allowed.add(node.children[1].start)
                if (node.children.size == 3 && node.children[2].kind !in listOf("block", "if")) allowed.add(node.children[2].start)
            }
            "while" -> if (node.children[1].kind != "block") allowed.add(node.children[1].start)
            "for" -> if (node.children[3].kind != "block") allowed.add(node.children[3].start)
            "params", "args", "initlist" -> {
                node.children.forEach {
                    allowed.add(it.start)
                }; node.trailing?.let {
                    tails.add(it)
                }
            }
        }
        node.children.forEach {
            walk(it)
        }
    }
    for (item in items) {
        allowed.add(item.start); walk(item)
    }
    for ((i, token) in tokens.withIndex()) for (comment in token.leading) {
        if (comment.own && i !in allowed || i in tails) throw SourceError(comment.line, comment.column, "comment not allowed here")
    }
}
class Construction(val tokens: List<Token>, val profile: Profile) {
    val originalTrailing = tokens.map {
        it.trailing.isNotEmpty()
    }
    val docs = DocBuilder()
    fun space(): Document = text(if (profile.yes("space_around_operators")) " " else "")
    fun keywordSpace(): Document = text(if (profile.yes("space_after_keyword")) " " else "")
    fun operatorLine(): Document = if (profile.yes("space_around_operators")) line() else softline()
    fun separator(blank: Int): Document = concat(List(1 + minOf(blank, profile.number("max_blank_lines"))) {
        hardline()
    })
    fun preblank(token: Int): Int = tokens[token].leading.firstOrNull()?.blank ?: tokens[token].blank
    fun comments(comments: List<Comment>, next: Int?): Document {
        val parts = mutableListOf<Document>()
        for ((i, comment) in comments.withIndex()) {
            parts.add(text(comment.text))
            val blank = comments.getOrNull(i + 1)?.blank ?: next
            if (blank != null) parts.add(if (comment.own) separator(blank) else text(" "))
        }
        return concat(parts)
    }
    fun trailing(token: Int): Document = if (tokens[token].trailing.isEmpty()) text("") else suffix(tokens[token].trailing.joinToString(" ") {
        it.text
    })
    fun tokenWith(token: Int, leading: List<Comment>): Document = concat(listOf(comments(leading, tokens[token].blank), text(tokens[token].text), trailing(token)))
    fun token(token: Int): Document = tokenWith(token, tokens[token].leading)
    fun group(child: Document): Document = docs.group(child)
    fun level(node: SyntaxNode): Int = when (node.kind) {
        "conditional" -> 0; "binary" -> Parser.precedence(tokens[node.tokens[0]].text); "unary" -> 7; else -> 8
    }
    fun open(node: SyntaxNode, required: Int): SyntaxNode {
        var current = node
        while (profile.yes("remove_parens") && current.kind == "paren" && level(current.children[0]) >= required && tokens[current.tokens[0]].leading.isEmpty() && tokens[current.tokens[1]].leading.isEmpty()) {
            val child = current.children[0]
            val left = tokens[current.tokens[0]]
            val right = tokens[current.tokens[1]]
            val first = left.trailing.toList()
            val last = right.trailing.toList()
            left.trailing.clear(); right.trailing.clear()
            tokens[child.start].trailing.addAll(0, first)
            tokens[child.end].trailing.addAll(last)
            current = child
        }
        return current
    }
    fun list(node: SyntaxNode): Document {
        val left = node.tokens.first()
        val right = node.tokens.last()
        if (node.children.isEmpty()) return concat(listOf(token(left), token(right)))
        val forced = (node.start until node.end).any {
            originalTrailing[it]
        }
        val inside = mutableListOf<Document>(softline())
        for ((i, child) in node.children.withIndex()) {
            if (i > 0) inside.addAll(listOf(token(node.tokens[i]), line()))
            inside.add(when (node.kind) {
                "params" -> parameter(child); "initlist" -> initializer(child); else -> expression(child, 0)
            })
        }
        if (node.kind == "initlist") {
            inside.add(ifBreak(",", "")); node.trailing?.let {
                inside.add(trailing(it))
            }
        }
        return group(concat(listOf(if (forced) breakParent() else text(""), token(left), nest(profile.number("indent"), concat(inside)), softline(), token(right))))
    }
    fun parameter(node: SyntaxNode): Document {
        val parts = mutableListOf(token(node.tokens[0]), text(" "), token(node.tokens[1]))
        for (dimension in node.children) parts.addAll(listOf(token(dimension.tokens[0]), token(dimension.tokens[1])))
        return concat(parts)
    }
    fun declaration(node: SyntaxNode): Document {
        val parts = mutableListOf(token(node.tokens[0]), text(" "), token(node.tokens[1]))
        var initial: SyntaxNode? = null
        for (child in node.children) {
            if (child.kind == "dimension") {
                parts.add(token(child.tokens[0])); child.children.firstOrNull()?.let {
                    parts.add(expression(it, 0))
                }; parts.add(token(child.tokens[1]))
            } else initial = child
        }
        for (t in node.tokens.drop(2)) {
            if (tokens[t].text == "=") parts.addAll(listOf(space(), token(t), space(), initializer(initial!!))) else parts.add(token(t))
        }
        return concat(parts)
    }
    fun initializer(node: SyntaxNode): Document = if (node.kind == "initlist") list(node) else expression(node, 0)
    fun closing(token: Int): Pair<List<Comment>, List<Comment>> {
        val comments = tokens[token].leading
        val split = comments.indexOfLast {
            it.own
        } + 1
        return Pair(comments.take(split), comments.drop(split))
    }
    fun block(node: SyntaxNode): Document {
        val close = node.tokens[1]
        val (h, g) = closing(close)
        if (node.children.isEmpty() && h.isEmpty()) return concat(listOf(token(node.tokens[0]), tokenWith(close, g)))
        val inside = mutableListOf<Document>(hardline())
        for ((i, child) in node.children.withIndex()) {
            if (i > 0) inside.add(separator(preblank(child.start))); inside.add(statement(child))
        }
        if (h.isNotEmpty()) {
            if (node.children.isNotEmpty()) inside.add(separator(h[0].blank)); inside.add(comments(h, null))
        }
        return concat(listOf(token(node.tokens[0]), nest(profile.number("indent"), concat(inside)), hardline(), tokenWith(close, g)))
    }
    fun body(node: SyntaxNode): Document {
        val separator = if (profile.kr) text(" ") else hardline()
        if (node.kind == "block") return concat(listOf(separator, block(node)))
        val document = statement(node)
        if (profile.yes("add_braces")) return concat(listOf(separator, text("{"), nest(profile.number("indent"), concat(listOf(hardline(), document))), hardline(), text("}")))
        return nest(profile.number("indent"), concat(listOf(hardline(), document)))
    }
    fun simple(node: SyntaxNode): Document = if (node.kind == "assign") concat(listOf(expression(node.children[0], 0), space(), token(node.tokens[0]), space(), expression(node.children[1], 0))) else expression(node.children[0], 0)
    fun clause(node: SyntaxNode): Document {
        val parts = mutableListOf(token(node.tokens[0]))
        val first = if (node.kind == "case") 1 else 0
        if (first == 1) parts.addAll(listOf(text(" "), expression(node.children[0], 0)))
        parts.add(token(node.tokens[1]))
        if (node.children.size > first) {
            val statements = mutableListOf<Document>(hardline())
            for ((i, child) in node.children.drop(first).withIndex()) {
                if (i > 0) statements.add(separator(preblank(child.start))); statements.add(statement(child))
            }
            parts.add(nest(profile.number("indent"), concat(statements)))
        }
        return concat(parts)
    }
    fun statement(node: SyntaxNode): Document {
        return when (node.kind) {
            "block" -> block(node)
            "decl" -> declaration(node)
            "statement" -> concat(listOf(simple(node.children[0]), token(node.tokens[0])))
            "break", "continue" -> concat(node.tokens.map {
                token(it)
            })
            "return" -> {
                val parts = mutableListOf(token(node.tokens[0])); node.children.firstOrNull()?.let {
                    parts.addAll(listOf(text(" "), expression(it, 0)))
                }; concat(parts + token(node.tokens[1]))
            }
            "while", "if" -> {
                val condition = expression(node.children[0], 0)
                val body = this.body(node.children[1])
                val parts = mutableListOf(token(node.tokens[0]), keywordSpace(), token(node.tokens[1]), condition, token(node.tokens[2]), body)
                if (node.kind == "if" && node.children.size == 3) {
                    parts.add(if (profile.kr && (node.children[1].kind == "block" || profile.yes("add_braces"))) text(" ") else hardline())
                    parts.add(token(node.tokens[3]))
                    if (node.children[2].kind == "if") parts.addAll(listOf(text(" "), statement(node.children[2]))) else parts.add(this.body(node.children[2]))
                }
                concat(parts)
            }
            "for" -> {
                val inner = mutableListOf<Document>()
                val initial = node.children[0]
                if (initial.kind != "empty") inner.add(if (initial.kind == "decl") declaration(initial) else simple(initial))
                inner.add(token(node.tokens[2]))
                if (node.children[1].kind != "empty") inner.addAll(listOf(line(), expression(node.children[1], 0)))
                inner.add(token(node.tokens[3]))
                if (node.children[2].kind != "empty") inner.addAll(listOf(line(), simple(node.children[2])))
                val group = group(align(concat(inner)))
                val body = body(node.children[3])
                concat(listOf(token(node.tokens[0]), keywordSpace(), token(node.tokens[1]), group, token(node.tokens[4]), body))
            }
            "switch" -> {
                val close = node.tokens[4]
                val (h, g) = closing(close)
                val condition = expression(node.children[0], 0)
                val parts = mutableListOf(token(node.tokens[0]), keywordSpace(), token(node.tokens[1]), condition, token(node.tokens[2]), if (profile.kr) text(" ") else hardline(), token(node.tokens[3]))
                if (node.children.size > 1 || h.isNotEmpty()) {
                    val inside = mutableListOf<Document>(hardline())
                    for ((i, child) in node.children.drop(1).withIndex()) {
                        if (i > 0) inside.add(separator(preblank(child.start))); inside.add(clause(child))
                    }
                    if (h.isNotEmpty()) {
                        if (node.children.size > 1) inside.add(separator(h[0].blank)); inside.add(comments(h, null))
                    }
                    parts.addAll(listOf(nest(if (profile.yes("indent_case_labels")) profile.number("indent") else 0, concat(inside)), hardline()))
                }
                concat(parts + tokenWith(close, g))
            }
            else -> error("invalid statement")
        }
    }
    fun function(node: SyntaxNode): Document {
        val parameters = list(node.children[0])
        val block = block(node.children[1])
        return concat(listOf(token(node.tokens[0]), text(" "), token(node.tokens[1]), parameters, hardline(), block))
    }
    fun postfix(node: SyntaxNode): Document = when (node.kind) {
        "call" -> list(node.children[1])
        "index" -> concat(listOf(token(node.tokens[0]), expression(node.children[1], 0), token(node.tokens[1])))
        "member" -> concat(listOf(token(node.tokens[0]), token(node.tokens[1])))
        else -> error("invalid postfix")
    }
    fun expression(original: SyntaxNode, required: Int): Document {
        val node = open(original, required)
        return when (node.kind) {
            "atom" -> token(node.tokens[0])
            "paren" -> concat(listOf(token(node.tokens[0]), expression(node.children[0], 0), token(node.tokens[1])))
            "unary" -> concat(listOf(token(node.tokens[0]), expression(node.children[0], 8)))
            "binary" -> {
                val p = level(node)
                var current = node
                val entries = mutableListOf<Pair<Int, SyntaxNode>>()
                while (current.kind == "binary" && level(current) == p) {
                    entries.add(Pair(current.tokens[0], current.children[1])); current = open(current.children[0], p)
                }
                val head = expression(current, p)
                val rest = mutableListOf<Document>()
                for ((op, right) in entries.asReversed()) rest.addAll(listOf(operatorLine(), token(op), space(), expression(right, p + 1)))
                group(concat(listOf(head, nest(profile.number("indent"), concat(rest)))))
            }
            "conditional" -> {
                val head = expression(node.children[0], 1)
                var current = node
                val rest = mutableListOf<Document>()
                while (true) {
                    rest.addAll(listOf(operatorLine(), token(current.tokens[0]), space(), expression(current.children[1], 0), operatorLine(), token(current.tokens[1]), space()))
                    val next = open(current.children[2], 0)
                    if (next.kind == "conditional") {
                        rest.add(expression(next.children[0], 1)); current = next
                    } else {
                        rest.add(expression(next, 0)); break
                    }
                }
                group(concat(listOf(head, nest(profile.number("indent"), concat(rest)))))
            }
            "call", "index", "member" -> {
                var current = node
                val operations = mutableListOf<SyntaxNode>()
                while (current.kind in listOf("call", "index", "member")) {
                    operations.add(current); current = open(current.children[0], 8)
                }
                val segments = mutableListOf(mutableListOf<SyntaxNode>())
                for (operation in operations.asReversed()) {
                    if (operation.kind == "member") segments.add(mutableListOf()); segments.last().add(operation)
                }
                val calls = segments.indices.drop(1).filter {
                    i -> segments[i].any {
                        it.kind == "call"
                    }
                }
                val parts = mutableListOf(expression(current, 8))
                if (calls.size < 2) {
                    for (operation in segments.flatten()) parts.add(postfix(operation)); concat(parts)
                }
                else {
                    val first = calls[0]
                    for (operation in segments.take(first).flatten()) parts.add(postfix(operation))
                    val rest = mutableListOf<Document>()
                    for (segment in segments.drop(first)) {
                        rest.add(softline()); for (operation in segment) rest.add(postfix(operation))
                    }
                    parts.add(nest(profile.number("indent"), concat(rest))); group(concat(parts))
                }
            }
            else -> error("invalid expression")
        }
    }
}
data class Formatted(val lines: List<String>, val firstFunction: Pair<String, Document>?, val modes: Map<Int, String>, val comments: Int)
fun formatSource(lines: List<String>, profile: Profile): Formatted {
    val (tokens, commentCount) = attach(Lexer.lex(lines))
    val items = Parser.parse(tokens)
    checkComments(items, tokens)
    val empty = items.isEmpty() && tokens.last().leading.isEmpty()
    val builder = Construction(tokens, profile)
    val parts = mutableListOf<Document>()
    var firstFunction: Pair<String, Document>? = null
    for ((i, node) in items.withIndex()) {
        if (i > 0) parts.add(builder.separator(builder.preblank(node.start)))
        val document = if (node.kind == "function") builder.function(node) else builder.declaration(node)
        if (node.kind == "function" && firstFunction == null) firstFunction = Pair(builder.tokens[node.tokens[1]].text, document)
        parts.add(document)
    }
    val closing = builder.tokens.last().leading
    if (closing.isNotEmpty()) {
        if (items.isNotEmpty()) parts.add(builder.separator(closing[0].blank)); parts.add(builder.comments(closing, null))
    }
    if (empty) return Formatted(emptyList(), firstFunction, emptyMap(), commentCount)
    val printed = Printer.print(concat(parts), profile.number("width"), profile.number("comment_column"))
    return Formatted(printed.lines, firstFunction, printed.modes, commentCount)
}
data class Source(val header: String, val name: String, val profile: String, val lines: MutableList<String> = mutableListOf())
fun inputs(): Pair<Map<String, Profile>, List<Source>> {
    val profiles = mutableMapOf<String, Profile>()
    var current = ""
    for (line in File("input/style.txt").readLines()) {
        if (line.isEmpty()) continue
        if (line.startsWith("[")) {
            current = line.substring(1, line.length - 1); profiles[current] = Profile()
        }
        else {
            val pair = line.split("=", limit = 2); profiles.getValue(current).values[pair[0]] = pair[1]
        }
    }
    val sources = mutableListOf<Source>()
    for (line in File("input/sources.txt").readLines()) {
        if (line.startsWith("=== ")) {
            val parts = line.split(" "); sources.add(Source(line, parts[1], parts[2]))
        } else sources.last().lines.add(line)
    }
    return Pair(profiles, sources)
}
fun write(name: String, lines: List<String>) {
    File("output").mkdirs()
    File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n")
}
fun main() {
    val (profiles, sources) = inputs()
    val formatted = mutableListOf<String>()
    val idempotency = mutableListOf<String>()
    val diagnostics = mutableListOf<String>()
    val docTree = mutableListOf<String>()
    val changes = mutableListOf<String>()
    for (source in sources) {
        val profile = profiles.getValue(source.profile)
        val original = source.lines.map {
            Lexer.trim(it)
        }
        formatted.add(source.header); docTree.add("=== ${source.name}"); changes.add("=== ${source.name}")
        try {
            val first = formatSource(source.lines, profile)
            formatted.addAll(first.lines)
            try {
                val second = formatSource(first.lines, profile)
                if (first.lines == second.lines) idempotency.add("${source.name}: stable")
                else {
                    val index = first.lines.zip(second.lines).indexOfFirst {
                        it.first != it.second
                    }.let {
                        if (it < 0) minOf(first.lines.size, second.lines.size) else it
                    }; idempotency.add("${source.name}: unstable at line ${index + 1}")
                }
            } catch (error: SourceError) {
                idempotency.add("${source.name}: unstable (second pass: ${error.line}:${error.column}: ${error.reason})")
            }
            val width = profile.number("width")
            for ((i, line) in first.lines.withIndex()) if (line.length > width) diagnostics.add("${source.name}:${i + 1}: warning: line too long (${line.length} > $width)")
            val longest = first.lines.maxOfOrNull {
                it.length
            } ?: 0
            val broken = first.modes.values.count {
                it != "flat"
            }
            val forced = first.modes.values.count {
                it == "forced"
            }
            docTree.add("metrics lines=${first.lines.size} longest=$longest comments=${first.comments} groups=${first.modes.size} broken=$broken forced=$forced")
            val function = first.firstFunction
            if (function == null) docTree.add("no function") else {
                docTree.add("function ${function.first}"); Report.tree(function.second, 0, first.modes, docTree)
            }
            changes.addAll(Report.diff(original, first.lines))
        } catch (error: SourceError) {
            formatted.addAll(original); idempotency.add("${source.name}: skipped (syntax error)")
            diagnostics.add("${source.name}:${error.line}:${error.column}: error: ${error.reason}")
            docTree.add("syntax error"); changes.add("skipped (syntax error)")
        }
    }
    if (diagnostics.isEmpty()) diagnostics.add("no diagnostics")
    write("formatted.txt", formatted); write("idempotency.txt", idempotency); write("diagnostics.txt", diagnostics); write("doc_tree.txt", docTree); write("changes.txt", changes)
}
