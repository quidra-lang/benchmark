private val TOKEN_PATTERN = Regex("[A-Za-z]+")
private val WORD_PATTERN = Regex("[A-Za-z]{1,30}")
private val NUMBER_PATTERN = Regex("[0-9]{1,7}")
private val PREFIX_TERM_PATTERN = Regex("""[A-Za-z]{1,30}\*""")
private val LEXEME_PATTERN = Regex("[()]|[^ ()]+")
private const val VOWELS = "aeiou"
private val STEP_NAMES = listOf("1a", "1b", "1c", "2", "3", "4", "5a", "5b")
private val STEP_4_SUFFIXES = listOf(
    "al", "ance", "ence", "er", "ic", "able", "ible", "ant", "ement", "ment",
    "ent", "ion", "ou", "ism", "ate", "iti", "ous", "ive", "ize",
)
private const val KWIC_WIDTH = 30
private const val MAX_COUNT = 100
private const val MAX_DOCUMENT_NUMBER = 999
private const val MAX_LINE_NUMBER = 999

class CommandError(message: String) : Exception(message)

fun letterPattern(word: String): String {
    val kinds = StringBuilder()
    for ((index, letter) in word.withIndex()) {
        val vowel = letter in VOWELS || (letter == 'y' && index > 0 && kinds[index - 1] == 'C')
        kinds.append(if (vowel) 'V' else 'C')
    }
    return kinds.toString()
}

fun measure(word: String): Int = letterPattern(word).windowed(2).count { it == "VC" }

fun hasVowel(word: String): Boolean = 'V' in letterPattern(word)

fun endsDouble(word: String): Boolean =
    letterPattern(word).endsWith("CC") && word.last() == word[word.length - 2]

fun endsCvc(word: String): Boolean =
    letterPattern(word).endsWith("CVC") && word.last() !in "wxy"

fun measureAboveZero(remainder: String): Boolean = measure(remainder) > 0

fun measureAboveOne(remainder: String): Boolean = measure(remainder) > 1

fun ionCondition(remainder: String): Boolean =
    measure(remainder) > 1 && (remainder.endsWith("s") || remainder.endsWith("t"))

fun finalECondition(remainder: String): Boolean {
    val value = measure(remainder)
    return value > 1 || (value == 1 && !endsCvc(remainder))
}

data class Rule(val suffix: String, val replacement: String, val condition: (String) -> Boolean)

fun rulesWith(
    condition: (String) -> Boolean,
    vararg replacements: Pair<String, String>,
): List<Rule> = replacements.map { (suffix, replacement) -> Rule(suffix, replacement, condition) }

private val RULE_TABLES: Map<String, List<Rule>> = mapOf(
    "1a" to rulesWith({ true }, "sses" to "ss", "ies" to "i", "ss" to "ss", "s" to ""),
    "1b" to listOf(
        Rule("eed", "ee", ::measureAboveZero),
        Rule("ed", "", ::hasVowel),
        Rule("ing", "", ::hasVowel),
    ),
    "1c" to listOf(Rule("y", "i", ::hasVowel)),
    "2" to rulesWith(
        ::measureAboveZero,
        "ational" to "ate", "tional" to "tion", "enci" to "ence", "anci" to "ance",
        "izer" to "ize", "abli" to "able", "alli" to "al", "entli" to "ent", "eli" to "e",
        "ousli" to "ous", "ization" to "ize", "ation" to "ate", "ator" to "ate",
        "alism" to "al", "iveness" to "ive", "fulness" to "ful", "ousness" to "ous",
        "aliti" to "al", "iviti" to "ive", "biliti" to "ble",
    ),
    "3" to rulesWith(
        ::measureAboveZero,
        "icate" to "ic", "ative" to "", "alize" to "al", "iciti" to "ic",
        "ical" to "ic", "ful" to "", "ness" to "",
    ),
    "4" to STEP_4_SUFFIXES.map { suffix ->
        Rule(suffix, "", if (suffix == "ion") ::ionCondition else ::measureAboveOne)
    },
    "5a" to listOf(Rule("e", "", ::finalECondition)),
)

data class RuleOutcome(val word: String, val suffix: String?)

fun applyRules(word: String, rules: List<Rule>): RuleOutcome {
    val rule = rules.filter { word.endsWith(it.suffix) }.maxByOrNull { it.suffix.length }
        ?: return RuleOutcome(word, null)
    val remainder = word.dropLast(rule.suffix.length)
    if (!rule.condition(remainder)) return RuleOutcome(word, null)
    return RuleOutcome(remainder + rule.replacement, rule.suffix)
}

fun tidyStep1b(word: String): String = when {
    listOf("at", "bl", "iz").any { word.endsWith(it) } -> word + "e"
    endsDouble(word) && word.last() !in "lsz" -> word.dropLast(1)
    measure(word) == 1 && endsCvc(word) -> word + "e"
    else -> word
}

fun applyStep(name: String, word: String): String {
    if (name == "5b") {
        val removable = measure(word) > 1 && endsDouble(word) && word.endsWith("l")
        return if (removable) word.dropLast(1) else word
    }
    val (result, suffix) = applyRules(word, RULE_TABLES.getValue(name))
    return if (name == "1b" && (suffix == "ed" || suffix == "ing")) tidyStep1b(result) else result
}

data class StepChange(val step: String, val word: String)

data class Stemming(val stem: String, val changes: List<StepChange>)

fun stemmingSteps(word: String): Stemming {
    val changes = mutableListOf<StepChange>()
    var current = word
    if (word.length > 2) {
        for (name in STEP_NAMES) {
            val result = applyStep(name, current)
            if (result != current) changes.add(StepChange(name, result))
            current = result
        }
    }
    return Stemming(current, changes)
}

fun porterStem(word: String): String = stemmingSteps(word).stem

fun yesNo(flag: Boolean): String = if (flag) "YES" else "NO"

fun wordArgument(text: String): String {
    if (!WORD_PATTERN.matches(text)) throw CommandError("BAD WORD $text")
    return text.lowercase()
}

fun numberArgument(text: String, minimum: Int, maximum: Int): Int {
    if (!NUMBER_PATTERN.matches(text)) throw CommandError("BAD NUMBER $text")
    val value = text.toInt()
    if (value !in minimum..maximum) throw CommandError("BAD NUMBER $text")
    return value
}

fun splitArguments(name: String, rest: String): List<String> = when (name) {
    "SEARCH" -> listOf(rest)
    "APPEND" -> rest.split(" ", limit = 2)
    else -> rest.split(" ")
}

private val BY_COUNT = compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key }

tailrec fun gcd(first: Int, second: Int): Int =
    if (second == 0) first else gcd(second, first % second)

data class Fraction(val numerator: Int, val denominator: Int) : Comparable<Fraction> {
    override fun compareTo(other: Fraction): Int =
        (numerator.toLong() * other.denominator).compareTo(other.numerator.toLong() * denominator)

    override fun toString(): String = "$numerator/$denominator"

    companion object {
        fun of(numerator: Int, denominator: Int): Fraction {
            val divisor = gcd(numerator, denominator)
            return Fraction(numerator / divisor, denominator / divisor)
        }
    }
}

data class Similarity(val document: Int, val score: Fraction)

data class Ranking(val document: Int, val matched: Int, val total: Int)

fun closestDistance(positions: List<Int>, others: List<Int>, sameStem: Boolean): Int? {
    val gaps = if (sameStem) {
        positions.zipWithNext { earlier, later -> later - earlier }
    } else {
        val merged = (positions.map { it to 0 } + others.map { it to 1 }).sortedBy { it.first }
        merged.zipWithNext()
            .filter { (earlier, later) -> earlier.second != later.second }
            .map { (earlier, later) -> later.first - earlier.first }
    }
    return gaps.minOrNull()
}

enum class Kind { AND, OR, NOT, OPEN, CLOSE, TERM, PREFIX }

data class QueryItem(val kind: Kind, val spelling: String)

data class QueryResult(val canonical: String, val documents: Set<Int>)

private val SYMBOLS = mapOf(
    "AND" to Kind.AND, "OR" to Kind.OR, "NOT" to Kind.NOT, "(" to Kind.OPEN, ")" to Kind.CLOSE,
)
private val CONJUNCTION_CONTINUATIONS = setOf(Kind.AND, Kind.NOT, Kind.OPEN, Kind.TERM, Kind.PREFIX)

fun classify(lexeme: String): QueryItem {
    SYMBOLS[lexeme]?.let { return QueryItem(it, lexeme) }
    return when {
        WORD_PATTERN.matches(lexeme) -> QueryItem(Kind.TERM, lexeme.lowercase())
        PREFIX_TERM_PATTERN.matches(lexeme) ->
            QueryItem(Kind.PREFIX, lexeme.dropLast(1).lowercase())
        else -> throw CommandError("BAD TERM $lexeme")
    }
}

data class Token(val text: String, val line: Int, val position: Int, val start: Int) {
    val form: String = text.lowercase()
    val stem: String = porterStem(form)
    val end: Int get() = start + text.length
}

class Document(val number: Int) {
    val lines = mutableListOf<String>()
    val tokens = mutableListOf<Token>()

    fun addLine(text: String): List<Token> {
        lines.add(text)
        val added = mutableListOf<Token>()
        for (match in TOKEN_PATTERN.findAll(text)) {
            val token = Token(match.value, lines.size, tokens.size + 1, match.range.first)
            tokens.add(token)
            added.add(token)
        }
        return added
    }

    fun lineTokens(lineNumber: Int): List<Token> = tokens.filter { it.line == lineNumber }

    fun reference(token: Token): String = "$number:${token.line}:${token.position}"
}

data class Occurrence(val document: Document, val token: Token) {
    val reference: String get() = document.reference(token)
}

fun documentCount(occurrences: List<Occurrence>): Int =
    occurrences.distinctBy { it.document.number }.size

class QueryParser(private val items: List<QueryItem>, private val stemSets: Map<Int, Set<String>>) {
    private var position = 0

    private fun peek(): Kind? = items.getOrNull(position)?.kind

    private fun take(): QueryItem {
        if (position >= items.size) throw CommandError("SYNTAX")
        return items[position++]
    }

    fun parse(): QueryResult {
        val result = expression()
        if (position < items.size) throw CommandError("SYNTAX")
        return result
    }

    private fun expression(): QueryResult {
        var result = conjunction()
        while (peek() == Kind.OR) {
            position++
            val right = conjunction()
            result = QueryResult(
                "(${result.canonical} OR ${right.canonical})",
                result.documents union right.documents,
            )
        }
        return result
    }

    private fun conjunction(): QueryResult {
        var result = negation()
        while (peek() in CONJUNCTION_CONTINUATIONS) {
            if (peek() == Kind.AND) position++
            val right = negation()
            result = QueryResult(
                "(${result.canonical} AND ${right.canonical})",
                result.documents intersect right.documents,
            )
        }
        return result
    }

    private fun negation(): QueryResult {
        if (peek() == Kind.NOT) {
            position++
            val inner = negation()
            return QueryResult("(NOT ${inner.canonical})", stemSets.keys - inner.documents)
        }
        return element()
    }

    private fun element(): QueryResult {
        val item = take()
        return when (item.kind) {
            Kind.OPEN -> {
                val result = expression()
                if (take().kind != Kind.CLOSE) throw CommandError("SYNTAX")
                result
            }
            Kind.TERM -> {
                val stem = porterStem(item.spelling)
                QueryResult(stem, documentsWhere { stem in it })
            }
            Kind.PREFIX -> QueryResult(
                "${item.spelling}*",
                documentsWhere { stems -> stems.any { it.startsWith(item.spelling) } },
            )
            else -> throw CommandError("SYNTAX")
        }
    }

    private fun documentsWhere(condition: (Set<String>) -> Boolean): Set<Int> =
        stemSets.filterValues(condition).keys
}

data class Command(val arity: IntRange, val handler: (List<String>) -> Unit)

class SearchEngine(private val stopwords: MutableSet<String>) {
    private val documents = sortedMapOf<Int, Document>()
    val output = StringBuilder()
    private val commands = mapOf(
        "STEM" to Command(1..10, ::stemWords),
        "STEPS" to Command(1..1, ::showSteps),
        "MEASURE" to Command(1..1, ::showMeasure),
        "INDEX" to Command(0..1, ::showIndex),
        "SEARCH" to Command(1..1, ::search),
        "PHRASE" to Command(2..10, ::phrase),
        "NEAR" to Command(3..3, ::near),
        "TOP" to Command(1..2, ::top),
        "KWIC" to Command(1..1, ::kwic),
        "TF" to Command(2..2, ::termFrequency),
        "DF" to Command(1..1, ::documentFrequency),
        "VARIANTS" to Command(1..1, ::variants),
        "SIMILAR" to Command(2..2, ::similar),
        "RANK" to Command(2..11, ::rank),
        "INFO" to Command(1..1, ::info),
        "LINE" to Command(2..2, ::showLine),
        "STATS" to Command(0..0, ::stats),
        "STOP" to Command(1..1, ::stop),
        "UNSTOP" to Command(1..1, ::unstop),
        "APPEND" to Command(2..2, ::append),
        "DELETE" to Command(1..1, ::delete),
    )

    private fun emit(head: String, items: List<String> = emptyList()) {
        output.appendLine((listOf(head) + items).joinToString(" "))
    }

    fun addDocument(number: Int): Document = Document(number).also { documents[number] = it }

    private fun isStopword(word: String): Boolean = word in stopwords

    private fun isIndexed(token: Token): Boolean = token.form !in stopwords

    private fun indexedTokens(document: Document): List<Token> = document.tokens.filter(::isIndexed)

    private fun termFrequencies(document: Document): Map<String, Int> =
        indexedTokens(document).groupingBy { it.stem }.eachCount()

    private fun stemSet(document: Document): Set<String> = termFrequencies(document).keys

    private fun totalFrequencies(): Map<String, Int> =
        documents.values.flatMap(::indexedTokens).groupingBy { it.stem }.eachCount()

    private fun occurrenceMap(): Map<String, List<Occurrence>> =
        documents.values
            .flatMap { document -> indexedTokens(document).map { Occurrence(document, it) } }
            .groupBy { it.token.stem }

    private fun occurrencesOf(stem: String): List<Occurrence> = occurrenceMap()[stem].orEmpty()

    private fun stemPositions(document: Document, stem: String): List<Int> =
        indexedTokens(document).filter { it.stem == stem }.map { it.position }

    private fun formCount(form: String): Int =
        documents.values.sumOf { document -> document.tokens.count { it.form == form } }

    private fun tokenMatches(token: Token, target: String): Boolean =
        target == "?" || (isIndexed(token) && token.stem == target)

    private fun describeToken(token: Token): String =
        if (isIndexed(token)) "${token.form}/${token.stem}" else "${token.form}/-"

    private fun termArgument(text: String): String {
        val word = wordArgument(text)
        if (isStopword(word)) throw CommandError("STOPWORD $word")
        return porterStem(word)
    }

    private fun documentArgument(text: String): Document {
        val number = numberArgument(text, 1, MAX_DOCUMENT_NUMBER)
        return documents[number] ?: throw CommandError("NO DOC $number")
    }

    private fun stemWords(arguments: List<String>) {
        val words = arguments.map(::wordArgument)
        emit("STEM", words.map { "$it:${porterStem(it)}" })
    }

    private fun showSteps(arguments: List<String>) {
        val word = wordArgument(arguments[0])
        val changes = stemmingSteps(word).changes
        if (changes.isEmpty()) {
            emit("STEPS $word NONE")
        } else {
            emit("STEPS $word", changes.map { "${it.step}:${it.word}" })
        }
    }

    private fun showMeasure(arguments: List<String>) {
        val word = wordArgument(arguments[0])
        emit(
            "MEASURE $word ${letterPattern(word)} m=${measure(word)} " +
                "vowel=${yesNo(hasVowel(word))} double=${yesNo(endsDouble(word))} " +
                "cvc=${yesNo(endsCvc(word))}",
        )
    }

    private fun showIndex(arguments: List<String>) {
        val prefix = if (arguments.isEmpty()) "" else wordArgument(arguments[0])
        val occurrences = occurrenceMap()
        val stems = occurrences.keys.filter { it.startsWith(prefix) }.sorted()
        emit("INDEX stems=${stems.size}")
        for (stem in stems) {
            val found = occurrences.getValue(stem)
            emit("$stem df=${documentCount(found)}", found.map { it.reference })
        }
    }

    private fun search(arguments: List<String>) {
        val items = LEXEME_PATTERN.findAll(arguments[0]).map { classify(it.value) }.toList()
        val stemSets = documents.values.associate { it.number to stemSet(it) }
        val (canonical, matches) = QueryParser(items, stemSets).parse()
        for (item in items) {
            if (item.kind == Kind.TERM && isStopword(item.spelling)) {
                throw CommandError("STOPWORD ${item.spelling}")
            }
        }
        emit("SEARCH $canonical count=${matches.size}", matches.sorted().map { it.toString() })
    }

    private fun phrase(arguments: List<String>) {
        val words = arguments.map(::wordArgument)
        if (words.all(::isStopword)) throw CommandError("STOPWORDS ONLY")
        val targets = words.map { if (isStopword(it)) "?" else porterStem(it) }
        val matches = mutableListOf<String>()
        for (document in documents.values) {
            val tokens = document.tokens
            for (start in 0..tokens.size - targets.size) {
                if (targets.indices.all { tokenMatches(tokens[start + it], targets[it]) }) {
                    matches.add(document.reference(tokens[start]))
                }
            }
        }
        emit("PHRASE \"${targets.joinToString(" ")}\" matches=${matches.size}", matches)
    }

    private fun near(arguments: List<String>) {
        val first = termArgument(arguments[0])
        val second = termArgument(arguments[1])
        val limit = numberArgument(arguments[2], 1, MAX_COUNT)
        val found = documents.values.mapNotNull { document ->
            val distance = closestDistance(
                stemPositions(document, first),
                stemPositions(document, second),
                first == second,
            )
            if (distance != null && distance <= limit) "${document.number}:$distance" else null
        }
        emit("NEAR $first $second $limit count=${found.size}", found)
    }

    private fun top(arguments: List<String>) {
        val limit = numberArgument(arguments[0], 1, MAX_COUNT)
        val (header, counts) = if (arguments.size == 2) {
            val document = documentArgument(arguments[1])
            "TOP $limit doc=${document.number}" to termFrequencies(document)
        } else {
            "TOP $limit" to totalFrequencies()
        }
        val ranked = counts.entries.sortedWith(BY_COUNT).take(limit)
        emit(header, ranked.map { (stem, count) -> "$stem:$count" })
    }

    private fun kwic(arguments: List<String>) {
        val stem = termArgument(arguments[0])
        val found = occurrencesOf(stem)
        emit("KWIC $stem count=${found.size}")
        for ((document, token) in found) {
            val text = document.lines[token.line - 1]
            val before = text.substring(maxOf(0, token.start - KWIC_WIDTH), token.start)
            val after = text.substring(token.end, minOf(text.length, token.end + KWIC_WIDTH))
            emit(
                "|${before.padStart(KWIC_WIDTH)}[${token.text}]${after.padEnd(KWIC_WIDTH)}| " +
                    document.reference(token),
            )
        }
    }

    private fun termFrequency(arguments: List<String>) {
        val document = documentArgument(arguments[0])
        val stem = termArgument(arguments[1])
        emit("TF ${document.number} $stem ${termFrequencies(document)[stem] ?: 0}")
    }

    private fun documentFrequency(arguments: List<String>) {
        val stem = termArgument(arguments[0])
        emit("DF $stem ${documentCount(occurrencesOf(stem))}")
    }

    private fun variants(arguments: List<String>) {
        val stem = termArgument(arguments[0])
        val forms = occurrencesOf(stem).groupingBy { it.token.form }.eachCount().toSortedMap()
        emit("VARIANTS $stem count=${forms.size}", forms.map { (form, count) -> "$form:$count" })
    }

    private fun similar(arguments: List<String>) {
        val document = documentArgument(arguments[0])
        val limit = numberArgument(arguments[1], 1, MAX_COUNT)
        val stems = stemSet(document)
        val scores = documents.values.filter { it !== document }.map { other ->
            val otherStems = stemSet(other)
            val union = (stems union otherStems).size
            val score = if (union > 0) {
                Fraction.of((stems intersect otherStems).size, union)
            } else {
                Fraction(0, 1)
            }
            Similarity(other.number, score)
        }
        val ranked = scores.sortedWith(
            compareByDescending<Similarity> { it.score }.thenBy { it.document },
        )
        emit("SIMILAR ${document.number}", ranked.take(limit).map { "${it.document}:${it.score}" })
    }

    private fun rank(arguments: List<String>) {
        val limit = numberArgument(arguments[0], 1, MAX_COUNT)
        val query = arguments.drop(1).map(::termArgument).toSet()
        val ranked = documents.values.mapNotNull { document ->
            val counts = termFrequencies(document)
            val matched = query.count { it in counts }
            val total = query.sumOf { counts[it] ?: 0 }
            if (matched > 0) Ranking(document.number, matched, total) else null
        }.sortedWith(
            compareByDescending<Ranking> { it.matched }
                .thenByDescending { it.total }
                .thenBy { it.document },
        )
        emit(
            "RANK count=${ranked.size}",
            ranked.take(limit).map { "${it.document}:${it.matched}:${it.total}" },
        )
    }

    private fun info(arguments: List<String>) {
        val document = documentArgument(arguments[0])
        val counts = termFrequencies(document)
        val top = counts.entries.minWithOrNull(BY_COUNT)
            ?.let { (stem, count) -> "$stem:$count" }
            ?: "-"
        emit(
            "INFO ${document.number} lines=${document.lines.size} tokens=${document.tokens.size} " +
                "indexed=${counts.values.sum()} stems=${counts.size} top=$top",
        )
    }

    private fun showLine(arguments: List<String>) {
        val document = documentArgument(arguments[0])
        val lineNumber = numberArgument(arguments[1], 1, MAX_LINE_NUMBER)
        if (lineNumber > document.lines.size) {
            throw CommandError("NO LINE ${document.number}:$lineNumber")
        }
        val tokens = document.lineTokens(lineNumber)
        emit(
            "LINE ${document.number}:$lineNumber tokens=${tokens.size}",
            tokens.map(::describeToken),
        )
    }

    private fun stats(arguments: List<String>) {
        val all = documents.values
        emit(
            "STATS docs=${all.size} lines=${all.sumOf { it.lines.size }} " +
                "tokens=${all.sumOf { it.tokens.size }} " +
                "indexed=${all.sumOf { indexedTokens(it).size }} " +
                "stems=${totalFrequencies().size} stopwords=${stopwords.size}",
        )
    }

    private fun stop(arguments: List<String>) {
        val word = wordArgument(arguments[0])
        if (isStopword(word)) throw CommandError("ALREADY STOPWORD $word")
        stopwords.add(word)
        emit("STOP $word unindexed=${formCount(word)}")
    }

    private fun unstop(arguments: List<String>) {
        val word = wordArgument(arguments[0])
        if (!isStopword(word)) throw CommandError("NOT STOPWORD $word")
        stopwords.remove(word)
        emit("UNSTOP $word indexed=${formCount(word)}")
    }

    private fun append(arguments: List<String>) {
        val number = numberArgument(arguments[0], 1, MAX_DOCUMENT_NUMBER)
        val created = number !in documents
        val document = documents[number] ?: addDocument(number)
        val tokens = document.addLine(arguments[1])
        val indexed = tokens.count(::isIndexed)
        emit(
            "APPEND $number line=${document.lines.size} tokens=${tokens.size} " +
                "indexed=$indexed new=${yesNo(created)}",
        )
    }

    private fun delete(arguments: List<String>) {
        val document = documentArgument(arguments[0])
        documents.remove(document.number)
        emit(
            "DELETE ${document.number} lines=${document.lines.size} " +
                "tokens=${document.tokens.size}",
        )
    }

    fun execute(line: String) {
        val name = line.substringBefore(" ")
        try {
            val command = commands[name] ?: throw CommandError("UNKNOWN COMMAND $name")
            val arguments =
                if (" " in line) splitArguments(name, line.substringAfter(" ")) else emptyList()
            if (arguments.size !in command.arity) throw CommandError("BAD ARGUMENTS $name")
            command.handler(arguments)
        } catch (error: CommandError) {
            emit("ERROR ${error.message}")
        }
    }
}

fun main() {
    val lines = System.`in`.bufferedReader().readLines()
    val engine = SearchEngine(lines[0].split(" ").drop(1).toMutableSet())
    var index = 1
    while (lines[index].startsWith("DOC ")) {
        val document = engine.addDocument(lines[index].substring(4).toInt())
        index++
        while (lines[index] != "ENDDOC") {
            document.addLine(lines[index])
            index++
        }
        index++
    }
    for (line in lines.drop(index)) {
        if (line == "END") break
        engine.execute(line)
    }
    print(engine.output)
}
