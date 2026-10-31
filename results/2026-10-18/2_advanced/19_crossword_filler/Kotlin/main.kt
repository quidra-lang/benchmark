import java.io.File

private val SYMMETRIES = listOf("rot180", "mirror", "none")
private val POINTS = intArrayOf(1, 3, 3, 2, 1, 4, 2, 4, 1, 8, 5, 1, 3, 1, 1, 3, 10, 1, 1, 1, 1, 4, 4, 8, 4, 10)
private data class Settings(val nodeBudget: Int, val minimum: Int, val symmetry: String, val relaxStep: Int, val weakScore: Int)
private data class Issue(val line: Int, val reason: String)
private data class Duplicate(val line: Int, val word: String, val first: Int)
private data class Unknown(val line: Int, val word: String)
private fun ignored(line: String) = line.isEmpty() || line.startsWith('#')
private fun read(name: String) = File("input", name).readLines(Charsets.US_ASCII)
private fun settings(lines: List<String>): Settings {
    val values = mutableMapOf<String, String>()
    for (line in lines) if (!ignored(line)) {
        val split = line.indexOf(' ')
        values[line.substring(0, split)] = line.substring(split + 1)
    }
    return Settings(values.getValue("node_budget").toInt(), values.getValue("min_score").toInt(), values.getValue("symmetry"), values.getValue("relax_step").toInt(), values.getValue("weak_score").toInt())
}
private fun joined(values: List<String>, separator: String) = if (values.isEmpty()) "-" else values.joinToString(separator)
private fun paragraphs(paragraphs: List<List<String>>): List<String> {
    val lines = mutableListOf<String>()
    for (paragraph in paragraphs) {
        if (lines.isNotEmpty()) lines.add("")
        lines.addAll(paragraph)
    }
    return lines
}
private class WordList(lines: List<String>) {
    private val lineCount = lines.size
    val scores = linkedMapOf<String, Int>()
    private val firstLines = mutableMapOf<String, Int>()
    private val invalid = mutableListOf<Issue>()
    private val duplicates = mutableListOf<Duplicate>()
    val index: WordIndex
    init {
        for ((i, text) in lines.withIndex()) {
            val error = WordIndex.wordError(text)
            if (error != null) { invalid.add(Issue(i + 1, error)); continue }
            val split = text.indexOf(' ')
            val word = text.substring(0, split)
            if (word in scores) duplicates.add(Duplicate(i + 1, word, firstLines.getValue(word)))
            else { scores[word] = text.substring(split + 1).toInt(); firstLines[word] = i + 1 }
        }
        index = WordIndex(scores)
    }
    fun report(): MutableList<String> {
        val lines = mutableListOf("WORDLIST lines=$lineCount valid=${scores.size} invalid=${invalid.size} duplicates=${duplicates.size}")
        for (issue in invalid) lines.add("invalid ${issue.line} ${issue.reason}")
        for (duplicate in duplicates) lines.add("duplicate ${duplicate.line} ${duplicate.word} first=${duplicate.first}")
        for ((length, words) in index.byLength) {
            val total = words.sumOf { scores.getValue(it) }
            val best = words.first()
            lines.add("length $length words=${words.size} average=${Render.decimal(total, words.size, 2)} best=$best:${scores.getValue(best)}")
        }
        val bands = IntArray(5)
        for (score in scores.values) bands[(score - 1) / 20]++
        lines.add("bands 1-20=${bands[0]} 21-40=${bands[1]} 41-60=${bands[2]} 61-80=${bands[3]} 81-100=${bands[4]}")
        lines.add("top " + index.ranked.take(5).joinToString(" ") { "$it:${scores.getValue(it)}" })
        val frequency = IntArray(26)
        for (word in scores.keys) for (i in 0 until 26) if ('A' + i in word) frequency[i]++
        val letters = (0 until 26).sortedWith(compareBy<Int> { frequency[it] }.thenBy { it }).take(5)
        lines.add("rare_letters " + letters.joinToString(" ") { "${'A' + it}:${frequency[it]}" })
        return lines
    }
}
private class Clue(val word: String, val number: Int, val text: String) {
    var uses = 0
}
private class ClueBook(lines: List<String>, scores: Map<String, Int>) {
    private var entries = 0
    private var added = 0
    private val invalid = mutableListOf<Issue>()
    private val unknown = mutableListOf<Unknown>()
    private val clues = sortedMapOf<String, MutableList<Clue>>()
    init {
        for ((i, text) in lines.withIndex()) {
            if (ignored(text)) continue
            entries++
            val error = WordIndex.clueError(text)
            if (error != null) { invalid.add(Issue(i + 1, error)); continue }
            val split = text.indexOf('|')
            val word = text.substring(0, split)
            if (word !in scores) { unknown.add(Unknown(i + 1, word)); continue }
            val list = clues.getOrPut(word) { mutableListOf() }
            list.add(Clue(word, list.size + 1, text.substring(split + 1)))
            added++
        }
    }
    fun choose(word: String): String? {
        val list = clues[word] ?: return null
        var chosen = list.first()
        for (clue in list) if (clue.uses < chosen.uses) chosen = clue
        chosen.uses++
        return chosen.text
    }
    fun report(): List<String> {
        val lines = mutableListOf("CLUES entries=$entries valid=$added invalid=${invalid.size} unknown=${unknown.size} words=${clues.size}")
        for (issue in invalid) lines.add("clue_invalid ${issue.line} ${issue.reason}")
        for (issue in unknown) lines.add("clue_unknown ${issue.line} ${issue.word}")
        val all = clues.values.flatten()
        val used = all.count { it.uses > 0 }
        val repeated = all.count { it.uses >= 2 }
        lines.add("CLUE_USE used=$used unused=${all.size - used} repeated=$repeated")
        for (clue in all) if (clue.uses >= 2) lines.add("repeated ${clue.word} clue=${clue.number} uses=${clue.uses}")
        return lines
    }
}
private class Block(val name: String) {
    val options = mutableListOf<String>()
    val rows = mutableListOf<String>()
}
private fun blocks(lines: List<String>): List<Block> {
    val blocks = mutableListOf<Block>()
    var current: Block? = null
    for (line in lines) {
        val block = current
        if (block == null) { if (line.startsWith("TEMPLATE ")) current = Block(line.substring(9)) }
        else if (line == "END") { blocks.add(block); current = null }
        else if (' ' in line) block.options.add(line)
        else block.rows.add(line)
    }
    return blocks
}
private fun validName(name: String) = name.length in 1..20 && name.all { it in 'a'..'z' || it in '0'..'9' || it == '_' }
private fun validRow(row: String, width: Int) = row.length in 3..15 && row.length == width && row.all { it == '#' || it == '.' || it in 'A'..'Z' }
private class Template(block: Block, settings: Settings) {
    val name = block.name
    private val options = block.options
    private val rows = block.rows
    private var budget = settings.nodeBudget
    private var minimum = settings.minimum
    private var symmetry = settings.symmetry
    var error: String? = null
    private val themes = mutableListOf<String>()
    private lateinit var grid: Grid
    lateinit var layout: Layout
    private lateinit var initial: GridState
    lateinit var state: GridState
    private val themeSlots = mutableSetOf<Int>()
    val attempts = mutableListOf<Attempt>()
    lateinit var finalAttempt: Attempt
    private lateinit var chosen: Array<String?>
    fun process(names: Set<String>, index: WordIndex, clues: ClueBook, relax: Int) {
        error = check(names, index)
        if (error != null) return
        var score = minimum
        while (true) {
            val attempt = Attempt(layout, index, initial, score, budget)
            attempt.run()
            attempts.add(attempt)
            finalAttempt = attempt
            if (attempt.outcome == "filled" || relax < 1 || score <= 1) break
            score = maxOf(score - relax, 1)
        }
        state = finalAttempt.finalState()
        chosen = arrayOfNulls(layout.slots.size)
        for (across in listOf(true, false)) for (slot in layout.slots) {
            val word = state.words[slot.index]
            if (slot.across == across && word != null) chosen[slot.index] = clues.choose(word)
        }
    }
    private fun readOptions(): Int {
        val seen = mutableSetOf<String>()
        for ((i, text) in options.withIndex()) {
            val split = text.indexOf(' ')
            val key = text.substring(0, split)
            val value = text.substring(split + 1)
            if (key == "theme") {
                if (!WordIndex.validWord(value) || value in themes) return i + 1
                themes.add(value)
            } else if (key in seen || !applyOption(key, value)) return i + 1
            seen.add(key)
        }
        return -1
    }
    private fun applyOption(key: String, value: String): Boolean {
        when {
            key == "node_budget" && WordIndex.validInteger(value, 1, 100000) -> budget = value.toInt()
            key == "min_score" && WordIndex.validInteger(value, 1, 100) -> minimum = value.toInt()
            key == "symmetry" && value in SYMMETRIES -> symmetry = value
            else -> return false
        }
        return true
    }
    private fun check(names: Set<String>, index: WordIndex): String? {
        if (!validName(name)) return "bad name"
        if (name in names) return "duplicate name"
        val bad = readOptions()
        if (bad >= 0) return "bad option $bad"
        if (rows.size !in 3..15) return "bad height"
        for ((i, row) in rows.withIndex()) if (!validRow(row, rows.first().length)) return "bad row ${i + 1}"
        grid = Grid(rows)
        if (symmetry != "none") {
            val cell = grid.asymmetric(symmetry)
            if (cell >= 0) return "asymmetric at ${grid.location(cell)}"
        }
        val components = grid.components()
        if (components != 1) return "disconnected components=$components"
        val short = Slots.shortRun(grid)
        if (short != null) return "short slot at ${grid.location(short.cell)} ${short.direction}"
        layout = Layout(grid)
        val orphan = layout.orphan()
        if (orphan >= 0) return "orphan cell ${grid.location(orphan)}"
        val initialState = GridState(grid.cells.copyOf(), arrayOfNulls(layout.slots.size))
        for ((i, word) in themes.withIndex()) {
            if (word !in index.scores) return "unknown theme ${i + 1}"
            val fitting = layout.slots.firstOrNull { initialState.words[it.index] == null && it.length == word.length && WordIndex.matches(word, initialState.pattern(it)) }
                ?: return "theme ${i + 1} does not fit"
            initialState.assign(fitting, word)
            themeSlots.add(fitting.index)
        }
        initial = initialState
        return null
    }
    fun filled() = error == null && finalAttempt.outcome == "filled"
    fun totalScore(scores: Map<String, Int>) = state.words.sumOf { scores.getValue(it!!) }
    private fun entry(slot: Slot, scores: Map<String, Int>): String {
        val word = state.words[slot.index]!!
        return "${slot.label}:$word:${scores.getValue(word)}"
    }
    private fun lengths() = layout.slots.map { it.length }.distinct().sorted()
    fun gridParagraph(): List<String> {
        val lines = mutableListOf("TEMPLATE $name")
        if (error != null) { lines.add("error $error"); return lines }
        lines.add("outcome=${finalAttempt.outcome} attempts=${attempts.size} min_score=${finalAttempt.minimum}")
        lines.addAll(Render.gridLines(grid, state.letters))
        lines.add("numbers")
        lines.addAll(Render.numberLines(layout))
        return lines
    }
    fun clueParagraph(scores: Map<String, Int>): List<String> {
        val lines = mutableListOf("TEMPLATE $name")
        var clued = 0
        var missing = 0
        var unfilled = 0
        for (across in listOf(true, false)) {
            val group = layout.slots.filter { it.across == across }
            if (group.isNotEmpty()) lines.add(if (across) "ACROSS" else "DOWN")
            for (slot in group) {
                val word = state.words[slot.index]
                if (word == null) { unfilled++; lines.add(Render.listLine(slot, "(unfilled)", state.pattern(slot), "-", false)) }
                else {
                    val clue = chosen[slot.index]
                    if (clue == null) missing++ else clued++
                    lines.add(Render.listLine(slot, clue ?: "(no clue)", word, scores.getValue(word).toString(), slot.index in themeSlots))
                }
            }
        }
        lines.add("clued=$clued missing=$missing unfilled=$unfilled")
        return lines
    }
    private fun gridSummary(): String {
        val whites = grid.whites()
        val blacks = grid.size - whites.size
        val givens = whites.count(grid::given)
        val holding = listOf("rot180", "mirror").filter { grid.asymmetric(it) < 0 }
        return "grid size=${grid.width}x${grid.height} blocks=$blacks white=${whites.size} density=${Render.decimal(100 * blacks, grid.size, 1)} givens=$givens required=$symmetry symmetry=${if (holding.isEmpty()) "none" else holding.joinToString(",")}"
    }
    private fun slotSummary(): String {
        var across = 0
        var totalLength = 0
        var longest = 0
        val counts = sortedMapOf<Int, Int>()
        for (slot in layout.slots) {
            if (slot.across) across++
            totalLength += slot.length
            longest = maxOf(longest, slot.length)
            counts[slot.length] = counts.getOrDefault(slot.length, 0) + 1
        }
        val unchecked = grid.whites().count { layout.owners(it) == 1 }
        val lengths = counts.entries.joinToString(",") { "${it.key}:${it.value}" }
        return "slots across=$across down=${layout.slots.size - across} total=${layout.slots.size} lengths=$lengths avg_length=${Render.decimal(totalLength, layout.slots.size, 2)} longest=$longest unchecked=$unchecked"
    }
    private fun coverage(index: WordIndex) = "coverage " + lengths().joinToString(" ") { length ->
        "$length:${index.byLength[length].orEmpty().count { index.scores.getValue(it) >= minimum }}"
    }
    private fun tightest(index: WordIndex): String {
        val counts = layout.slots.filter { it.index !in themeSlots }.map { it to index.candidates(initial.pattern(it), minimum, initial.used).size }
            .sortedWith(compareBy<Pair<Slot, Int>> { it.second }.thenBy { it.first.index }).take(3)
        return "tightest " + joined(counts.map { "${it.first.label}:${it.second}" }, " ")
    }
    private fun hotspots(): String {
        val failed = layout.slots.filter { finalAttempt.failures[it.index] > 0 }
            .sortedWith(compareByDescending<Slot> { finalAttempt.failures[it.index] }.thenBy { it.index }).take(3)
        return "hotspots " + joined(failed.map { "${it.label}:${finalAttempt.failures[it.index]}" }, " ")
    }
    private fun worstCrossing(scores: Map<String, Int>): String {
        var worst = -1
        var worstSum = 0
        for (cell in grid.whites()) {
            val across = layout.acrossSlot[cell]
            val down = layout.downSlot[cell]
            if (across < 0 || down < 0) continue
            val sum = scores.getValue(state.words[across]!!) + scores.getValue(state.words[down]!!)
            if (worst < 0 || sum < worstSum) { worst = cell; worstSum = sum }
        }
        if (worst < 0) return "-"
        val across = layout.slots[layout.acrossSlot[worst]]
        val down = layout.slots[layout.downSlot[worst]]
        return "${grid.location(worst)} ${across.label}:${state.words[across.index]}+${down.label}:${state.words[down.index]}=$worstSum"
    }
    private fun quality(scores: Map<String, Int>, weakScore: Int): List<String> {
        val total = totalScore(scores)
        var weakest = layout.slots.first()
        val weak = mutableListOf<String>()
        for (slot in layout.slots) {
            if (scores.getValue(state.words[slot.index]!!) < scores.getValue(state.words[weakest.index]!!)) weakest = slot
            if (scores.getValue(state.words[slot.index]!!) < weakScore) weak.add(entry(slot, scores))
        }
        val distinct = mutableSetOf<Char>()
        var points = 0
        for (cell in grid.whites()) {
            val letter = state.letters[cell]
            distinct.add(letter)
            points += POINTS[letter - 'A']
        }
        val missing = ('A'..'Z').filter { it !in distinct }.joinToString("")
        return listOf("quality total=$total average=${Render.decimal(total, layout.slots.size, 2)} weakest=${entry(weakest, scores)} weak=${joined(weak, ",")}",
            "letters distinct=${distinct.size} pangram=${if (missing.isEmpty()) "yes" else "no"} missing=${if (missing.isEmpty()) "-" else missing} scrabble=${Render.decimal(points, grid.whites().size, 2)} worst_crossing=${worstCrossing(scores)}")
    }
    private fun partial(index: WordIndex): String {
        val assigned = state.words.count { it != null }
        val lettered = grid.whites().count { state.letters[it] != '.' }
        val blocked = layout.slots.filter { state.words[it.index] == null && index.candidates(state.pattern(it), finalAttempt.minimum, state.used).isEmpty() }.map { it.label }
        return "partial assigned=$assigned/${layout.slots.size} letters=$lettered/${grid.whites().size} blocked=${joined(blocked, ",")}"
    }
    fun stats(index: WordIndex, weakScore: Int): List<String> {
        val lines = mutableListOf("TEMPLATE $name", gridSummary(), slotSummary())
        if (themeSlots.isNotEmpty()) lines.add("themes " + layout.slots.filter { it.index in themeSlots }.joinToString(" ") { entry(it, index.scores) })
        lines.add(coverage(index))
        lines.add(tightest(index))
        for ((i, attempt) in attempts.withIndex()) lines.add("attempt ${i + 1} min_score=${attempt.minimum} budget=${attempt.budget} outcome=${attempt.outcome} nodes=${attempt.nodes} backtracks=${attempt.backtracks} prunes=${attempt.prunes} dead_ends=${attempt.deadEnds} max_depth=${attempt.maxDepth}")
        lines.add("trace " + joined(finalAttempt.trace, " "))
        lines.add(hotspots())
        if (filled()) { lines.add("order " + joined(finalAttempt.sequence.map { it.label }, " ")); lines.addAll(quality(index.scores, weakScore)) }
        else lines.add(partial(index))
        return lines
    }
}
private fun ranking(filled: List<Template>, scores: Map<String, Int>): List<String> {
    val ranked = filled.sortedWith { a, b ->
        val left = a.totalScore(scores) * b.layout.slots.size
        val right = b.totalScore(scores) * a.layout.slots.size
        if (left != right) right.compareTo(left) else a.name.compareTo(b.name)
    }
    val lines = mutableListOf("RANKING")
    for ((i, template) in ranked.withIndex()) {
        val total = template.totalScore(scores)
        val entries = template.layout.slots.size
        lines.add("rank ${i + 1} ${template.name} average=${Render.decimal(total, entries, 2)} total=$total entries=$entries")
    }
    return lines
}
private fun reuse(filled: List<Template>): List<String> {
    val appearances = mutableMapOf<String, MutableList<String>>()
    for (template in filled) for (word in template.state.words) appearances.getOrPut(word!!) { mutableListOf() }.add(template.name)
    val words = appearances.keys.filter { appearances.getValue(it).size >= 2 }.sortedWith(compareByDescending<String> { appearances.getValue(it).size }.thenBy { it })
    val lines = mutableListOf("REUSE")
    for (word in words) lines.add("reused $word ${appearances.getValue(word).size} ${appearances.getValue(word).joinToString(",")}")
    return lines
}
private fun summary(templates: List<Template>): List<String> {
    var invalid = 0
    var filled = 0
    var unfillable = 0
    var budget = 0
    var attempts = 0
    var nodes = 0
    for (template in templates) {
        if (template.error != null) { invalid++; continue }
        when (template.finalAttempt.outcome) { "filled" -> filled++; "unfillable" -> unfillable++; "budget" -> budget++ }
        attempts += template.attempts.size
        nodes += template.attempts.sumOf { it.nodes }
    }
    return listOf("SUMMARY templates=${templates.size} invalid=$invalid filled=$filled unfillable=$unfillable budget=$budget attempts=$attempts nodes=$nodes")
}
fun main() {
    val settings = settings(read("params.txt"))
    val words = WordList(read("words.txt"))
    val clues = ClueBook(read("clues.txt"), words.scores)
    val templates = mutableListOf<Template>()
    val names = mutableSetOf<String>()
    for (block in blocks(read("templates.txt"))) {
        val template = Template(block, settings)
        template.process(names, words.index, clues, settings.relaxStep)
        names.add(block.name)
        templates.add(template)
    }
    val valid = templates.filter { it.error == null }
    val filled = valid.filter { it.filled() }
    val stats = valid.map { it.stats(words.index, settings.weakScore) }.toMutableList()
    stats.add(ranking(filled, words.scores))
    stats.add(reuse(filled))
    stats.add(summary(templates))
    val wordReport = words.report()
    wordReport.addAll(clues.report())
    val files = linkedMapOf("grid.txt" to paragraphs(templates.map { it.gridParagraph() }),
        "clues.txt" to paragraphs(valid.map { it.clueParagraph(words.scores) }), "search_stats.txt" to paragraphs(stats), "wordlist.txt" to wordReport)
    File("output").mkdirs()
    for ((name, lines) in files) File("output", name).writeText(if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n", Charsets.US_ASCII)
}
