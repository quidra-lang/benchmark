sealed interface ReplacementItem {
    data class Sequence(val tokens: List<Token>) : ReplacementItem
    data class Paste(val token: Token) : ReplacementItem
}
data class Collected(val arguments: List<List<Token>>, val consumed: Int, val closing: Token)
class Expander {
    val table = mutableMapOf<String, Macro>(); val diagnostics = mutableListOf<Diagnostic>(); val uses = mutableMapOf("__COUNTER__" to 0, "__FILE__" to 0, "__LINE__" to 0); var counter = 0
    fun diagnostic(position: Position, kind: String, message: String) {
        diagnostics.add(Diagnostic(position, kind, message))
    }
    fun error(token: Token, file: String, offset: Int, message: String) {
        diagnostic(Position(file, token.line + offset), "error", message)
    }
    fun expand(tokens: List<Token>, file: String, offset: Int): List<Token> {
        val input = tokens.asReversed().toMutableList(); val result = mutableListOf<Token>()
        while (input.isNotEmpty()) {
            val token = input.removeAt(input.lastIndex)
            if (token.kind != "identifier" || token.text in token.hide) {
                result.add(token); continue
            }
            if (builtin(token.text)) {
                uses[token.text] = uses.getValue(token.text) + 1
                val kind: String; val text: String
                when (token.text) {
                    "__LINE__" -> {
                        kind = "number"; text = (token.line + offset).toString()
                    }; "__FILE__" -> {
                        kind = "string"; text = "\"$file\""
                    }; else -> {
                        kind = "number"; text = counter.toString(); counter++
                    }
                }
                result.add(Token(kind, text, token.line, token.space)); continue
            }
            val definition = table[token.text]
            if (definition == null) {
                result.add(token); continue
            }
            var hide = token.hide; var arguments: List<List<Token>> = emptyList()
            if (definition.parameters != null) {
                if (input.lastOrNull()?.text != "(") {
                    result.add(token); continue
                }
                val collected = collect(definition, input, token, file, offset)
                if (collected == null) {
                    result.add(token); continue
                }
                arguments = collected.arguments; repeat(collected.consumed) {
                    input.removeAt(input.lastIndex)
                }; hide = token.hide intersect collected.closing.hide
            }
            hide = hide + definition.name
            val replacement = substitute(definition, arguments, token, hide, file, offset); definition.expanded++
            if (replacement.isEmpty() && token.space && input.isNotEmpty()) input[input.lastIndex] = input.last().copy(space = true)
            input.addAll(replacement.asReversed())
        }
        return result
    }
    fun collect(definition: Macro, reversed: List<Token>, token: Token, file: String, offset: Int): Collected? {
        var arguments = mutableListOf(mutableListOf<Token>()); val separators = mutableListOf<Token>(); var depth = 0; var closing: Pair<Int, Token>? = null
        for ((i, current) in reversed.asReversed().withIndex().drop(1)) {
            if (current.text == ")" && depth == 0) {
                closing = Pair(i, current); break
            }
            if (current.text == "," && depth == 0) {
                separators.add(current); arguments.add(mutableListOf())
            }
            else {
                if (current.text == "(") depth++ else if (current.text == ")") depth--; arguments.last().add(current)
            }
        }
        if (closing == null) {
            error(token, file, offset, "unterminated argument list invoking macro \"${definition.name}\""); return null
        }
        val k = arguments.size; val n = definition.parameters!!.size - if (definition.variadic) 1 else 0; val emptyZero = !definition.variadic && n == 0 && k == 1 && arguments[0].isEmpty()
        val message = when {
            !definition.variadic && n == 0 && !emptyZero -> "macro \"${definition.name}\" passed $k arguments, but takes just 0"; k < n -> "macro \"${definition.name}\" requires $n arguments, but only $k given"; k > n && !definition.variadic -> "macro \"${definition.name}\" passed $k arguments, but takes just $n"; else -> null
        }
        if (message != null) {
            error(token, file, offset, message); return null
        }
        if (definition.variadic) {
            val variable = mutableListOf<Token>(); for (i in n until k) {
                if (i > n) variable.add(separators[i - 1]); variable.addAll(arguments[i])
            }; arguments = arguments.take(n).toMutableList(); arguments.add(variable)
        } else if (emptyZero) arguments = mutableListOf()
        return Collected(arguments.map {
            it.toList()
        }, closing.first + 1, closing.second)
    }
    fun stringize(tokens: List<Token>, template: Token): Token {
        val text = buildString {
            for ((i, token) in tokens.withIndex()) {
                if (i > 0 && token.space) append(' '); if (token.kind in listOf("string", "character")) {
                    for (c in token.text) {
                        if (c.code in listOf(92, 34)) append(92.toChar()); append(c)
                    }
                } else append(token.text)
            }
        }
        return Token("string", "\"$text\"", template.line, template.space)
    }
    fun paste(left: Token, right: Token, invocation: Token, file: String, offset: Int): List<Token> {
        if (left.kind == "placemarker") return listOf(right.copy(space = left.space))
        if (right.kind == "placemarker") return listOf(left)
        val text = left.text + right.text; val kind = Lexer.single(text)
        if (kind != null) return listOf(Token(kind, text, left.line, left.space, left.hide intersect right.hide))
        error(invocation, file, offset, "pasting \"${left.text}\" and \"${right.text}\" does not give a valid preprocessing token"); return listOf(left, right.copy(space = false))
    }
    fun substitute(definition: Macro, arguments: List<List<Token>>, invocation: Token, hide: Set<String>, file: String, offset: Int): List<Token> {
        val names = definition.parameters.orEmpty(); val replacement = definition.replacement; val expanded = mutableMapOf<Int, List<Token>>(); val items = mutableListOf<ReplacementItem>(); var i = 0
        while (i < replacement.size) {
            val token = replacement[i]
            if (token.text == "#" && definition.parameters != null) {
                val parameter = names.indexOf(replacement[i + 1].text); items.add(ReplacementItem.Sequence(listOf(stringize(arguments[parameter], token)))); i += 2; continue
            }
            if (token.text == "##") items.add(ReplacementItem.Paste(token))
            else if (token.kind == "identifier" && token.text in names) {
                val parameter = names.indexOf(token.text); val raw = i > 0 && replacement[i - 1].text == "##" || i + 1 < replacement.size && replacement[i + 1].text == "##"
                val sequence = if (raw) arguments[parameter] else expanded.getOrPut(parameter) {
                    expand(arguments[parameter], file, offset)
                }
                items.add(ReplacementItem.Sequence(if (sequence.isEmpty()) listOf(Token("placemarker", "", token.line, token.space)) else sequence.mapIndexed {
                    k, value -> if (k == 0) value.copy(space = token.space) else value
                }))
            } else items.add(ReplacementItem.Sequence(listOf(token)))
            i++
        }
        val output = mutableListOf<Token>(); i = 0
        while (i < items.size) {
            when (val item = items[i]) {
                is ReplacementItem.Sequence -> output.addAll(item.tokens)
                is ReplacementItem.Paste -> {
                    val left = output.removeAt(output.lastIndex); val right = when (val next = items[i + 1]) {
                        is ReplacementItem.Sequence -> next.tokens; is ReplacementItem.Paste -> listOf(next.token)
                    }; output.addAll(paste(left, right[0], invocation, file, offset)); output.addAll(right.drop(1)); i++
                }
            }
            i++
        }
        val result = mutableListOf<Token>(); var space = false
        for (token in output) {
            if (token.kind == "placemarker") {
                space = space || token.space; continue
            }; result.add(token.copy(line = invocation.line, space = token.space || space, hide = token.hide + hide)); space = false
        }
        if (result.isNotEmpty()) result[0] = result[0].copy(space = invocation.space)
        return result
    }
}
