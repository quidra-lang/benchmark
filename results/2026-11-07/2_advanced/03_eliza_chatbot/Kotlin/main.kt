import java.io.File

val sources = listOf("keyword", "memory", "question", "default", "repeat")
val cycledLists = listOf("DEFAULT", "QUESTION", "REPEAT")

fun normalize(text: String): List<List<String>> = text.lowercase().split(',', '.', '?', '!', ';').map { part ->
    part.map { if (it in 'a'..'z' || it in '0'..'9' || it == '\'') it else ' ' }.joinToString("")
        .split(' ').map { it.trim('\'') }.filter { it.isNotEmpty() }
}.filter { it.isNotEmpty() }

fun groupedLines(values: List<String>, width: Int) = values.chunked(width).map { it.joinToString(" ") }
fun rankedCounts(counts: Map<String, Int>): String = counts.filterValues { it > 0 }.entries.sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key }).take(5).joinToString(", ") { "${it.key} ${it.value}" }.ifEmpty { "none" }
fun sourceLine(turns: Int, counts: Map<String, Int>) = "turns=$turns " + sources.joinToString(" ") { "$it=${counts.getValue(it)}" }

class Session(val name: String) {
    var turns = 0
    val counts = sources.associateWith { 0 }.toMutableMap()
    var previous: List<List<String>>? = null
    val history = mutableListOf<String>()
    var lastTrace: List<String>? = null
    var traceOn = false
    val topics = mutableMapOf<String, Int>()
    val words = mutableMapOf<String, Int>()
    var stored = 0
    var recalled = 0
    val unrecognized = mutableListOf<Int>()
    var undo: BotState? = null

    fun copy(): Session {
        val result = Session(name)
        result.turns = turns
        result.counts.putAll(counts)
        result.previous = previous
        result.history.addAll(history)
        result.lastTrace = lastTrace
        result.traceOn = traceOn
        result.topics.putAll(topics)
        result.words.putAll(words)
        result.stored = stored
        result.recalled = recalled
        result.unrecognized.addAll(unrecognized)
        result.undo = undo
        return result
    }
}

class BotState(script: Script) {
    var positions = IntArray(script.rules.size)
    var hits = IntArray(script.rules.size)
    var itemUses = IntArray(script.items.size)
    var keywordUses = IntArray(script.keywords.size)
    var keywordReplies = IntArray(script.keywords.size)
    val listPositions = cycledLists.associateWith { 0 }.toMutableMap()
    var memory = MemoryQueue(script.capacity)
    var session = Session("")

    fun copy(script: Script): BotState {
        val result = BotState(script)
        result.positions = positions.copyOf()
        result.hits = hits.copyOf()
        result.itemUses = itemUses.copyOf()
        result.keywordUses = keywordUses.copyOf()
        result.keywordReplies = keywordReplies.copyOf()
        result.listPositions.putAll(listPositions)
        result.memory = memory.copy()
        result.session = session.copy()
        return result
    }
}

class Chatbot(val script: Script) {
    var state = BotState(script)
    val transcript = mutableListOf<String>()
    var totalTurns = 0
    val totalSources = sources.associateWith { 0 }.toMutableMap()

    fun logPrefix() = "${state.session.name} ${state.session.turns}"
    fun resetCycles() { state.positions.fill(0); for (name in cycledLists) state.listPositions[name] = 0 }
    fun takeText(name: String): String {
        val texts = script.texts.getValue(name)
        val position = state.listPositions.getValue(name)
        state.listPositions[name] = (position + 1) % texts.size
        return texts[position]
    }
    fun takeItem(ruleId: Int): Pair<Int, Item> {
        val rule = script.rules[ruleId]
        val position = state.positions[ruleId]
        val itemId = rule.items[position]
        state.itemUses[itemId]++
        state.positions[ruleId] = (position + 1) % rule.items.size
        return position + 1 to script.items[itemId]
    }
    fun preSubstitute(clauses: List<List<String>>) = clauses.map { clause -> clause.flatMap { script.pre[it] ?: listOf(it) } }
    fun prepared(text: String) = preSubstitute(normalize(text))
    fun isQuit(text: String): Boolean { val words = normalize(text).flatten(); return words.size == 1 && words[0] in script.quit }
    fun selectClause(clauses: List<List<String>>) = clauses.withIndex().firstOrNull { clause -> clause.value.any { it in script.keywordMap } }
    fun keywordList(words: List<String>) = words.mapNotNull { script.keywordMap[it] }.distinct().sortedByDescending { script.keywords[it].rank }
    fun ruleEntries(keyword: Keyword) = keyword.memories.mapIndexed { index, rule -> Triple("memory", index + 1, rule) } + keyword.decomps.mapIndexed { index, rule -> Triple("decomp", index + 1, rule) }
    fun findRule(rules: List<Int>, words: List<String>): Triple<Int, Int, List<List<String>>>? {
        for ((index, ruleId) in rules.withIndex()) {
            val bindings = matchPattern(script.rules[ruleId].pattern, words, script.groupWords)
            if (bindings != null) return Triple(index + 1, ruleId, bindings)
        }
        return null
    }
    fun keywordReply(clauses: List<List<String>>, trace: MutableList<String>): String? {
        val selected = selectClause(clauses)
        if (selected == null) { trace += "CLAUSE none"; return null }
        val words = selected.value
        trace += "CLAUSE ${selected.index + 1} ${words.joinToString(" ")}"
        val keys = keywordList(words)
        trace += "KEYS " + keys.joinToString(" ") { script.keywords[it].word }
        val first = script.keywords[keys[0]]
        val memory = findRule(first.memories, words)
        if (memory != null) {
            val (number, ruleId, bindings) = memory
            trace += "MEMORY ${first.word} $number"
            state.hits[ruleId]++
            if (script.rules[ruleId].items.isNotEmpty()) {
                val text = buildReply(takeItem(ruleId).second.text, bindings, script.post)
                if (state.memory.store(logPrefix(), first.word, text)) state.session.stored++
            }
        }
        val entered = mutableSetOf<Int>()
        for (original in keys) {
            if (original in entered) continue
            var current = original
            var currentWords = words
            trace += "ENTER ${script.keywords[current].word}"
            while (true) {
                entered += current
                state.keywordUses[current]++
                val keyword = script.keywords[current]
                val found = findRule(keyword.decomps, currentWords)
                if (found == null) { trace += "NOMATCH ${keyword.word}"; break }
                val (number, ruleId, bindings) = found
                state.hits[ruleId]++
                if (script.rules[ruleId].items.isEmpty()) { trace += "DECOMP ${keyword.word} $number 0"; break }
                val (itemNumber, item) = takeItem(ruleId)
                trace += "DECOMP ${keyword.word} $number $itemNumber"
                if (item.kind == "REASM") {
                    state.keywordReplies[current]++
                    state.session.topics[keyword.word] = state.session.topics.getOrDefault(keyword.word, 0) + 1
                    return buildReply(item.text, bindings, script.post)
                }
                if (item.kind == "NEWKEY") break
                val target = script.keywordMap[item.arguments[0]]
                if (target == null || target in entered) { trace += "BLOCKED ${item.arguments[0]}"; break }
                if (item.kind == "RESTATE") {
                    currentWords = restatedWords(item.arguments.drop(1), bindings)
                    trace += (listOf("RESTATE", item.arguments[0]) + currentWords).joinToString(" ")
                } else trace += "GOTO ${item.arguments[0]}"
                current = target
            }
        }
        return null
    }

    fun decide(text: String): Pair<String, List<String>> {
        val clauses = normalize(text)
        val session = state.session
        val trace = mutableListOf<String>()
        val reply: String
        val source: String
        if (script.texts.getValue("REPEAT").isNotEmpty() && clauses.isNotEmpty() && clauses == session.previous) {
            trace += "REPEAT"
            reply = takeText("REPEAT")
            source = "repeat"
        } else {
            val keyword = keywordReply(preSubstitute(clauses), trace)
            when {
                keyword != null -> { reply = keyword; source = "keyword" }
                state.memory.texts.isNotEmpty() -> { session.recalled++; reply = state.memory.recall(logPrefix()); source = "memory" }
                text.endsWith("?") && script.texts.getValue("QUESTION").isNotEmpty() -> { reply = takeText("QUESTION"); source = "question" }
                else -> { reply = takeText("DEFAULT"); source = "default" }
            }
        }
        trace += "REPLY $source"
        session.previous = clauses
        session.counts[source] = session.counts.getValue(source) + 1
        if (source == "question" || source == "default") session.unrecognized += session.turns
        return reply to trace
    }

    fun respond(text: String) {
        val snapshot = state.copy(script)
        snapshot.session.undo = null
        val session = state.session
        session.undo = snapshot
        session.turns++
        for (word in normalize(text).flatten()) if (word !in script.stop) session.words[word] = session.words.getOrDefault(word, 0) + 1
        session.history += "${session.turns}: $text"
        val (reply, trace) = decide(text)
        transcript.addAll(elizaLines(reply))
        session.lastTrace = trace
        if (session.traceOn) transcript.addAll(trace.map { "  $it" })
    }

    fun command(line: String): List<String> {
        val name = line.substringBefore(' ')
        val text = line.substringAfter(' ', "")
        val args = if (text.isEmpty()) emptyList() else text.split(' ')
        val none = setOf(":keys", ":why", ":history", ":memory", ":forget", ":reset", ":unused", ":stats", ":undo")
        val some = setOf(":prepare", ":reflect", ":say", ":explain")
        val one = setOf(":groups", ":find", ":script", ":cycles", ":coverage")
        if (name !in none + some + one + setOf(":trace", ":test")) return listOf("unknown command $name")
        if (name in none && args.isNotEmpty() || name in some && text.isEmpty() || name in one && args.size != 1 || name == ":trace" && args != listOf("on") && args != listOf("off") || name == ":test" && args.size < 2) return listOf("bad arguments")
        if (name in setOf(":script", ":cycles", ":coverage", ":test") && args[0] !in script.keywordMap) return listOf("unknown keyword ${args[0]}")
        val session = state.session
        return when (name) {
            ":prepare" -> {
                val clauses = prepared(text)
                val result = clauses.mapIndexed { index, clause -> "clause ${index + 1}: ${clause.joinToString(" ")}" }.toMutableList()
                if (clauses.isEmpty()) result += "no words"
                val selected = selectClause(clauses)
                if (selected == null) result += "selected none"
                else { result += "selected ${selected.index + 1}"; result += "keys " + keywordList(selected.value).joinToString(" ") { "${script.keywords[it].word}/${script.keywords[it].rank}" } }
                result
            }
            ":test" -> {
                val words = prepared(text.substringAfter(' ')).flatten()
                ruleEntries(script.keywords[script.keywordMap.getValue(args[0])]).map { (label, number, rule) ->
                    val bindings = matchPattern(script.rules[rule].pattern, words, script.groupWords)
                    val result = if (bindings == null) "no match" else if (bindings.isEmpty()) "match" else bindings.joinToString(" ") { "[${it.joinToString(" ")}]" }
                    "$label $number: $result"
                }.ifEmpty { listOf("no rules") }
            }
            ":reflect" -> prepared(text).map { reflect(it, script.post).joinToString(" ") }.ifEmpty { listOf("no words") }
            ":keys" -> groupedLines(script.keywords.sortedWith(compareByDescending<Keyword> { it.rank }.thenBy { it.word }).map { "${it.word}/${it.rank}" }, 8)
            ":groups" -> listOf(script.groups.filter { args[0] in it.members }.map { it.name }.sorted().joinToString(" ").ifEmpty { "none" })
            ":find" -> find(args[0])
            ":script" -> {
                val keyword = script.keywords[script.keywordMap.getValue(args[0])]
                val numbers = listOf(keyword.line) + (keyword.memories + keyword.decomps).flatMap { listOf(script.rules[it].line) + script.rules[it].items.map { id -> script.items[id].line } }
                numbers.sorted().map { "$it ${script.lines[it - 1]}" }
            }
            ":why" -> session.lastTrace ?: listOf("no reply yet")
            ":trace" -> { session.traceOn = args[0] == "on"; listOf("trace ${args[0]}") }
            ":history" -> session.history.takeLast(5).ifEmpty { listOf("no turns yet") }
            ":memory" -> listOf("memory ${state.memory.texts.size}/${state.memory.capacity}") + state.memory.texts.mapIndexed { index, value -> "${index + 1}: $value" }
            ":forget" -> { val count = state.memory.texts.size; state.memory.clear(logPrefix()); listOf("forgot $count") }
            ":cycles", ":coverage" -> ruleEntries(script.keywords[script.keywordMap.getValue(args[0])]).map { (label, number, ruleId) ->
                val rule = script.rules[ruleId]
                val details = if (name == ":cycles") {
                    if (rule.items.isEmpty()) "empty" else "next ${state.positions[ruleId] + 1}/${rule.items.size}"
                } else "hits ${state.hits[ruleId]} entries ${rule.items.joinToString(" ") { state.itemUses[it].toString() }.ifEmpty { "-" }}"
                "$label $number: $details"
            }.ifEmpty { listOf("no rules") }
            ":reset" -> { resetCycles(); listOf("cycles reset") }
            ":unused" -> {
                val numbers = script.items.indices.filter { state.itemUses[it] == 0 }.map { script.items[it].line }.sorted()
                listOf("unused ${numbers.size}") + groupedLines(numbers.map(Int::toString), 12)
            }
            ":stats" -> listOf(sourceLine(session.turns, session.counts))
            ":say", ":explain" -> {
                if (isQuit(text)) listOf("would quit")
                else {
                    val saved = state
                    state = state.copy(script)
                    val result = decide(text)
                    state = saved
                    if (name == ":say") listOf(result.first) else result.second
                }
            }
            else -> {
                val snapshot = session.undo
                if (snapshot == null) listOf("nothing to undo")
                else { state = snapshot.copy(script); listOf("undone turn ${state.session.turns + 1}") }
            }
        }
    }

    fun find(word: String): List<String> {
        val result = mutableListOf<String>()
        script.keywordMap[word]?.let { result += "keyword rank ${script.keywords[it].rank}" }
        for ((label, substitutions) in listOf("pre" to script.pres, "post" to script.posts)) for (sub in substitutions) if (sub.source == word || word in sub.replacement) result += "$label ${sub.line}: ${sub.source} -> ${sub.replacement.joinToString(" ")}"
        for (group in script.groups) if (word in group.members) result += "group ${group.name} line ${group.line}"
        for (keyword in script.keywords) for ((label, number, rule) in ruleEntries(keyword)) if (word in script.rules[rule].pattern) result += "pattern ${keyword.word} $label $number"
        if (word in script.stop) result += "stop word"
        if (word in script.quit) result += "quit word"
        return result.ifEmpty { listOf("not found") }
    }

    fun notes() {
        val session = state.session
        transcript += "NOTES ${session.name}"
        transcript.addAll(listOf(sourceLine(session.turns, session.counts), "topics: ${rankedCounts(session.topics)}", "words: ${rankedCounts(session.words)}", "memory: stored=${session.stored} recalled=${session.recalled} pending=${state.memory.texts.size}", "unrecognized: ${session.unrecognized.joinToString(" ").ifEmpty { "none" }}").map { "  $it" })
        totalTurns += session.turns
        for (source in sources) totalSources[source] = totalSources.getValue(source) + session.counts.getValue(source)
    }

    fun run(lines: List<String>) {
        var sessions = 0
        for (line in lines) {
            if (line.startsWith("SESSION ")) {
                val name = line.drop(8)
                sessions++
                if (sessions > 1) {
                    transcript += ""
                    if ("cycles" !in script.persist) resetCycles()
                    if ("memory" !in script.persist) state.memory.clear("$name 0")
                }
                state.session = Session(name)
                transcript += line
                val texts = script.texts.getValue("INITIAL")
                transcript.addAll(elizaLines(texts[(sessions - 1) % texts.size]))
            } else if (line.startsWith(":")) {
                transcript += line
                transcript.addAll(command(line).map { "  $it" })
            } else {
                transcript += "YOU: $line"
                if (isQuit(line)) {
                    val texts = script.texts.getValue("FINAL")
                    transcript.addAll(elizaLines(texts[(sessions - 1) % texts.size]))
                    notes()
                } else respond(line)
            }
        }
        transcript += ""
        transcript += "SUMMARY sessions=$sessions ${sourceLine(totalTurns, totalSources)}"
    }

    fun keywordStats(): List<String> = listOf("keyword,rank,uses,replies,decomposition_hits") + script.keywords.indices.sortedWith(compareByDescending<Int> { state.keywordUses[it] }.thenBy { script.keywords[it].word }).map { index ->
        val keyword = script.keywords[index]
        val hits = keyword.decomps.joinToString("/") { state.hits[it].toString() }.ifEmpty { "-" }
        "${keyword.word},${keyword.rank},${state.keywordUses[index]},${state.keywordReplies[index]},$hits"
    }
}

fun writeLines(name: String, lines: List<String>) { File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n", postfix = "\n")) }

fun main() {
    val script = loadScript("input/script.txt")
    File("output").mkdirs()
    writeLines("lint.txt", lintLines(lint(script)))
    val bot = Chatbot(script)
    bot.run(File("input/dialogue.txt").readLines())
    writeLines("transcript.txt", bot.transcript)
    writeLines("keyword_stats.csv", bot.keywordStats())
    writeLines("memory_log.txt", bot.state.memory.log)
}
