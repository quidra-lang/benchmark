private sealed interface Value
private data object Absent : Value
private data class Text(val value: String) : Value
private data class NumberValue(val value: Long) : Value
private data class BooleanValue(val value: Boolean) : Value
private data class ListValue(val values: List<Value>) : Value
private data class MapValue(val values: Map<String, Value>) : Value
private class Problem(val reason: String, val line: Int = 0) : RuntimeException(reason)

private fun identifier(s: String) = s.matches(Regex("[A-Za-z_][A-Za-z_0-9]*"))
private fun subscript(s: String) = s.matches(Regex("0|[1-9][0-9]*"))
private fun integerArgument(s: String): Long? = if (s.matches(Regex("-?[0-9]{1,9}"))) s.toLong() else null
private sealed interface Part
private data class Key(val name: String) : Part
private data class Index(val index: Int) : Part
private data class KeyPart(val part: Part, val prefix: String)
private fun keyParts(s: String): List<KeyPart>? {
    var at = 0
    val parts = mutableListOf<KeyPart>()
    while (true) {
        val start = at
        while (at < s.length && (s[at] in 'A'..'Z' || s[at] in 'a'..'z' || s[at] in '0'..'9' || s[at] == '_')) at++
        if (!identifier(s.substring(start, at))) return null
        parts.add(KeyPart(Key(s.substring(start, at)), s.substring(0, at)))
        while (true) {
            if (at == s.length) return parts
            if (s[at] == '.') { at++; break }
            if (s[at] != '[') return null
            val end = s.indexOf(']', at + 1)
            if (end < 0 || !subscript(s.substring(at + 1, end))) return null
            val index = s.substring(at + 1, end).toIntOrNull() ?: return null
            at = end + 1
            parts.add(KeyPart(Index(index), s.substring(0, at)))
        }
    }
}
private class ValueParser(private val text: String) {
    private var at = 0
    private fun scalar(): Value? {
        if (text.getOrNull(at) == '"') {
            at++
            val s = StringBuilder()
            while (at < text.length) {
                when (val c = text[at++]) {
                    '"' -> return Text(s.toString())
                    '\\' -> {
                        if (at == text.length) return null
                        s.append(when (text[at++]) { '"' -> '"'; '\\' -> '\\'; 'n' -> '\n'; else -> return null })
                    }
                    else -> s.append(c)
                }
            }
            return null
        }
        val start = at
        while (at < text.length && text[at] != ',' && text[at] != ']') at++
        val word = text.substring(start, at)
        return when (word) {
            "true" -> BooleanValue(true)
            "false" -> BooleanValue(false)
            else -> if (word != "-0" && subscript(word.removePrefix("-"))) word.toLongOrNull()?.let(::NumberValue) else null
        }
    }
    fun parse(): Value? {
        if (text == "{}") return MapValue(emptyMap())
        if (text == "[]") return ListValue(emptyList())
        if (text.startsWith('[')) {
            at = 1
            val list = mutableListOf<Value>()
            while (true) {
                list.add(scalar() ?: return null)
                if (text.getOrNull(at) == ']') return if (at + 1 == text.length) ListValue(list) else null
                if (!text.startsWith(", ", at)) return null
                at += 2
            }
        }
        val value = scalar()
        return if (at == text.length) value else null
    }
}
private fun child(value: Value, part: Part): Value? = when {
    value is MapValue && part is Key -> value.values[part.name]
    value is ListValue && part is Index -> value.values.getOrNull(part.index)
    else -> null
}
private fun assign(container: Value, parts: List<KeyPart>, at: Int, value: Value): Value {
    val (part, prefix) = parts[at]
    if (container is ListValue && part is Index && part.index > container.values.size) throw Problem("index gap at '$prefix'")
    val next = if (at == parts.lastIndex) value else {
        val mapNeeded = parts[at + 1].part is Key
        val old = child(container, part) ?: if (mapNeeded) MapValue(emptyMap()) else ListValue(emptyList())
        if ((mapNeeded && old !is MapValue) || (!mapNeeded && old !is ListValue)) throw Problem("type conflict at '$prefix'")
        assign(old, parts, at + 1, value)
    }
    return when {
        container is MapValue && part is Key -> MapValue(container.values + (part.name to next))
        container is ListValue && part is Index -> {
            val list = container.values.toMutableList()
            if (part.index == list.size) list.add(next) else list[part.index] = next
            ListValue(list)
        }
        else -> error("invalid container")
    }
}
private fun remove(container: Value, parts: List<KeyPart>, at: Int): Value? {
    val part = parts[at].part
    val old = child(container, part) ?: return null
    if (at == parts.lastIndex) return when {
        container is MapValue && part is Key -> MapValue(container.values - part.name)
        container is ListValue && part is Index -> ListValue(container.values.toMutableList().also { it.removeAt(part.index) })
        else -> null
    }
    val next = remove(old, parts, at + 1) ?: return null
    return when {
        container is MapValue && part is Key -> MapValue(container.values + (part.name to next))
        container is ListValue && part is Index -> ListValue(container.values.toMutableList().also { it[part.index] = next })
        else -> null
    }
}
private fun stringify(v: Value): String = when (v) {
    Absent -> ""
    is Text -> v.value
    is NumberValue -> v.value.toString()
    is BooleanValue -> v.value.toString()
    is ListValue -> v.values.joinToString(", ", transform = ::stringify)
    is MapValue -> throw Problem("cannot render map")
}
private fun truthy(v: Value): Boolean = when (v) {
    Absent -> false
    is Text -> v.value.isNotEmpty()
    is NumberValue -> v.value != 0L
    is BooleanValue -> v.value
    is ListValue -> v.values.isNotEmpty()
    is MapValue -> v.values.isNotEmpty()
}
private fun number(v: Value, f: String): Long = when (v) {
    Absent -> 0L
    is NumberValue -> v.value
    is Text -> integerArgument(v.value) ?: throw Problem("not a number for '$f'")
    else -> throw Problem("not a number for '$f'")
}
private fun quotedSplit(s: String, separator: Char): List<String> {
    var quoted = false
    var start = 0
    val pieces = mutableListOf<String>()
    for ((i, c) in s.withIndex()) {
        if (c == '\'') quoted = !quoted
        if (c == separator && !quoted) { pieces.add(s.substring(start, i)); start = i + 1 }
    }
    pieces.add(s.substring(start))
    return pieces
}
private fun validName(s: String) = s == "." || s in setOf("@index", "@number", "@first", "@last") || s.split('.').all { identifier(it) || subscript(it) }
private data class Filter(val name: String, val args: List<Value>)
private data class Expression(val name: String, val filters: List<Filter>)
private fun expression(s: String): Expression {
    val pieces = quotedSplit(s, '|')
    val name = pieces[0].trim(' ')
    if (!validName(name)) throw Problem("invalid name '$name'")
    val noArgs = setOf("upper", "lower", "title", "trim", "length", "first", "last", "reverse", "items", "comma", "sum", "min", "max")
    val others = setOf("default", "eq", "pad", "lpad", "truncate", "replace", "join", "sort", "pluck", "add", "sub", "mul", "div", "mod", "gt", "lt")
    val filters = pieces.drop(1).map { piece ->
        val items = quotedSplit(piece.trim(' '), ':')
        val f = items[0]
        if (f !in noArgs && f !in others) throw Problem("unknown filter '$f'")
        val args = items.drop(1).map { arg ->
            if (arg.length >= 2 && arg.first() == '\'' && arg.last() == '\'' && '\'' !in arg.substring(1, arg.lastIndex)) Text(arg.substring(1, arg.lastIndex))
            else integerArgument(arg)?.let(::NumberValue) ?: throw Problem("bad arguments for '$f'")
        }
        fun n(i: Int) = (args.getOrNull(i) as? NumberValue)?.value
        fun t(i: Int) = (args.getOrNull(i) as? Text)?.value
        val valid = if (f in noArgs) args.isEmpty() else when (f) {
            "default", "eq" -> args.size == 1
            "pad", "lpad" -> args.size in 1..2 && (n(0) ?: -1L) >= 0 && (args.size == 1 || t(1)?.length == 1)
            "truncate" -> args.size == 1 && (n(0) ?: -1L) >= 0
            "replace" -> args.size == 2 && !t(0).isNullOrEmpty() && t(1) != null
            "join", "pluck" -> args.size == 1 && t(0) != null
            "sort" -> args.isEmpty() || (args.size == 1 && t(0) != null)
            "div", "mod" -> args.size == 1 && n(0) != null && n(0) != 0L
            else -> args.size == 1 && n(0) != null
        }
        if (!valid) throw Problem("bad arguments for '$f'")
        Filter(f, args)
    }
    return Expression(name, filters)
}
private fun sortCompare(a: Value, b: Value): Int {
    fun rank(v: Value) = when (v) { Absent -> 0; is NumberValue -> 1; is Text -> 2; is BooleanValue -> 3; else -> 4 }
    val order = rank(a).compareTo(rank(b))
    if (order != 0) return order
    return when {
        a is NumberValue && b is NumberValue -> a.value.compareTo(b.value)
        a is Text && b is Text -> a.value.compareTo(b.value)
        a is BooleanValue && b is BooleanValue -> a.value.compareTo(b.value)
        else -> 0
    }
}
private fun applyFilter(v: Value, f: Filter): Value {
    val name = f.name
    fun n() = (f.args[0] as NumberValue).value
    fun s(i: Int) = (f.args[i] as Text).value
    return when (name) {
        "default" -> if (truthy(v)) v else f.args[0]
        "eq" -> BooleanValue(stringify(v) == stringify(f.args[0]))
        "length" -> NumberValue((when (v) { is ListValue -> v.values.size; is MapValue -> v.values.size; else -> stringify(v).length }).toLong())
        "first", "last" -> if (v is ListValue) (if (name == "first") v.values.firstOrNull() else v.values.lastOrNull()) ?: Absent else v
        "reverse" -> when (v) { is ListValue -> ListValue(v.values.reversed()); is Text -> Text(v.value.reversed()); else -> v }
        "items" -> if (v is MapValue) ListValue(v.values.toSortedMap().map { (k, value) -> MapValue(mapOf("key" to Text(k), "value" to value)) }) else v
        "sort" -> if (v is ListValue) {
            fun key(value: Value) = if (f.args.isEmpty()) value else (value as? MapValue)?.values?.get(s(0)) ?: Absent
            ListValue(v.values.sortedWith { a, b -> sortCompare(key(a), key(b)) })
        } else v
        "pluck" -> if (v is ListValue) ListValue(v.values.map { (it as? MapValue)?.values?.get(s(0)) ?: Absent }) else v
        "sum", "min", "max" -> if (v is ListValue) {
            val numbers = v.values.map { number(it, name) }
            when (name) { "sum" -> NumberValue(numbers.sum()); "min" -> numbers.minOrNull()?.let(::NumberValue) ?: Absent; else -> numbers.maxOrNull()?.let(::NumberValue) ?: Absent }
        } else NumberValue(number(v, name))
        "add", "sub", "mul", "div", "mod", "gt", "lt" -> {
            val a = number(v, name)
            val b = n()
            fun floor(): Long { val q = a / b; return if (a % b != 0L && (a < 0) != (b < 0)) q - 1 else q }
            when (name) { "add" -> NumberValue(a+b); "sub" -> NumberValue(a-b); "mul" -> NumberValue(a*b); "div" -> NumberValue(floor()); "mod" -> NumberValue(a-b*floor()); "gt" -> BooleanValue(a>b); else -> BooleanValue(a<b) }
        }
        "comma" -> {
            val a = number(v, name)
            val digits = kotlin.math.abs(a).toString()
            Text((if (a < 0) "-" else "") + digits.mapIndexed { i, c -> (if (i > 0 && (digits.length-i)%3 == 0) "," else "") + c }.joinToString(""))
        }
        "join" -> Text(if (v is ListValue) v.values.joinToString(s(0), transform = ::stringify) else stringify(v))
        else -> {
            val text = stringify(v)
            Text(when (name) {
                "upper" -> text.uppercase()
                "lower" -> text.lowercase()
                "trim" -> text.trim(' ')
                "title" -> text.mapIndexed { i, c -> if (i == 0 || text[i-1] == ' ') c.uppercaseChar() else c.lowercaseChar() }.joinToString("")
                "pad" -> text.padEnd(n().toInt(), if (f.args.size == 2) s(1)[0] else ' ')
                "lpad" -> text.padStart(n().toInt(), if (f.args.size == 2) s(1)[0] else ' ')
                "truncate" -> if (text.length > n()) text.take(n().toInt()) + "..." else text
                else -> text.replace(s(0), s(1))
            })
        }
    }
}

private data class SourceLine(val line: Int, val text: String)
private data class Tag(val kind: Char, val text: String, val line: Int, val expr: Expression? = null, var indent: String = "", var end: Int = 0)
private fun analyze(source: List<SourceLine>): List<Tag> {
    var open = "{{"
    var close = "}}"
    val stack = mutableListOf<Pair<String, Int>>()
    val tokens = mutableListOf<Tag>()
    for ((line, text) in source) {
        var at = 0
        val row = mutableListOf<Tag>()
        while (true) {
            val start = text.indexOf(open, at)
            if (start < 0) break
            row.add(Tag('t', text.substring(at, start), line))
            var begin = start + open.length
            val triple = text.startsWith("{", begin)
            if (triple) begin++
            val ending = if (triple) "}$close" else close
            val finish = text.indexOf(ending, begin)
            if (finish < 0) throw Problem("unclosed tag", line)
            val content = text.substring(begin, finish).trim(' ')
            at = finish + ending.length
            val kind = if (triple) '&' else content.firstOrNull()?.takeIf { it in "#^/!>&=" } ?: 'v'
            val arg = if (!triple && kind != 'v') content.substring(1).trim(' ') else content
            var expr: Expression? = null
            try {
                when (kind) {
                    'v', '&', '#', '^' -> { expr = expression(arg); if (kind == '#' || kind == '^') stack.add(expr.name to line) }
                    '/' -> {
                        if (!validName(arg)) throw Problem("invalid name '$arg'")
                        val top = stack.lastOrNull() ?: throw Problem("unexpected closing '$arg'")
                        if (top.first != arg) throw Problem("mismatched closing '$arg', expected '${top.first}'")
                        stack.removeAt(stack.lastIndex)
                    }
                    '>' -> if (!identifier(arg)) throw Problem("invalid name '$arg'")
                    '=' -> {
                        if (content.length < 2 || !content.endsWith('=')) throw Problem("invalid delimiters")
                        val pair = content.substring(1, content.lastIndex).split(' ').filter { it.isNotEmpty() }
                        if (pair.size != 2 || pair.any { '=' in it }) throw Problem("invalid delimiters")
                        open = pair[0]; close = pair[1]
                    }
                }
            } catch (p: Problem) { throw Problem(p.reason, line) }
            row.add(Tag(kind, arg, line, expr))
        }
        row.add(Tag('t', text.substring(at), line))
        val positions = row.indices.filter { row[it].kind != 't' }
        if (positions.size == 1 && row[positions[0]].kind in "#^/!>=" && row.filter { it.kind == 't' }.all { it.text.all { c -> c == ' ' } }) {
            val i = positions[0]
            val tag = row[i]
            if (tag.kind == '>') tag.indent = row.take(i).joinToString("") { it.text }
            tokens.add(tag)
        } else { tokens.addAll(row); tokens.add(Tag('t', "\n", line)) }
    }
    stack.lastOrNull()?.let { throw Problem("unclosed section '${it.first}'", it.second) }
    val openings = mutableListOf<Int>()
    for (i in tokens.indices) {
        if (tokens[i].kind == '#' || tokens[i].kind == '^') openings.add(i)
        if (tokens[i].kind == '/') tokens[openings.removeAt(openings.lastIndex)].end = i
    }
    return tokens
}
private fun resolve(name: String, contexts: List<Value>, loops: List<Pair<Int, Int>>): Value? {
    if (name == ".") return contexts.last()
    if (name.startsWith('@')) {
        val (i, n) = loops.lastOrNull() ?: return null
        return when (name) { "@index" -> NumberValue(i.toLong()); "@number" -> NumberValue(i+1L); "@first" -> BooleanValue(i==0); else -> BooleanValue(i==n-1) }
    }
    val parts = name.split('.').map { if (subscript(it)) Index(it.toIntOrNull() ?: Int.MAX_VALUE) else Key(it) }
    for (context in contexts.asReversed()) {
        var value = child(context, parts[0]) ?: continue
        for (part in parts.drop(1)) value = child(value, part) ?: return null
        return value
    }
    return null
}
private fun escape(s: String) = s.map { when (it) { '&' -> "&amp;"; '<' -> "&lt;"; '>' -> "&gt;"; '"' -> "&quot;"; '\'' -> "&#39;"; else -> it.toString() } }.joinToString("")
private fun render(tags: List<Tag>, start: Int, end: Int, contexts: List<Value>, loops: List<Pair<Int, Int>>, partials: Map<String, List<SourceLine>>, strict: Boolean, depth: Int): String = buildString {
    var at = start
    while (at < end) {
        val tag = tags[at]
        try {
            when (tag.kind) {
                't' -> append(tag.text)
                'v', '&', '#', '^' -> {
                    val expr = tag.expr!!
                    val found = resolve(expr.name, contexts, loops)
                    if (strict && tag.kind in "v&" && found == null) throw Problem("missing '${expr.name}'")
                    var value: Value = found ?: Absent
                    for (filter in expr.filters) value = applyFilter(value, filter)
                    if (tag.kind in "v&") { val text = stringify(value); append(if (tag.kind == 'v') escape(text) else text) }
                    else {
                        if (tag.kind == '^') { if (!truthy(value)) append(render(tags, at+1, tag.end, contexts, loops, partials, strict, depth)) }
                        else if (value is ListValue) { for ((i, item) in value.values.withIndex()) append(render(tags, at+1, tag.end, contexts+item, loops+(i to value.values.size), partials, strict, depth)) }
                        else if (truthy(value)) append(render(tags, at+1, tag.end, contexts+value, loops, partials, strict, depth))
                        at = tag.end
                    }
                }
                '>' -> {
                    val source = partials[tag.text] ?: throw Problem("unknown partial '${tag.text}'")
                    if (depth == 8) throw Problem("partial depth exceeded at '${tag.text}'")
                    val parsed = analyze(source.map { SourceLine(it.line, if (it.text.isEmpty()) "" else tag.indent+it.text) })
                    append(render(parsed, 0, parsed.size, contexts, loops, partials, strict, depth+1))
                }
            }
        } catch (p: Problem) { throw Problem(p.reason, if (p.line == 0) tag.line else p.line) }
        at++
    }
}
private fun dump(v: Value, path: String, leaves: MutableList<String>) {
    when {
        v is MapValue && v.values.isNotEmpty() -> for ((key, value) in v.values.toSortedMap()) dump(value, if (path.isEmpty()) key else "$path.$key", leaves)
        v is ListValue && v.values.isNotEmpty() -> for ((i, value) in v.values.withIndex()) dump(value, "$path[$i]", leaves)
        path.isNotEmpty() -> {
            val notation = when (v) { is Text -> "\""+v.value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")+"\""; is MapValue -> "{}"; is ListValue -> "[]"; else -> stringify(v) }
            leaves.add("$path = $notation")
        }
    }
}
private fun outputTemplate(name: String, source: List<SourceLine>, root: Value, partials: Map<String, List<SourceLine>>, strict: Boolean) {
    try {
        val tags = analyze(source)
        val text = render(tags, 0, tags.size, listOf(root), emptyList(), partials, strict, 0)
        val lines = if (text.isEmpty()) 0 else text.count { it == '\n' } + if (text.endsWith('\n')) 0 else 1
        println("TEMPLATE $name OK lines=$lines chars=${text.length}")
        if (text.isNotEmpty()) { print(text); if (!text.endsWith('\n')) println() }
    } catch (p: Problem) { println("TEMPLATE $name ERROR line ${p.line}: ${p.reason}") }
}
fun main() {
    val lines = generateSequence(::readLine).toList()
    var at = 0
    var root: Value = MapValue(emptyMap())
    val partials = mutableMapOf<String, List<SourceLine>>()
    val templates = mutableMapOf<String, List<SourceLine>>()
    var strict = false
    while (at < lines.size) {
        val command = lines[at]
        val number = ++at
        if (command == "END") break
        if (command == "DATA") {
            var set = 0
            var unset = 0
            val errors = mutableListOf<String>()
            while (lines[at] != "ENDDATA") {
                val line = lines[at]
                val lineNumber = ++at
                if (line.isEmpty() || line.startsWith('#')) continue
                try {
                    val deletion = line.startsWith("UNSET ")
                    val pos = if (deletion) -1 else line.indexOf(" = ")
                    if (!deletion && pos < 0) throw Problem("bad line")
                    val key = if (deletion) line.substring(6) else line.substring(0, pos)
                    val parts = keyParts(key) ?: throw Problem("bad key '$key'")
                    if (deletion) { root = remove(root, parts, 0) ?: throw Problem("no value at '$key'"); unset++ }
                    else {
                        val notation = line.substring(pos+3)
                        val value = ValueParser(notation).parse() ?: throw Problem("bad value '$notation'")
                        root = assign(root, parts, 0, value); set++
                    }
                } catch (p: Problem) { errors.add("ERROR line $lineNumber: ${p.reason}") }
            }
            at++
            println("DATA set=$set unset=$unset errors=${errors.size}")
            errors.forEach(::println)
        } else if (command.startsWith("PARTIAL ") || command.startsWith("TEMPLATE ")) {
            val partial = command.startsWith("PARTIAL ")
            val name = command.substringAfter(' ')
            val end = if (partial) "ENDPARTIAL" else "ENDTEMPLATE"
            val source = mutableListOf<SourceLine>()
            while (lines[at] != end) { source.add(SourceLine(at+1, lines[at])); at++ }
            at++
            if (partial) {
                try {
                    analyze(source)
                    println("PARTIAL $name ${if (name in partials) "REPLACED" else "DEFINED"} lines=${source.size}")
                    partials[name] = source
                } catch (p: Problem) { println("PARTIAL $name ERROR line ${p.line}: ${p.reason}") }
            } else { templates[name] = source; outputTemplate(name, source, root, partials, strict) }
        } else if (command.startsWith("RENDER ")) {
            val name = command.substring(7)
            val source = templates[name]
            if (source != null) outputTemplate(name, source, root, partials, strict)
            else println("TEMPLATE $name ERROR line $number: unknown template '$name'")
        } else if (command == "DUMP") {
            val leaves = mutableListOf<String>(); dump(root, "", leaves)
            println("DUMP leaves=${leaves.size}"); leaves.forEach(::println)
        } else if (command == "RESET") { root = MapValue(emptyMap()); partials.clear(); templates.clear(); println("RESET") }
        else { strict = command == "STRICT ON"; println(command) }
    }
}
