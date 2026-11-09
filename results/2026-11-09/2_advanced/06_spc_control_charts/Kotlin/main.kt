import java.io.File
import java.util.Locale
import kotlin.math.abs
import kotlin.math.sqrt

val chartOrder = listOf("XBAR_R", "R", "XBAR_S", "S", "I", "MR", "CUSUM", "EWMA", "MA")
val familyNames = listOf("XBAR_R", "XBAR_S", "I_MR")
val familyCharts = mapOf("XBAR_R" to listOf("XBAR_R", "R"), "XBAR_S" to listOf("XBAR_S", "S"), "I_MR" to listOf("I", "MR"))
val ruleOrder = (1..8).map(Int::toString) + listOf("UPPER", "LOWER")
fun real(value: Double): String = String.format(Locale.ROOT, "%.4f", value).let { if (it == "-0.0000") "0.0000" else it }
fun numbers(values: List<Int>) = if (values.isEmpty()) "none" else values.sorted().joinToString(" ")
fun status(converged: Boolean) = if (converged) "converged" else "stopped"
fun limitsText(label: String, limits: Limits) = "$label lcl ${real(limits.lcl)} cl ${real(limits.cl)} ucl ${real(limits.ucl)}"
fun pairText(family: String, pair: FamilyLimits) = limitsText(if (family == "I_MR") "I" else "XBAR", pair.first) + " " + limitsText(familyCharts.getValue(family)[1], pair.second)
data class EstimationPass(val points: Int, val limits: FamilyLimits, val out: List<Int>)
data class Estimate(val passes: List<EstimationPass>, val converged: Boolean, val retained: List<Int>, val removed: List<Int>) { val limits get() = passes.last().limits }
data class PatternCheck(val chart: String, val points: Int, val signals: List<Signal>)
data class Proposal(val family: String, val points: Int, val limits: FamilyLimits)
data class CusumPoint(val number: Int, val upper: Double, val lower: Double)
data class BandPoint(val number: Int, val value: Double, val width: Double)
data class Event(val number: Int, val start: Int, var end: Int) {
    var signals = emptyList<Signal>()
    val counts = IntArray(5)
    var onset = start
    var shift = 0.0
    var spread = 0.0
    var outside = 0
    var detection = emptyList<Int?>()
    val length get() = end - start + 1
    val kind get() = listOf("SHIFT_UP", "SHIFT_DOWN", "SPREAD_UP", "SPREAD_DOWN", "PATTERN")[counts.indexOf(counts.max())]
    fun contains(group: Int) = group in start..end
}
data class AttributePass(val lots: Int, val center: Double, val out: List<Int>)
data class AttributeResult(val chart: String, val passes: List<AttributePass>, val converged: Boolean, val retained: Int, val removed: List<Int>, val points: List<LotPoint>, val signals: List<Signal>)
data class CapabilityGroup(val name: String, val groups: Int, val result: Capability)
data class RollingResult(val first: Int, val last: Int, val result: Capability)

class Analysis(val settings: Settings, val samples: List<Long>, val lots: List<Lot>) {
    val groups = samples.chunked(settings.size).mapIndexed { index, values -> Subgroup(index + 1, values) }
    val constants = controlConstants(settings.size)
    val estimates = mutableMapOf<String, Estimate>()
    val checks = mutableListOf<PatternCheck>()
    val signals = mutableListOf<Signal>()
    val cusum = mutableListOf<CusumPoint>()
    val ewma = mutableListOf<BandPoint>()
    val movingAverage = mutableListOf<BandPoint>()
    val events = mutableListOf<Event>()
    val proposals = mutableListOf<Proposal>()
    val attributes = mutableListOf<AttributeResult>()
    val capabilities = mutableListOf<CapabilityGroup>()
    val rolling = mutableListOf<RollingResult>()
    var mu = 0.0
    var sigma = 0.0
    var reference = 0.0
    var interval = 0.0
    var ewmaWidth = 0.0
    var maWidth = 0.0
    val phase2 get() = groups.drop(settings.phase1)

    fun limits(family: String, ids: List<Int>) = familyLimits(family, ids, groups, samples, settings.size, constants)
    fun chartLimits(chart: String): Limits {
        val family = familyNames.first { chart in familyCharts.getValue(it) }
        val pair = estimates.getValue(family).limits
        return if (chart == familyCharts.getValue(family)[0]) pair.first else pair.second
    }
    fun series(family: String, ids: List<Int>): Pair<List<Point>, List<Point>> {
        if (family == "I_MR") {
            return ids.map { Point(it, samples[it - 1].toDouble()) } to ids.zipWithNext { a, b -> Point(b, abs(samples[b - 1] - samples[a - 1]).toDouble()) }
        }
        val chosen = ids.map { groups[it - 1] }
        return chosen.map { Point(it.number, it.mean) } to chosen.map { Point(it.number, if (family == "XBAR_R") it.range.toDouble() else it.sd) }
    }
    fun estimate(family: String) {
        val initial = (1..if (family == "I_MR") settings.phase1 * settings.size else settings.phase1).toList()
        var ids = initial
        val passes = mutableListOf<EstimationPass>()
        var converged = false
        for (pass in 1..settings.passes) {
            val limits = limits(family, ids)
            val pair = series(family, ids)
            val out = (pair.first.filter { limits.first.outside(it.value) } + pair.second.filter { limits.second.outside(it.value) }).map { it.number }.distinct().sorted()
            passes += EstimationPass(ids.size, limits, out)
            if (out.isEmpty()) { converged = true; break }
            if (pass == settings.passes) break
            ids = ids.filter { it !in out }
        }
        estimates[family] = Estimate(passes, converged, ids, initial.filter { it !in ids })
    }
    fun phase2Series(chart: String): List<Point> {
        if (chart == "I" || chart == "MR") return (settings.phase1 * settings.size + 1..samples.size).map { number -> Point(number, if (chart == "I") samples[number - 1].toDouble() else abs(samples[number - 1] - samples[number - 2]).toDouble()) }
        return phase2.map { Point(it.number, when (chart) { "R" -> it.range.toDouble(); "S" -> it.sd; else -> it.mean }) }
    }
    fun hasSignal(chart: String, end: Int, rule: String? = null) = signals.any { it.chart == chart && it.end == end && (rule == null || it.rule == rule) }
    fun eventOf(group: Int) = events.firstOrNull { it.contains(group) }
    fun addBandSignal(chart: String, point: BandPoint, start: Int) {
        if (point.value > mu + point.width) signals += Signal(chart, "UPPER", start, point.number, point.value, "UP")
        else if (point.value < mu - point.width) signals += Signal(chart, "LOWER", start, point.number, point.value, "DOWN")
    }
    fun monitor() {
        for (chart in chartOrder.take(6)) signals += runRules(chart, phase2Series(chart), chartLimits(chart), settings.rules.getValue(chart))
        var upper = 0.0
        var lower = 0.0
        var upperRun = 0
        var lowerRun = 0
        var smoothed = mu
        var factor = 1.0
        val decay = (1.0 - settings.lambda) * (1.0 - settings.lambda)
        val ratio = settings.lambda / (2.0 - settings.lambda)
        ewmaWidth = settings.ewmaL * sigma * sqrt(ratio)
        maWidth = 3.0 * sigma / sqrt(settings.maSpan.toDouble())
        for (group in phase2) {
            val number = group.number
            upper = maxOf(0.0, upper + (group.mean - mu - reference))
            lower = maxOf(0.0, lower + (mu - group.mean - reference))
            upperRun = if (upper > 0.0) upperRun + 1 else 0
            lowerRun = if (lower > 0.0) lowerRun + 1 else 0
            cusum += CusumPoint(number, upper, lower)
            if (upper > interval) { signals += Signal("CUSUM", "UPPER", number - upperRun + 1, number, upper, "UP"); upper = 0.0; upperRun = 0 }
            if (lower > interval) { signals += Signal("CUSUM", "LOWER", number - lowerRun + 1, number, lower, "DOWN"); lower = 0.0; lowerRun = 0 }
            smoothed = settings.lambda * group.mean + (1.0 - settings.lambda) * smoothed
            factor *= decay
            val weighted = BandPoint(number, smoothed, settings.ewmaL * sigma * sqrt(ratio * (1.0 - factor)))
            ewma += weighted
            addBandSignal("EWMA", weighted, number)
            val first = maxOf(settings.phase1 + 1, number - settings.maSpan + 1)
            val count = number - first + 1
            val average = BandPoint(number, groups.subList(first - 1, number).sumOf { it.total }.toDouble() / (settings.size * count).toDouble(), 3.0 * sigma / sqrt(count.toDouble()))
            movingAverage += average
            addBandSignal("MA", average, first)
        }
        signals.sortWith(compareBy({ chartOrder.indexOf(it.chart) }, { it.end }, { ruleOrder.indexOf(it.rule) }))
    }
    fun buildEvents() {
        for (group in signals.map { it.subgroup(settings.size) }.distinct().sorted()) {
            if (events.isNotEmpty() && group - events.last().end - 1 <= settings.eventGap) events.last().end = group
            else events += Event(events.size + 1, group, group)
        }
        val locations = setOf("XBAR_R", "XBAR_S", "I", "CUSUM", "EWMA", "MA")
        for (event in events) {
            event.signals = signals.filter { event.contains(it.subgroup(settings.size)) }
            for (signal in event.signals) {
                val index = if (signal.direction == "NONE") 4 else if (signal.chart in locations) if (signal.direction == "UP") 0 else 1 else if (signal.direction == "UP") 2 else 3
                event.counts[index]++
            }
            event.onset = event.signals.filter { it.chart == "CUSUM" }.minOfOrNull { it.start } ?: event.start
            val covered = groups.subList(event.start - 1, event.end)
            val mean = covered.sumOf { it.total }.toDouble() / (settings.size * event.length).toDouble()
            event.shift = (mean - mu) / sigma
            event.spread = realSum(covered.map { it.sd }) / event.length.toDouble() / estimates.getValue("XBAR_S").limits.second.cl
            event.outside = covered.sumOf { group -> group.values.count { it < settings.lsl || it > settings.usl } }
            event.detection = chartOrder.map { chart -> event.signals.filter { it.chart == chart }.minOfOrNull { it.subgroup(settings.size) } }
        }
    }
    fun estimateAttribute(chart: String) {
        var chosen = lots
        val passes = mutableListOf<AttributePass>()
        var converged = false
        var center = attributeCenter(chart, chosen)
        for (pass in 1..settings.passes) {
            center = attributeCenter(chart, chosen)
            val out = chosen.filter { attributePoint(it, center).status != "ok" }.map { it.number }
            passes += AttributePass(chosen.size, center.value, out)
            if (out.isEmpty()) { converged = true; break }
            if (pass == settings.passes) break
            chosen = chosen.filter { it.number !in out }
        }
        val points = lots.map { attributePoint(it, center) }
        attributes += AttributeResult(chart, passes, converged, chosen.size, lots.filter { it !in chosen }.map { it.number }, points, runRules(chart, points.map { Point(it.lot.number, it.z) }, Limits(-3.0, 0.0, 3.0), settings.rules.getValue("STD")))
    }
    fun run() {
        for (family in familyNames) estimate(family)
        for (family in familyNames) {
            val estimate = estimates.getValue(family)
            val pair = series(family, estimate.retained)
            val charts = familyCharts.getValue(family)
            checks += PatternCheck(charts[0], pair.first.size, runRules(charts[0], pair.first, estimate.limits.first, settings.rules.getValue(charts[0])))
            checks += PatternCheck(charts[1], pair.second.size, runRules(charts[1], pair.second, estimate.limits.second, settings.rules.getValue(charts[1])))
        }
        mu = estimates.getValue("XBAR_R").limits.first.cl
        sigma = estimates.getValue("XBAR_R").limits.second.cl / constants.d2 / sqrt(settings.size.toDouble())
        reference = settings.cusumK * sigma
        interval = settings.cusumH * sigma
        monitor()
        buildEvents()
        val free = phase2.filter { eventOf(it.number) == null }.map { it.number }
        for (family in familyNames) {
            val added = if (family == "I_MR") free.flatMap { ((it - 1) * settings.size + 1..it * settings.size).toList() } else free
            val ids = estimates.getValue(family).retained + added
            proposals += Proposal(family, ids.size, limits(family, ids))
        }
        for (chart in listOf("p", "np", "c", "u")) estimateAttribute(chart)
        for ((name, ids) in listOf("phase1" to estimates.getValue("XBAR_R").retained, "phase2" to phase2.map { it.number })) capabilities += CapabilityGroup(name, ids.size, capability(ids, groups, settings, constants))
        var first = settings.phase1 + 1
        while (first + settings.rollingWindow - 1 <= groups.size) {
            val last = first + settings.rollingWindow - 1
            rolling += RollingResult(first, last, capability((first..last).toList(), groups, settings, constants))
            first += settings.rollingStep
        }
    }
    fun limitsLines(): List<String> {
        val lines = mutableListOf("characteristic ${settings.characteristic}", "subgroup_size ${settings.size}", "subgroups ${groups.size}", "samples ${samples.size}", "phase1_subgroups ${settings.phase1}")
        for (family in familyNames) {
            val estimate = estimates.getValue(family)
            lines += "family $family"
            for ((index, pass) in estimate.passes.withIndex()) lines += "pass ${index + 1} points ${pass.points} ${pairText(family, pass.limits)} out ${numbers(pass.out)}"
            lines += "result ${status(estimate.converged)} passes ${estimate.passes.size} retained ${estimate.retained.size} removed ${numbers(estimate.removed)}"
        }
        for (check in checks) {
            for (signal in check.signals) lines += "phase1_signal ${check.chart} ${signal.rule} ${signal.start} ${signal.end} ${real(signal.value)}"
            lines += "phase1_check ${check.chart} points ${check.points} signals ${check.signals.size}"
        }
        for (proposal in proposals) lines += "proposed ${proposal.family} points ${proposal.points} ${pairText(proposal.family, proposal.limits)}"
        val target = "target ${real(mu)} sigma ${real(sigma)}"
        lines += "cusum $target k ${real(reference)} h ${real(interval)}"
        lines += "ewma $target lcl ${real(mu - ewmaWidth)} ucl ${real(mu + ewmaWidth)}"
        lines += "ma $target span ${settings.maSpan} lcl ${real(mu - maWidth)} ucl ${real(mu + maWidth)}"
        for (chart in chartOrder) {
            val selected = signals.filter { it.chart == chart }
            val points = if (chart == "I" || chart == "MR") samples.size - settings.phase1 * settings.size else phase2.size
            val rules = if (chart in chartOrder.take(6)) settings.rules.getValue(chart).map(Int::toString) else listOf("UPPER", "LOWER")
            val ends = selected.map { it.end }.distinct()
            val counts = rules.joinToString(" ") { rule -> "$rule:${selected.count { it.rule == rule }}" }
            lines += "phase2 $chart points $points signals ${selected.size} signalled ${ends.size} first ${ends.minOrNull()?.toString() ?: "none"} by_rule $counts"
        }
        return lines
    }
    fun signalLines() = listOf("chart,rule,start,end,value,direction") + signals.map { "${it.chart},${it.rule},${it.start},${it.end},${real(it.value)},${it.direction}" }
    fun eventLines(): List<String> {
        val lines = mutableListOf("events ${events.size}")
        for (event in events) {
            val charts = chartOrder.filterIndexed { index, _ -> event.detection[index] != null }.joinToString(",")
            val counts = event.counts
            lines += "event ${event.number} start ${event.start} end ${event.end} length ${event.length} signals ${event.signals.size} charts $charts location_up ${counts[0]} location_down ${counts[1]} spread_up ${counts[2]} spread_down ${counts[3]} pattern ${counts[4]} onset ${event.onset} shift ${real(event.shift)} spread ${real(event.spread)} out_of_spec ${event.outside} type ${event.kind}"
            lines += "detection ${event.number} " + chartOrder.mapIndexed { index, chart -> "$chart:${event.detection[index]?.toString() ?: "-"}" }.joinToString(" ")
        }
        return lines
    }
    fun subgroupLines(): List<String> {
        val lines = mutableListOf("subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event")
        val estimate = estimates.getValue("XBAR_R")
        for (group in groups) {
            val index = group.number - settings.phase1 - 1
            val phase = if (index >= 0) "phase2" else if (group.number in estimate.removed) "excluded" else "phase1"
            val monitored = if (index >= 0) listOf(real(cusum[index].upper), real(cusum[index].lower), real(ewma[index].value), real(movingAverage[index].value)) else List(4) { "-" }
            lines += (listOf(group.number.toString(), phase, real(group.mean), zoneName(group.mean, estimate.limits.first), group.range.toString(), real(group.sd)) + monitored + listOf(signals.count { it.subgroup(settings.size) == group.number }.toString(), eventOf(group.number)?.number?.toString() ?: "-")).joinToString(",")
        }
        return lines
    }
    fun attributeLines(): List<String> {
        val lines = mutableListOf<String>()
        for (result in attributes) {
            lines += "chart ${result.chart}"
            for ((index, pass) in result.passes.withIndex()) lines += "pass ${index + 1} lots ${pass.lots} center ${real(pass.center)} out ${numbers(pass.out)}"
            lines += "result ${status(result.converged)} passes ${result.passes.size} retained ${result.retained} removed ${numbers(result.removed)}"
            for (point in result.points) {
                val value = when (result.chart) { "np" -> point.lot.defectives.toString(); "c" -> point.lot.defects.toString(); else -> real(point.value) }
                lines += "lot ${point.lot.number} size ${point.lot.inspected} value $value lcl ${real(point.lcl)} ucl ${real(point.ucl)} z ${real(point.z)} status ${point.status}"
            }
            for (signal in result.signals) lines += "signal ${signal.rule} ${signal.start} ${signal.end} ${real(signal.value)}"
            lines += "signals ${result.signals.size}"
        }
        return lines
    }
    fun capabilityLines(): List<String> {
        val lines = mutableListOf<String>()
        for (group in capabilities) {
            val result = group.result
            lines += "group ${group.name} subgroups ${group.groups} values ${result.samples.size}"
            for ((name, value) in result.values) if (name != "ppm") lines += "$name ${real(value)}"
            for (name in listOf("cpk", "ppk")) {
                val bounds = confidence(result.values.getValue(name), result.samples.size, settings.ciZ)
                lines += "${name}_ci ${real(bounds.first)} ${real(bounds.second)}"
            }
            lines += "below_lsl ${result.below}"
            lines += "above_usl ${result.above}"
            lines += "ppm ${real(result.values.getValue("ppm"))}"
            for (sample in result.samples) if (sample.value < settings.lsl || sample.value > settings.usl) lines += "out_of_spec sample ${sample.number} subgroup ${sample.subgroup} value ${sample.value} side ${if (sample.value < settings.lsl) "low" else "high"}"
            lines += "verdict ${result.verdict}"
            lines += histogram(result, settings)
        }
        for (window in rolling) {
            val result = window.result
            val metrics = listOf("mean", "sigma_within", "sigma_overall", "cpk", "ppk").joinToString(" ") { "$it ${real(result.values.getValue(it))}" }
            lines += "rolling ${window.first} ${window.last} $metrics verdict ${result.verdict}"
        }
        return lines
    }
    fun chartLines(): List<String> {
        val lines = mutableListOf<String>()
        for ((name, chart, family) in listOf(Triple("XBAR", "XBAR_R", "XBAR_R"), Triple("R", "R", "XBAR_R"), Triple("S", "S", "XBAR_S"))) {
            val limits = chartLimits(chart)
            lines += limitsText("chart $name", limits)
            for (group in groups) {
                val value = when (chart) { "R" -> group.range.toDouble(); "S" -> group.sd; else -> group.mean }
                val mark = if (group.number > settings.phase1) "2" else if (group.number in estimates.getValue(family).removed) "x" else "1"
                lines += "${group.number.toString().padStart(3)} $mark ${variableBand(limits, value, group.number > settings.phase1 && hasSignal(chart, group.number))} ${real(value)}"
            }
        }
        lines += "chart CUSUM h ${real(interval)}"
        for (point in cusum) lines += "${point.number.toString().padStart(3)} ${cusumBand(point.upper, point.lower, interval, hasSignal("CUSUM", point.number, "UPPER"), hasSignal("CUSUM", point.number, "LOWER"))} ${real(point.upper)} ${real(point.lower)}"
        for ((chart, points, width) in listOf(Triple("EWMA", ewma, ewmaWidth), Triple("MA", movingAverage, maWidth))) {
            lines += limitsText("chart $chart", Limits(mu - width, mu, mu + width))
            for (point in points) lines += "${point.number.toString().padStart(3)} ${smoothBand(width, point.width, point.value, mu, hasSignal(chart, point.number))} ${real(point.value)} ${real(mu - point.width)} ${real(mu + point.width)}"
        }
        for ((index, result) in attributes.withIndex()) {
            lines += limitsText("chart ${listOf("P_STD", "NP_STD", "C_STD", "U_STD")[index]}", Limits(-3.0, 0.0, 3.0))
            for (point in result.points) lines += "${point.lot.number.toString().padStart(3)} ${standardBand(point.z, point.status == "ok")} ${real(point.z)}"
        }
        return lines
    }
}

fun main() {
    val analysis = Analysis(readSettings(), readMeasurements(), readLots())
    analysis.run()
    File("output").mkdirs()
    for ((name, lines) in listOf("limits.txt" to analysis.limitsLines(), "signals.csv" to analysis.signalLines(), "events.txt" to analysis.eventLines(), "subgroups.csv" to analysis.subgroupLines(), "attribute_charts.txt" to analysis.attributeLines(), "capability.txt" to analysis.capabilityLines(), "charts.txt" to analysis.chartLines())) File("output/$name").writeText(lines.joinToString("\n", postfix = "\n"))
}
