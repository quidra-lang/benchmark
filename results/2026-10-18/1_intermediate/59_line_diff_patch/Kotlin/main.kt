private val DATA_COMMANDS = setOf("FILE", "PATCH", "EDIT")
private val FORMATS_WITH_ARGUMENT = setOf("IFDEF", "UNIFIED", "CONTEXT", "SIDE")
private val OFFSETS = listOf(0, 1, -1, 2, -2, 3, -3)
private const val GRAPH_WIDTH = 20
private val NUMBER_PAIR = Regex("([0-9]{1,4})(?:,([0-9]{1,4}))?")
private val SPACE_RUN = Regex(" {2,}")
private const val SEPARATOR = "======="

class CommandError(override val message: String) : Exception(message)

fun rangeR(start: Int, count: Int): String = when {
    count >= 2 -> "${start + 1},${start + count}"
    count == 1 -> "${start + 1}"
    else -> "$start"
}

fun rangeU(start: Int, count: Int): String = when {
    count >= 2 -> "${start + 1},$count"
    count == 1 -> "${start + 1}"
    else -> "$start,0"
}

fun rangeM(start: Int, count: Int) = "${start + 1},$count"

fun comparisonKey(line: String, options: List<String>): String {
    var key = line
    if ("ICASE" in options) key = key.lowercase()
    if ("IWHITE" in options) key = key.replace(" ", "")
    if ("ISPACE" in options) key = SPACE_RUN.replace(key, " ")
    return key
}

fun matchedPairs(first: List<String>, second: List<String>): List<Pair<Int, Int>> {
    val rows = first.size
    val columns = second.size
    val table = Array(rows + 1) { IntArray(columns + 1) }
    for (i in 1..rows) {
        for (j in 1..columns) {
            table[i][j] = if (first[i - 1] == second[j - 1]) {
                table[i - 1][j - 1] + 1
            } else {
                maxOf(table[i - 1][j], table[i][j - 1])
            }
        }
    }
    val pairs = mutableListOf(rows + 1 to columns + 1)
    var i = rows
    var j = columns
    while (i >= 1 && j >= 1) {
        when {
            first[i - 1] == second[j - 1] -> {
                pairs.add(i to j)
                i--
                j--
            }
            table[i - 1][j] >= table[i][j - 1] -> i--
            else -> j--
        }
    }
    pairs.add(0 to 0)
    return pairs.asReversed()
}

data class ChangeBlock(val p: Int, val q: Int, val x: Int, val y: Int) {
    val letter: Char
        get() = when {
            x >= 1 && y >= 1 -> 'c'
            y == 0 -> 'd'
            else -> 'a'
        }
}

fun changeBlocks(first: List<String>, second: List<String>): List<ChangeBlock> =
    matchedPairs(first, second).zipWithNext().mapNotNull { (current, next) ->
        val (i, j) = current
        val (nextI, nextJ) = next
        ChangeBlock(i, j, nextI - i - 1, nextJ - j - 1).takeIf { it.x > 0 || it.y > 0 }
    }

data class Step(val oldIndex: Int, val newIndex: Int, val block: ChangeBlock?)

fun walk(blocks: List<ChangeBlock>, oldStart: Int, newStart: Int, oldEnd: Int): List<Step> {
    val steps = mutableListOf<Step>()
    var oldIndex = oldStart
    var newIndex = newStart
    for (block in blocks) {
        while (oldIndex < block.p) {
            steps.add(Step(oldIndex++, newIndex++, null))
        }
        steps.add(Step(oldIndex, newIndex, block))
        oldIndex = block.p + block.x
        newIndex = block.q + block.y
    }
    while (oldIndex < oldEnd) {
        steps.add(Step(oldIndex++, newIndex++, null))
    }
    return steps
}

fun sideRow(left: String, symbol: Char, right: String, width: Int): String =
    "${left.take(width).padEnd(width)} $symbol ${right.take(width)}".trimEnd(' ')

fun statGraph(inserted: Int, deleted: Int): String {
    val total = inserted + deleted
    var plus = inserted
    var minus = deleted
    if (total > GRAPH_WIDTH) {
        plus = GRAPH_WIDTH * inserted / total
        minus = GRAPH_WIDTH * deleted / total
        if (inserted >= 1 && plus == 0) plus = 1
        if (deleted >= 1 && minus == 0) minus = 1
    }
    return "+".repeat(plus) + "-".repeat(minus)
}

class Hunk(val blocks: List<ChangeBlock>, context: Int, oldTotal: Int) {
    val oldStart: Int
    val oldCount: Int
    val newStart: Int
    val newCount: Int

    init {
        val first = blocks.first()
        val last = blocks.last()
        val before = minOf(context, first.p)
        val after = minOf(context, oldTotal - last.p - last.x)
        oldStart = first.p - before
        oldCount = last.p + last.x + after - oldStart
        newStart = first.q - before
        newCount = last.q + last.y + after - newStart
    }

    fun steps() = walk(blocks, oldStart, newStart, oldStart + oldCount)
}

class LineDiff(
    private val oldLines: List<String>,
    private val newLines: List<String>,
    options: List<String> = emptyList(),
) {
    val blocks = changeBlocks(
        oldLines.map { comparisonKey(it, options) },
        newLines.map { comparisonKey(it, options) },
    )

    fun deleted(block: ChangeBlock) = oldLines.subList(block.p, block.p + block.x)

    fun inserted(block: ChangeBlock) = newLines.subList(block.q, block.q + block.y)

    fun hunks(context: Int): List<Hunk> {
        val groups = mutableListOf<MutableList<ChangeBlock>>()
        for (block in blocks) {
            val previous = groups.lastOrNull()?.last()
            if (previous != null && block.p - (previous.p + previous.x) <= 2 * context) {
                groups.last().add(block)
            } else {
                groups.add(mutableListOf(block))
            }
        }
        return groups.map { Hunk(it, context, oldLines.size) }
    }

    fun normal(): List<String> = buildList {
        for (block in blocks) {
            add(rangeR(block.p, block.x) + block.letter + rangeR(block.q, block.y))
            addAll(deleted(block).map { "< $it" })
            if (block.letter == 'c') add("---")
            addAll(inserted(block).map { "> $it" })
        }
    }

    fun ed(): List<String> = buildList {
        for (block in blocks.asReversed()) {
            add(rangeR(block.p, block.x) + block.letter)
            if (block.letter != 'd') {
                addAll(inserted(block))
                add(".")
            }
        }
    }

    fun rcs(): List<String> = buildList {
        for (block in blocks) {
            if (block.x >= 1) add("d${block.p + 1} ${block.x}")
            if (block.y >= 1) {
                add("a${block.p + block.x} ${block.y}")
                addAll(inserted(block))
            }
        }
    }

    fun ifdef(macro: String): List<String> = buildList {
        for ((oldIndex, _, block) in walk(blocks, 0, 0, oldLines.size)) {
            when {
                block == null -> add(oldLines[oldIndex])
                block.x >= 1 && block.y >= 1 -> {
                    add("#ifndef $macro")
                    addAll(deleted(block))
                    add("#else /* $macro */")
                    addAll(inserted(block))
                    add("#endif /* $macro */")
                }
                block.y == 0 -> {
                    add("#ifndef $macro")
                    addAll(deleted(block))
                    add("#endif /* ! $macro */")
                }
                else -> {
                    add("#ifdef $macro")
                    addAll(inserted(block))
                    add("#endif /* $macro */")
                }
            }
        }
    }

    fun unified(context: Int, oldName: String, newName: String): List<String> = buildList {
        add("--- $oldName")
        add("+++ $newName")
        for (hunk in hunks(context)) {
            val oldRange = rangeU(hunk.oldStart, hunk.oldCount)
            val newRange = rangeU(hunk.newStart, hunk.newCount)
            add("@@ -$oldRange +$newRange @@")
            for ((oldIndex, _, block) in hunk.steps()) {
                if (block == null) {
                    add(" " + oldLines[oldIndex])
                } else {
                    addAll(deleted(block).map { "-$it" })
                    addAll(inserted(block).map { "+$it" })
                }
            }
        }
    }

    fun context(context: Int, oldName: String, newName: String): List<String> = buildList {
        add("*** $oldName")
        add("--- $newName")
        for (hunk in hunks(context)) {
            add("*".repeat(15))
            add("*** ${rangeR(hunk.oldStart, hunk.oldCount)} ****")
            if (hunk.blocks.any { it.x >= 1 }) {
                for ((oldIndex, _, block) in hunk.steps()) {
                    if (block == null) {
                        add("  " + oldLines[oldIndex])
                    } else {
                        val marker = if (block.y >= 1) "! " else "- "
                        addAll(deleted(block).map { marker + it })
                    }
                }
            }
            add("--- ${rangeR(hunk.newStart, hunk.newCount)} ----")
            if (hunk.blocks.any { it.y >= 1 }) {
                for ((_, newIndex, block) in hunk.steps()) {
                    if (block == null) {
                        add("  " + newLines[newIndex])
                    } else {
                        val marker = if (block.x >= 1) "! " else "+ "
                        addAll(inserted(block).map { marker + it })
                    }
                }
            }
        }
    }

    fun sideBySide(width: Int): List<String> = buildList {
        for ((oldIndex, newIndex, block) in walk(blocks, 0, 0, oldLines.size)) {
            if (block == null) {
                add(sideRow(oldLines[oldIndex], ' ', newLines[newIndex], width))
                continue
            }
            for (row in 0 until maxOf(block.x, block.y)) {
                val line = when {
                    row < block.x && row < block.y ->
                        sideRow(oldLines[block.p + row], '|', newLines[block.q + row], width)
                    row < block.x -> sideRow(oldLines[block.p + row], '<', "", width)
                    else -> sideRow("", '>', newLines[block.q + row], width)
                }
                add(line)
            }
        }
    }
}

class TokenTotals {
    var deleted = 0
    var inserted = 0
    var common = 0
}

fun splitTokens(line: String, byWord: Boolean): List<String> =
    if (byWord) line.split(" ").filter { it.isNotEmpty() } else line.map { it.toString() }

fun deletion(tokens: List<String>, separator: String) = tokens.joinToString(separator, "[-", "-]")

fun insertion(tokens: List<String>, separator: String) = tokens.joinToString(separator, "{+", "+}")

fun compareTokens(
    oldTokens: List<String>,
    newTokens: List<String>,
    separator: String,
    totals: TokenTotals,
): String {
    val parts = mutableListOf<String>()
    for ((oldIndex, _, block) in walk(changeBlocks(oldTokens, newTokens), 0, 0, oldTokens.size)) {
        if (block == null) {
            parts.add(oldTokens[oldIndex])
            totals.common++
            continue
        }
        if (block.x >= 1) {
            parts.add(deletion(oldTokens.subList(block.p, block.p + block.x), separator))
        }
        if (block.y >= 1) {
            parts.add(insertion(newTokens.subList(block.q, block.q + block.y), separator))
        }
        totals.deleted += block.x
        totals.inserted += block.y
    }
    return parts.joinToString(separator)
}

data class LineRange(val start: Int, val count: Int)

data class BodyLine(val kind: Char, val text: String)

class PatchHunk(val lineNumber: Int, val oldRange: LineRange, val newRange: LineRange) {
    val body = mutableListOf<BodyLine>()

    fun sequences(reverse: Boolean): Pair<List<String>, List<String>> {
        val oldKind = if (reverse) '+' else '-'
        val newKind = if (reverse) '-' else '+'
        val oldLines = body.filter { it.kind == ' ' || it.kind == oldKind }.map { it.text }
        val newLines = body.filter { it.kind == ' ' || it.kind == newKind }.map { it.text }
        return oldLines to newLines
    }

    fun start(reverse: Boolean) = if (reverse) newRange.start else oldRange.start

    fun leadingContext() = body.takeWhile { it.kind == ' ' }.size

    fun trailingContext() = body.takeLastWhile { it.kind == ' ' }.size
}

class HunkMatch(val fuzz: Int, val delta: Int, val position: Int, val lines: List<String>) {
    fun report(number: Int): String = buildString {
        append("Hunk #$number succeeded at ${position + 1}")
        if (fuzz >= 1) append(" with fuzz $fuzz")
        if (delta == 1 || delta == -1) {
            append(" (offset $delta line)")
        } else if (delta != 0) {
            append(" (offset $delta lines)")
        }
    }
}

fun parseRange(text: String, sign: Char): LineRange? {
    if (!text.startsWith(sign)) return null
    val match = NUMBER_PAIR.matchEntire(text.substring(1)) ?: return null
    val start = match.groupValues[1].toInt()
    val count = match.groups[2]?.value?.toInt() ?: 1
    if (start == 0 && count != 0) return null
    return LineRange(start, count)
}

fun parseHunkHeader(line: String, lineNumber: Int): PatchHunk {
    val parts = line.split(" ")
    if (parts.size == 4 && parts[0] == "@@" && parts[3] == "@@") {
        val oldRange = parseRange(parts[1], '-')
        val newRange = parseRange(parts[2], '+')
        if (oldRange != null && newRange != null) return PatchHunk(lineNumber, oldRange, newRange)
    }
    throw CommandError("PATCH ERROR line $lineNumber: bad hunk header")
}

fun parsePatch(patchLines: List<String>): List<PatchHunk> {
    var index = patchLines.indexOfFirst { it.startsWith("@@") }
    if (index < 0) throw CommandError("PATCH ERROR no hunks")
    val hunks = mutableListOf<PatchHunk>()
    while (index < patchLines.size) {
        val hunk = parseHunkHeader(patchLines[index], index + 1)
        index++
        val oldCount = hunk.oldRange.count
        val newCount = hunk.newRange.count
        var oldSeen = 0
        var newSeen = 0
        while (oldSeen < oldCount || newSeen < newCount) {
            if (index == patchLines.size) {
                throw CommandError("PATCH ERROR line ${hunk.lineNumber}: truncated hunk")
            }
            val line = patchLines[index]
            val kind = line[0]
            val inOld = kind == ' ' || kind == '-'
            val inNew = kind == ' ' || kind == '+'
            if (line.length < 2 ||
                !(inOld || inNew) ||
                (inOld && oldSeen == oldCount) ||
                (inNew && newSeen == newCount)
            ) {
                throw CommandError("PATCH ERROR line ${index + 1}: bad hunk line")
            }
            hunk.body.add(BodyLine(kind, line.substring(1)))
            if (inOld) oldSeen++
            if (inNew) newSeen++
            index++
        }
        if (hunk.body.all { it.kind == ' ' }) {
            throw CommandError("PATCH ERROR line ${hunk.lineNumber}: no changes")
        }
        hunks.add(hunk)
    }
    return hunks
}

fun searchHunk(
    hunk: PatchHunk,
    lines: List<String>,
    adjustment: Int,
    reverse: Boolean,
    maxFuzz: Int,
): HunkMatch? {
    val (oldLines, newLines) = hunk.sequences(reverse)
    val start = hunk.start(reverse)
    val expected = if (oldLines.isEmpty()) start + adjustment else start - 1 + adjustment
    val leading = hunk.leadingContext()
    val trailing = hunk.trailingContext()
    for (fuzz in 0..maxFuzz) {
        val head = minOf(fuzz, leading)
        val tail = minOf(fuzz, trailing)
        val oldPart = oldLines.subList(head, oldLines.size - tail)
        val newPart = newLines.subList(head, newLines.size - tail)
        for (delta in OFFSETS) {
            val position = expected + head + delta
            val end = position + oldPart.size
            if (position < 0 || end > lines.size) continue
            if (lines.subList(position, end) == oldPart) {
                val result = lines.subList(0, position) + newPart + lines.subList(end, lines.size)
                return HunkMatch(fuzz, delta, position, result)
            }
        }
    }
    return null
}

data class EditCommand(val instruction: Char, val first: Int, val last: Int)

fun parseEditCommand(line: String): EditCommand? {
    val instruction = line.last()
    val match = NUMBER_PAIR.matchEntire(line.dropLast(1))
    if (instruction !in "acd" || match == null) return null
    val second = match.groups[2]?.value?.toInt()
    if (instruction == 'a' && second != null) return null
    val first = match.groupValues[1].toInt()
    return EditCommand(instruction, first, second ?: first)
}

fun runEditScript(original: List<String>, script: List<String>): Pair<List<String>, Int> {
    val lines = original.toMutableList()
    var executed = 0
    var index = 0
    while (index < script.size) {
        val lineNumber = index + 1
        val (instruction, first, last) = parseEditCommand(script[index])
            ?: throw CommandError("EDIT ERROR line $lineNumber: bad command")
        val valid = if (instruction == 'a') {
            first <= lines.size
        } else {
            first in 1..last && last <= lines.size
        }
        if (!valid) throw CommandError("EDIT ERROR line $lineNumber: bad range")
        index++
        var text = emptyList<String>()
        if (instruction == 'a' || instruction == 'c') {
            var end = index
            while (end < script.size && script[end] != ".") {
                end++
            }
            if (end == script.size) {
                throw CommandError("EDIT ERROR line $lineNumber: missing terminator")
            }
            text = script.subList(index, end)
            index = end + 1
        }
        if (instruction == 'a') {
            lines.addAll(first, text)
        } else {
            lines.subList(first - 1, last).clear()
            lines.addAll(first - 1, text)
        }
        executed++
    }
    return lines to executed
}

enum class ChunkKind { STABLE, A, B, BOTH, CONFLICT }

class Chunk(
    val kind: ChunkKind,
    val baseStart: Int,
    val oursStart: Int,
    val theirsStart: Int,
    val base: List<String>,
    val ours: List<String>,
    val theirs: List<String>,
) {
    fun location() =
        "base ${rangeM(baseStart, base.size)} a ${rangeM(oursStart, ours.size)} " +
            "b ${rangeM(theirsStart, theirs.size)}"
}

fun chunkKind(base: List<String>, ours: List<String>, theirs: List<String>) = when {
    ours == base -> ChunkKind.B
    theirs == base -> ChunkKind.A
    ours == theirs -> ChunkKind.BOTH
    else -> ChunkKind.CONFLICT
}

fun matchTable(first: List<String>, second: List<String>): IntArray {
    val matches = IntArray(first.size + 2)
    val pairs = matchedPairs(first, second)
    for ((i, j) in pairs.subList(1, pairs.size - 1)) {
        matches[i] = j
    }
    return matches
}

fun threeWayChunks(base: List<String>, ours: List<String>, theirs: List<String>): List<Chunk> {
    val oursMatch = matchTable(base, ours)
    val theirsMatch = matchTable(base, theirs)
    val chunks = mutableListOf<Chunk>()
    var x = 0
    var y = 0
    var z = 0
    while (x < base.size || y < ours.size || z < theirs.size) {
        if (x < base.size && oursMatch[x + 1] == y + 1 && theirsMatch[x + 1] == z + 1) {
            val line = base.subList(x, x + 1)
            chunks.add(Chunk(ChunkKind.STABLE, x, y, z, line, line, line))
            x++
            y++
            z++
            continue
        }
        var anchor = x + 1
        while (anchor <= base.size && (oursMatch[anchor] == 0 || theirsMatch[anchor] == 0)) {
            anchor++
        }
        val (nextX, nextY, nextZ) = if (anchor <= base.size) {
            Triple(anchor - 1, oursMatch[anchor] - 1, theirsMatch[anchor] - 1)
        } else {
            Triple(base.size, ours.size, theirs.size)
        }
        val basePart = base.subList(x, nextX)
        val oursPart = ours.subList(y, nextY)
        val theirsPart = theirs.subList(z, nextZ)
        val kind = chunkKind(basePart, oursPart, theirsPart)
        chunks.add(Chunk(kind, x, y, z, basePart, oursPart, theirsPart))
        x = nextX
        y = nextY
        z = nextZ
    }
    return chunks
}

fun kindCounts(chunks: List<Chunk>): String {
    val counts = chunks.groupingBy { it.kind }.eachCount().withDefault { 0 }
    return "a=${counts.getValue(ChunkKind.A)} b=${counts.getValue(ChunkKind.B)} " +
        "both=${counts.getValue(ChunkKind.BOTH)} conflicts=${counts.getValue(ChunkKind.CONFLICT)}"
}

fun commonPrefixLength(first: List<String>, second: List<String>): Int {
    var length = 0
    while (length < first.size && length < second.size && first[length] == second[length]) {
        length++
    }
    return length
}

fun commonSuffixLength(first: List<String>, second: List<String>, limit: Int): Int {
    var length = 0
    while (length < limit && first[first.size - 1 - length] == second[second.size - 1 - length]) {
        length++
    }
    return length
}

fun conflictLines(
    chunk: Chunk,
    mode: String,
    baseName: String,
    oursName: String,
    theirsName: String,
): List<String> {
    if (mode == "OURS") return chunk.ours
    if (mode == "THEIRS") return chunk.theirs
    if (mode == "DIFF3") {
        return listOf("<<<<<<< $oursName") + chunk.ours + "||||||| $baseName" + chunk.base +
            SEPARATOR + chunk.theirs + ">>>>>>> $theirsName"
    }
    val ours = chunk.ours
    val theirs = chunk.theirs
    val head = commonPrefixLength(ours, theirs)
    val tail = commonSuffixLength(ours, theirs, minOf(ours.size, theirs.size) - head)
    val oursMiddle = ours.subList(head, ours.size - tail)
    val theirsMiddle = theirs.subList(head, theirs.size - tail)
    val middle = if (mode == "UNION") {
        oursMiddle + theirsMiddle
    } else {
        listOf("<<<<<<< $oursName") + oursMiddle + SEPARATOR + theirsMiddle + ">>>>>>> $theirsName"
    }
    return ours.subList(0, head) + middle + ours.subList(ours.size - tail, ours.size)
}

enum class Marker { START, BASE, SEPARATOR, END }

private val MARKER_PREFIXES =
    mapOf("<<<<<<<" to Marker.START, "|||||||" to Marker.BASE, ">>>>>>>" to Marker.END)

fun markerKind(line: String): Marker? {
    if (line == SEPARATOR) return Marker.SEPARATOR
    val marker = MARKER_PREFIXES[line.take(7)]
    return if (marker != null && (line.length == 7 || line[7] == ' ')) marker else null
}

fun nextMarker(lines: List<String>, index: Int): Int {
    var next = index + 1
    while (next < lines.size && markerKind(lines[next]) == null) {
        next++
    }
    return next
}

class ConflictRegion(
    val start: Int,
    val end: Int,
    val ours: List<String>,
    val base: List<String>?,
    val theirs: List<String>,
) {
    fun part(side: String): List<String> = when (side) {
        "OURS" -> ours
        "THEIRS" -> theirs
        "BASE" -> base!!
        else -> ours + theirs
    }
}

fun regionAt(lines: List<String>, start: Int): ConflictRegion? {
    if (markerKind(lines[start]) != Marker.START) return null
    var middle = nextMarker(lines, start)
    var baseMarker: Int? = null
    if (middle < lines.size && markerKind(lines[middle]) == Marker.BASE) {
        baseMarker = middle
        middle = nextMarker(lines, middle)
    }
    if (middle == lines.size || markerKind(lines[middle]) != Marker.SEPARATOR) return null
    val end = nextMarker(lines, middle)
    if (end == lines.size || markerKind(lines[end]) != Marker.END) return null
    val ours = lines.subList(start + 1, baseMarker ?: middle)
    val base = baseMarker?.let { lines.subList(it + 1, middle) }
    return ConflictRegion(start + 1, end + 1, ours, base, lines.subList(middle + 1, end))
}

fun conflictRegions(lines: List<String>): List<ConflictRegion> {
    val regions = mutableListOf<ConflictRegion>()
    var index = 0
    while (index < lines.size) {
        val region = regionAt(lines, index)
        if (region == null) {
            index++
        } else {
            regions.add(region)
            index = region.end
        }
    }
    return regions
}

class Workspace {
    private val files = mutableMapOf<String, List<String>>()
    private val history = mutableMapOf<String, MutableList<List<String>?>>()
    val output = StringBuilder()

    fun execute(words: List<String>, data: List<String>) {
        val arguments = words.drop(1)
        try {
            when (words[0]) {
                "FILE" -> loadFile(arguments, data)
                "COPY" -> copy(arguments)
                "PRINT" -> printFile(arguments)
                "FILES" -> listFiles()
                "DIFF" -> diff(arguments)
                "WORDDIFF" -> tokenDiff(arguments, true)
                "CHARDIFF" -> tokenDiff(arguments, false)
                "STAT" -> stat(arguments)
                "PATCH" -> patch(arguments, data)
                "EDIT" -> edit(arguments, data)
                "DIFF3" -> diff3(arguments)
                "MERGE" -> merge(arguments)
                "CONFLICTS" -> conflicts(arguments)
                "RESOLVE" -> resolve(arguments)
                "UNDO" -> undo(arguments)
            }
        } catch (error: CommandError) {
            emit(error.message)
        }
    }

    private fun emit(line: String) {
        output.append(line).append('\n')
    }

    private fun emitAll(lines: List<String>) = lines.forEach(::emit)

    private fun requireFiles(vararg names: String) {
        for (name in names) {
            if (name !in files) throw CommandError("ERROR no such file $name")
        }
    }

    private fun save(name: String, lines: List<String>) {
        history.getOrPut(name) { mutableListOf() }.add(files[name])
        files[name] = lines.toList()
    }

    private fun loadFile(arguments: List<String>, data: List<String>) {
        val name = arguments[0]
        save(name, data)
        emit("FILE $name lines=${data.size}")
    }

    private fun copy(arguments: List<String>) {
        val (source, target) = arguments
        requireFiles(source)
        val lines = files.getValue(source)
        save(target, lines)
        emit("COPY $source $target lines=${lines.size}")
    }

    private fun printFile(arguments: List<String>) {
        val name = arguments[0]
        requireFiles(name)
        val lines = files.getValue(name)
        emit("PRINT $name lines=${lines.size}")
        lines.forEachIndexed { index, line -> emit("${(index + 1).toString().padStart(3)}| $line") }
    }

    private fun listFiles() {
        emit("FILES count=${files.size}")
        for (name in files.keys.sorted()) {
            emit("$name lines=${files.getValue(name).size} undo=${history.getValue(name).size}")
        }
    }

    private fun undo(arguments: List<String>) {
        val name = arguments[0]
        val states = history[name]
        if (states.isNullOrEmpty()) throw CommandError("ERROR nothing to undo $name")
        val state = states.removeAt(states.lastIndex)
        if (state == null) {
            files.remove(name)
            emit("UNDO $name removed")
        } else {
            files[name] = state
            emit("UNDO $name lines=${state.size}")
        }
    }

    private fun diff(arguments: List<String>) {
        val (oldName, newName, form) = arguments
        requireFiles(oldName, newName)
        val hasParameter = form in FORMATS_WITH_ARGUMENT
        val parameter = if (hasParameter) arguments[3] else ""
        val options = arguments.drop(if (hasParameter) 4 else 3)
        val diff = LineDiff(files.getValue(oldName), files.getValue(newName), options)
        if (diff.blocks.isEmpty()) {
            emit("Files $oldName and $newName are identical")
            return
        }
        when (form) {
            "BRIEF" -> emit("Files $oldName and $newName differ")
            "NORMAL" -> emitAll(diff.normal())
            "ED" -> emitAll(diff.ed())
            "RCS" -> emitAll(diff.rcs())
            "IFDEF" -> emitAll(diff.ifdef(parameter))
            "UNIFIED" -> emitAll(diff.unified(parameter.toInt(), oldName, newName))
            "CONTEXT" -> emitAll(diff.context(parameter.toInt(), oldName, newName))
            else -> emitAll(diff.sideBySide(parameter.toInt()))
        }
    }

    private fun tokenDiff(arguments: List<String>, byWord: Boolean) {
        val (oldName, newName) = arguments
        requireFiles(oldName, newName)
        val oldLines = files.getValue(oldName)
        val newLines = files.getValue(newName)
        val diff = LineDiff(oldLines, newLines)
        if (diff.blocks.isEmpty()) {
            emit("Files $oldName and $newName are identical")
            return
        }
        val separator = if (byWord) " " else ""
        val totals = TokenTotals()
        for (block in diff.blocks) {
            for (row in 0 until maxOf(block.x, block.y)) {
                val oldNumber = block.p + row + 1
                val newNumber = block.q + row + 1
                if (row < block.x && row < block.y) {
                    val oldTokens = splitTokens(oldLines[oldNumber - 1], byWord)
                    val newTokens = splitTokens(newLines[newNumber - 1], byWord)
                    val text = compareTokens(oldTokens, newTokens, separator, totals)
                    emit("a$oldNumber b$newNumber: $text")
                } else if (row < block.x) {
                    val oldTokens = splitTokens(oldLines[oldNumber - 1], byWord)
                    totals.deleted += oldTokens.size
                    emit("a$oldNumber: ${deletion(oldTokens, separator)}")
                } else {
                    val newTokens = splitTokens(newLines[newNumber - 1], byWord)
                    totals.inserted += newTokens.size
                    emit("b$newNumber: ${insertion(newTokens, separator)}")
                }
            }
        }
        val label = if (byWord) "WORDS" else "CHARS"
        emit("$label deleted=${totals.deleted} inserted=${totals.inserted} common=${totals.common}")
    }

    private fun stat(arguments: List<String>) {
        val (oldName, newName) = arguments
        requireFiles(oldName, newName)
        val oldLines = files.getValue(oldName)
        val newLines = files.getValue(newName)
        val diff = LineDiff(oldLines, newLines, arguments.drop(2))
        val deleted = diff.blocks.sumOf { it.x }
        val inserted = diff.blocks.sumOf { it.y }
        val total = deleted + inserted
        val unchanged = oldLines.size - deleted
        val graph = if (total > 0) " " + statGraph(inserted, deleted) else ""
        emit("$oldName -> $newName | $total$graph")
        val lineTotal = oldLines.size + newLines.size
        val similarity = if (lineTotal > 0) 200 * unchanged / lineTotal else 100
        emit(
            "changes=${diff.blocks.size} insertions=$inserted deletions=$deleted " +
                "unchanged=$unchanged similarity=$similarity%",
        )
    }

    private fun patch(arguments: List<String>, data: List<String>) {
        val name = arguments[0]
        requireFiles(name)
        val options = arguments.drop(2)
        val reverse = "REVERSE" in options
        val dryRun = "DRYRUN" in options
        val fuzzIndex = options.indexOf("FUZZ")
        val maxFuzz = if (fuzzIndex >= 0) options[fuzzIndex + 1].toInt() else 0
        val hunks = parsePatch(data)
        emit((if (dryRun) "checking file " else "patching file ") + name)
        var lines = files.getValue(name)
        val first = hunks.first()
        if (searchHunk(first, lines, 0, reverse, maxFuzz) == null &&
            searchHunk(first, lines, 0, !reverse, maxFuzz) != null
        ) {
            emit("Reversed (or previously applied) patch detected! Skipping patch.")
            emit("RESULT applied=0 failed=0 ignored=${hunks.size} lines=${lines.size}")
            return
        }
        var adjustment = 0
        var applied = 0
        var failed = 0
        for ((index, hunk) in hunks.withIndex()) {
            val match = searchHunk(hunk, lines, adjustment, reverse, maxFuzz)
            if (match == null) {
                failed++
                emit("Hunk #${index + 1} FAILED at ${hunk.start(reverse)}")
                continue
            }
            val (oldLines, newLines) = hunk.sequences(reverse)
            lines = match.lines
            adjustment += match.delta + newLines.size - oldLines.size
            applied++
            emit(match.report(index + 1))
        }
        emit("RESULT applied=$applied failed=$failed ignored=0 lines=${lines.size}")
        if (!dryRun && applied >= 1) save(name, lines)
    }

    private fun edit(arguments: List<String>, data: List<String>) {
        val name = arguments[0]
        requireFiles(name)
        val (lines, executed) = runEditScript(files.getValue(name), data)
        emit("EDIT $name commands=$executed lines=${lines.size}")
        save(name, lines)
    }

    private fun threeWay(baseName: String, oursName: String, theirsName: String): List<Chunk> {
        requireFiles(baseName, oursName, theirsName)
        return threeWayChunks(
            files.getValue(baseName),
            files.getValue(oursName),
            files.getValue(theirsName),
        )
    }

    private fun diff3(arguments: List<String>) {
        val (baseName, oursName, theirsName) = arguments
        val chunks = threeWay(baseName, oursName, theirsName)
        val changes = chunks.filter { it.kind != ChunkKind.STABLE }
        for (chunk in changes) {
            emit("==== ${chunk.kind.name.lowercase()} ${chunk.location()}")
            chunk.base.forEach { emit("O $it") }
            if (chunk.kind != ChunkKind.B) chunk.ours.forEach { emit("A $it") }
            if (chunk.kind == ChunkKind.B || chunk.kind == ChunkKind.CONFLICT) {
                chunk.theirs.forEach { emit("B $it") }
            }
        }
        emit("DIFF3 chunks=${changes.size} ${kindCounts(chunks)}")
    }

    private fun merge(arguments: List<String>) {
        val (baseName, oursName, theirsName, target) = arguments
        val mode = arguments.getOrElse(4) { "MARKERS" }
        val chunks = threeWay(baseName, oursName, theirsName)
        val result = mutableListOf<String>()
        val conflicts = mutableListOf<Chunk>()
        for (chunk in chunks) {
            when (chunk.kind) {
                ChunkKind.B -> result.addAll(chunk.theirs)
                ChunkKind.CONFLICT -> {
                    result.addAll(conflictLines(chunk, mode, baseName, oursName, theirsName))
                    conflicts.add(chunk)
                }
                else -> result.addAll(chunk.ours)
            }
        }
        emit("MERGE $target lines=${result.size} ${kindCounts(chunks)}")
        conflicts.forEachIndexed { index, chunk ->
            emit("CONFLICT ${index + 1} ${chunk.location()}")
        }
        save(target, result)
    }

    private fun conflicts(arguments: List<String>) {
        val name = arguments[0]
        requireFiles(name)
        val regions = conflictRegions(files.getValue(name))
        emit("CONFLICTS $name count=${regions.size}")
        regions.forEachIndexed { index, region ->
            val base = region.base?.size?.toString() ?: "none"
            emit(
                "${index + 1}: lines ${region.start}-${region.end} ours=${region.ours.size} " +
                    "base=$base theirs=${region.theirs.size}",
            )
        }
    }

    private fun resolve(arguments: List<String>) {
        val (name, numberText, side) = arguments
        requireFiles(name)
        val number = numberText.toInt()
        val lines = files.getValue(name)
        val regions = conflictRegions(lines)
        if (regions.size < number) throw CommandError("ERROR no conflict $number in $name")
        val region = regions[number - 1]
        if (side == "BASE" && region.base == null) {
            throw CommandError("ERROR no base section in conflict $number")
        }
        val content = lines.subList(0, region.start - 1) + region.part(side) +
            lines.subList(region.end, lines.size)
        val remaining = conflictRegions(content).size
        emit("RESOLVE $name $number $side lines=${content.size} remaining=$remaining")
        save(name, content)
    }
}

fun main() {
    val lines = generateSequence(::readlnOrNull).toList()
    val workspace = Workspace()
    var position = 1
    repeat(lines[0].toInt()) {
        val words = lines[position].split(" ")
        position++
        var data = emptyList<String>()
        if (words[0] in DATA_COMMANDS) {
            val count = words[2].toInt()
            data = lines.subList(position, position + count)
            position += count
        }
        workspace.execute(words, data)
    }
    print(workspace.output)
}
