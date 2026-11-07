import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import kotlin.math.max
import kotlin.math.min

private data class TimeRange(val low: Long, val high: Long)
private class QueryError(message: String) : RuntimeException(message)
private fun readLines(name: String): List<String> = Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII)
private fun yearStart(year: Int): Long = DayRules.dayNumber(year, 1, 1) * DayRules.DAY
private fun clockSeconds(text: String): Long = text.substring(0, 2).toLong() * 3600 + text.substring(3, 5).toLong() * 60
private fun namesOrNone(names: List<String>, separator: String): String = if (names.isEmpty()) "none" else names.joinToString(separator)
private fun indented(lines: List<String>): List<String> = lines.mapIndexed { i, line -> (if (i == 0) "" else "  ") + line }

private fun mergeIntervals(intervals: List<TimeRange>): List<TimeRange> {
    val result = mutableListOf<TimeRange>()
    for (range in intervals.sortedWith(compareBy<TimeRange> { it.low }.thenBy { it.high })) {
        if (result.isNotEmpty() && range.low <= result.last().high) result[result.lastIndex] = TimeRange(result.last().low, max(result.last().high, range.high))
        else result.add(range)
    }
    return result
}

private fun intersectIntervals(first: List<TimeRange>, second: List<TimeRange>): List<TimeRange> {
    val pieces = mutableListOf<TimeRange>()
    for (one in first) for (other in second) {
        val low = max(one.low, other.low)
        val high = min(one.high, other.high)
        if (low < high) pieces.add(TimeRange(low, high))
    }
    return mergeIntervals(pieces)
}

private class SourceLine(val number: Int, content: String) {
    val fields = TzParser.fields(content)
    val kind = if (TzParser.continuation(content)) "continuation" else if (fields[0] in listOf("Rule", "Zone", "Link")) fields[0] else "unknown"
    var block: Block? = null
    var position = 0
    var zoneLine: ZoneLine? = null
    var fieldError = false
    var error: String? = null
    fun acceptsContinuation(): Boolean = if (kind == "Zone") fields.size >= 6 else kind == "continuation" && fields.size >= 4
}

private class Block(first: SourceLine) {
    val name = first.fields[1]
    val number = first.number
    val lines = mutableListOf<SourceLine>()
    var defined = false
    init { add(first) }
    fun add(line: SourceLine) { line.block = this; line.position = lines.size; lines.add(line) }
}

private class ZoneLine(fields: List<String>) {
    val stdoff: Long
    val rulesText: String
    val ruleSet: String?
    val format: String
    val save: Long
    val until: TzParser.Until?
    var start = DayRules.NEG_INFINITY
    var end = DayRules.POS_INFINITY

    init {
        stdoff = TzParser.offset(fields[0])
        rulesText = fields[1]
        if (rulesText[0] in '0'..'9') { save = TzParser.save(rulesText); ruleSet = null }
        else { save = 0; ruleSet = if (rulesText == "-") null else rulesText }
        format = fields[2]
        TzParser.checkFormat(format, ruleSet != null)
        until = if (fields.size > 3) TzParser.until(fields.drop(3)) else null
    }
    fun rulesNotation(): String = ruleSet ?: if (rulesText == "-") "-" else Report.clock(save)
    fun untilNotation(): String = until!!.let { "${it.yearText} ${it.monthText} ${it.dayText} ${Report.clock(it.time)}${it.type}" }
}

private class Zone(val name: String, val lines: List<ZoneLine>) {
    val aliases = mutableListOf<String>()
    val applied = mutableMapOf<Int, Int>()
    lateinit var timeline: Resolver.Timeline
    fun ruleSets(): List<String> {
        val names = mutableListOf<String>()
        for (line in lines) if (line.ruleSet != null && line.ruleSet !in names) names.add(line.ruleSet)
        return names
    }
    fun lineNumberAt(time: Long): Int {
        for (i in lines.indices) if (lines[i].start <= time && time < lines[i].end) return i + 1
        error("missing zone line")
    }
}

private fun parseRule(line: SourceLine): Transitions.Rule {
    val fields = line.fields
    val from = TzParser.year(fields[2])
    val to = TzParser.toYear(fields[3], from)
    if (fields[4] != "-") throw TzParser.FieldError("syntax error")
    val month = TzParser.month(fields[5])
    val day = TzParser.day(fields[6], month)
    val time = TzParser.time(fields[7])
    val save = TzParser.save(fields[8])
    val letter = TzParser.letter(fields[9])
    return Transitions.Rule(line.number, fields, from, to, month, day, time.value, time.type, save, letter)
}

private class Database(rawLines: List<String>) {
    val lines = mutableListOf<SourceLine>()
    val blocks = mutableListOf<Block>()
    val rules = linkedMapOf<String, MutableList<Transitions.Rule>>()
    private val sequences = mutableMapOf<String, List<Transitions.Instance>>()
    val zones = linkedMapOf<String, Zone>()
    private val aliases = mutableMapOf<String, Zone>()

    init {
        for ((i, raw) in rawLines.withIndex()) { val content = TzParser.content(raw); if (content.isNotEmpty()) lines.add(SourceLine(i + 1, content)) }
        var previous: SourceLine? = null
        for (line in lines) {
            if (line.kind == "Zone") blocks.add(Block(line))
            else if (line.kind == "continuation" && previous != null && previous.block != null && previous.acceptsContinuation()) previous.block!!.add(line)
            previous = line
        }
        for (line in lines) {
            try { parseFields(line) }
            catch (exception: TzParser.FieldError) { line.fieldError = true; line.error = exception.message }
        }
        val zoneNames = mutableSetOf<String>()
        for (line in lines) if (line.zoneLine != null) line.error = structuralError(line, zoneNames)
        for ((name, set) in rules) sequences[name] = Transitions.instances(set)
        for (block in blocks) { block.defined = block.lines.all { it.error == null }; if (block.defined) defineZone(block) }
        for (line in lines) if (line.kind == "Link" && line.error == null) registerLink(line)
    }

    private fun parseFields(line: SourceLine) {
        val limits = when (line.kind) {
            "Rule" -> 10..10
            "Zone" -> 5..9
            "continuation" -> { if (line.block == null) throw TzParser.FieldError("syntax error"); 3..7 }
            "Link" -> 3..3
            else -> throw TzParser.FieldError("syntax error")
        }
        if (line.fields.size !in limits) throw TzParser.FieldError("syntax error")
        when (line.kind) {
            "Rule" -> { val rule = parseRule(line); rules.getOrPut(rule.name) { mutableListOf() }.add(rule) }
            "Zone" -> line.zoneLine = ZoneLine(line.fields.drop(2))
            "continuation" -> line.zoneLine = ZoneLine(line.fields)
        }
    }

    private fun structuralError(line: SourceLine, zoneNames: MutableSet<String>): String? {
        val value = line.zoneLine!!
        if (line.kind == "Zone" && !zoneNames.add(line.fields[1])) return "duplicate zone " + line.fields[1]
        if (value.ruleSet != null && value.ruleSet !in rules) return "unknown rule " + value.ruleSet
        if (value.until == null) return null
        if (line.kind == "continuation") {
            val previous = line.block!!.lines[line.position - 1]
            if (!previous.fieldError && value.until.value <= previous.zoneLine!!.until!!.value) return "until not increasing"
        }
        return if (line.position == line.block!!.lines.lastIndex) "missing continuation" else null
    }

    private fun defineZone(block: Block) {
        val zone = Zone(block.name, block.lines.map { it.zoneLine!! })
        val switches = mutableListOf<Resolver.Period>()
        var start = DayRules.NEG_INFINITY
        for (line in zone.lines) {
            line.start = start
            for (value in lineSwitches(zone, line)) switches.add(Resolver.Period(value.time, line.stdoff + value.save, value.save != 0L, Transitions.abbreviation(line.format, value.save, value.letter)))
            start = line.end
        }
        val periods = mutableListOf<Resolver.Period>()
        for (period in switches) if (periods.isEmpty() || !periods.last().sameState(period)) periods.add(period)
        zone.timeline = Resolver.Timeline(periods)
        zones[zone.name] = zone
    }

    private fun lineSwitches(zone: Zone, line: ZoneLine): List<Transitions.Switch> {
        if (line.ruleSet == null) {
            if (line.until != null) line.end = line.until.value - Transitions.adjustment(line.until.type, line.stdoff, line.save)
            return listOf(Transitions.Switch(line.start, line.save, ""))
        }
        val instances = sequences.getValue(line.ruleSet)
        val run = Transitions.run(instances, line.stdoff, line.start, line.until)
        line.end = run.end
        val save: Long
        val letter: String
        if (run.preStart.isNotEmpty()) { val last = run.preStart.last(); save = last.save; letter = last.letter }
        else { save = 0; letter = instances.firstOrNull { it.rule.save == 0L }?.rule?.letter ?: "" }
        val switches = mutableListOf(Transitions.Switch(line.start, save, letter))
        for (value in run.applied) {
            switches.add(Transitions.Switch(value.time, value.rule.save, value.rule.letter))
            zone.applied[value.rule.number] = zone.applied.getOrDefault(value.rule.number, 0) + 1
        }
        return switches
    }

    private fun registerLink(line: SourceLine) {
        val target = line.fields[1]
        val alias = line.fields[2]
        if (target !in zones) line.error = "unknown link target $target"
        else if (alias in zones || alias in aliases) line.error = "duplicate link $alias"
        else { aliases[alias] = zones.getValue(target); zones.getValue(target).aliases.add(alias) }
    }
    fun findZone(name: String): Zone? = zones[name] ?: aliases[name]
    fun errorLines(): List<String> = lines.filter { it.error != null }.map { "line ${it.number}: ${it.error}" }
}

private fun offsetShift(timeline: Resolver.Timeline, index: Int): Long = timeline.periods[index].offset - timeline.periods[index - 1].offset
private fun transitionsBetween(timeline: Resolver.Timeline, low: Long, high: Long): List<Int> =
    (1 until timeline.periods.size).filter { low <= timeline.periods[it].start && timeline.periods[it].start < high }
private fun changeAt(timeline: Resolver.Timeline, index: Int): String = Report.change(timeline.periods[index].start, timeline.periods[index - 1], timeline.periods[index])
private fun transitionLine(timeline: Resolver.Timeline, index: Int): String {
    val time = timeline.periods[index].start
    val shift = offsetShift(timeline, index)
    val kind = if (shift > 0) "gap " + Report.duration(shift) else if (shift < 0) "overlap " + Report.duration(-shift) else "no shift"
    return "${changeAt(timeline, index)} (local ${Report.local(time + timeline.periods[index - 1].offset)} -> ${Report.local(time + timeline.periods[index].offset)}, $kind)"
}
private fun shiftsText(timeline: Resolver.Timeline, indices: List<Int>): String {
    var gaps = 0
    var overlaps = 0
    var unchanged = 0
    for (index in indices) { val shift = offsetShift(timeline, index); if (shift > 0) gaps++ else if (shift < 0) overlaps++ else unchanged++ }
    return "gaps $gaps, overlaps $overlaps, no shift $unchanged"
}
private fun candidateText(timeline: Resolver.Timeline, local: Long, index: Int): String {
    val period = timeline.periods[index]
    return "${Report.ut(local - period.offset)} (${Report.state(period)})"
}
private fun chosenCandidate(candidates: List<Int>, option: String?): Int? {
    if (candidates.size == 1 || candidates.size == 2 && option == "EARLIER") return candidates[0]
    return if (candidates.size == 2 && option == "LATER") candidates[1] else null
}
private fun unresolvedText(timeline: Resolver.Timeline, local: Long, candidates: List<Int>): String {
    if (candidates.isNotEmpty()) return "AMBIGUOUS " + candidates.joinToString(" or ") { candidateText(timeline, local, it) }
    val index = timeline.skippingTransition(local)
    val time = timeline.periods[index].start
    return "NONEXISTENT gap ${Report.local(time + timeline.periods[index - 1].offset)} to ${Report.local(time + timeline.periods[index].offset)} at ${Report.ut(time)}"
}
private fun workingHours(timeline: Resolver.Timeline, start: Long, end: Long): List<TimeRange> {
    val pieces = mutableListOf<TimeRange>()
    for (i in timeline.nearbyFirst(start)..timeline.nearbyLast(end)) {
        val offset = timeline.periods[i].offset
        val low = max(start - offset, timeline.periods[i].start)
        val high = min(end - offset, timeline.endOf(i))
        if (low < high) pieces.add(TimeRange(low, high))
    }
    return mergeIntervals(pieces)
}
private fun parseValue(kind: String, word: String): Long? {
    val year = word.substring(0, 4).toInt()
    if (year !in 1800..2099) return null
    if (kind == "year") return year.toLong()
    val month = word.substring(5, 7).toInt()
    val day = word.substring(8, 10).toInt()
    if (month !in 1..12 || day < 1 || day > DayRules.daysInMonth(year, month)) return null
    if (kind == "date") return DayRules.dayNumber(year, month, day)
    val hour = word.substring(11, 13).toInt()
    val minute = word.substring(14, 16).toInt()
    val second = word.substring(17, 19).toInt()
    return if (hour > 23 || minute > 59 || second > 59) null else DayRules.timeValue(year, month, day, hour, minute, second)
}

private class QueryRunner(val database: Database, val workStart: Long, val workEnd: Long) {
    val answers = mutableListOf<String>()
    val transitionBlocks = mutableListOf<List<String>>()

    fun run(line: String) {
        val words = line.split(' ')
        val command = words[0]
        val arguments = words.drop(1).toMutableList()
        var option: String? = null
        if (command in listOf("TOUTC", "CONVERT") && arguments.last() in listOf("EARLIER", "LATER")) option = arguments.removeAt(arguments.lastIndex)
        val kinds = when (command) {
            "TOUTC" -> listOf("zone", "local")
            "TOLOCAL", "OFFSET" -> listOf("zone", "ut")
            "CONVERT" -> listOf("zone", "zone", "local")
            "TRANSITIONS" -> listOf("zone", "year", "year")
            "DURATION" -> listOf("zone", "local", "local")
            else -> listOf("date") + List(arguments.size - 1) { "zone" }
        }
        val result = try {
            val values = arguments.mapIndexed { i, word ->
                if (kinds[i] == "zone") database.findZone(word) ?: throw QueryError("unknown zone $word")
                else parseValue(kinds[i], word) ?: throw QueryError("invalid value $word")
            }
            answer(line, command, values, arguments, option)
        } catch (exception: QueryError) { "ERROR ${exception.message}" }
        answers.add("$line => $result")
    }

    private fun answer(line: String, command: String, values: List<Any>, arguments: List<String>, option: String?): String {
        if (command == "MEETING") return meeting(values[0] as Long, values.drop(1).map { it as Zone }, arguments.drop(1))
        val zone = values[0] as Zone
        return when (command) {
            "TOUTC" -> toUtc(zone, values[1] as Long, option)
            "TOLOCAL" -> toLocal(zone, values[1] as Long)
            "CONVERT" -> convert(zone, values[1] as Zone, values[2] as Long, option)
            "OFFSET" -> offset(zone, values[1] as Long)
            "TRANSITIONS" -> transitions(line, zone, (values[1] as Long).toInt(), (values[2] as Long).toInt())
            else -> duration(zone, values[1] as Long, values[2] as Long, arguments.drop(1))
        }
    }
    private fun toUtc(zone: Zone, local: Long, option: String?): String {
        val candidates = zone.timeline.candidates(local)
        val index = chosenCandidate(candidates, option)
        return if (index == null) unresolvedText(zone.timeline, local, candidates) else candidateText(zone.timeline, local, index)
    }
    private fun toLocal(zone: Zone, time: Long): String {
        val period = zone.timeline.periodAt(time)
        return "${Report.local(time + period.offset)} (${Report.state(period)})"
    }
    private fun convert(source: Zone, target: Zone, local: Long, option: String?): String {
        val candidates = source.timeline.candidates(local)
        val index = chosenCandidate(candidates, option) ?: return unresolvedText(source.timeline, local, candidates)
        val time = local - source.timeline.periods[index].offset
        val period = target.timeline.periodAt(time)
        val targetLocal = time + period.offset
        val shift = Math.floorDiv(targetLocal, DayRules.DAY) - Math.floorDiv(local, DayRules.DAY)
        return "${Report.local(targetLocal)} (${Report.state(period)}) at ${Report.ut(time)}, day shift ${if (shift > 0) "+" else ""}$shift"
    }
    private fun offset(zone: Zone, time: Long): String {
        val timeline = zone.timeline
        val index = timeline.indexAt(time)
        var text = Report.state(timeline.periods[index])
        if (index >= 1) text += " since " + Report.ut(timeline.periods[index].start)
        if (index + 1 < timeline.periods.size) text += " until " + Report.ut(timeline.periods[index + 1].start)
        return text
    }
    private fun transitions(line: String, zone: Zone, first: Int, last: Int): String {
        if (first > last) throw QueryError("invalid range")
        val selected = transitionsBetween(zone.timeline, yearStart(first), yearStart(last + 1))
        val block = mutableListOf(line)
        for (index in selected) block.add(transitionLine(zone.timeline, index))
        block.add(shiftsText(zone.timeline, selected))
        transitionBlocks.add(block)
        return "transitions: ${selected.size}"
    }
    private fun duration(zone: Zone, first: Long, second: Long, words: List<String>): String {
        val periods = mutableListOf<Resolver.Period>()
        val locals = longArrayOf(first, second)
        for (i in 0..1) {
            val candidates = zone.timeline.candidates(locals[i])
            if (candidates.size == 2) return "AMBIGUOUS " + words[i]
            if (candidates.isEmpty()) return "NONEXISTENT " + words[i]
            periods.add(zone.timeline.periods[candidates[0]])
        }
        val elapsed = (second - periods[1].offset) - (first - periods[0].offset)
        val change = periods[1].offset - periods[0].offset
        return "$elapsed s (${Report.duration(elapsed)}), wall clock ${Report.duration(second - first)}, offset change ${Report.offset(change)}"
    }
    private fun meeting(day: Long, zones: List<Zone>, words: List<String>): String {
        val start = day * DayRules.DAY + workStart
        val end = day * DayRules.DAY + workEnd
        var common = workingHours(zones[0].timeline, start, end)
        for (zone in zones.drop(1)) common = intersectIntervals(common, workingHours(zone.timeline, start, end))
        val parts = mutableListOf<String>()
        for (range in common) {
            val members = zones.mapIndexed { i, zone ->
                val period = zone.timeline.periodAt(range.low)
                "${words[i]} ${Report.local(range.low + period.offset)} ${period.abbreviation}"
            }
            parts.add("${Report.ut(range.low)} to ${Report.ut(range.high)} (${Report.duration(range.high - range.low)}) [${members.joinToString(", ")}]")
        }
        return if (parts.isEmpty()) "NONE" else parts.joinToString("; ")
    }
}

private fun ruleText(rule: Transitions.Rule): String {
    val fields = rule.fields
    return "rule ${rule.name} ${fields[2]} ${fields[3]} ${fields[5]} ${fields[6]} ${Report.clock(rule.at)}${rule.type} ${Report.clock(rule.save)} ${fields[9]}"
}
private fun databaseBlock(database: Database): List<String> {
    val ruleLines = database.lines.count { it.kind == "Rule" }
    val linkLines = database.lines.count { it.kind == "Link" }
    val validRules = database.lines.count { it.kind == "Rule" && it.error == null }
    val validLinks = database.lines.count { it.kind == "Link" && it.error == null }
    val used = database.zones.values.flatMap { it.ruleSets() }.toSet()
    val unused = database.rules.keys.filter { it !in used }
    val invalid = database.blocks.filter { !it.defined }.map { "${it.name} (line ${it.number})" }
    val lines = mutableListOf(
        "DATABASE", "rule lines: $validRules valid, ${ruleLines - validRules} invalid", "zones: ${database.zones.size} defined, ${database.blocks.size - database.zones.size} invalid",
        "zone lines: ${database.zones.values.sumOf { it.lines.size }} in defined zones", "links: $validLinks defined, ${linkLines - validLinks} invalid", "errors: ${database.errorLines().size}",
        "unused rules: " + namesOrNone(unused, " "), "invalid zones: " + namesOrNone(invalid, ", ")
    )
    for ((name, rules) in database.rules) {
        val first = rules.minOf { it.fromYear }
        val last = if (rules.any { it.fields[3] == "max" }) "max" else rules.maxOf { it.toYear }.toString()
        val count = database.zones.values.count { name in it.ruleSets() }
        lines.add("rule set $name: lines ${rules.size}, years $first-$last, zones $count")
    }
    return lines
}
private fun dstLines(timeline: Resolver.Timeline, reference: Long): List<String> {
    val indices = timeline.periods.indices.filter { timeline.periods[it].dst }
    val lines = mutableListOf<String>()
    if (indices.isEmpty()) lines.add("dst years: none")
    else { val years = indices.map { DayRules.splitTime(timeline.periods[it].start)[0] }; lines.add("dst years: ${years.min()}-${years.max()}") }
    val year = DayRules.splitTime(reference)[0]
    val low = yearStart(year)
    val high = yearStart(year + 1)
    val pieces = mutableListOf<TimeRange>()
    for (index in indices) { val start = max(low, timeline.periods[index].start); val end = min(high, timeline.endOf(index)); if (start < end) pieces.add(TimeRange(start, end)) }
    var total = 0L
    for (range in mergeIntervals(pieces)) { lines.add("dst period: ${Report.ut(range.low)} to ${Report.ut(range.high)} (${Report.duration(range.high - range.low)})"); total += range.high - range.low }
    lines.add("dst total $year: ${Report.duration(total)}")
    return lines
}
private fun zoneBlock(database: Database, zone: Zone, reference: Long): List<String> {
    val timeline = zone.timeline
    val periods = timeline.periods
    val lines = mutableListOf("ZONE " + zone.name, "aliases: " + namesOrNone(zone.aliases, " "))
    for ((i, value) in zone.lines.withIndex()) {
        var text = "line ${i + 1}: ${Report.offset(value.stdoff)} ${value.rulesNotation()} ${value.format}"
        if (i >= 1) text += " from " + Report.ut(value.start)
        if (value.until != null) text += " until ${value.untilNotation()} = ${Report.ut(value.end)}"
        lines.add("$text, transitions ${transitionsBetween(timeline, value.start, value.end).size}")
    }
    for (name in zone.ruleSets()) for (rule in database.rules.getValue(name)) lines.add("${ruleText(rule)}, applied ${zone.applied.getOrDefault(rule.number, 0)}")
    lines.add("offset range: ${Report.offset(periods.minOf { it.offset })} to ${Report.offset(periods.maxOf { it.offset })}")
    val states = linkedMapOf<String, Int>()
    for (period in periods) { val state = Report.state(period); states[state] = states.getOrDefault(state, 0) + 1 }
    for ((state, count) in states) lines.add("state $state, periods $count")
    val index = timeline.indexAt(reference)
    val period = periods[index]
    lines.add("reference: ${Report.local(reference + period.offset)} (${Report.state(period)}), line ${zone.lineNumberAt(reference)}")
    lines.add("previous transition: " + if (index >= 1) changeAt(timeline, index) else "none")
    lines.add("next transition: " + if (index + 1 < periods.size) changeAt(timeline, index + 1) else "none")
    val every = (1 until periods.size).toList()
    lines.add("transitions: ${every.size}, ${shiftsText(timeline, every)}")
    lines.addAll(dstLines(timeline, reference))
    return lines
}

fun main() {
    val database = Database(readLines("tzdata.txt"))
    val parameters = readLines("params.txt")
    val reference = parseValue("ut", parameters[0].split(' ')[1])!!
    val workday = parameters[1].split(' ')
    val runner = QueryRunner(database, clockSeconds(workday[1]), clockSeconds(workday[2]))
    for (line in readLines("queries.txt")) runner.run(line)
    val blocks = mutableListOf(indented(databaseBlock(database)))
    for (name in database.zones.keys.sorted()) blocks.add(indented(zoneBlock(database, database.zones.getValue(name), reference)))
    Files.createDirectories(Path.of("output"))
    Report.writeLines("answers.txt", runner.answers)
    Report.writeLines("errors.txt", database.errorLines())
    Report.writeBlocks("transitions.txt", runner.transitionBlocks)
    Report.writeBlocks("zone_summary.txt", blocks)
}
