private sealed interface Value
private data class ObjectValue(val members: List<Pair<String, Value>>) : Value
private data class ArrayValue(val elements: List<Value>) : Value
private data class StringValue(val text: String) : Value
private data class NumberValue(val number: Long) : Value
private data class BooleanValue(val boolean: Boolean) : Value
private data object NullValue : Value
private class Problem(val text: String) : RuntimeException(text)
private class ParseProblem(val position: Int, val reason: String) : RuntimeException(reason)
private fun identifier(s: String) = s.matches(Regex("[A-Za-z_][A-Za-z0-9_]*"))
private fun integer(s: String): Long? = if (s.matches(Regex("0|-?[1-9][0-9]{0,8}"))) s.toLong() else null
private fun quote(s: String, q: Char): String = buildString {
    append(q)
    for (c in s) {
        if (c == q || c == '\\') append('\\').append(c)
        else append(when (c) {
            '\b' -> "\\b"
            '\u000c' -> "\\f"
            '\n' -> "\\n"
            '\r' -> "\\r"
            '\t' -> "\\t"
            else -> if (c.code < 32 || c.code == 127) "\\u%04x".format(c.code) else c.toString()
        })
    }
    append(q)
}
private fun kind(v: Value): String = when (v) {
    is ObjectValue -> "object"
    is ArrayValue -> "array"
    is StringValue -> "string"
    is NumberValue -> "number"
    is BooleanValue -> "boolean"
    NullValue -> "null"
}
private fun compact(v: Value): String = when (v) {
    is ObjectValue -> v.members.joinToString(",", "{", "}") {
        quote(it.first, '"')+":"+compact(it.second)
    }
    is ArrayValue -> v.elements.joinToString(",", "[", "]", transform = ::compact)
    is StringValue -> quote(v.text, '"')
    is NumberValue -> v.number.toString()
    is BooleanValue -> v.boolean.toString()
    NullValue -> "null"
}
private fun pretty(v: Value, indent: String = ""): String {
    val next = "$indent  "
    return when {
        v is ObjectValue && v.members.isNotEmpty() -> "{\n"+v.members.joinToString(",\n") {
            next+quote(it.first, '"')+": "+pretty(it.second, next)
        }+"\n$indent}"
        v is ArrayValue && v.elements.isNotEmpty() -> "[\n"+v.elements.joinToString(",\n") {
            next+pretty(it, next)
        }+"\n$indent]"
        else -> compact(v)
    }
}
private fun children(v: Value): Int = when (v) {
    is ObjectValue -> v.members.size
    is ArrayValue -> v.elements.size
    else -> 0
}
private fun child(v: Value, i: Int): Value = when (v) {
    is ObjectValue -> v.members[i].second
    is ArrayValue -> v.elements[i]
    else -> error("not a container")
}
private fun length(v: Value): Int? = when (v) {
    is ObjectValue -> v.members.size
    is ArrayValue -> v.elements.size
    is StringValue -> v.text.length
    else -> null
}
private fun sizeDepth(v: Value): Pair<Int, Int> {
    var size = 1
    var depth = 1
    for (i in 0 until children(v)) {
        val (n, d) = sizeDepth(child(v, i))
        size += n
        depth = maxOf(depth, d+1)
    }
    return size to depth
}
private fun equal(a: Value, b: Value): Boolean = when {
    a is ObjectValue && b is ObjectValue -> a.members.size == b.members.size && a.members.all {
        (key, value) -> b.members.firstOrNull {
            it.first == key
        }?.let {
            equal(value, it.second)
        } == true
    }
    a is ArrayValue && b is ArrayValue -> a.elements.size == b.elements.size && a.elements.zip(b.elements).all {
        equal(it.first, it.second)
    }
    else -> a == b
}
private class JsonParser(private val text: String) {
    private var at = 0
    private fun current() = text.getOrNull(at)
    private fun fail(reason: String, position: Int = at): Nothing = throw ParseProblem(position, reason)
    private fun skip() {
        while (current() == ' ' || current() == '\n') at++
    }
    private fun string(): String {
        at++
        val out = StringBuilder()
        while (true) {
            when (val c = current()) {
                null, '\n' -> fail("unterminated string")
                '"' -> {
                    at++
                    return out.toString()
                }
                '\\' -> {
                    val start = at
                    when (val e = text.getOrNull(at+1)) {
                        null, '\n' -> fail("unterminated string", at+1)
                        'u' -> {
                            if (at+6 > text.length || text.substring(at+2, at+6).any {
                                it.digitToIntOrNull(16) == null
                            }) fail("bad unicode escape")
                            val n = text.substring(at+2, at+6).toInt(16)
                            if (n > 127) fail("non-ascii escape")
                            out.append(n.toChar())
                            at += 6
                        }
                        else -> {
                            out.append(when (e) {
                                '"' -> '"'
                                '\\' -> '\\'
                                '/' -> '/'
                                'b' -> '\b'
                                'f' -> '\u000c'
                                'n' -> '\n'
                                'r' -> '\r'
                                't' -> '\t'
                                else -> fail("invalid escape '\\$e'", start)
                            })
                            at += 2
                        }
                    }
                }
                else -> {
                    out.append(c)
                    at++
                }
            }
        }
    }
    private fun value(): Value {
        skip()
        return when (val c = current()) {
            null -> fail("unexpected end of input")
            '"' -> StringValue(string())
            '{' -> {
                at++
                skip()
                val members = mutableListOf<Pair<String, Value>>()
                if (current() == '}') {
                    at++
                    return ObjectValue(members)
                }
                while (true) {
                    skip()
                    val start = at
                    if (current() == null) fail("unexpected end of input")
                    if (current() != '"') fail("expected key")
                    val key = string()
                    if (members.any {
                        it.first == key
                    }) fail("duplicate key ${quote(key, '"')}", start)
                    skip()
                    if (current() == null) fail("unexpected end of input")
                    if (current() != ':') fail("expected ':'")
                    at++
                    members.add(key to value())
                    skip()
                    when (current()) {
                        '}' -> {
                            at++
                            break
                        }
                        null -> fail("unexpected end of input")
                        ',' -> at++
                        else -> fail("expected ',' or '}'")
                    }
                    skip()
                    if (current() == '}') fail("trailing comma")
                }
                ObjectValue(members)
            }
            '[' -> {
                at++
                skip()
                val elements = mutableListOf<Value>()
                if (current() == ']') {
                    at++
                    return ArrayValue(elements)
                }
                while (true) {
                    elements.add(value())
                    skip()
                    when (current()) {
                        ']' -> {
                            at++
                            break
                        }
                        null -> fail("unexpected end of input")
                        ',' -> at++
                        else -> fail("expected ',' or ']'")
                    }
                    skip()
                    if (current() == ']') fail("trailing comma")
                }
                ArrayValue(elements)
            }
            else -> when {
                c == '-' || c in '0'..'9' -> {
                    val start = at
                    if (c == '-') at++
                    val digits = at
                    while (current()?.let {
                        it in '0'..'9'
                    } == true) at++
                    if (at == digits) fail("invalid number", start)
                    if (at-digits >= 2 && text[digits] == '0') fail("leading zero", digits)
                    if (current() == '.') fail("fraction not allowed")
                    if (current() == 'e' || current() == 'E') fail("exponent not allowed")
                    if (at-digits >= 10) fail("number out of range", start)
                    NumberValue(text.substring(start, at).toLong())
                }
                c in 'A'..'Z' || c in 'a'..'z' -> {
                    val start = at
                    while (current()?.let {
                        it in 'A'..'Z' || it in 'a'..'z'
                    } == true) at++
                    when (val word = text.substring(start, at)) {
                        "null" -> NullValue
                        "true" -> BooleanValue(true)
                        "false" -> BooleanValue(false)
                        else -> fail("invalid literal '$word'", start)
                    }
                }
                else -> fail("unexpected character '$c'")
            }
        }
    }
    fun parse(): Value {
        val value = value()
        skip()
        if (at != text.length) fail("trailing characters")
        return value
    }
}
private sealed interface Selector
private data class Key(val key: String) : Selector
private data class Index(val index: Long) : Selector
private data object All : Selector
private data class Slice(val start: Long?, val end: Long?) : Selector
private data class Segment(val descendant: Boolean, val selector: Selector)
private class PathParser(private val text: String) {
    var at = 0
    fun quoted(): String? {
        if (text.getOrNull(at) != '\'') return null
        at++
        val out = StringBuilder()
        while (at < text.length) {
            val c = text[at++]
            if (c == '\'') return out.toString()
            if (c != '\\') {
                out.append(c)
                continue
            }
            val e = text.getOrNull(at++) ?: return null
            if (e == 'u') {
                if (at+4 > text.length || text.substring(at, at+4).any {
                    it.digitToIntOrNull(16) == null
                }) return null
                val n = text.substring(at, at+4).toInt(16)
                if (n > 127) return null
                out.append(n.toChar())
                at += 4
            } else out.append(when (e) {
                '\'' -> '\''
                '\\' -> '\\'
                '/' -> '/'
                'b' -> '\b'
                'f' -> '\u000c'
                'n' -> '\n'
                'r' -> '\r'
                't' -> '\t'
                else -> return null
            })
        }
        return null
    }
    fun parse(field: Boolean): List<Segment>? {
        if (text.firstOrNull() != if (field) '@' else '$') return null
        at = 1
        val segments = mutableListOf<Segment>()
        while (at < text.length) {
            var descendant = false
            if (text[at] == '.') {
                at++
                if (text.getOrNull(at) == '.') {
                    if (field) return null
                    descendant = true
                    at++
                }
                else if (text.getOrNull(at) == '[') return null
            } else if (text[at] != '[') return null
            val selector: Selector
            if (text.getOrNull(at) == '[') {
                at++
                if (text.getOrNull(at) == '\'') {
                    val key = quoted() ?: return null
                    if (text.getOrNull(at++) != ']') return null
                    selector = Key(key)
                } else {
                    val end = text.indexOf(']', at)
                    if (end < 0) return null
                    val item = text.substring(at, end)
                    at = end+1
                    selector = if (item == "*" && !field) All else if (':' in item) {
                        if (field || item.count {
                            it == ':'
                        } != 1) return null
                        val a = item.substringBefore(':')
                        val b = item.substringAfter(':')
                        Slice(if (a.isEmpty()) null else integer(a) ?: return null, if (b.isEmpty()) null else integer(b) ?: return null)
                    } else Index(integer(item) ?: return null)
                }
            } else if (text.getOrNull(at) == '*' && !field) {
                at++
                selector = All
            }
            else {
                val start = at
                while (at < text.length && (text[at] in 'A'..'Z' || text[at] in 'a'..'z' || text[at] in '0'..'9' || text[at] == '_')) at++
                val key = text.substring(start, at)
                if (!identifier(key)) return null
                selector = Key(key)
            }
            segments.add(Segment(descendant, selector))
        }
        return segments
    }
}
// Child positions preserve document order even when object keys are renamed.
private typealias Location = List<Int>
private fun valueAt(root: Value, location: Location): Value = location.fold(root, ::child)
private fun update(root: Value, location: Location, change: (Value) -> Value): Value {
    if (location.isEmpty()) return change(root)
    val i = location[0]
    val next = update(child(root, i), location.drop(1), change)
    return when (root) {
        is ObjectValue -> ObjectValue(root.members.toMutableList().also {
            it[i] = it[i].first to next
        })
        is ArrayValue -> ArrayValue(root.elements.toMutableList().also {
            it[i] = next
        })
        else -> error("not a container")
    }
}
private fun notation(root: Value, location: Location): String = buildString {
    append('$')
    var value = root
    for (i in location) {
        if (value is ObjectValue) {
            val key = value.members[i].first
            if (identifier(key)) append('.').append(key) else append('[').append(quote(key, '\'')).append(']')
        }
        else append('[').append(i).append(']')
        value = child(value, i)
    }
}
private fun preorder(root: Value, location: Location, out: MutableList<Location>) {
    out.add(location)
    for (i in 0 until children(valueAt(root, location))) preorder(root, location+i, out)
}
private fun selection(v: Value, s: Selector): List<Int> = when {
    v is ObjectValue && s is Key -> v.members.indexOfFirst {
        it.first == s.key
    }.takeIf {
        it >= 0
    }?.let(::listOf) ?: emptyList()
    (v is ObjectValue || v is ArrayValue) && s == All -> (0 until children(v)).toList()
    v is ArrayValue && s is Index -> {
        val j = if (s.index < 0) v.elements.size+s.index else s.index
        if (j >= 0 && j < v.elements.size) listOf(j.toInt()) else emptyList()
    }
    v is ArrayValue && s is Slice -> {
        val n = v.elements.size.toLong()
        fun bound(x: Long) = (if (x < 0) x+n else x).coerceIn(0, n)
        (bound(s.start ?: 0).toInt() until bound(s.end ?: n).toInt()).toList()
    }
    else -> emptyList()
}
private fun apply(root: Value, matches: List<Location>, segment: Segment): List<Location> = buildList {
    for (location in matches) {
        val parents = mutableListOf<Location>()
        if (segment.descendant) preorder(root, location, parents) else parents.add(location)
        for (parent in parents) for (i in selection(valueAt(root, parent), segment.selector)) add(parent+i)
    }
}
private fun evaluate(root: Value, path: List<Segment>): List<Location> = path.fold(listOf(emptyList<Int>()), {
    matches, segment -> apply(root, matches, segment)
})
private fun fieldValue(root: Value, field: List<Segment>): Value? {
    var value = root
    for (segment in field) value = child(value, selection(value, segment.selector).firstOrNull() ?: return null)
    return value
}
private fun sortOrder(a: Value?, b: Value?): Int {
    fun rank(v: Value?) = when (v) {
        NullValue -> 0
        is NumberValue -> 1
        is StringValue -> 2
        else -> 3
    }
    val order = rank(a).compareTo(rank(b))
    if (order != 0) return order
    return when {
        a is NumberValue && b is NumberValue -> a.number.compareTo(b.number)
        a is StringValue && b is StringValue -> a.text.compareTo(b.text)
        else -> 0
    }
}
private fun merge(target: Value, source: Value): Value {
    val members = (target as ObjectValue).members.toMutableList()
    for ((key, value) in (source as ObjectValue).members) {
        val i = members.indexOfFirst {
            it.first == key
        }
        if (i < 0) members.add(key to value)
        else members[i] = key to if (members[i].second is ObjectValue && value is ObjectValue) merge(members[i].second, value) else value
    }
    return ObjectValue(members)
}
private class Tool {
    var root: Value = NullValue
    val history = mutableListOf<Value>()
    fun load(text: String) {
        try {
            val value = JsonParser(text).parse()
            val (nodes, depth) = sizeDepth(value)
            history.add(root)
            root = value
            println("LOADED nodes=$nodes depth=$depth")
        } catch (p: ParseProblem) {
            val prefix = text.substring(0, p.position)
            println("PARSE ERROR line ${prefix.count { it == '\n' }+1} col ${prefix.substringAfterLast('\n').length+1}: ${p.reason}")
        }
    }
    fun command(line: String): List<String> {
        val command = line.substringBefore(' ')
        val arg = if (' ' in line) line.substringAfter(' ') else null
        val known = setOf("GET", "COMPACT", "PRETTY", "TYPE", "LENGTH", "KEYS", "FLATTEN", "COUNT", "SUM", "MIN", "MAX", "AVG", "FILTER", "SET", "DELETE", "INSERT", "MERGE", "SORT", "RENAME", "UNDO")
        if (command !in known) throw Problem("ERROR unknown command '$command'")
        val words = arg?.split(' ', limit = when (command) {
            "SET", "MERGE" -> 2
            "INSERT" -> 3
            "FILTER" -> 4
            else -> 0
        }) ?: emptyList()
        val shape = when (command) {
            "UNDO" -> words.isEmpty()
            "COMPACT", "PRETTY", "FLATTEN" -> words.size <= 1
            "SET", "MERGE", "RENAME" -> words.size == 2
            "INSERT" -> words.size == 3
            "FILTER" -> words.size >= 3 && if (words[2] == "EXISTS") words.size == 3 else words.size == 4
            "SORT" -> words.size in 1..3 && (words.size < 3 || (words[1] != "DESC" && words[2] == "DESC"))
            else -> words.size == 1
        }
        if (!shape) throw Problem("ERROR bad arguments")
        if (command == "UNDO") {
            if (history.isEmpty()) throw Problem("ERROR nothing to undo")
            root = history.removeAt(history.lastIndex)
            return listOf("UNDO ${history.size}")
        }
        val path = PathParser(words.firstOrNull() ?: "$").parse(false) ?: throw Problem("ERROR bad path")
        val field = if (command == "FILTER" || command == "SORT") PathParser(if (command == "FILTER") words[1] else words.getOrNull(1)?.takeIf {
            it != "DESC"
        } ?: "@").parse(true) ?: throw Problem("ERROR bad field") else emptyList()
        if (command == "FILTER" && words[2] !in setOf("==", "!=", "<", "<=", ">", ">=", "EXISTS")) throw Problem("ERROR bad operator")
        val index = if (command == "INSERT") integer(words[1]) ?: throw Problem("ERROR bad index") else 0L
        val rename = if (command == "RENAME") {
            if (identifier(words[1])) words[1] else {
                val p = PathParser(words[1])
                val key = p.quoted() ?: throw Problem("ERROR bad key")
                if (p.at != words[1].length) throw Problem("ERROR bad key")
                key
            }
        } else ""
        val json = when (command) {
            "SET", "MERGE" -> words[1]
            "INSERT" -> words[2]
            "FILTER" -> if (words[2] != "EXISTS") words[3] else null
            else -> null
        }
        val supplied = json?.let {
            try {
                JsonParser(it).parse()
            } catch (p: ParseProblem) {
                throw Problem("PARSE ERROR col ${p.position+1}: ${p.reason}")
            }
        }
        if (command == "MERGE" && supplied !is ObjectValue) throw Problem("ERROR merge value is not an object")
        val matches = evaluate(root, path)
        val required = when (command) {
            "FILTER", "INSERT", "SORT" -> "array"
            "MERGE", "KEYS" -> "object"
            else -> null
        }
        for (location in matches) {
            val value = valueAt(root, location)
            val loc = notation(root, location)
            if (required != null && kind(value) != required) throw Problem("ERROR not an $required at $loc")
            if (command == "LENGTH" && length(value) == null) throw Problem("ERROR no length at $loc")
            if (command == "RENAME" && (location.isEmpty() || valueAt(root, location.dropLast(1)) !is ObjectValue)) throw Problem("ERROR not a member at $loc")
        }
        if (command == "INSERT") for (location in matches) {
            val n = children(valueAt(root, location)).toLong()
            if (index < -n-1 || index > n) throw Problem("ERROR index out of range at ${notation(root, location)}")
        }
        if (command == "COUNT") return listOf("COUNT ${matches.size}")
        if (command in setOf("SUM", "MIN", "MAX", "AVG")) {
            val nums = matches.mapNotNull {
                (valueAt(root, it) as? NumberValue)?.number
            }
            val sum = nums.sum()
            val result = when (command) {
                "SUM" -> sum.toString()
                "MIN" -> nums.minOrNull()?.toString() ?: "null"
                "MAX" -> nums.maxOrNull()?.toString() ?: "null"
                else -> if (nums.isEmpty()) "null" else {
                    val n = nums.size.toLong()
                    val q = (kotlin.math.abs(sum)*200+n)/(2*n)
                    (if (sum < 0 && q > 0) "-" else "")+"${q/100}."+(q%100).toString().padStart(2, '0')
                }
            }
            return listOf("$command $result")
        }
        if (command in setOf("GET", "COMPACT", "PRETTY", "TYPE", "LENGTH", "KEYS", "FLATTEN", "FILTER")) {
            val output = mutableListOf<String>()
            for (location in matches) {
                val value = valueAt(root, location)
                val loc = notation(root, location)
                when (command) {
                    "GET" -> output.add("$loc = ${compact(value)}")
                    "COMPACT" -> output.add(compact(value))
                    "PRETTY" -> output.add(pretty(value))
                    "TYPE" -> output.add("$loc ${kind(value)}")
                    "LENGTH" -> output.add("$loc ${length(value)}")
                    "KEYS" -> output.add("$loc ${compact(ArrayValue((value as ObjectValue).members.map { StringValue(it.first) }))}")
                    "FLATTEN" -> {
                        val leaves = mutableListOf<Location>()
                        preorder(root, location, leaves)
                        for (leaf in leaves) if (children(valueAt(root, leaf)) == 0) output.add("${notation(root, leaf)} = ${compact(valueAt(root, leaf))}")
                    }
                    else -> for (i in 0 until children(value)) {
                        val element = child(value, i)
                        val f = fieldValue(element, field)
                        val eq = f != null && supplied != null && equal(f, supplied)
                        val cmp = when {
                            f is NumberValue && supplied is NumberValue -> f.number.compareTo(supplied.number)
                            f is StringValue && supplied is StringValue -> f.text.compareTo(supplied.text)
                            else -> null
                        }
                        val good = when (words[2]) {
                            "EXISTS" -> f != null
                            "==" -> eq
                            "!=" -> !eq
                            "<" -> cmp != null && cmp < 0
                            "<=" -> cmp != null && cmp <= 0
                            ">" -> cmp != null && cmp > 0
                            else -> cmp != null && cmp >= 0
                        }
                        if (good) output.add("${notation(root, location+i)} = ${compact(element)}")
                    }
                }
            }
            return output.ifEmpty {
                listOf("no match")
            }
        }
        if (command == "DELETE" && path.isEmpty()) throw Problem("ERROR cannot delete root")
        val newKey = if (command == "SET" && path.lastOrNull()?.descendant == false) (path.last().selector as? Key)?.key else null
        val targets = if (command == "SET" && newKey != null) evaluate(root, path.dropLast(1)).mapNotNull {
            parent ->
            val objectValue = valueAt(root, parent) as? ObjectValue ?: return@mapNotNull null
            parent+(objectValue.members.indexOfFirst {
                it.first == newKey
            }.takeIf {
                it >= 0
            } ?: objectValue.members.size)
        } else matches
        val order = Comparator<Location> {
            a, b -> var result = 0
            for (i in 0 until minOf(a.size, b.size)) {
                result = a[i].compareTo(b[i])
                if (result != 0) break
            }
            if (result == 0) a.size.compareTo(b.size) else result
        }
        val unique = targets.distinct().sortedWith(order.reversed())
        var changed = root
        for (location in unique) {
            if (command in setOf("SET", "DELETE", "RENAME") && location.isNotEmpty()) {
                val i = location.last()
                changed = update(changed, location.dropLast(1)) {
                    parent ->
                    when (parent) {
                        is ObjectValue -> {
                            val members = parent.members.toMutableList()
                            when (command) {
                                "SET" -> if (i == members.size) members.add(newKey!! to supplied!!) else members[i] = members[i].first to supplied!!
                                "DELETE" -> members.removeAt(i)
                                else -> {
                                    if (members[i].first != rename && members.any {
                                        it.first == rename
                                    }) throw Problem("ERROR key exists at ${notation(root, location)}")
                                    members[i] = rename to members[i].second
                                }
                            }
                            ObjectValue(members)
                        }
                        is ArrayValue -> {
                            val elements = parent.elements.toMutableList()
                            if (command == "SET") elements[i] = supplied!! else elements.removeAt(i)
                            ArrayValue(elements)
                        }
                        else -> error("not a container")
                    }
                }
            } else changed = update(changed, location) {
                target ->
                when (command) {
                    "SET" -> supplied!!
                    "MERGE" -> merge(target, supplied!!)
                    "INSERT" -> {
                        val elements = (target as ArrayValue).elements.toMutableList()
                        val j = if (index < 0) elements.size+1+index else index
                        elements.add(j.toInt(), supplied!!)
                        ArrayValue(elements)
                    }
                    "SORT" -> {
                        val desc = words.last() == "DESC"
                        ArrayValue((target as ArrayValue).elements.sortedWith {
                            a, b -> val cmp = sortOrder(fieldValue(a, field), fieldValue(b, field))
                            if (desc) -cmp else cmp
                        })
                    }
                    else -> error("invalid command")
                }
            }
        }
        history.add(root)
        root = changed
        return listOf("$command ${unique.size}")
    }
}
fun main() {
    val lines = generateSequence(::readLine).toList()
    var at = 0
    val tool = Tool()
    while (true) {
        val start = at
        while (lines[at] != "%%") at++
        tool.load(lines.subList(start, at).joinToString("\n"))
        at++
        while (lines[at] != "LOAD" && lines[at] != "END") {
            try {
                tool.command(lines[at]).forEach(::println)
            } catch (p: Problem) {
                println(p.text)
            }
            at++
        }
        if (lines[at] == "END") break
        at++
    }
}
