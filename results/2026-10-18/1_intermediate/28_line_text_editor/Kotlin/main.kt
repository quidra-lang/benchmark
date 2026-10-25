private class CommandError(reason: String) : RuntimeException(reason)

private fun ensure(condition: Boolean, reason: String) {
    if (!condition) throw CommandError(reason)
}

private fun digit(c: Char) = c in '0'..'9'
private fun lower(c: Char) = c in 'a'..'z'
private fun upper(c: Char) = c in 'A'..'Z'
private fun digits(s: String) = s.isNotEmpty() && s.all(::digit)

private data class Atom(val character: Char, val matched: Boolean)
private data class Delimited(val text: String, val atoms: List<Atom>, val end: Int)

private fun delimited(s: String, start: Int, delimiter: Char): Delimited {
    var position = start
    val text = StringBuilder()
    val atoms = mutableListOf<Atom>()
    while (position < s.length) {
        var character = s[position++]
        if (character == delimiter) return Delimited(text.toString(), atoms.toList(), position)
        val escaped = character == '\\'
        if (escaped) {
            ensure(position < s.length, "missing delimiter")
            character = s[position++]
        }
        text.append(character)
        atoms.add(Atom(character, character == '&' && !escaped))
    }
    throw CommandError("missing delimiter")
}

private data class Token(val kind: Char, val number: Int = 0, val name: Char? = null, val search: String = "")
private data class Lexed(val tokens: List<Token>, val end: Int)

private fun lexAddresses(s: String): Lexed {
    val tokens = mutableListOf<Token>()
    var position = 0
    while (position < s.length) {
        val c = s[position]
        val token = when {
            digit(c) -> {
                val start = position
                while (position < s.length && digit(s[position])) position++
                Token('N', s.substring(start, position).toInt())
            }
            c == '+' || c == '-' -> {
                val start = ++position
                while (position < s.length && digit(s[position])) position++
                val value = if (position == start) 1 else s.substring(start, position).toInt()
                Token('O', if (c == '-') -value else value)
            }
            c in ".\$,;%" -> { position++; Token(c) }
            c == '\'' -> {
                position++
                val name = s.getOrNull(position)
                if (name != null) position++
                Token(c, name = name)
            }
            c == '/' || c == '?' -> {
                val search = delimited(s, position + 1, c)
                position = search.end
                Token(c, search = search.text)
            }
            else -> break
        }
        tokens.add(token)
    }
    return Lexed(tokens, position)
}

private fun withText(line: String): Boolean = try {
    val part = line.substring(lexAddresses(line).end)
    when {
        part == "a" || part == "i" || part == "c" -> true
        part.length >= 2 && part[0] in "gv" && part[1] !in " \\" -> {
            val rest = part.substring(delimited(part, 2, part[1]).end)
            rest == "a" || rest == "i" || rest == "c"
        }
        else -> false
    }
} catch (_: CommandError) {
    false
}

private fun validAddress(tokens: List<Token>) = tokens.withIndex().all { (i, token) ->
    token.kind == 'O' || i == 0 && token.kind in "N.\$'/?"
}

private data class Addresses(val count: Int, val left: List<Token>, val right: List<Token>, val semicolon: Boolean) {
    companion object {
        fun parse(tokens: List<Token>): Addresses {
            if (tokens.isEmpty()) return Addresses(0, emptyList(), emptyList(), false)
            if (tokens.size == 1 && tokens[0].kind == '%')
                return Addresses(2, listOf(Token('N', 1)), listOf(Token('$')), false)
            val separators = tokens.indices.filter { tokens[it].kind in ",;" }
            ensure(separators.size <= 1, "bad address")
            val separator = separators.firstOrNull()
            val left = if (separator == null) tokens else tokens.subList(0, separator)
            val right = if (separator == null) emptyList() else tokens.subList(separator + 1, tokens.size)
            ensure(validAddress(left) && validAddress(right), "bad address")
            return Addresses(if (separator == null) 1 else 2, left, right, separator != null && tokens[separator].kind == ';')
        }
    }
}

private enum class Kind {
    EMPTY, APPEND, INSERT, CHANGE, PRINT, NUMBER, LIST, EQUALS, COUNT, YANK, MARKS, HISTORY, FILES,
    DELETE, PUT, JOIN, JOIN_SPACE, PAGE, INDENT, UNINDENT, UNDO, REDO, CASE, READ, WRITE,
    WRITE_APPEND, EDIT, WRITE_PRINT, MARK, MOVE, COPY, SUBSTITUTE, GLOBAL, INVERSE, SORT
}

private fun printSuffix(s: String): Char? {
    ensure(s.isEmpty() || s.length == 1 && s[0] in "pnl", "invalid suffix")
    return s.firstOrNull()
}

private fun positive(s: String): Int {
    if (s.isEmpty()) return 0
    ensure(digits(s), "invalid suffix")
    val value = s.toInt()
    ensure(value > 0, "invalid suffix")
    return value
}

private fun filename(s: String): String {
    ensure(s.length in 2..9 && s[0] == ' ', "invalid file name")
    val name = s.substring(1)
    ensure(name.all { lower(it) || digit(it) }, "invalid file name")
    return name
}

private fun sortForm(s: String) = s == "sort" || s.startsWith("sort ")

private class Command(var kind: Kind = Kind.EMPTY) {
    var number = 0
    var suffix: Char? = null
    var option: Char? = null
    var name = ""
    var search = ""
    var destination: List<Token> = emptyList()
    var replacement: List<Atom>? = null
    var all = false
    var reverse = false
    var unique = false
    var insensitive = false
    var numeric = false
    var sub: Command? = null

    companion object {
        fun parse(part: String): Command {
            val c = Command()
            if (sortForm(part)) {
                c.kind = Kind.SORT
                ensure(part != "sort ", "invalid suffix")
                val options = if (part.length > 4) part.substring(5) else ""
                for (option in options) {
                    when (option) {
                        'r' -> { ensure(!c.reverse, "invalid suffix"); c.reverse = true }
                        'u' -> { ensure(!c.unique, "invalid suffix"); c.unique = true }
                        'i' -> { ensure(!c.insensitive, "invalid suffix"); c.insensitive = true }
                        'n' -> { ensure(!c.numeric, "invalid suffix"); c.numeric = true }
                        else -> throw CommandError("invalid suffix")
                    }
                }
                ensure(!c.insensitive || !c.numeric, "invalid suffix")
                return c
            }
            if (part.isEmpty()) return c
            val first = part[0]
            val arg = part.substring(1)
            val kinds = listOf(Kind.APPEND, Kind.INSERT, Kind.CHANGE, Kind.PRINT, Kind.NUMBER, Kind.LIST,
                Kind.EQUALS, Kind.COUNT, Kind.YANK, Kind.MARKS, Kind.HISTORY, Kind.FILES)
            val index = "aicpnl=#yKhf".indexOf(first)
            if (index >= 0) {
                c.kind = kinds[index]
                ensure(arg.isEmpty(), "invalid suffix")
                return c
            }
            when (first) {
                'd', 'x', 'j', 'J' -> {
                    c.kind = when (first) { 'd' -> Kind.DELETE; 'x' -> Kind.PUT; 'j' -> Kind.JOIN; else -> Kind.JOIN_SPACE }
                    c.suffix = printSuffix(arg)
                }
                'z', '>', '<', 'u' -> {
                    c.kind = when (first) { 'z' -> Kind.PAGE; '>' -> Kind.INDENT; '<' -> Kind.UNINDENT; else -> Kind.UNDO }
                    c.number = positive(arg)
                }
                '~' -> {
                    c.kind = Kind.CASE
                    ensure(arg.isEmpty() || arg == "u" || arg == "l", "invalid suffix")
                    c.option = arg.firstOrNull()
                }
                'r' -> {
                    if (arg.isEmpty() || digits(arg)) { c.kind = Kind.REDO; c.number = positive(arg) }
                    else { c.kind = Kind.READ; c.name = filename(arg) }
                }
                'w', 'W', 'e' -> {
                    if (first == 'w' && arg.isEmpty()) c.kind = Kind.WRITE_PRINT
                    else {
                        c.kind = when (first) { 'w' -> Kind.WRITE; 'W' -> Kind.WRITE_APPEND; else -> Kind.EDIT }
                        c.name = filename(arg)
                    }
                }
                'k' -> {
                    c.kind = Kind.MARK
                    ensure(arg.length == 1 && lower(arg[0]), "invalid mark")
                    c.option = arg[0]
                }
                'm', 't' -> {
                    c.kind = if (first == 'm') Kind.MOVE else Kind.COPY
                    val destination = lexAddresses(arg)
                    ensure(destination.tokens.isNotEmpty() && validAddress(destination.tokens), "invalid destination")
                    c.destination = destination.tokens
                    c.suffix = printSuffix(arg.substring(destination.end))
                }
                's' -> {
                    c.kind = Kind.SUBSTITUTE
                    c.number = 1
                    val repeated = arg.all { it in "gpnl" || digit(it) }
                    var position = 0
                    if (!repeated) {
                        val delimiter = arg[0]
                        ensure(delimiter !in " \\", "missing delimiter")
                        val search = delimited(arg, 1, delimiter)
                        val replacement = delimited(arg, search.end, delimiter)
                        c.search = search.text
                        if (arg.substring(search.end, replacement.end - 1) != "%") c.replacement = replacement.atoms
                        position = replacement.end
                    }
                    var counted = false
                    while (position < arg.length) {
                        val flag = arg[position++]
                        when {
                            flag == 'g' -> { ensure(!c.all, "invalid suffix"); c.all = true }
                            flag in "pnl" -> { ensure(c.suffix == null, "invalid suffix"); c.suffix = flag }
                            digit(flag) -> {
                                ensure(!counted, "invalid suffix")
                                counted = true
                                val start = position - 1
                                while (position < arg.length && digit(arg[position])) position++
                                c.number = arg.substring(start, position).toInt()
                                ensure(c.number > 0, "invalid suffix")
                            }
                            else -> throw CommandError("invalid suffix")
                        }
                    }
                }
                'g', 'v' -> {
                    c.kind = if (first == 'g') Kind.GLOBAL else Kind.INVERSE
                    ensure(arg.isNotEmpty() && arg[0] !in " \\", "missing delimiter")
                    val search = delimited(arg, 1, arg[0])
                    c.search = search.text
                    val body = arg.substring(search.end).ifEmpty { "p" }
                    ensure(body[0] in "pnldmtjJs><~aicx" && !sortForm(body), "invalid global command")
                    c.sub = parse(body)
                }
                else -> throw CommandError("unknown command")
            }
            return c
        }
    }

    fun addressKind() = when (kind) {
        Kind.UNDO, Kind.REDO, Kind.HISTORY, Kind.MARKS, Kind.FILES, Kind.EDIT -> 0
        Kind.APPEND, Kind.INSERT, Kind.PUT, Kind.EQUALS, Kind.READ, Kind.MARK, Kind.PAGE -> 1
        else -> 2
    }

    fun modifying(): Boolean = when (kind) {
        Kind.APPEND, Kind.INSERT, Kind.CHANGE, Kind.DELETE, Kind.PUT, Kind.JOIN, Kind.JOIN_SPACE,
        Kind.MOVE, Kind.COPY, Kind.SUBSTITUTE, Kind.INDENT, Kind.UNINDENT, Kind.CASE, Kind.SORT, Kind.READ, Kind.EDIT -> true
        Kind.GLOBAL, Kind.INVERSE -> sub!!.modifying()
        else -> false
    }
}

private data class Line(val id: Long, val text: String)
private data class Snapshot(val buffer: List<Line>, val current: Int)
private data class HistoryRecord(val command: String, val state: Snapshot)
private data class Range(val first: Int, val last: Int)

private class State(
    var buffer: MutableList<Line> = mutableListOf(),
    var current: Int = 0,
    val marks: LongArray = LongArray(26),
    var cut: List<String> = emptyList(),
    var pattern: String? = null,
    var replacement: List<Atom>? = null,
    var display: Int = 5,
    val undo: MutableList<HistoryRecord> = mutableListOf(),
    val redo: MutableList<HistoryRecord> = mutableListOf(),
    val files: MutableMap<String, List<String>> = mutableMapOf(),
    var nextId: Long = 1
) {
    fun fork() = State(buffer.toMutableList(), current, marks.copyOf(), cut, pattern, replacement, display,
        undo.toMutableList(), redo.toMutableList(), files.toMutableMap(), nextId)

    fun snapshot() = Snapshot(buffer.toList(), current)
    fun locate(id: Long) = buffer.indexOfFirst { it.id == id } + 1

    fun resolvePattern(search: String): String {
        if (search.isNotEmpty()) pattern = search
        return pattern ?: throw CommandError("no previous pattern")
    }

    fun address(tokens: List<Token>): Int {
        var value = current
        for (token in tokens) {
            when (token.kind) {
                'O' -> value += token.number
                'N' -> value = token.number
                '.' -> value = current
                '$' -> value = buffer.size
                '\'' -> {
                    val name = token.name?.takeIf(::lower) ?: throw CommandError("invalid mark")
                    value = locate(marks[name - 'a'])
                    ensure(value != 0, "mark not set")
                }
                '/', '?' -> {
                    val pattern = resolvePattern(token.search)
                    val size = buffer.size
                    val start = if (token.kind == '?' && current == 0) size + 1 else current
                    value = 0
                    for (step in 1..size) {
                        val index = if (token.kind == '/') (start + step - 1) % size else (start - step - 1).mod(size)
                        if (pattern in buffer[index].text) { value = index + 1; break }
                    }
                    ensure(value != 0, "no match")
                }
                else -> error("Invalid address token")
            }
        }
        return value
    }

    fun evaluate(addresses: Addresses): Range {
        if (addresses.count == 0) return Range(0, 0)
        val a = if (addresses.left.isEmpty()) { if (addresses.semicolon) current else 1 } else address(addresses.left)
        var b = 0
        if (addresses.count == 2) {
            if (addresses.semicolon) {
                ensure(a in 0..buffer.size, "address out of range")
                current = a
            }
            b = if (addresses.right.isEmpty()) buffer.size else address(addresses.right)
        }
        return Range(a, b)
    }

    fun checkedRange(c: Command, count: Int, values: Range): Range {
        val size = buffer.size
        var a = values.first
        var b = values.last
        if (c.addressKind() == 0) return Range(0, 0)
        if (c.addressKind() == 1) {
            if (count == 0) a = when (c.kind) {
                Kind.EQUALS, Kind.READ -> size
                Kind.PAGE -> current + 1
                else -> current
            }
            val minimum = if (c.kind == Kind.MARK || c.kind == Kind.PAGE) 1 else 0
            ensure(a in minimum..size, "address out of range")
            return Range(a, a)
        }
        if (count == 0) {
            when (c.kind) {
                Kind.WRITE, Kind.WRITE_APPEND, Kind.WRITE_PRINT, Kind.COUNT -> return Range(1, size)
                Kind.GLOBAL, Kind.INVERSE, Kind.SORT -> { a = 1; b = size }
                Kind.JOIN, Kind.JOIN_SPACE -> { a = current; b = current + 1 }
                else -> { a = current; b = current }
            }
        } else if (count == 1) b = a
        ensure(a in 1..size && b in 1..size, "address out of range")
        ensure(a <= b && (a != b || c.kind != Kind.JOIN && c.kind != Kind.JOIN_SPACE), "invalid range")
        return Range(a, b)
    }

    fun printLine(number: Int, form: Char, output: StringBuilder) {
        val text = buffer[number - 1].text
        when (form) {
            'n' -> output.appendLine("${number.toString().padStart(3)} $text")
            'l' -> {
                val escaped = text.replace("\\", "\\\\") + '$'
                var position = 0
                while (escaped.length - position > 40) {
                    output.append(escaped, position, position + 39).appendLine('\\')
                    position += 39
                }
                output.appendLine(escaped.substring(position))
            }
            else -> output.appendLine(text)
        }
    }

    fun contents(range: Range) = buffer.subList(range.first - 1, range.last).map { it.text }

    fun insert(after: Int, text: List<String>) {
        val lines = text.map { Line(nextId++, it) }
        buffer.addAll(after, lines)
    }

    fun setText(index: Int, text: String) { buffer[index] = buffer[index].copy(text = text) }

    fun substitute(c: Command, range: Range, output: StringBuilder, inGlobal: Boolean): Boolean {
        val pattern = resolvePattern(c.search)
        val used = c.replacement ?: replacement ?: throw CommandError("no previous substitution")
        replacement = used
        val expanded = buildString {
            for (atom in used) {
                if (atom.matched) append(pattern) else append(atom.character)
            }
        }
        var last = 0
        for (i in range.first..range.last) {
            val old = buffer[i - 1].text
            val result = StringBuilder()
            var position = 0
            var occurrence = 0
            var changed = false
            while (true) {
                val start = old.indexOf(pattern, position)
                if (start < 0) break
                result.append(old, position, start)
                occurrence++
                if (occurrence == c.number || c.all && occurrence > c.number) {
                    result.append(expanded)
                    changed = true
                } else result.append(pattern)
                position = start + pattern.length
            }
            result.append(old, position, old.length)
            if (changed) {
                ensure(result.length <= 80, "line too long")
                ensure(result.isNotEmpty() && result.last() != ' ', "bad line")
                setText(i - 1, result.toString())
                last = i
            }
        }
        ensure(last != 0 || inGlobal, "no match")
        if (last != 0) {
            current = last
            c.suffix?.let { printLine(last, it, output) }
        }
        return last != 0
    }

    fun sortLines(c: Command, range: Range) {
        val key: Comparator<Line> = if (c.numeric) compareBy { leadingInteger(it.text) }
            else compareBy { if (c.insensitive) it.text.lowercase() else it.text }
        val sorted = buffer.subList(range.first - 1, range.last).sortedWith(if (c.reverse) key.reversed() else key)
        val kept = if (c.unique) {
            val unique = mutableListOf<Line>()
            for (line in sorted) if (unique.isEmpty() || key.compare(unique.last(), line) != 0) unique.add(line)
            unique
        } else sorted
        buffer.subList(range.first - 1, range.last).clear()
        buffer.addAll(range.first - 1, kept)
        current = range.first + kept.size - 1
    }

    fun fileCommand(c: Command, range: Range, output: StringBuilder) {
        val file = if (c.kind == Kind.WRITE || c.kind == Kind.WRITE_APPEND) {
            val saved = if (c.kind == Kind.WRITE_APPEND) files[c.name].orEmpty() else emptyList()
            (saved + contents(range)).also { files[c.name] = it }
        } else {
            val saved = files[c.name] ?: throw CommandError("no such file")
            val after = if (c.kind == Kind.EDIT) { buffer.clear(); 0 } else range.first
            insert(after, saved)
            current = after + saved.size
            saved
        }
        output.appendLine("file ${c.name} lines=${file.size} bytes=${fileBytes(file)}")
    }

    fun transferHistory(isRedo: Boolean, count: Int) {
        val from = if (isRedo) redo else undo
        val to = if (isRedo) undo else redo
        ensure(from.size >= count, if (isRedo) "nothing to redo" else "nothing to undo")
        repeat(count) {
            val record = from.removeAt(from.lastIndex)
            to.add(HistoryRecord(record.command, snapshot()))
            buffer = record.state.buffer.toMutableList()
            current = record.state.current
        }
    }

    fun execute(c: Command, range: Range, text: List<String>, output: StringBuilder, inGlobal: Boolean): Boolean {
        val (a, b) = range
        when (c.kind) {
            Kind.EMPTY -> { printLine(b, 'p', output); current = b }
            Kind.PRINT, Kind.NUMBER, Kind.LIST -> {
                val form = when (c.kind) { Kind.PRINT -> 'p'; Kind.NUMBER -> 'n'; else -> 'l' }
                for (i in a..b) printLine(i, form, output)
                current = b
            }
            Kind.PAGE -> {
                if (c.number != 0) display = c.number
                val last = minOf(a + display - 1, buffer.size)
                for (i in a..last) printLine(i, 'p', output)
                current = last
            }
            Kind.EQUALS -> output.appendLine(a)
            Kind.COUNT, Kind.WRITE_PRINT -> {
                var words = 0
                var chars = 0
                for (i in a..b) {
                    val value = buffer[i - 1].text
                    chars += value.length
                    for (j in value.indices) if (value[j] != ' ' && (j == 0 || value[j - 1] == ' ')) words++
                    if (c.kind == Kind.WRITE_PRINT) printLine(i, 'p', output)
                }
                val count = b - a + 1
                if (c.kind == Kind.COUNT) output.appendLine("count lines=$count words=$words chars=$chars")
                else output.appendLine("lines=$count bytes=${chars + count}")
            }
            Kind.APPEND, Kind.INSERT -> {
                val after = if (c.kind == Kind.APPEND) a else maxOf(a, 1) - 1
                insert(after, text)
                current = after + text.size
            }
            Kind.CHANGE, Kind.DELETE -> {
                cut = contents(range)
                buffer.subList(a - 1, b).clear()
                if (c.kind == Kind.CHANGE) insert(a - 1, text)
                current = if (c.kind == Kind.CHANGE && text.isNotEmpty()) a + text.size - 1 else minOf(a, buffer.size)
            }
            Kind.YANK -> cut = contents(range)
            Kind.PUT -> {
                ensure(cut.isNotEmpty(), "nothing to put")
                insert(a, cut)
                current = a + cut.size
            }
            Kind.MOVE, Kind.COPY -> {
                var destination = address(c.destination)
                ensure(destination in 0..buffer.size, "address out of range")
                ensure(c.kind != Kind.MOVE || destination < a || destination >= b, "invalid destination")
                val moved = buffer.subList(a - 1, b).toMutableList()
                if (c.kind == Kind.MOVE) {
                    buffer.subList(a - 1, b).clear()
                    if (destination >= b) destination -= moved.size
                } else {
                    for (i in moved.indices) moved[i] = moved[i].copy(id = nextId++)
                }
                buffer.addAll(destination, moved)
                current = destination + moved.size
            }
            Kind.JOIN, Kind.JOIN_SPACE -> {
                val joined = buildString {
                    append(buffer[a - 1].text)
                    for (i in a + 1..b) {
                        val value = buffer[i - 1].text
                        if (c.kind == Kind.JOIN_SPACE) { append(' '); append(value.trimStart(' ')) }
                        else append(value)
                    }
                }
                ensure(joined.length <= 80, "line too long")
                setText(a - 1, joined)
                buffer.subList(a, b).clear()
                current = a
            }
            Kind.INDENT, Kind.UNINDENT, Kind.CASE -> {
                val width = if (c.number == 0) 4 else c.number
                for (i in a..b) {
                    val old = buffer[i - 1].text
                    val value = when (c.kind) {
                        Kind.INDENT -> {
                            ensure(old.length + width <= 80, "line too long")
                            " ".repeat(width) + old
                        }
                        Kind.UNINDENT -> old.drop(minOf(width, old.takeWhile { it == ' ' }.length))
                        else -> buildString {
                            for (character in old) append(when {
                                lower(character) && c.option != 'l' -> character.uppercaseChar()
                                upper(character) && c.option != 'u' -> character.lowercaseChar()
                                else -> character
                            })
                        }
                    }
                    setText(i - 1, value)
                }
                current = b
            }
            Kind.SORT -> sortLines(c, range)
            Kind.SUBSTITUTE -> return substitute(c, range, output, inGlobal)
            Kind.MARK -> marks[c.option!! - 'a'] = buffer[a - 1].id
            Kind.MARKS -> {
                output.append("marks")
                var any = false
                for (name in marks.indices) {
                    val position = locate(marks[name])
                    if (position != 0) { output.append(" ${'a' + name}=$position"); any = true }
                }
                output.appendLine(if (any) "" else " none")
            }
            Kind.UNDO, Kind.REDO -> transferHistory(c.kind == Kind.REDO, if (c.number == 0) 1 else c.number)
            Kind.HISTORY -> {
                output.appendLine("history undo=${undo.size} redo=${redo.size}")
                for ((name, records) in listOf("undo" to undo, "redo" to redo)) {
                    for ((i, record) in records.asReversed().withIndex()) output.appendLine("$name ${i + 1}: ${record.command}")
                }
            }
            Kind.READ, Kind.WRITE, Kind.WRITE_APPEND, Kind.EDIT -> fileCommand(c, range, output)
            Kind.FILES -> {
                output.append("files")
                for (name in files.keys.sorted()) output.append(" $name=${files.getValue(name).size}")
                output.appendLine(if (files.isEmpty()) " none" else "")
            }
            Kind.GLOBAL, Kind.INVERSE -> {
                val pattern = resolvePattern(c.search)
                val selected = buffer.subList(a - 1, b).filter { (pattern in it.text) == (c.kind == Kind.GLOBAL) }.map { it.id }
                ensure(selected.isNotEmpty(), "no match")
                val sub = c.sub!!
                var substituted = false
                for (id in selected) {
                    val position = locate(id)
                    if (position != 0) {
                        current = position
                        val subrange = checkedRange(sub, 0, Range(0, 0))
                        val changed = execute(sub, subrange, text, output, true)
                        substituted = substituted || changed
                    }
                }
                ensure(sub.kind != Kind.SUBSTITUTE || substituted, "no match")
            }
        }
        c.suffix?.let { if (current >= 1) printLine(current, it, output) }
        return false
    }
}

private fun leadingInteger(text: String): Long {
    val negative = text.startsWith('-')
    var position = if (negative) 1 else 0
    var value = 0L
    while (position < text.length && digit(text[position])) value = value * 10 + (text[position++] - '0')
    return if (negative) -value else value
}

private fun fileBytes(file: List<String>) = file.sumOf { it.length + 1 }

private class Editor {
    private var state = State()

    fun apply(line: String, text: List<String>): String {
        val lexed = lexAddresses(line)
        val addresses = Addresses.parse(lexed.tokens)
        val command = Command.parse(line.substring(lexed.end))
        ensure(command.addressKind() != 0 || addresses.count == 0, "unexpected address")
        ensure(command.addressKind() != 1 || addresses.count != 2, "too many addresses")
        val trial = state.fork()
        val values = trial.evaluate(addresses)
        val range = trial.checkedRange(command, addresses.count, values)
        val output = StringBuilder()
        trial.execute(command, range, text, output, false)
        ensure(trial.buffer.size <= 200, "buffer full")
        if (command.modifying()) {
            trial.undo.add(HistoryRecord(line, state.snapshot()))
            trial.redo.clear()
        }
        state = trial
        return output.toString()
    }
}

fun main() {
    val input = System.`in`.bufferedReader(Charsets.US_ASCII)
    val output = System.out.bufferedWriter(Charsets.US_ASCII)
    val editor = Editor()
    while (true) {
        val line = input.readLine() ?: break
        if (line == "Q") break
        val text = mutableListOf<String>()
        if (withText(line)) {
            while (true) {
                val entered = input.readLine() ?: break
                if (entered == ".") break
                text.add(entered)
            }
        }
        try {
            output.write(editor.apply(line, text))
        } catch (error: CommandError) {
            output.write("? ${error.message}\n")
        }
    }
    output.flush()
}
