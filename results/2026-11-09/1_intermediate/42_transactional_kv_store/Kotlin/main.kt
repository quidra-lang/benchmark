import java.util.TreeMap
import java.util.TreeSet
import kotlin.math.abs

private const val WRONG_TYPE = "WRONGTYPE Operation against a key holding the wrong kind of value"
private const val NOT_INTEGER = "ERR value is not an integer or out of range"
private const val POSITIVE = "ERR value is out of range, must be positive"
private class CommandError(message: String) : RuntimeException(message)

private sealed interface Value {
    val kind: String get() = when (this) {
        is TextValue -> "string"
        is ListValue -> "list"
        is HashValue -> "hash"
        is SetValue -> "set"
        is SortedSetValue -> "zset"
    }
    val empty: Boolean get() = when (this) {
        is TextValue -> false
        is ListValue -> items.isEmpty()
        is HashValue -> fields.isEmpty()
        is SetValue -> members.isEmpty()
        is SortedSetValue -> scores.isEmpty()
    }
}
private data class TextValue(val text: String) : Value
private class ListValue(items: List<String>) : Value { val items = items.toList() }
private class HashValue(fields: Map<String, String>) : Value { val fields = fields.toMap() }
private class SetValue(members: Set<String>) : Value { val members = members.toSet() }
private class SortedSetValue(scores: Map<String, Int>) : Value { val scores = scores.toMap() }
private data class Entry(val value: Value, val expiry: Int? = null)
private typealias Database = TreeMap<String, Entry>
private data class Range(val start: Int, val end: Int)

private fun quoted(text: String?): String = text?.let { "\"" + it.replace("\\", "\\\\").replace("\"", "\\\"") + "\"" } ?: "(nil)"
private fun integerReply(value: Int) = "(integer) $value"
private fun arrayReply(values: Collection<String?>): String {
    if (values.isEmpty()) return "(empty array)"
    val width = values.size.toString().length
    return values.mapIndexed { i, value -> "${(i + 1).toString().padStart(width)}) ${quoted(value)}" }.joinToString("\n")
}

private fun splitLine(line: String): List<String>? {
    val words = mutableListOf<String>()
    var position = 0
    while (position < line.length) {
        if (line[position] == ' ') { position++; continue }
        if (line[position] != '"') {
            val start = position
            while (position < line.length && line[position] != ' ') position++
            words += line.substring(start, position)
            continue
        }
        position++
        val word = StringBuilder()
        while (position < line.length && line[position] != '"') {
            var c = line[position++]
            if (c == '\\') {
                if (position == line.length) return null
                c = line[position++]
                if (c != '\\' && c != '"') return null
            }
            word.append(c)
        }
        if (position == line.length) return null
        position++
        if (position < line.length && line[position] != ' ') return null
        words += word.toString()
    }
    return words
}

private fun parseInteger(text: String): Int? {
    if (text == "0") return 0
    val start = if (text.startsWith('-')) 1 else 0
    if (text.length - start !in 1..9 || text[start] !in '1'..'9') return null
    if ((start until text.length).any { text[it] !in '0'..'9' }) return null
    return text.toInt()
}
private fun number(text: String) = parseInteger(text) ?: throw CommandError(NOT_INTEGER)
private fun increment(old: Int, delta: Int): Int {
    val value = old + delta
    if (value !in -999_999_999..999_999_999) throw CommandError("ERR increment or decrement would overflow")
    return value
}
private fun range(length: Int, first: Int, last: Int): Range {
    val start = maxOf(0, if (first < 0) first + length else first)
    val stop = minOf(length - 1, if (last < 0) last + length else last)
    return if (start <= stop) Range(start, stop + 1) else Range(0, 0)
}

private sealed interface Bound { fun accepts(score: Int, lower: Boolean): Boolean }
private enum class Infinity : Bound {
    NEGATIVE, POSITIVE;
    override fun accepts(score: Int, lower: Boolean) = lower == (this == NEGATIVE)
}
private data class FiniteBound(val value: Int, val exclusive: Boolean) : Bound {
    override fun accepts(score: Int, lower: Boolean) =
        (if (lower) score > value else score < value) || (!exclusive && score == value)
}
private fun bound(text: String): Bound {
    if (text == "-inf") return Infinity.NEGATIVE
    if (text == "+inf") return Infinity.POSITIVE
    val exclusive = text.startsWith('(')
    val value = parseInteger(if (exclusive) text.substring(1) else text)
        ?: throw CommandError("ERR min or max is not a float")
    return FiniteBound(value, exclusive)
}

private sealed interface PatternPart { fun accepts(c: Char): Boolean }
private data class Literal(val value: Char) : PatternPart { override fun accepts(c: Char) = value == c }
private data object AnyCharacter : PatternPart { override fun accepts(c: Char) = true }
private data object Star : PatternPart { override fun accepts(c: Char) = true }
private class CharacterClass(val members: BooleanArray, val negated: Boolean) : PatternPart {
    override fun accepts(c: Char) = members[c.code] != negated
}
private fun pattern(text: String): List<PatternPart> {
    val parts = mutableListOf<PatternPart>()
    var i = 0
    while (i < text.length) {
        when (val c = text[i]) {
            '\\' -> {
                if (++i == text.length) throw CommandError("ERR invalid pattern")
                parts += Literal(text[i])
            }
            '[' -> {
                val end = text.indexOf(']', i + 1)
                if (end < 0) throw CommandError("ERR invalid pattern")
                i++
                val negated = i < end && text[i] == '^'
                if (negated) i++
                if (i == end) throw CommandError("ERR invalid pattern")
                val members = BooleanArray(128)
                while (i < end) {
                    val first = text[i].code
                    if (i + 2 < end && text[i + 1] == '-') {
                        val last = text[i + 2].code
                        members.fill(true, minOf(first, last), maxOf(first, last) + 1)
                        i += 3
                    } else { members[first] = true; i++ }
                }
                parts += CharacterClass(members, negated)
            }
            '*' -> parts += Star
            '?' -> parts += AnyCharacter
            else -> parts += Literal(c)
        }
        i++
    }
    return parts
}
private fun matches(parts: List<PatternPart>, text: String): Boolean {
    var previous = BooleanArray(text.length + 1)
    previous[0] = true
    for (part in parts) {
        val next = BooleanArray(previous.size)
        if (part === Star) {
            next[0] = previous[0]
            for (i in 1 until next.size) next[i] = previous[i] || next[i - 1]
        } else {
            for (i in text.indices) next[i + 1] = previous[i] && part.accepts(text[i])
        }
        previous = next
    }
    return previous[text.length]
}

private data class Arity(val minimum: Int, val maximum: Int = minimum, val parity: Int = -1) {
    fun accepts(count: Int) = count >= minimum && (maximum < 0 || count <= maximum) && (parity < 0 || count % 2 == parity)
}
private fun arity(command: String): Arity? = when (command) {
    "TIME", "DBSIZE", "FLUSH", "INFO", "BEGIN", "COMMIT", "ROLLBACK" -> Arity(0)
    "GET", "INCR", "DECR", "STRLEN", "LLEN", "HGETALL", "HLEN", "HKEYS", "HVALS", "SMEMBERS", "SCARD",
    "ZCARD", "TYPE", "KEYS", "TTL", "PERSIST", "TICK", "SNAPSHOT", "RESTORE" -> Arity(1)
    "INCRBY", "DECRBY", "APPEND", "LINDEX", "HGET", "HEXISTS", "SISMEMBER", "ZSCORE", "ZRANK", "RENAME", "RENAMENX" -> Arity(2)
    "GETRANGE", "LRANGE", "LSET", "LREM", "LTRIM", "HINCRBY", "ZINCRBY" -> Arity(3)
    "LINSERT" -> Arity(4)
    "LPOP", "RPOP" -> Arity(1, 2)
    "EXPIRE" -> Arity(2, 3)
    "ZRANGE", "ZRANGEBYSCORE" -> Arity(3, 4)
    "MGET", "SINTER", "SUNION", "SDIFF", "DEL", "EXISTS" -> Arity(1, -1)
    "SET", "LPUSH", "RPUSH", "HDEL", "SADD", "SREM", "ZREM", "SINTERSTORE", "SUNIONSTORE", "SDIFFSTORE" -> Arity(2, -1)
    "MSET" -> Arity(2, -1, 0)
    "HSET", "ZADD" -> Arity(3, -1, 1)
    else -> null
}

private class Store {
    private var database = Database()
    private val stack = mutableListOf<Database>()
    private val snapshots = TreeMap<String, Database>()
    private var time = 0

    private inline fun <reified T : Value> read(key: String, empty: T): T {
        val value = database[key]?.value ?: return empty
        return value as? T ?: throw CommandError(WRONG_TYPE)
    }
    private fun text(key: String) = read(key, TextValue("")).text
    private fun list(key: String) = read(key, ListValue(emptyList())).items.toMutableList()
    private fun hash(key: String) = read(key, HashValue(emptyMap())).fields.toSortedMap()
    private fun set(key: String) = read(key, SetValue(emptySet())).members.toSortedSet()
    private fun sortedSet(key: String) = read(key, SortedSetValue(emptyMap())).scores.toSortedMap()
    private fun replace(key: String, value: Value, expiry: Int? = null) {
        if (value.empty) database.remove(key) else database[key] = Entry(value, expiry)
    }
    private fun update(key: String, value: Value) = replace(key, value, database[key]?.expiry)
    private fun purge(): Int {
        val before = database.size
        database.entries.removeIf { it.value.expiry?.let { deadline -> deadline <= time } == true }
        return before - database.size
    }

    private fun textCommand(command: String, a: List<String>): String {
        val key = a.first()
        return when (command) {
            "SET" -> {
                val options = mutableSetOf<String>()
                var secondsText: String? = null
                var i = 2
                while (i < a.size) {
                    val option = a[i++].uppercase()
                    if (option !in setOf("NX", "XX", "EX", "KEEPTTL", "GET") || !options.add(option)) throw CommandError("ERR syntax error")
                    if (option == "EX") {
                        if (i == a.size) throw CommandError("ERR syntax error")
                        secondsText = a[i++]
                    }
                }
                if (("NX" in options && "XX" in options) || ("EX" in options && "KEEPTTL" in options)) throw CommandError("ERR syntax error")
                var expiry = secondsText?.let {
                    val seconds = number(it)
                    if (seconds <= 0) throw CommandError("ERR invalid expire time in 'set' command")
                    time + seconds
                }
                val old = database[key]
                val oldText = if ("GET" in options) text(key).takeIf { old != null } else null
                val blocked = ("NX" in options && old != null) || ("XX" in options && old == null)
                if (!blocked) {
                    if ("KEEPTTL" in options && old != null) expiry = old.expiry
                    replace(key, TextValue(a[1]), expiry)
                }
                if ("GET" in options) quoted(oldText) else if (blocked) "(nil)" else "OK"
            }
            "MSET" -> {
                for (i in a.indices step 2) replace(a[i], TextValue(a[i + 1]))
                "OK"
            }
            "MGET" -> arrayReply(a.map { (database[it]?.value as? TextValue)?.text })
            "INCR", "DECR", "INCRBY", "DECRBY" -> {
                var delta = if (a.size == 2) number(a[1]) else 1
                if (command.startsWith("DECR")) delta = -delta
                val old = text(key)
                val value = increment(if (key in database) number(old) else 0, delta)
                update(key, TextValue(value.toString()))
                integerReply(value)
            }
            "APPEND" -> {
                val value = text(key) + a[1]
                update(key, TextValue(value))
                integerReply(value.length)
            }
            "GETRANGE" -> {
                val start = number(a[1])
                val stop = number(a[2])
                val value = text(key)
                val selected = range(value.length, start, stop)
                quoted(value.substring(selected.start, selected.end))
            }
            "STRLEN" -> integerReply(text(key).length)
            else -> quoted(text(key).takeIf { key in database })
        }
    }

    private fun listCommand(command: String, a: List<String>): String {
        val key = a.first()
        return when (command) {
            "LPUSH", "RPUSH" -> {
                val values = list(key)
                for (value in a.drop(1)) if (command == "LPUSH") values.add(0, value) else values.add(value)
                update(key, ListValue(values))
                integerReply(values.size)
            }
            "LPOP", "RPOP" -> {
                val count = if (a.size == 1) null else {
                    parseInteger(a[1])?.takeIf { it >= 0 } ?: throw CommandError(POSITIVE)
                }
                val values = list(key)
                if (key !in database) return "(nil)"
                val removed = mutableListOf<String>()
                repeat(minOf(count ?: 1, values.size)) { removed += values.removeAt(if (command == "LPOP") 0 else values.lastIndex) }
                update(key, ListValue(values))
                if (count == null) quoted(removed.first()) else arrayReply(removed)
            }
            "LRANGE", "LTRIM" -> {
                val start = number(a[1])
                val stop = number(a[2])
                val values = list(key)
                val selected = range(values.size, start, stop)
                val kept = values.subList(selected.start, selected.end)
                if (command == "LRANGE") arrayReply(kept) else { update(key, ListValue(kept)); "OK" }
            }
            "LLEN" -> integerReply(list(key).size)
            "LINDEX", "LSET" -> {
                var index = number(a[1])
                val values = list(key)
                if (index < 0) index += values.size
                if (command == "LINDEX") return quoted(values.getOrNull(index))
                if (key !in database) throw CommandError("ERR no such key")
                if (index !in values.indices) throw CommandError("ERR index out of range")
                values[index] = a[2]
                update(key, ListValue(values))
                "OK"
            }
            "LREM" -> {
                val count = number(a[1])
                val values = list(key)
                if (count < 0) values.reverse()
                var removed = 0
                val kept = values.filterNot { value ->
                    if (value == a[2] && (count == 0 || removed < abs(count))) { removed++; true } else false
                }.toMutableList()
                if (count < 0) kept.reverse()
                update(key, ListValue(kept))
                integerReply(removed)
            }
            else -> {
                val where = a[1].uppercase()
                if (where !in setOf("BEFORE", "AFTER")) throw CommandError("ERR syntax error")
                val values = list(key)
                if (key !in database) return integerReply(0)
                val index = values.indexOf(a[2])
                if (index < 0) return integerReply(-1)
                values.add(index + if (where == "AFTER") 1 else 0, a[3])
                update(key, ListValue(values))
                integerReply(values.size)
            }
        }
    }

    private fun hashCommand(command: String, a: List<String>): String {
        val key = a.first()
        if (command == "HINCRBY") {
            val delta = number(a[2])
            val fields = hash(key)
            val old = if (a[1] in fields) parseInteger(fields.getValue(a[1])) ?: throw CommandError("ERR hash value is not an integer") else 0
            val value = increment(old, delta)
            fields[a[1]] = value.toString()
            update(key, HashValue(fields))
            return integerReply(value)
        }
        val fields = hash(key)
        return when (command) {
            "HSET" -> {
                var added = 0
                for (i in 1 until a.size step 2) if (fields.put(a[i], a[i + 1]) == null) added++
                update(key, HashValue(fields))
                integerReply(added)
            }
            "HDEL" -> {
                val removed = a.drop(1).count { fields.remove(it) != null }
                update(key, HashValue(fields))
                integerReply(removed)
            }
            "HGET" -> quoted(fields[a[1]])
            "HEXISTS" -> integerReply(if (a[1] in fields) 1 else 0)
            "HLEN" -> integerReply(fields.size)
            "HKEYS" -> arrayReply(fields.keys)
            "HVALS" -> arrayReply(fields.values)
            else -> arrayReply(fields.flatMap { (field, value) -> listOf(field, value) })
        }
    }

    private fun setCommand(command: String, a: List<String>): String {
        val key = a.first()
        val storing = command.endsWith("STORE")
        if (command.startsWith("SINTER") || command.startsWith("SUNION") || command.startsWith("SDIFF")) {
            val sources = a.drop(if (storing) 1 else 0).map { set(it) }
            val result = TreeSet(sources.first())
            for (source in sources.drop(1)) {
                when {
                    command.startsWith("SINTER") -> result.retainAll(source)
                    command.startsWith("SUNION") -> result.addAll(source)
                    else -> result.removeAll(source)
                }
            }
            if (!storing) return arrayReply(result)
            replace(key, SetValue(result))
            return integerReply(result.size)
        }
        val members = set(key)
        return when (command) {
            "SADD", "SREM" -> {
                val changed = a.drop(1).count { if (command == "SADD") members.add(it) else members.remove(it) }
                update(key, SetValue(members))
                integerReply(changed)
            }
            "SCARD" -> integerReply(members.size)
            "SISMEMBER" -> integerReply(if (a[1] in members) 1 else 0)
            else -> arrayReply(members)
        }
    }

    private fun sortedSetCommand(command: String, a: List<String>): String {
        val key = a.first()
        if (command == "ZADD") {
            val numbers = (1 until a.size step 2).map { number(a[it]) }
            val scores = sortedSet(key)
            var added = 0
            for ((i, score) in numbers.withIndex()) if (scores.put(a[2 * i + 2], score) == null) added++
            update(key, SortedSetValue(scores))
            return integerReply(added)
        }
        if (command == "ZINCRBY") {
            val delta = number(a[1])
            val scores = sortedSet(key)
            val value = increment(scores[a[2]] ?: 0, delta)
            scores[a[2]] = value
            update(key, SortedSetValue(scores))
            return quoted(value.toString())
        }
        var withScores = false
        var start = 0
        var stop = 0
        var minimum: Bound? = null
        var maximum: Bound? = null
        if (command == "ZRANGE" || command == "ZRANGEBYSCORE") {
            withScores = a.size == 4
            if (withScores && a[3].uppercase() != "WITHSCORES") throw CommandError("ERR syntax error")
            if (command == "ZRANGE") { start = number(a[1]); stop = number(a[2]) }
            else { minimum = bound(a[1]); maximum = bound(a[2]) }
        }
        val scores = sortedSet(key)
        when (command) {
            "ZREM" -> {
                val removed = a.drop(1).count { scores.remove(it) != null }
                update(key, SortedSetValue(scores))
                return integerReply(removed)
            }
            "ZCARD" -> return integerReply(scores.size)
            "ZSCORE" -> return quoted(scores[a[1]]?.toString())
        }
        val ordered = scores.entries.sortedWith(compareBy<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
        if (command == "ZRANK") {
            val index = ordered.indexOfFirst { it.key == a[1] }
            return if (index < 0) "(nil)" else integerReply(index)
        }
        val selected = if (command == "ZRANGE") range(ordered.size, start, stop) else Range(0, ordered.size)
        val result = mutableListOf<String>()
        for (item in ordered.subList(selected.start, selected.end)) {
            if (minimum != null && (!minimum.accepts(item.value, true) || !maximum!!.accepts(item.value, false))) continue
            result += item.key
            if (withScores) result += item.value.toString()
        }
        return arrayReply(result)
    }

    private fun keyCommand(command: String, a: List<String>): String {
        when (command) {
            "TIME" -> return integerReply(time)
            "DBSIZE" -> return integerReply(database.size)
            "FLUSH" -> { database.clear(); return "OK" }
            "INFO" -> {
                val counts = database.values.groupingBy { it.value.kind }.eachCount()
                val expires = database.values.count { it.expiry != null }
                return "keys=${database.size},expires=$expires,string=${counts["string"] ?: 0}" +
                    ",list=${counts["list"] ?: 0},hash=${counts["hash"] ?: 0},set=${counts["set"] ?: 0},zset=${counts["zset"] ?: 0}" +
                    ",time=$time,depth=${stack.size},snapshots=${snapshots.size}"
            }
            "DEL", "EXISTS" -> return integerReply(a.count { if (command == "DEL") database.remove(it) != null else it in database })
            "KEYS" -> {
                val parts = pattern(a.first())
                return arrayReply(database.keys.filter { matches(parts, it) })
            }
            "TICK" -> {
                val ticks = number(a.first())
                if (ticks <= 0) throw CommandError(POSITIVE)
                time += ticks
                return integerReply(purge())
            }
        }
        val key = a.first()
        if (command == "EXPIRE") {
            val condition = if (a.size == 3) a[2].uppercase() else ""
            if (a.size == 3 && condition !in setOf("NX", "XX", "GT", "LT")) throw CommandError("ERR Unsupported option ${a[2]}")
            val seconds = number(a[1])
            val entry = database[key] ?: return integerReply(0)
            val expiry = time + seconds
            val rejected = when (condition) {
                "NX" -> entry.expiry != null
                "XX" -> entry.expiry == null
                "GT" -> entry.expiry == null || expiry <= entry.expiry
                "LT" -> entry.expiry != null && expiry >= entry.expiry
                else -> false
            }
            if (rejected) return integerReply(0)
            if (seconds <= 0) database.remove(key) else database[key] = entry.copy(expiry = expiry)
            return integerReply(1)
        }
        val entry = database[key]
        return when (command) {
            "TYPE" -> entry?.value?.kind ?: "none"
            "TTL" -> integerReply(if (entry == null) -2 else entry.expiry?.let { it - time } ?: -1)
            "PERSIST" -> {
                if (entry?.expiry == null) return integerReply(0)
                database[key] = entry.copy(expiry = null)
                integerReply(1)
            }
            else -> {
                if (entry == null) throw CommandError("ERR no such key")
                val destination = a[1]
                if (command == "RENAMENX" && destination in database) return integerReply(0)
                if (key != destination) { database.remove(key); database[destination] = entry }
                if (command == "RENAME") "OK" else integerReply(1)
            }
        }
    }

    private fun controlCommand(command: String, a: List<String>): String {
        when (command) {
            "BEGIN" -> stack.add(Database(database))
            "COMMIT", "ROLLBACK" -> {
                if (stack.isEmpty()) throw CommandError("ERR no transaction")
                val saved = stack.removeAt(stack.lastIndex)
                if (command == "ROLLBACK") { database = saved; purge() }
            }
            "SNAPSHOT" -> snapshots[a.first()] = Database(database)
            "RESTORE" -> {
                val saved = snapshots[a.first()] ?: throw CommandError("ERR no such snapshot")
                database = Database(saved)
                purge()
            }
        }
        return "OK"
    }

    fun execute(command: String, args: List<String>): String = when (command) {
        "SET", "GET", "MSET", "MGET", "INCR", "DECR", "INCRBY", "DECRBY", "APPEND", "STRLEN", "GETRANGE" -> textCommand(command, args)
        "LPUSH", "RPUSH", "LPOP", "RPOP", "LRANGE", "LLEN", "LINDEX", "LSET", "LREM", "LTRIM", "LINSERT" -> listCommand(command, args)
        "HSET", "HGET", "HDEL", "HGETALL", "HLEN", "HEXISTS", "HKEYS", "HVALS", "HINCRBY" -> hashCommand(command, args)
        "SADD", "SREM", "SISMEMBER", "SMEMBERS", "SCARD", "SINTER", "SUNION", "SDIFF", "SINTERSTORE", "SUNIONSTORE", "SDIFFSTORE" -> setCommand(command, args)
        "ZADD", "ZSCORE", "ZINCRBY", "ZREM", "ZCARD", "ZRANK", "ZRANGE", "ZRANGEBYSCORE" -> sortedSetCommand(command, args)
        "BEGIN", "COMMIT", "ROLLBACK", "SNAPSHOT", "RESTORE" -> controlCommand(command, args)
        else -> keyCommand(command, args)
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val store = Store()
    repeat(input.readLine().toInt()) {
        val words = splitLine(input.readLine())
        val result = if (words == null) "Invalid argument(s)" else {
            val command = words.first().uppercase()
            val format = arity(command)
            when {
                format == null -> "(error) ERR unknown command '${words.first()}'"
                !format.accepts(words.size - 1) -> "(error) ERR wrong number of arguments for '${command.lowercase()}' command"
                else -> try { store.execute(command, words.drop(1)) } catch (error: CommandError) { "(error) ${error.message}" }
            }
        }
        output.write(result)
        output.write("\n")
    }
    output.flush()
}
