import java.io.File
import kotlin.math.abs

data class Argument(val name: String, val low: String = "", val high: String = "") {
    val kind get() = when (name) { "dst", "var" -> "name"; "src" -> "signal"; "metric" -> "metric"; "op" -> "operator"; else -> "integer" }
}
fun bounded(name: String, low: Long, high: Long) = Argument(name, low.toString(), high.toString())
data class Command(val arguments: List<Argument>, val repeated: List<Argument> = emptyList(), val repeatMin: Int = 0, val repeatMax: Int = 0) {
    fun accepts(count: Int): Boolean { val extra = count - arguments.size; return if (repeated.isEmpty()) extra == 0 else extra >= 0 && extra % repeated.size == 0 && extra / repeated.size in repeatMin..repeatMax }
    fun argumentAt(index: Int) = if (index < arguments.size) arguments[index] else repeated[(index - arguments.size) % repeated.size]
}
fun commandTable(): Map<String, Command> {
    val dst = Argument("dst")
    val src = Argument("src")
    val rate = bounded("rate", 1000, 48000)
    val count = bounded("count", 1, 20000)
    val numerator = bounded("num", -65536, 65536)
    val denominator = bounded("den", 1, 65536)
    val attack = bounded("attack", 1, 32768)
    val release = bounded("release", 1, 32768)
    val minHz = Argument("min_hz", "1", "rate / 2 - 1")
    val maxHz = Argument("max_hz", "min_hz + 1", "rate / 2")
    val start = Argument("start", "0", "L - 1")
    val testSignal = listOf(dst, rate, count, Argument("pos", "0", "count - 1"), bounded("amp", -32768, 32767))
    return mapOf(
        "SET" to Command(listOf(Argument("var"), bounded("value", -10000000, 10000000)), listOf(Argument("op"), bounded("operand", -10000000, 10000000)), 0, 1),
        "IMPULSE" to Command(testSignal), "STEP" to Command(testSignal), "NOISE" to Command(listOf(dst, rate, count, bounded("seed", 1, 2147483646))),
        "GAIN" to Command(listOf(dst, src, numerator, denominator)), "MIX" to Command(listOf(dst, denominator), listOf(src, bounded("weight", -65536, 65536)), 1, 8),
        "DELAY" to Command(listOf(dst, src, bounded("samples", 0, 20000))), "ECHO" to Command(listOf(dst, src, bounded("delay", 1, 20000), numerator, denominator, bounded("tail", 0, 20000))),
        "RESAMPLE" to Command(listOf(dst, src, bounded("new_rate", 1000, 48000))), "FADE" to Command(listOf(dst, src, Argument("in", "0", "L"), Argument("out", "0", "L"))),
        "TRIM" to Command(listOf(dst, src, start, Argument("count", "1", "L - start"))), "CONCAT" to Command(listOf(dst), listOf(src), 2, 8),
        "FIR" to Command(listOf(dst, src, bounded("divisor", 1, 1000000)), listOf(bounded("tap", -32768, 32767)), 1, 64),
        "BIQUAD" to Command(listOf(dst, src), listOf("b0", "b1", "b2", "a1", "a2").map { bounded(it, -65536, 65536) }, 1, 4),
        "MOVAVG" to Command(listOf(dst, src, bounded("width", 1, 1000))), "DCBLOCK" to Command(listOf(dst, src, bounded("num", 0, 65535), Argument("den", "num + 1", "65536"))),
        "NORMALIZE" to Command(listOf(dst, src, bounded("target", 1, 32767))), "GATE" to Command(listOf(dst, src, bounded("threshold", 1, 32768), bounded("hold", 0, 20000))),
        "ENVELOPE" to Command(listOf(dst, src, attack, release)), "COMPRESS" to Command(listOf(dst, src, bounded("threshold", 1, 32767), bounded("ratio_num", 1, 100), Argument("ratio_den", "1", "ratio_num"), attack, release)),
        "ANALYZE" to Command(listOf(src, minHz, maxHz)), "COMPARE" to Command(listOf(src, src)), "EXPECT" to Command(listOf(src, Argument("metric"), Argument("op"), bounded("value", -1000000000, 1000000000))),
        "SEGMENTS" to Command(listOf(src, bounded("threshold", 1, 32768), bounded("gap", 1, 20000), bounded("min_length", 1, 20000))),
        "ONSETS" to Command(listOf(src, attack, release, bounded("threshold", 1, 32767), bounded("min_gap", 1, 20000))),
        "PITCHTRACK" to Command(listOf(src, Argument("frame", "16", "L"), Argument("hop", "1", "frame"), minHz, maxHz, bounded("threshold", 0, 32767))),
        "EXCERPT" to Command(listOf(src, start, bounded("count", 1, 1000))), "PLOT" to Command(listOf(src, start, Argument("count", "1", "L - start"), Argument("columns", "8", "min(120, count)"), bounded("half", 2, 20), attack, release)),
        "METER" to Command(listOf(src, bounded("block", 1, 20000))), "HISTOGRAM" to Command(listOf(src, bounded("bins", 2, 64))), "TRACE" to Command(listOf(src)), "SAVE" to Command(listOf(src))
    )
}
class CommandError(message: String) : Exception(message)
data class ParsedValue(val token: String, val number: Long? = null, val signal: AudioSignal? = null)
data class Parsed(val values: List<ParsedValue>) {
    fun n(index: Int) = values[index].number!!
    fun i(index: Int) = n(index).toInt()
    fun s(index: Int) = values[index].signal!!
    fun t(index: Int) = values[index].token
    val sources get() = values.mapNotNull { it.signal }
}
fun resolveBound(bound: String, known: Map<String, Long>, source: AudioSignal?): Long = bound.toLongOrNull() ?: when (bound) {
    "count - 1" -> known.getValue("count") - 1L
    "min(120, count)" -> minOf(120L, known.getValue("count"))
    "min_hz + 1" -> known.getValue("min_hz") + 1L
    "num + 1" -> known.getValue("num") + 1L
    "L" -> source!!.samples.size.toLong()
    "L - 1" -> source!!.samples.size.toLong() - 1L
    "L - start" -> source!!.samples.size.toLong() - known.getValue("start")
    "rate / 2" -> source!!.rate / 2L
    "rate / 2 - 1" -> source!!.rate / 2L - 1L
    else -> known.getValue(bound)
}
fun milliseconds(index: Int, rate: Long) = index.toLong() * 1000L / rate
fun twoDecimals(value: Long) = "${value / 100L}.${(value % 100L).toString().padStart(2, '0')}"
fun frequency(rate: Long, lag: Int) = twoDecimals(rdiv(100L * rate, lag.toLong()))
fun waveformPlot(source: AudioSignal, start: Int, count: Int, columns: Int, half: Int, attack: Long, release: Long): List<String> {
    val window = source.samples.subList(start, start + count)
    val levels = envelope(source.samples, attack, release).subList(start, start + count)
    val rows = 2 * half + 1
    val scale = maxOf(1L, peak(window))
    fun row(value: Long) = rdiv((scale - value) * (rows - 1).toLong(), 2L * scale).toInt()
    val grid = List(rows) { CharArray(columns) { ' ' } }
    for (column in 0 until columns) {
        val first = column * count / columns
        val last = (column + 1) * count / columns
        val part = window.subList(first, last)
        val top = row(part.max())
        val bottom = row(part.min())
        val level = minOf(scale, levels.subList(first, last).max())
        val positive = row(level)
        val negative = row(-level)
        for (r in 0 until rows) grid[r][column] = when { r == positive || r == negative -> '*'; r in top..bottom -> '#'; r == half -> '-'; else -> ' ' }
    }
    val lines = mutableListOf("PLOT ${source.name} rate=${source.rate} start=$start count=$count columns=$columns rows=$rows scale=$scale attack=$attack release=$release")
    for (r in 0 until rows) { val label = when (r) { 0 -> scale.toString(); half -> "0"; rows - 1 -> (-scale).toString(); else -> "" }; lines += "${label.padStart(6)} |${grid[r].concatToString()}|" }
    lines += "       +" + (0 until columns).joinToString("") { if (it % 10 == 0) "+" else "-" } + "+"
    val timeline = StringBuilder("    ms")
    for (column in 0 until columns step 10) { while (timeline.length < 8 + column) timeline.append(' '); timeline.append(milliseconds(start + column * count / columns, source.rate)) }
    lines += timeline.toString()
    return lines
}
fun meterPlot(source: AudioSignal, block: Int): List<String> {
    val count = (source.samples.size + block - 1) / block
    val lines = mutableListOf("METER ${source.name} rate=${source.rate} samples=${source.samples.size} block=$block blocks=$count")
    for (index in 0 until count) {
        val part = source.samples.subList(index * block, minOf((index + 1) * block, source.samples.size))
        val p = peak(part)
        val q = rms(part)
        val np = rdiv(p * 40L, 32768L)
        val nq = rdiv(q * 40L, 32768L)
        val bar = (0 until 40).joinToString("") { if (it.toLong() < nq) "#" else if (it.toLong() < np) "-" else " " }
        lines += "${milliseconds(index * block, source.rate).toString().padStart(6)} |$bar| peak=$p rms=$q clipped=${countClipped(part)}"
    }
    return lines
}
fun histogramPlot(source: AudioSignal, bins: Int): List<String> {
    val counts = LongArray(bins)
    for (value in source.samples) counts[((value + 32768L) * bins.toLong() / 65536L).toInt()]++
    val top = counts.max()
    val lines = mutableListOf("HISTOGRAM ${source.name} rate=${source.rate} samples=${source.samples.size} bins=$bins max=$top")
    for (index in 0 until bins) { val low = (index.toLong() * 65536L + bins.toLong() - 1L) / bins.toLong() - 32768L; val high = ((index + 1).toLong() * 65536L + bins.toLong() - 1L) / bins.toLong() - 32769L; lines += "${low.toString().padStart(6)} ${high.toString().padStart(6)} ${counts[index].toString().padStart(5)} |${"#".repeat(rdiv(counts[index] * 50L, top).toInt())}" }
    return lines
}
class Pipeline(loaded: List<AudioSignal>) {
    val commands = commandTable()
    val signals = loaded.associateBy { it.name }.toMutableMap()
    val variables = mutableMapOf<String, Long>()
    val log = loaded.map { "load ${it.name} rate=${it.rate} samples=${it.samples.size} peak=${peak(it.samples)}" }.toMutableList()
    val analysis = mutableListOf("signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz")
    val excerpts = mutableListOf<String>()
    val waveforms = mutableListOf<String>()
    val saved = mutableListOf<String>()
    var steps = 0
    var errors = 0
    var passed = 0
    var failed = 0
    fun parse(name: String, command: Command, tokens: List<String>): Parsed {
        val known = mutableMapOf<String, Long>()
        val values = mutableListOf<ParsedValue>()
        var firstSource: AudioSignal? = null
        for ((index, token) in tokens.withIndex()) {
            val argument = command.argumentAt(index)
            when (argument.kind) {
                "name" -> { if (!Regex("[a-z][a-z0-9_]{0,15}").matches(token)) throw CommandError("bad name $token"); values += ParsedValue(token) }
                "signal" -> { val source = signals[token] ?: throw CommandError("unknown signal $token"); if (firstSource == null) firstSource = source; values += ParsedValue(token, signal = source) }
                "metric" -> { if (token !in listOf("samples", "peak", "rms", "sum", "zero_crossings", "clipped")) throw CommandError("unknown metric $token"); values += ParsedValue(token) }
                "operator" -> { val allowed = if (name == "SET") listOf("+", "-", "*", "/") else listOf("eq", "ne", "lt", "le", "gt", "ge"); if (token !in allowed) throw CommandError("unknown operator $token"); values += ParsedValue(token) }
                else -> {
                    val value = if (token.startsWith('$')) variables[token.drop(1)] ?: throw CommandError("undefined variable $token") else { if (token == "-0" || !Regex("-?(0|[1-9][0-9]{0,9})").matches(token)) throw CommandError("bad integer $token"); token.toLong() }
                    if (value < resolveBound(argument.low, known, firstSource) || value > resolveBound(argument.high, known, firstSource)) throw CommandError("${argument.name} out of range")
                    known[argument.name] = value
                    values += ParsedValue(token, number = value)
                }
            }
        }
        return Parsed(values)
    }
    fun setResult(arguments: Parsed): Long {
        if (arguments.values.size == 2) return arguments.n(1)
        val value = arguments.n(1)
        val operand = arguments.n(3)
        return when (arguments.t(2)) { "+" -> value + operand; "-" -> value - operand; "*" -> value * operand; else -> floorDivide(value, operand) }
    }
    fun check(name: String, arguments: Parsed) {
        if (name == "SET") {
            if (arguments.values.size == 4 && arguments.t(2) == "/" && arguments.n(3) == 0L) throw CommandError("division by zero")
            if (abs(setResult(arguments)) > 10000000L) throw CommandError("value out of range")
            return
        }
        val sources = arguments.sources
        if (sources.isEmpty()) return
        val source = sources[0]
        when (name) {
            "MIX", "CONCAT", "COMPARE" -> { if (sources.any { it.rate != source.rate }) throw CommandError("rate mismatch"); if (name == "CONCAT" && sources.sumOf { it.samples.size } > 20000) throw CommandError("result too long") }
            "DELAY" -> if (source.samples.size.toLong() + arguments.n(2) > 20000L) throw CommandError("result too long")
            "ECHO" -> { if (abs(arguments.n(3)) >= arguments.n(4)) throw CommandError("unstable feedback"); if (source.samples.size.toLong() + arguments.n(5) > 20000L) throw CommandError("result too long") }
            "RESAMPLE" -> if (resampledLength(source.samples.size, source.rate, arguments.n(2)) > 20000) throw CommandError("result too long")
            "ANALYZE", "PITCHTRACK" -> {
                val min = arguments.n(if (name == "ANALYZE") 1 else 3)
                val max = arguments.n(if (name == "ANALYZE") 2 else 4)
                val low = (source.rate + max - 1L) / max
                val high = source.rate / min
                if (low > high) throw CommandError("empty lag range")
                if (name == "ANALYZE" && high >= source.samples.size.toLong()) throw CommandError("signal too short")
                if (name == "PITCHTRACK" && high >= arguments.n(1)) throw CommandError("frame too short")
            }
        }
    }
    fun register(line: Int, name: String, arguments: Parsed, rate: Long, samples: List<Long>, extras: String = ""): List<String> {
        val destination = arguments.t(0)
        signals[destination] = AudioSignal(destination, rate, samples, "line $line $name", arguments.sources)
        return listOf("$destination rate=$rate samples=${samples.size} peak=${peak(samples)} sum=${samples.sum()}$extras")
    }
    fun generate(line: Int, name: String, arguments: Parsed): List<String> {
        if (name == "IMPULSE" || name == "STEP") return register(line, name, arguments, arguments.n(1), if (name == "IMPULSE") impulse(arguments.i(2), arguments.i(3), arguments.n(4)) else step(arguments.i(2), arguments.i(3), arguments.n(4)))
        if (name == "NOISE") return register(line, name, arguments, arguments.n(1), noise(arguments.i(2), arguments.n(3)))
        val source = arguments.sources[0]
        var rate = source.rate
        var extras = ""
        val samples = when (name) {
            "GAIN" -> gain(source.samples, arguments.n(2), arguments.n(3)).let { extras = " clipped=${it.clipped}"; it.samples }
            "MIX" -> mix(arguments.sources.map { it.samples }, arguments.values.indices.filter { it >= 3 && it % 2 == 1 }.map(arguments::n), arguments.n(1)).let { extras = " clipped=${it.clipped}"; it.samples }
            "DELAY" -> delay(source.samples, arguments.i(2))
            "ECHO" -> echo(source.samples, arguments.i(2), arguments.n(3), arguments.n(4), arguments.i(5)).let { extras = " clipped=${it.clipped}"; it.samples }
            "RESAMPLE" -> { rate = arguments.n(2); resample(source.samples, source.rate, rate) }
            "FADE" -> fade(source.samples, arguments.i(2), arguments.i(3))
            "TRIM" -> source.samples.subList(arguments.i(2), arguments.i(2) + arguments.i(3)).toList()
            "CONCAT" -> arguments.sources.flatMap { it.samples }
            "FIR" -> fir(source.samples, arguments.n(2), arguments.values.drop(3).map { it.number!! }).let { extras = " clipped=${it.clipped}"; it.samples }
            "BIQUAD" -> { val sections = arguments.values.drop(2).map { it.number!! }.chunked(5); biquad(source.samples, sections).let { extras = " sections=${sections.size} clipped=${it.clipped}"; it.samples } }
            "MOVAVG" -> movingAverage(source.samples, arguments.i(2))
            "DCBLOCK" -> dcBlock(source.samples, arguments.n(2), arguments.n(3)).let { extras = " clipped=${it.clipped}"; it.samples }
            "NORMALIZE" -> normalize(source.samples, arguments.n(2)).let { extras = " source_peak=${it.second}"; it.first }
            "GATE" -> gate(source.samples, arguments.n(2), arguments.i(3)).let { extras = " muted=${it.second}"; it.first }
            "ENVELOPE" -> envelope(source.samples, arguments.n(2), arguments.n(3))
            else -> compress(source.samples, arguments.n(2), arguments.n(3), arguments.n(4), arguments.n(5), arguments.n(6)).let { extras = " min_gain=${it.minGain} reduced=${it.reduced}"; it.samples }
        }
        return register(line, name, arguments, rate, samples, extras)
    }
    fun trace(source: AudioSignal, depth: Int): List<String> = listOf("${"  ".repeat(depth)}${source.name} <- ${source.origin}") + source.ingredients.flatMap { trace(it, depth + 1) }
    fun segments(source: AudioSignal, threshold: Long, gap: Int, minimum: Int): List<String> {
        val found = mutableListOf<Pair<Int, Int>>()
        for ((index, value) in source.samples.withIndex()) if (abs(value) >= threshold) { if (found.isNotEmpty() && index - found.last().second <= gap) found[found.lastIndex] = found.last().first to index else found += index to index }
        val lines = found.filter { it.second - it.first + 1 >= minimum }.mapIndexed { number, (first, last) -> val samples = source.samples.subList(first, last + 1); "  segment ${number + 1} start=$first end=$last start_ms=${milliseconds(first, source.rate)} end_ms=${milliseconds(last, source.rate)} peak=${peak(samples)} rms=${rms(samples)} crossings=${zeroCrossings(samples)}" }
        return listOf("${source.name} segments=${lines.size}") + lines
    }
    fun onsets(source: AudioSignal, attack: Long, release: Long, threshold: Long, minGap: Int): List<String> {
        val levels = envelope(source.samples, attack, release)
        val found = mutableListOf<Int>()
        for (index in levels.indices) if (levels[index] >= threshold && (index == 0 || levels[index - 1] < threshold) && (found.isEmpty() || index - found.last() >= minGap)) found += index
        val intervals = found.zipWithNext { first, second -> second - first }
        val tempo = if (found.size < 2) "none" else twoDecimals(rdiv(6000L * source.rate, intervals.sorted()[(found.size - 2) / 2].toLong()))
        return listOf("${source.name} onsets=${found.size} tempo=$tempo") + found.mapIndexed { number, index -> "  onset ${number + 1} sample=$index ms=${milliseconds(index, source.rate)} interval=${if (number == 0) "none" else intervals[number - 1].toString()}" }
    }
    fun pitchTrack(source: AudioSignal, frame: Int, hop: Int, minHz: Long, maxHz: Long, threshold: Long): List<String> {
        val low = ((source.rate + maxHz - 1L) / maxHz).toInt()
        val high = (source.rate / minHz).toInt()
        val count = (source.samples.size - frame) / hop + 1
        var voiced = 0
        val rows = (0 until count).map { index ->
            val start = index * hop
            val samples = source.samples.subList(start, start + frame)
            val level = rms(samples)
            val lag = if (level < threshold) null else pitchLag(samples, low, high)
            val band = CharArray(41) { ' ' }
            val detail = if (lag == null) "unvoiced rms=$level" else { voiced++; val position = if (high > low) rdiv((high - lag).toLong() * 40L, (high - low).toLong()).toInt() else 0; band[position] = 'o'; "lag=$lag hz=${frequency(source.rate, lag)} rms=$level" }
            "${milliseconds(start, source.rate).toString().padStart(6)} |${band.concatToString()}| $detail"
        }
        waveforms += "PITCHTRACK ${source.name} rate=${source.rate} frame=$frame hop=$hop lags=$low-$high threshold=$threshold frames=$count voiced=$voiced"
        waveforms += rows
        return listOf("${source.name} frames=$count voiced=$voiced")
    }
    fun execute(line: Int, name: String, tokens: List<String>): List<String> {
        val command = commands[name] ?: throw CommandError("unknown command $name")
        if (!command.accepts(tokens.size)) throw CommandError("wrong number of arguments")
        val arguments = parse(name, command, tokens)
        check(name, arguments)
        if (name == "SET") { val result = setResult(arguments); variables[arguments.t(0)] = result; return listOf("${arguments.t(0)}=$result") }
        if (name in listOf("IMPULSE", "STEP", "NOISE", "GAIN", "MIX", "DELAY", "ECHO", "RESAMPLE", "FADE", "TRIM", "CONCAT", "FIR", "BIQUAD", "MOVAVG", "DCBLOCK", "NORMALIZE", "GATE", "ENVELOPE", "COMPRESS")) return generate(line, name, arguments)
        val source = arguments.s(0)
        when (name) {
            "ANALYZE" -> {
                val low = ((source.rate + arguments.n(2) - 1L) / arguments.n(2)).toInt()
                val high = (source.rate / arguments.n(1)).toInt()
                val lag = pitchLag(source.samples, low, high)
                analysis += "${source.name},${peak(source.samples)},${rms(source.samples)},${zeroCrossings(source.samples)},${countClipped(source.samples)},${crestFraction(source.samples)},${lag?.toString() ?: "none"},${lag?.let { frequency(source.rate, it) } ?: "none"}"
                return listOf("${source.name} lags=$low-$high")
            }
            "COMPARE" -> {
                val other = arguments.s(1)
                val differences = List(maxOf(source.samples.size, other.samples.size)) { (source.samples.getOrNull(it) ?: 0L) - (other.samples.getOrNull(it) ?: 0L) }
                return listOf("${source.name} ${other.name} differing=${differences.count { it != 0L }} max_diff=${peak(differences)} first=${differences.indexOfFirst { it != 0L }.takeIf { it >= 0 }?.toString() ?: "none"} error_energy=${energy(differences)}")
            }
            "EXPECT" -> {
                val measured = when (arguments.t(1)) { "samples" -> source.samples.size.toLong(); "peak" -> peak(source.samples); "rms" -> rms(source.samples); "sum" -> source.samples.sum(); "zero_crossings" -> zeroCrossings(source.samples); else -> countClipped(source.samples) }
                val value = arguments.n(3)
                val satisfied = when (arguments.t(2)) { "eq" -> measured == value; "ne" -> measured != value; "lt" -> measured < value; "le" -> measured <= value; "gt" -> measured > value; else -> measured >= value }
                if (satisfied) passed++ else failed++
                return listOf("${source.name} ${arguments.t(1)}=$measured ${arguments.t(2)} $value ${if (satisfied) "pass" else "fail"}")
            }
            "SEGMENTS" -> return segments(source, arguments.n(1), arguments.i(2), arguments.i(3))
            "ONSETS" -> return onsets(source, arguments.n(1), arguments.n(2), arguments.n(3), arguments.i(4))
            "PITCHTRACK" -> return pitchTrack(source, arguments.i(1), arguments.i(2), arguments.n(3), arguments.n(4), arguments.n(5))
            "EXCERPT" -> {
                val start = arguments.i(1)
                val count = minOf(arguments.i(2), source.samples.size - start)
                excerpts += "EXCERPT ${source.name} rate=${source.rate} samples=${source.samples.size} start=$start count=$count"
                for (offset in 0 until count step 8) excerpts += (start + offset).toString().padStart(5) + ":" + source.samples.subList(start + offset, start + minOf(count, offset + 8)).joinToString("") { " ${it.toString().padStart(6)}" }
                return listOf("${source.name} start=$start count=$count")
            }
            "PLOT" -> { waveforms += waveformPlot(source, arguments.i(1), arguments.i(2), arguments.i(3), arguments.i(4), arguments.n(5), arguments.n(6)); return listOf("${source.name} start=${arguments.n(1)} count=${arguments.n(2)} columns=${arguments.n(3)} rows=${2 * arguments.n(4) + 1L}") }
            "METER" -> { waveforms += meterPlot(source, arguments.i(1)); return listOf("${source.name} block=${arguments.n(1)}") }
            "HISTOGRAM" -> { waveforms += histogramPlot(source, arguments.i(1)); return listOf("${source.name} bins=${arguments.n(1)}") }
            "TRACE" -> return listOf(source.name) + trace(source, 1)
            else -> { saved += formatSignal(source); return listOf("${source.name} samples=${source.samples.size}") }
        }
    }
    fun run() {
        for ((index, line) in File("input/pipeline.txt").readLines().withIndex()) {
            if (line.isEmpty() || line.startsWith('#')) continue
            val tokens = line.split(' ')
            try { val details = execute(index + 1, tokens[0], tokens.drop(1)); log += "line ${index + 1}: ${tokens[0]} ${details[0]}"; log += details.drop(1); steps++ }
            catch (error: CommandError) { log += "line ${index + 1}: error: ${error.message}"; errors++ }
        }
        for (name in signals.keys.sorted()) { val source = signals.getValue(name); log += "signal $name rate=${source.rate} samples=${source.samples.size} peak=${peak(source.samples)} rms=${rms(source.samples)}" }
        log += "summary steps=$steps errors=$errors signals=${signals.size} passed=$passed failed=$failed"
    }
    fun write() {
        File("output").mkdirs()
        for ((name, lines) in listOf("log.txt" to log, "analysis.csv" to analysis, "excerpts.txt" to excerpts, "waveforms.txt" to waveforms, "signals_out.txt" to saved)) File("output/$name").writeText(lines.joinToString("\n", postfix = if (lines.isEmpty()) "" else "\n"))
    }
}
fun main() { val pipeline = Pipeline(readSignals()); pipeline.run(); pipeline.write() }
