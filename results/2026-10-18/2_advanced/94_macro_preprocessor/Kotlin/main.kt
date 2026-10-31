import java.io.File
data class Header(val name: String, val rendering: String, val quoted: Boolean, val end: Int)
fun readHeader(tokens: List<Token>, index: Int = 0): Header? {
    val token = tokens.getOrNull(index) ?: return null
    if (token.kind in listOf("string", "header")) return Header(token.text.drop(1).dropLast(1), token.text, token.kind == "string", index + 1)
    if (token.text == "<") {
        val end = (index + 1 until tokens.size).firstOrNull {
            tokens[it].text == ">"
        } ?: throw PPError("missing terminating > character")
        val name = Lexer.render(tokens.subList(index + 1, end))
        return Header(name, "<$name>", false, end + 1)
    }
    return null
}
class ConditionalBlock(val kind: String, val start: Position, val parent: Boolean) {
    var chosen = false
    var active = false
    var elseSeen = false
    var skipStart: Int? = null
}
class Inclusion(val path: String, val depth: Int) {
    var file = path
    var offset = 0
    val blocks = mutableListOf<ConditionalBlock>()
    val segment = mutableListOf<Token>()
    val active: Boolean get() = blocks.lastOrNull()?.active ?: true
    fun position(physical: Int): Position = Position(file, physical + offset)
}
class Preprocessor {
    val expander = Expander()
    val includes = IncludeManager()
    val history = mutableListOf<String>()
    val ever = mutableSetOf<String>()
    val poison = mutableSetOf<String>()
    val saves = mutableMapOf<String, MutableList<Macro?>>()
    val output = mutableListOf<String>()
    val tree = mutableListOf("main.c")
    val records = mutableListOf<String>()
    val results = mutableListOf<String>()
    val regions = mutableListOf<String>()
    var previous = Position("main.c", 0)
    fun diagnostic(position: Position, kind: String, message: String) {
        expander.diagnostic(position, kind, message)
    }
    fun event(position: Position, text: String) {
        history.add("$position: $text")
    }
    fun poisonCheck(tokens: List<Token>, state: Inclusion) {
        for (token in tokens) if (token.kind == "identifier" && token.text in poison) diagnostic(state.position(token.line), "error", "attempt to use poisoned \"${token.text}\"")
    }
    fun unused(definition: Macro) {
        if (definition.main && definition.expanded == 0 && definition.tested == 0) diagnostic(definition.position, "warning", "macro \"${definition.name}\" is not used")
    }
    fun define(tokens: List<Token>, position: Position, main: Boolean) {
        val definition = Definitions.parse(tokens, position, main)
        val name = definition.name
        val old = expander.table[name]
        if (old != null) {
            if (old.identical(definition)) {
                event(position, "identical " + definition.signature)
                return
            }
            unused(old)
            diagnostic(position, "warning", "\"$name\" redefined (previous definition at ${old.position})")
            event(position, "redefine " + definition.signature)
        } else event(position, "define " + definition.signature)
        expander.table[name] = definition
        ever.add(name)
    }
    fun undef(tokens: List<Token>, position: Position) {
        val name = Definitions.name(tokens, "undef")
        if (tokens.size > 1) diagnostic(position, "warning", "extra tokens at end of #undef directive")
        val old = expander.table.remove(name)
        if (old != null) {
            unused(old)
            event(position, "undef $name")
        } else event(position, "undef $name (not defined)")
    }
    fun marker(file: String, line: Int, flag: String = "") {
        output.add("# $line \"$file\"$flag")
        previous = Position(file, line - 1)
    }
    fun outputLine(text: String, physical: Int, state: Inclusion) {
        val position = state.position(physical)
        if (previous.file == position.file && previous.line < position.line && position.line <= previous.line + 8) repeat(position.line - previous.line - 1) {
            output.add("")
        } else marker(position.file, position.line)
        output.add(text)
        previous = position
        includes.files.getValue(state.path).output++
    }
    fun flush(state: Inclusion) {
        poisonCheck(state.segment, state)
        val tokens = expander.expand(state.segment, state.file, state.offset)
        state.segment.clear()
        var i = 0
        while (i < tokens.size) {
            var end = i + 1
            while (end < tokens.size && tokens[end].line == tokens[i].line) end++
            outputLine(Lexer.render(tokens.subList(i, end), true), tokens[i].line, state)
            i = end
        }
    }
    fun defined(name: String): Boolean {
        val definition = expander.table[name]
        if (definition != null) {
            definition.tested++
            return true
        }
        return builtin(name) || name == "__has_include"
    }
    fun replaceOperators(tokens: List<Token>): List<Token> {
        val result = mutableListOf<Token>()
        var i = 0
        while (i < tokens.size) {
            val token = tokens[i]
            if (token.kind == "identifier" && token.text == "defined") {
                i++
                val paren = tokens.getOrNull(i)?.text == "("
                if (paren) i++
                if (tokens.getOrNull(i)?.kind != "identifier") throw PPError("operator \"defined\" requires an identifier")
                val name = tokens[i++].text
                if (paren) {
                    if (tokens.getOrNull(i)?.text != ")") throw PPError("missing ')' after \"defined\"")
                    i++
                }
                result.add(Token("number", if (defined(name)) "1" else "0", token.line, token.space))
            } else if (token.kind == "identifier" && token.text == "__has_include") {
                i++
                if (tokens.getOrNull(i)?.text != "(") throw PPError("missing '(' after \"__has_include\"")
                i++
                val header = readHeader(tokens, i)
                if (header == null || header.name.isEmpty()) throw PPError("operator \"__has_include\" requires a header-name")
                i = header.end
                if (tokens.getOrNull(i)?.text != ")") throw PPError("missing ')' after \"__has_include\" operand")
                i++
                result.add(Token("number", if (IncludeManager.search(header.name, header.quoted) == null) "0" else "1", token.line, token.space))
            } else {
                result.add(token)
                i++
            }
        }
        return result
    }
    fun test(directive: String, tokens: List<Token>, position: Position, state: Inclusion): Pair<Boolean, String> {
        poisonCheck(tokens, state)
        if (directive !in listOf("if", "elif")) {
            if (tokens.isEmpty()) {
                diagnostic(position, "error", "no macro name given in #$directive directive")
                return Pair(false, "not taken (error)")
            }
            if (tokens[0].kind != "identifier") {
                diagnostic(position, "error", "macro names must be identifiers")
                return Pair(false, "not taken (error)")
            }
            if (tokens.size > 1) diagnostic(position, "warning", "extra tokens at end of #$directive directive")
            val value = defined(tokens[0].text)
            val taken = if (directive in listOf("ifndef", "elifndef")) !value else value
            return Pair(taken, if (taken) "taken" else "not taken")
        }
        val replaced: List<Token>
        try {
            replaced = replaceOperators(tokens)
        } catch (error: PPError) {
            diagnostic(position, "error", error.reason)
            return Pair(false, "not taken (error)")
        }
        val expanded = expander.expand(replaced, state.file, state.offset)
        val (value, diagnostics) = ExpressionParser.test(expanded, directive)
        for ((kind, message) in diagnostics) diagnostic(position, kind, message)
        val result = if (value == null) "not taken (error)" else (if (value != 0L) "taken" else "not taken") + " (value $value)"
        return Pair(value != null && value != 0L, result + " [" + Lexer.render(expanded, true) + "]")
    }
    fun close(block: ConditionalBlock, end: Int, state: Inclusion) {
        val start = block.skipStart
        if (start != null && end >= start) {
            regions.add("${state.file}:${start + state.offset}-${end + state.offset} lines=${end - start + 1}")
            includes.files.getValue(state.path).skippedLines += end - start + 1
        }
        block.skipStart = null
    }
    fun conditional(directive: String, operands: List<Token>, line: LogicalLine, state: Inclusion) {
        val position = state.position(line.tokens[0].line)
        val opening = directive in listOf("if", "ifdef", "ifndef")
        val level = if (opening) state.blocks.size else state.blocks.size - 1
        val result: String
        if (opening) {
            val block = ConditionalBlock(directive, position, state.active)
            if (block.parent) {
                val (taken, text) = test(directive, operands, position, state)
                block.chosen = taken
                block.active = taken
                if (!taken) block.skipStart = line.end + 1
                result = text
            } else result = "skipped"
            state.blocks.add(block)
        } else {
            val block = state.blocks.lastOrNull()
            if (block == null) {
                diagnostic(position, "error", "#$directive without #if")
                return
            }
            close(block, line.start - 1, state)
            if (directive == "endif") {
                state.blocks.removeAt(state.blocks.lastIndex)
                if (block.parent && operands.isNotEmpty()) diagnostic(position, "warning", "extra tokens at end of #endif directive")
                result = "closes #${block.kind} at line ${block.start.line}"
            }
            else {
                if (block.elseSeen) diagnostic(position, "error", "#$directive after #else")
                if (directive == "else") {
                    if (block.parent && operands.isNotEmpty()) diagnostic(position, "warning", "extra tokens at end of #else directive")
                    block.elseSeen = true
                    if (block.parent) {
                        block.active = !block.chosen
                        block.chosen = true
                        result = if (block.active) "taken" else "not taken"
                    } else result = "skipped"
                }
                else if (!block.parent) {
                    block.active = false
                    result = "skipped"
                } else if (block.chosen) {
                    block.active = false
                    result = "not evaluated"
                }
                else {
                    val (taken, text) = test(directive, operands, position, state)
                    block.active = taken
                    if (taken) block.chosen = true
                    result = text
                }
                if (block.parent && !block.active) block.skipStart = line.end + 1
            }
        }
        val rendering = "#$directive" + if (operands.isEmpty()) "" else " " + Lexer.render(operands)
        records.add("$position: " + " ".repeat(2 * level) + rendering + " => " + result)
        results.add(result)
    }
    fun include(operands: List<Token>, line: LogicalLine, state: Inclusion) {
        val position = state.position(line.tokens[0].line)
        var tokens = operands
        var header = readHeader(tokens)
        if (header == null && tokens.isNotEmpty()) {
            tokens = expander.expand(tokens, state.file, state.offset)
            header = readHeader(tokens)
        }
        val target = header ?: throw PPError("#include expects \"FILENAME\" or <FILENAME>")
        if (target.end < tokens.size) diagnostic(position, "warning", "extra tokens at end of #include directive")
        if (target.name.isEmpty()) throw PPError("empty filename in #include")
        val prefix = " ".repeat(2 * (state.depth + 1)) + "${line.tokens[0].line}: "
        val path = IncludeManager.search(target.name, target.quoted)
        if (path == null) {
            tree.add(prefix + target.rendering + " [not found]")
            throw PPError("cannot find include file " + target.rendering)
        }
        val file = includes.files[path]
        if (file != null) {
            if (file.once) {
                tree.add(prefix + path + " [skipped: pragma once]")
                file.skipped++
                return
            }
            if (file.guardName != null && file.guardName in expander.table) {
                tree.add(prefix + path + " [skipped: guard ${file.guardName}]")
                file.skipped++
                return
            }
        }
        if (state.depth + 1 > 8) {
            tree.add(prefix + path + " [too deep]")
            throw PPError("#include nested too deeply")
        }
        tree.add(prefix + path)
        marker(path, 1, " 1")
        process(path, state.depth + 1)
        marker(state.file, line.end + 1 + state.offset, " 2")
    }
    fun pragma(operands: List<Token>, line: LogicalLine, position: Position, state: Inclusion) {
        val first = operands.firstOrNull()
        if (first?.kind == "identifier" && first.text == "once") {
            if (operands.size > 1) diagnostic(position, "warning", "extra tokens at end of #pragma once directive")
            if (state.depth == 0) diagnostic(position, "warning", "#pragma once in main file")
            includes.files.getValue(state.path).once = true
        }
        else if (operands.size >= 2 && operands[0].text == "GCC" && operands[1].text == "poison") {
            if (operands.drop(2).any {
                it.kind != "identifier"
            }) throw PPError("invalid #pragma GCC poison directive")
            for (token in operands.drop(2)) {
                if (token.text in expander.table) diagnostic(position, "warning", "poisoning existing macro \"${token.text}\"")
                poison.add(token.text)
            }
        } else if (first?.kind == "identifier" && first.text in listOf("push_macro", "pop_macro")) {
            val command = first.text
            if (operands.size != 4 || operands[1].text != "(" || operands[2].kind != "string" || operands[3].text != ")") throw PPError("invalid #pragma $command directive")
            val name = operands[2].text.drop(1).dropLast(1)
            val stack = saves.getOrPut(name) {
                mutableListOf()
            }
            if (command == "push_macro") {
                stack.add(expander.table[name])
                event(position, "push $name")
            }
            else if (stack.isEmpty()) diagnostic(position, "warning", "no matching push_macro for \"$name\"")
            else {
                val old = stack.removeAt(stack.lastIndex)
                if (old == null) expander.table.remove(name) else expander.table[name] = old
                event(position, "pop $name" + if (old == null) " (undefined)" else "")
            }
        } else outputLine("#pragma" + (if (operands.isEmpty()) "" else " " + Lexer.render(operands)), line.tokens[0].line, state)
    }
    fun directive(name: String, operands: List<Token>, line: LogicalLine, state: Inclusion) {
        val position = state.position(line.tokens[0].line)
        if (line.tokens.size == 1) return
        if (!(name == "pragma" && operands.size >= 2 && operands[0].text == "GCC" && operands[1].text == "poison")) poisonCheck(operands, state)
        try {
            when (name) {
                "define" -> define(operands, position, state.depth == 0)
                "undef" -> undef(operands, position)
                "include" -> include(operands, line, state)
                "line" -> {
                    fun decimal(token: Token): Boolean = token.kind == "number" && token.text.isNotEmpty() && token.text.all {
                        it in '0'..'9'
                    }
                    val tokens = if (operands.firstOrNull()?.let {
                        decimal(it)
                    } == true) operands else expander.expand(operands, state.file, state.offset)
                    if (tokens.size !in 1..2 || !decimal(tokens[0]) || tokens.size == 2 && tokens[1].kind != "string") throw PPError("invalid #line directive")
                    val number = tokens[0].text.toLong()
                    if (number !in 1..2147483647L) throw PPError("line number out of range")
                    state.offset = number.toInt() - line.end - 1
                    if (tokens.size == 2) state.file = tokens[1].text.drop(1).dropLast(1)
                }
                "error", "warning" -> diagnostic(position, name, "#$name" + if (operands.isEmpty()) "" else " " + Lexer.render(operands))
                "pragma" -> pragma(operands, line, position, state)
                else -> throw PPError("invalid preprocessing directive #" + line.tokens[1].text)
            }
        } catch (error: PPError) {
            diagnostic(position, "error", error.reason)
        }
    }
    fun process(path: String, depth: Int) {
        val file = includes.enter(path)
        val state = Inclusion(path, depth)
        for (line in file.lines) {
            val tokens = line.tokens
            if (tokens.firstOrNull()?.text == "#") {
                val name = if (tokens.size >= 2 && tokens[1].kind == "identifier") tokens[1].text else ""
                val operands = tokens.drop(2)
                if (name in listOf("if", "ifdef", "ifndef", "elif", "elifdef", "elifndef", "else", "endif")) {
                    flush(state)
                    conditional(name, operands, line, state)
                } else if (state.active) {
                    flush(state)
                    directive(name, operands, line, state)
                }
            }
            else if (state.active) state.segment.addAll(tokens)
        }
        flush(state)
        for (block in state.blocks) close(block, file.physicalLines, state)
        for (block in state.blocks) diagnostic(block.start, "error", "unterminated #" + block.kind)
    }
    fun run() {
        for ((i, line) in File("input/defines.txt").readLines().withIndex()) {
            if (line.isEmpty()) continue
            val equals = line.indexOf('=')
            val text = if (equals < 0) "$line 1" else line.substring(0, equals) + " " + line.substring(equals + 1)
            val position = Position("defines.txt", i + 1)
            val tokens = Lexer.lex(text + "\n").flatMap {
                it.tokens
            }
            try {
                define(tokens, position, false)
            } catch (error: PPError) {
                diagnostic(position, "error", error.reason)
            }
        }
        marker("main.c", 1)
        process("main.c", 0)
        for (name in expander.table.keys.sorted()) unused(expander.table.getValue(name))
        finish()
    }
    fun finish() {
        val includeLines = (tree + listOf("", "== files ==")).toMutableList()
        for (path in includes.files.keys.sorted()) {
            val file = includes.files.getValue(path)
            includeLines.add("$path entered=${file.entered} skipped=${file.skipped} lines=${file.physicalLines} output_lines=${file.output} skipped_lines=${file.skippedLines} guard=${file.guardName ?: "-"} once=${if (file.once) "yes" else "no"}")
        }
        includeLines.add("")
        var dependency = "main.o:"
        var hasPath = false
        for (path in includes.order) {
            if (dependency.length + 1 + path.length > 76 && hasPath) {
                includeLines.add(dependency + " " + 92.toChar())
                dependency = " "
                hasPath = false
            }
            dependency += " $path"
            hasPath = true
        }
        includeLines.add(dependency)
        val table = expander.table
        val references = table.mapValues {
            (_, definition) -> val parameters = definition.parameters.orEmpty().toSet()
            definition.replacement.filter {
                it.kind == "identifier" && it.text in table && it.text !in parameters
            }.map {
                it.text
            }.distinct().sorted()
        }
        fun recursive(name: String): Boolean {
            val seen = mutableSetOf<String>()
            val pending = references.getValue(name).toMutableList()
            while (pending.isNotEmpty()) {
                val current = pending.removeAt(pending.lastIndex)
                if (current == name) return true
                if (seen.add(current)) pending.addAll(references.getValue(current))
            }
            return false
        }
        val macros = (listOf("== history ==") + history + listOf("", "== table ==")).toMutableList()
        for (name in table.keys.sorted()) {
            val definition = table.getValue(name)
            macros.addAll(listOf(definition.definition, "  at ${definition.position} expanded=${definition.expanded} tested=${definition.tested} recursive=${if (recursive(name)) "yes" else "no"}", "  refs:" + references.getValue(name).joinToString("") {
                " $it"
            }))
        }
        val functionLike = table.values.count {
            it.parameters != null
        }
        macros.addAll(listOf("", "macros=${table.size} object_like=${table.size - functionLike} function_like=$functionLike", "undefined:" + (ever - table.keys).sorted().joinToString("") {
            " $it"
        }, "builtins: __COUNTER__=${expander.uses.getValue("__COUNTER__")} __FILE__=${expander.uses.getValue("__FILE__")} __LINE__=${expander.uses.getValue("__LINE__")}"))
        fun count(prefix: String): Int = results.count {
            it.startsWith(prefix)
        }
        val conditionals = records + listOf("", "== skipped regions ==") + regions + listOf("", "directives=${records.size} taken=${count("taken")} not_taken=${count("not taken")} skipped=${count("skipped")} not_evaluated=${count("not evaluated")} endif=${count("closes")} regions=${regions.size}")
        val errors = expander.diagnostics.count {
            it.kind == "error"
        }
        val diagnostics = expander.diagnostics.map {
            "${it.position}: ${it.kind}: ${it.message}"
        } + "errors=$errors warnings=${expander.diagnostics.size - errors}"
        write("preprocessed.txt", output)
        write("includes.txt", includeLines)
        write("macros.txt", macros)
        write("conditionals.txt", conditionals)
        write("diagnostics.txt", diagnostics)
    }
}
fun write(name: String, lines: List<String>) {
    File("output").mkdirs()
    File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n")
}
fun main() {
    Preprocessor().run()
}
