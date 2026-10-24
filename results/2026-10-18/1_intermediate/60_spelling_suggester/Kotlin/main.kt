import java.io.BufferedReader
import java.io.InputStreamReader

private val adjacentKeys = arrayOf(
    "qswz", "ghnv", "dfvx", "cefrsx", "drsw", "cdgrtv", "bfhtvy", "bgjnuy",
    "jkou", "hikmnu", "ijlmo", "kop", "jkn", "bhjm", "iklp", "lo", "aw",
    "deft", "adewxz", "fgry", "hijy", "bcfg", "aeqs", "cdsz", "ghtu", "asx"
)
private val soundexDigits = CharArray(26).also { digits ->
    arrayOf("bfpv", "cgjkqsxz", "dt", "l", "mn", "r", "aeiouy")
        .forEachIndexed { index, letters ->
            letters.forEach { letter -> digits[letter - 'a'] = if (index == 6) '0' else '1' + index }
        }
}
private val wordPattern = Regex("[A-Za-z]{1,30}")
private val numberPattern = Regex("[0-9]{1,7}")
private val tokenPattern = Regex("[A-Za-z]+")
private val counterNames = listOf("checked", "unknown", "case", "capital", "repeats", "corrected")
private val findingNames = listOf("unknown", "case", "capital", "repeats")
private val textCommands = setOf("CHECK", "CORRECT", "FIX", "PROFILE", "LEARN")
private val arities = mapOf(
    "SUGGEST" to 1, "DIST" to 2, "SOUNDEX" to 1, "SOUNDS" to 1,
    "SPLIT" to 1, "PREFIX" to 2, "COMPLETE" to 2, "LIST" to 2,
    "WORD" to 1, "ADD" to 2, "REMOVE" to 1, "IGNORE" to 1,
    "UNIGNORE" to 1, "RULE" to 2, "UNRULE" to 1, "RULES" to 0,
    "KEYBOARD" to 1, "SET" to 2, "UNDO" to 0, "REPORT" to 0,
    "HISTORY" to 0, "STATS" to 0
)

private class CommandError(message: String) : RuntimeException(message)

private fun wordArgument(text: String): String {
    if (!wordPattern.matches(text)) throw CommandError("BAD WORD $text")
    return text.lowercase()
}

private fun numberArgument(text: String, minimum: Int, maximum: Int): Int {
    if (!numberPattern.matches(text)) throw CommandError("BAD NUMBER $text")
    val value = text.toInt()
    if (value !in minimum..maximum) throw CommandError("BAD NUMBER $text")
    return value
}

private fun decimalText(numerator: Long, denominator: Long, digits: Int): String {
    val scale = if (digits == 1) 10L else 100L
    val value = (2 * numerator * scale + denominator) / (2 * denominator)
    return "${value / scale}.${(value % scale).toString().padStart(digits, '0')}"
}

private fun applyCase(original: String, word: String): String = when {
    original.length >= 2 && original.all { it.isUpperCase() } -> word.uppercase()
    original.first().isUpperCase() -> word.replaceFirstChar { it.uppercase() }
    else -> word
}

private data class Token(
    val number: Int, val original: String, val start: Int, val end: Int,
    val gap: String, val previous: Token?
) {
    val word = original.lowercase()
    val sentenceStart = previous == null || gap.any { it in ".!?" }
    val repeated = previous != null && word == previous.word && gap.all { it == ' ' }
    val mixedCase = original.drop(1).any { it.isUpperCase() } && !original.all { it.isUpperCase() }
}

private fun textTokens(text: String): List<Token> {
    val tokens = mutableListOf<Token>()
    var position = 0
    for (match in tokenPattern.findAll(text)) {
        val token = Token(tokens.size + 1, match.value, match.range.first,
            match.range.last + 1, text.substring(position, match.range.first), tokens.lastOrNull())
        tokens += token
        position = token.end
    }
    return tokens
}

private fun substitutionCost(first: Char, second: Char, keyboard: Boolean): Int = when {
    first == second -> 0
    !keyboard || second in adjacentKeys[first - 'a'] -> 1
    else -> 2
}

private fun isSwap(first: String, second: String, i: Int, j: Int) =
    i >= 2 && j >= 2 && first[i - 1] == second[j - 2] && first[i - 2] == second[j - 1]

private fun distanceTable(first: String, second: String, keyboard: Boolean): Array<IntArray> {
    val m = first.length
    val n = second.length
    val gap = if (keyboard) 2 else 1
    val table = Array(m + 1) { IntArray(n + 1) }
    for (i in 0..m) table[i][0] = i * gap
    for (j in 0..n) table[0][j] = j * gap
    for (i in 1..m) {
        for (j in 1..n) {
            var best = minOf(table[i - 1][j] + gap, table[i][j - 1] + gap,
                table[i - 1][j - 1] + substitutionCost(first[i - 1], second[j - 1], keyboard))
            if (isSwap(first, second, i, j)) best = minOf(best, table[i - 2][j - 2] + 1)
            table[i][j] = best
        }
    }
    return table
}

private fun editDistance(first: String, second: String, keyboard: Boolean): Int =
    distanceTable(first, second, keyboard)[first.length][second.length]

private fun prefixDistance(word: String, other: String, keyboard: Boolean): Int =
    distanceTable(word, other, keyboard)[word.length].min()

private fun editOperations(first: String, second: String, keyboard: Boolean): Pair<Int, List<String>> {
    val table = distanceTable(first, second, keyboard)
    val gap = if (keyboard) 2 else 1
    var i = first.length
    var j = second.length
    val operations = mutableListOf<String>()
    while (i > 0 || j > 0) {
        if (i >= 1 && j >= 1 && table[i][j] == table[i - 1][j - 1] +
            substitutionCost(first[i - 1], second[j - 1], keyboard)) {
            if (first[i - 1] != second[j - 1]) operations += "sub:${first[i - 1]}>${second[j - 1]}"
            --i; --j
        } else if (isSwap(first, second, i, j) && table[i][j] == table[i - 2][j - 2] + 1) {
            operations += "swap:${first.substring(i - 2, i)}"
            i -= 2; j -= 2
        } else if (i >= 1 && table[i][j] == table[i - 1][j] + gap) {
            operations += "del:${first[i - 1]}"
            --i
        } else {
            operations += "ins:${second[j - 1]}"
            --j
        }
    }
    return table[first.length][second.length] to operations.asReversed()
}

private fun soundex(word: String): String {
    val code = StringBuilder(word.first().uppercase())
    var previous = if (word.first() in "hw") '0' else soundexDigits[word.first() - 'a']
    for (letter in word.drop(1)) {
        if (letter in "hw") continue
        val digit = soundexDigits[letter - 'a']
        if (digit != '0' && digit != previous) code.append(digit)
        previous = digit
    }
    return (code.toString() + "000").take(4)
}

private data class Segmentation(val ways: Long, val words: List<String>?)
private fun segment(word: String, dictionary: Map<String, Int>): Segmentation {
    val n = word.length
    val ways = LongArray(n + 1)
    val best = arrayOfNulls<List<String>>(n + 1)
    ways[n] = 1
    best[n] = emptyList()
    for (start in n - 1 downTo 0) {
        for (end in start + 1..n) {
            val piece = word.substring(start, end)
            if (piece !in dictionary || ways[end] == 0L) continue
            ways[start] += ways[end]
            val candidate = listOf(piece) + best[end]!!
            val current = best[start]
            if (current == null || candidate.size < current.size ||
                (candidate.size == current.size && lexicographic(candidate, current) < 0)) {
                best[start] = candidate
            }
        }
    }
    return Segmentation(ways[0], best[0])
}

private fun lexicographic(first: List<String>, second: List<String>): Int {
    for (index in 0 until minOf(first.size, second.size)) {
        val comparison = first[index].compareTo(second[index])
        if (comparison != 0) return comparison
    }
    return first.size.compareTo(second.size)
}

private data class Candidate(val word: String, val distance: Int, val frequency: Int)
private data class UndoRecord(
    val command: String, val dictionary: MutableMap<String, Int>,
    val ignored: MutableSet<String>, val rules: MutableMap<String, String>
)

private class SpellChecker(initial: Map<String, Int>) {
    private var dictionary = initial.toMutableMap()
    private var ignored = mutableSetOf<String>()
    private var rules = mutableMapOf<String, String>()
    private var keyboard = false
    private var baseLimit = 2
    private var suggestionCount = 5
    private val undoHistory = mutableListOf<UndoRecord>()
    private val unknownLog = mutableMapOf<String, Int>()
    private val correctionLog = mutableMapOf<String, Int>()
    private val counters = counterNames.associateWith { 0 }.toMutableMap()
    val output = mutableListOf<String>()

    private fun emit(vararg parts: Any) { output += parts.joinToString(" ") }
    private fun limit() = if (keyboard) 2 * baseLimit else baseLimit
    private fun isKnown(word: String) = word in dictionary || word in ignored

    private fun frequencyOrder(): List<String> = dictionary.entries.sortedWith(
        compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key }
    ).map { it.key }

    private fun requireEntry(word: String): Int = dictionary[word] ?: throw CommandError("NOT FOUND $word")

    private fun candidates(word: String): List<Candidate> {
        val gap = if (keyboard) 2 else 1
        val maximum = limit()
        return dictionary.mapNotNull { (other, frequency) ->
            if (other == word || kotlin.math.abs(other.length - word.length) * gap > maximum) {
                null
            } else {
                val distance = editDistance(word, other, keyboard)
                if (distance <= maximum) Candidate(other, distance, frequency) else null
            }
        }.sortedWith(compareBy<Candidate> { it.distance }.thenByDescending { it.frequency }.thenBy { it.word })
    }

    private fun correction(word: String): String? = when {
        isKnown(word) -> null
        word in rules -> rules[word]
        else -> candidates(word).firstOrNull()?.word
    }

    private fun recordUndo(command: String) {
        undoHistory += UndoRecord(command, dictionary.toMutableMap(), ignored.toMutableSet(), rules.toMutableMap())
    }

    private fun logCorrection(word: String, replacement: String) {
        val key = "$word>$replacement"
        correctionLog[key] = correctionLog.getOrDefault(key, 0) + 1
        counters["corrected"] = counters.getValue("corrected") + 1
    }

    private fun unknownFinding(token: Token): String {
        val prefix = "UNKNOWN ${token.number} ${token.original}"
        rules[token.word]?.let { return "$prefix RULE $it" }
        val found = candidates(token.word)
        return if (found.isEmpty()) "$prefix NONE" else
            "$prefix SUGGEST ${found.take(suggestionCount).joinToString(" ") { it.word }}"
    }

    private fun checkText(text: String) {
        val tokens = textTokens(text)
        val findings = mutableListOf<String>()
        val counts = findingNames.associateWith { 0 }.toMutableMap()
        fun finding(kind: String, line: String) {
            findings += line
            counts[kind] = counts.getValue(kind) + 1
        }
        for (token in tokens) {
            if (!isKnown(token.word)) {
                finding("unknown", unknownFinding(token))
                unknownLog[token.word] = unknownLog.getOrDefault(token.word, 0) + 1
            }
            if (token.mixedCase) finding("case", "CASE ${token.number} ${token.original}")
            if (token.sentenceStart && token.original.first().isLowerCase())
                finding("capital", "CAPITAL ${token.number} ${token.original}")
            if (token.repeated) finding("repeats", "REPEAT ${token.number} ${token.original}")
        }
        counters["checked"] = counters.getValue("checked") + tokens.size
        findingNames.forEach { counters[it] = counters.getValue(it) + counts.getValue(it) }
        emit("CHECK words=${tokens.size}", findingNames.joinToString(" ") { "$it=${counts.getValue(it)}" })
        output.addAll(findings)
    }

    private fun correctText(text: String) {
        val result = StringBuilder()
        var position = 0
        var changed = 0
        for (token in textTokens(text)) {
            val replacement = correction(token.word)
            result.append(token.gap)
            if (replacement == null) {
                result.append(token.original)
            } else {
                result.append(applyCase(token.original, replacement))
                logCorrection(token.word, replacement)
                changed++
            }
            position = token.end
        }
        result.append(text.substring(position))
        output += "CORRECT changed=$changed: $result"
    }

    private fun fixText(text: String) {
        val result = StringBuilder()
        var position = 0
        var removed = 0
        var replaced = 0
        var recased = 0
        for (token in textTokens(text)) {
            position = token.end
            if (token.repeated) { removed++; continue }
            val replacement = correction(token.word)
            var revised = applyCase(token.original, replacement ?: token.word)
            if (token.sentenceStart && revised[0].isLowerCase())
                revised = revised.replaceFirstChar { it.uppercase() }
            if (replacement != null) {
                logCorrection(token.word, replacement)
                replaced++
            } else if (revised != token.original) {
                recased++
            }
            result.append(token.gap).append(revised)
        }
        result.append(text.substring(position))
        output += "FIX removed=$removed replaced=$replaced recased=$recased: $result"
    }

    private fun profile(text: String) {
        val tokens = textTokens(text)
        val size = tokens.size
        val distinct = tokens.map { it.word }.toSet().size
        val unknown = tokens.count { !isKnown(it.word) }
        val sentences = tokens.count { it.sentenceStart }
        val longest = tokens.maxByOrNull { it.original.length }?.word ?: "-"
        val rate = if (size == 0) "0.0" else decimalText(100L * unknown, size.toLong(), 1)
        val average = if (size == 0) "0.00" else
            decimalText(tokens.sumOf { it.original.length }.toLong(), size.toLong(), 2)
        emit("PROFILE words=$size distinct=$distinct unknown=$unknown rate=$rate avglen=$average longest=$longest sentences=$sentences")
    }

    private fun learn(text: String) {
        recordUndo("LEARN")
        var updated = 0
        var added = 0
        var skipped = 0
        for (token in textTokens(text)) {
            when {
                token.word.length > 30 -> skipped++
                token.word in dictionary -> { dictionary[token.word] = dictionary.getValue(token.word) + 1; updated++ }
                else -> { dictionary[token.word] = 1; ignored.remove(token.word); added++ }
            }
        }
        emit("LEARN updated=$updated added=$added skipped=$skipped")
    }

    private fun suggest(args: List<String>) {
        val word = wordArgument(args[0])
        when {
            isKnown(word) -> emit("SUGGEST", word, "KNOWN")
            word in rules -> emit("SUGGEST", word, "RULE", rules.getValue(word))
            else -> {
                val found = candidates(word)
                val entries = found.take(suggestionCount).joinToString(" ") { "${it.word}:${it.distance}" }
                output += "SUGGEST $word found=${found.size}${if (entries.isEmpty()) "" else " $entries"}"
            }
        }
    }

    private fun dist(args: List<String>) {
        val first = wordArgument(args[0]); val second = wordArgument(args[1])
        val (distance, operations) = editOperations(first, second, keyboard)
        output += (listOf("DIST", first, second, distance.toString()) + operations).joinToString(" ")
    }

    private fun sounds(args: List<String>) {
        val word = wordArgument(args[0])
        val code = soundex(word)
        val found = frequencyOrder().filter { it != word && soundex(it) == code }
        output += (listOf("SOUNDS", word, code, "count=${found.size}") + found.take(10)).joinToString(" ")
    }

    private fun split(args: List<String>) {
        val word = wordArgument(args[0])
        val result = segment(word, dictionary)
        output += (listOf("SPLIT", word, "ways=${result.ways}", "->") +
            (result.words ?: listOf("NONE"))).joinToString(" ")
    }

    private fun prefix(args: List<String>) {
        val word = wordArgument(args[0])
        val count = numberArgument(args[1], 1, 20)
        val found = frequencyOrder().filter { it.startsWith(word) }
        output += (listOf("PREFIX", word, "count=${found.size}") +
            found.take(count).map { "$it:${dictionary.getValue(it)}" }).joinToString(" ")
    }

    private fun complete(args: List<String>) {
        val word = wordArgument(args[0])
        val count = numberArgument(args[1], 1, 20)
        val threshold = limit() / 2
        val found = dictionary.mapNotNull { (other, frequency) ->
            val distance = prefixDistance(word, other, keyboard)
            if (distance <= threshold) Candidate(other, distance, frequency) else null
        }.sortedWith(compareBy<Candidate> { it.distance }.thenByDescending { it.frequency }.thenBy { it.word })
        output += (listOf("COMPLETE", word, "count=${found.size}") +
            found.take(count).map { "${it.word}:${it.distance}" }).joinToString(" ")
    }

    private fun listWords(args: List<String>) {
        val word = wordArgument(args[0])
        val count = numberArgument(args[1], 1, 20)
        val found = dictionary.keys.filter { it >= word }.sorted()
        output += (listOf("LIST", word, "count=${found.size}") +
            found.take(count).map { "$it:${dictionary.getValue(it)}" }).joinToString(" ")
    }

    private fun wordInfo(args: List<String>) {
        val word = wordArgument(args[0])
        val frequency = requireEntry(word)
        val rank = frequencyOrder().indexOf(word) + 1
        emit("WORD $word freq=$frequency rank=$rank soundex=${soundex(word)} neighbors=${candidates(word).size}")
    }

    private fun add(args: List<String>) {
        val word = wordArgument(args[0])
        val frequency = numberArgument(args[1], 1, 1000000)
        if (word in dictionary) throw CommandError("DUPLICATE $word")
        recordUndo("ADD")
        dictionary[word] = frequency
        ignored.remove(word)
        emit("ADD", word, frequency)
    }

    private fun remove(args: List<String>) {
        val word = wordArgument(args[0])
        val frequency = requireEntry(word)
        recordUndo("REMOVE")
        dictionary.remove(word)
        emit("REMOVE", word, frequency)
    }

    private fun ignore(args: List<String>) {
        val word = wordArgument(args[0])
        if (word in dictionary) throw CommandError("IN DICTIONARY $word")
        if (word in ignored) throw CommandError("ALREADY IGNORED $word")
        recordUndo("IGNORE")
        ignored.add(word)
        emit("IGNORE", word)
    }

    private fun unignore(args: List<String>) {
        val word = wordArgument(args[0])
        if (word !in ignored) throw CommandError("NOT IGNORED $word")
        recordUndo("UNIGNORE")
        ignored.remove(word)
        emit("UNIGNORE", word)
    }

    private fun rule(args: List<String>) {
        val source = wordArgument(args[0])
        val target = wordArgument(args[1])
        if (source in dictionary) throw CommandError("IN DICTIONARY $source")
        if (target !in dictionary) throw CommandError("NOT FOUND $target")
        recordUndo("RULE")
        val previous = rules.put(source, target)
        if (previous == null) emit("RULE", source, target)
        else emit("RULE", source, target, "REPLACED", previous)
    }

    private fun unrule(args: List<String>) {
        val word = wordArgument(args[0])
        if (word !in rules) throw CommandError("NO RULE $word")
        recordUndo("UNRULE")
        val target = rules.remove(word)!!
        emit("UNRULE", word, target)
    }

    private fun showRules() {
        val entries = rules.toSortedMap().map { (source, target) -> "$source>$target" }
        output += (listOf("RULES", "count=${entries.size}") + entries).joinToString(" ")
    }

    private fun keyboardMode(args: List<String>) {
        val mode = args[0]
        if (mode != "ON" && mode != "OFF") throw CommandError("BAD MODE $mode")
        keyboard = mode == "ON"
        emit("KEYBOARD", mode)
    }

    private fun setOption(args: List<String>) {
        val option = args[0]
        if (option != "LIMIT" && option != "SUGGESTIONS") throw CommandError("BAD OPTION $option")
        val value = numberArgument(args[1], 1, if (option == "LIMIT") 3 else 10)
        if (option == "LIMIT") baseLimit = value else suggestionCount = value
        emit("SET", option, value)
    }

    private fun undo() {
        if (undoHistory.isEmpty()) throw CommandError("NOTHING TO UNDO")
        val snapshot = undoHistory.removeAt(undoHistory.lastIndex)
        dictionary = snapshot.dictionary
        ignored = snapshot.ignored
        rules = snapshot.rules
        emit("UNDO", snapshot.command)
    }

    private fun report() {
        val entries = unknownLog.entries.sortedWith(
            compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key }
        ).take(10).map { "${it.key}:${it.value}" }
        output += (listOf("REPORT", "distinct=${unknownLog.size}") + entries).joinToString(" ")
    }

    private fun history() {
        val entries = correctionLog.entries.sortedWith(
            compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key }
        ).take(10).map { "${it.key}:${it.value}" }
        output += (listOf("HISTORY", "distinct=${correctionLog.size}") + entries).joinToString(" ")
    }

    private fun stats() {
        val top = frequencyOrder().first()
        val total = dictionary.values.sumOf { it.toLong() }
        val characters = dictionary.keys.sumOf { it.length.toLong() }
        emit("STATS words=${dictionary.size} total=$total avglen=${decimalText(characters, dictionary.size.toLong(), 2)}",
            "top=$top:${dictionary.getValue(top)} ignored=${ignored.size} rules=${rules.size}",
            "keyboard=${if (keyboard) "ON" else "OFF"} limit=${limit()}",
            "suggestions=$suggestionCount undo=${undoHistory.size}")
        output += (listOf("SESSION") + counterNames.map { "$it=${counters.getValue(it)}" }).joinToString(" ")
    }

    fun execute(line: String) {
        val separator = line.indexOf(' ')
        val command = if (separator == -1) line else line.substring(0, separator)
        val rest = if (separator == -1) "" else line.substring(separator + 1)
        try {
            if (command in textCommands) {
                if (separator == -1) throw CommandError("BAD ARGUMENTS $command")
                when (command) {
                    "CHECK" -> checkText(rest)
                    "CORRECT" -> correctText(rest)
                    "FIX" -> fixText(rest)
                    "PROFILE" -> profile(rest)
                    "LEARN" -> learn(rest)
                }
                return
            }
            val expected = arities[command] ?: throw CommandError("UNKNOWN COMMAND $command")
            val args = if (separator == -1) emptyList() else rest.split(' ')
            if (args.size != expected) throw CommandError("BAD ARGUMENTS $command")
            when (command) {
                "SUGGEST" -> suggest(args)
                "DIST" -> dist(args)
                "SOUNDEX" -> { val word = wordArgument(args[0]); emit("SOUNDEX", word, soundex(word)) }
                "SOUNDS" -> sounds(args)
                "SPLIT" -> split(args)
                "PREFIX" -> prefix(args)
                "COMPLETE" -> complete(args)
                "LIST" -> listWords(args)
                "WORD" -> wordInfo(args)
                "ADD" -> add(args)
                "REMOVE" -> remove(args)
                "IGNORE" -> ignore(args)
                "UNIGNORE" -> unignore(args)
                "RULE" -> rule(args)
                "UNRULE" -> unrule(args)
                "RULES" -> showRules()
                "KEYBOARD" -> keyboardMode(args)
                "SET" -> setOption(args)
                "UNDO" -> undo()
                "REPORT" -> report()
                "HISTORY" -> history()
                "STATS" -> stats()
            }
        } catch (error: CommandError) {
            emit("ERROR", error.message!!)
        }
    }
}

fun main() {
    val input = BufferedReader(InputStreamReader(System.`in`))
    val size = input.readLine().toInt()
    val dictionary = mutableMapOf<String, Int>()
    repeat(size) {
        val entry = input.readLine().split(' ')
        dictionary[entry[0]] = entry[1].toInt()
    }
    val checker = SpellChecker(dictionary)
    val count = input.readLine().toInt()
    repeat(count) { checker.execute(input.readLine()) }
    print(checker.output.joinToString("\n", postfix = "\n"))
}
