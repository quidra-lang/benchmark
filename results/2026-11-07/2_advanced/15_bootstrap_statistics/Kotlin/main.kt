import Report.real
import Report.pValue
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.sqrt

class Summary(val estimate: Double, val values: DoubleArray, lowRank: Int, highRank: Int) {
    val ordered = values.sortedArray()
    private val spread = Resampling.meanAndSe(values)
    val average = spread[0]
    val se = spread[1]
    val bias = average - estimate
    val low = ordered[lowRank - 1]
    val high = ordered[highRank - 1]
    val basicLow = 2 * estimate - high
    val basicHigh = 2 * estimate - low
    fun csv(name: String, statistic: String): String =
        (listOf(name, statistic) + listOf(estimate, se, bias, low, high, basicLow, basicHigh).map { real(it) }).joinToString(",")
    fun interval(): String = "se ${real(se)} bias ${real(bias)} percentile ${real(low)} ${real(high)} basic ${real(basicLow)} ${real(basicHigh)}"
}
class GroupBootstrap(val group: Group, val indices: Array<IntArray>, low: Int, high: Int) {
    val samples = indices.map { Resampling.sample(group.values, it) }
    val summaries = Array(4) { statistic ->
        Summary(Resampling.groupStatistic(statistic, group.values),
            DoubleArray(samples.size) { Resampling.groupStatistic(statistic, samples[it]) }, low, high)
    }
}
class PairBootstrap(val first: GroupBootstrap, val second: GroupBootstrap, low: Int, high: Int) {
    val name = "${first.group.name}-${second.group.name}"
    val summaries = Array(4) { statistic ->
        Summary(Resampling.pairStatistic(statistic, first.group.values, second.group.values),
            DoubleArray(first.samples.size) { Resampling.pairStatistic(statistic, first.samples[it], second.samples[it]) }, low, high)
    }
}
fun jackknifeSpread(values: DoubleArray): DoubleArray {
    val average = Resampling.sequentialSum(values) / values.size
    var squares = 0.0
    for (value in values) { val difference = value - average; squares += difference * difference }
    return doubleArrayOf(average, (values.size - 1) * squares / values.size)
}
class Jackknife(estimate: Double, val values: DoubleArray) {
    private val spread = jackknifeSpread(values)
    val average = spread[0]
    val variance = spread[1]
    val bias = (values.size - 1) * (average - estimate)
    val se = sqrt(variance)
}
class Tally(val observed: Long) {
    var extreme = 0
        private set
    var greater = 0
        private set
    fun count(value: Long) {
        if (abs(value) >= abs(observed)) extreme++
        if (value >= observed) greater++
    }
    fun text(offset: Int, denominator: Int): String =
        "extreme $extreme greater $greater p_two ${pValue(extreme + offset, denominator)} p_greater ${pValue(greater + offset, denominator)}"
}
class DisplayRange(values: LongArray) {
    private val low = values.min()
    private val delta = 100 * (values.max() - low)
    fun position(value: Long): Int = ((120 * (value - 100 * low) + delta) / (2 * delta)).toInt()
}
data class TestResult(val lines: List<String>, val extremes: IntArray)
data class Delta(val numerator: Long, val denominator: Long) : Comparable<Delta> {
    override fun compareTo(other: Delta): Int = (numerator * other.denominator).compareTo(other.numerator * denominator)
}

class Study(private val data: Dataset) {
    private val settings = data.settings
    private val generator = Minstd(settings.seed)
    private val lowRank = (settings.bootstrap + 1) * (100 - settings.confidence) / 200
    private val highRank = settings.bootstrap + 1 - lowRank
    private val zLow = Resampling.phiInverse((100 - settings.confidence) / 200.0)

    private fun outliers(values: LongArray): List<Int> {
        val first = Resampling.quantileNumerator(values, 25)
        val third = Resampling.quantileNumerator(values, 75)
        return values.indices.filter { 200 * values[it] < 5 * first - 3 * third || 200 * values[it] > 5 * third - 3 * first }
    }
    private fun seriesLines(kind: String, name: String, values: LongArray, display: DisplayRange, stems: Boolean): List<String> {
        val ordered = values.sortedArray()
        val count = values.size
        val mean = Resampling.mean(values)
        val sd = Resampling.sd(values)
        val moments = Resampling.centralMoments(values)
        val clipped = Resampling.winsorized(values)
        val first = Resampling.quantileNumerator(values, 25)
        val third = Resampling.quantileNumerator(values, 75)
        val outliers = outliers(values)
        val inside = values.filterIndexed { index, _ -> index !in outliers }
        val low = inside.min()
        val high = inside.max()
        val band = CharArray(61) { '.' }
        for (i in display.position(100 * low)..display.position(100 * high)) band[i] = '-'
        for (i in display.position(first)..display.position(third)) band[i] = '='
        band[display.position(Resampling.quantileNumerator(values, 50))] = '|'
        for (index in outliers) band[display.position(100 * values[index])] = 'o'
        val lines = mutableListOf("$kind $name", "n $count", "mean ${real(mean)}", "median ${real(Resampling.median(values))}",
            "trimmed_mean ${real(Resampling.trimmedMean(values))} trim ${count / 10}",
            "winsorized_mean ${real(Resampling.mean(clipped))} winsorized_sd ${real(Resampling.sd(clipped))}",
            "sd ${real(sd)}", "se_mean ${real(sd / sqrt(count.toDouble()))}", "cv ${real(sd / mean)}",
            "skewness ${real(moments[1] / (moments[0] * sqrt(moments[0])))}", "kurtosis ${real(moments[2] / (moments[0] * moments[0]) - 3)}",
            "mad ${real(Resampling.mad(values))}", "min ${real(ordered.first() / 100.0)}", "q1 ${real(first / 10000.0)}",
            "q3 ${real(third / 10000.0)}", "iqr ${real((third - first) / 10000.0)}", "max ${real(ordered.last() / 100.0)}")
        val percentiles = listOf(5, 10, 90, 95).joinToString(" ") { percent ->
            "p${percent.toString().padStart(2, '0')} ${real(Resampling.quantileNumerator(values, percent) / 10000.0)}"
        }
        lines += "percentiles $percentiles"
        lines += "whiskers ${real(low / 100.0)} ${real(high / 100.0)}"
        lines += "outliers ${Report.numberList(outliers.map { it + 1 })}"
        lines += "box ${band.concatToString()}"
        if (stems)
            for (stem in ordered.first() / 100..ordered.last() / 100) {
                val leaves = ordered.filter { it / 100 == stem }.joinToString("") { (it % 100 / 10).toString() }
                lines += "stem $stem" + if (leaves.isEmpty()) "" else " $leaves"
            }
        return lines
    }
    private fun descriptiveLines(): List<String> {
        val everything = data.groups.flatMap { it.values.toList() }.toLongArray()
        val lines = mutableListOf("groups ${data.groups.size} observations ${everything.size}")
        var display = DisplayRange(everything)
        for (group in data.groups) lines += seriesLines("group", group.name, group.values, display, true)
        val paired = data.paired
        lines += "paired subjects ${paired.differences.size}"
        display = DisplayRange(paired.before + paired.after)
        lines += seriesLines("series", "before", paired.before, display, false)
        lines += seriesLines("series", "after", paired.after, display, false)
        lines += seriesLines("series", "diff", paired.differences, DisplayRange(paired.differences), false)
        return lines
    }
    private fun pairedBootstrap(): Array<Summary> {
        val paired = data.paired
        val means = DoubleArray(settings.bootstrap)
        val correlations = DoubleArray(settings.bootstrap)
        val indices = Resampling.ordinaryIndices(generator, paired.before.size, settings.bootstrap)
        for (i in indices.indices) {
            means[i] = Resampling.mean(Resampling.sample(paired.differences, indices[i]))
            correlations[i] = Resampling.correlation(Resampling.sample(paired.before, indices[i]), Resampling.sample(paired.after, indices[i]))
        }
        return arrayOf(Summary(Resampling.mean(paired.differences), means, lowRank, highRank),
            Summary(Resampling.correlation(paired.before, paired.after), correlations, lowRank, highRank))
    }
    private fun bootstrapLines(ordinary: List<GroupBootstrap>, balanced: List<GroupBootstrap>, pairs: List<PairBootstrap>): List<String> = buildList {
        add("group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi")
        for (i in ordinary.indices) {
            for (statistic in 0..3) add(ordinary[i].summaries[statistic].csv(ordinary[i].group.name, GROUP_STATISTICS[statistic]))
            for (statistic in 0..3) add(balanced[i].summaries[statistic].csv(ordinary[i].group.name, "balanced_" + GROUP_STATISTICS[statistic]))
        }
        for (pair in pairs) for (statistic in 0..3) add(pair.summaries[statistic].csv(pair.name, PAIR_STATISTICS[statistic]))
    }
    private fun histogramLines(name: String, statistic: String, summary: Summary): List<String> {
        val bins = settings.bins
        val low = summary.ordered.first()
        val high = summary.ordered.last()
        val counts = IntArray(bins)
        for (value in summary.values) counts[Report.binNumber(value, low, high, bins) - 1]++
        val top = counts.max()
        val marks = List(bins) { mutableListOf<String>() }
        marks[Report.binNumber(summary.low, low, high, bins) - 1] += "L"
        var estimateBin = "none"
        if (summary.estimate >= low && summary.estimate <= high) {
            val bin = Report.binNumber(summary.estimate, low, high, bins)
            estimateBin = bin.toString(); marks[bin - 1] += "E"
        }
        marks[Report.binNumber(summary.high, low, high, bins) - 1] += "H"
        val convergence = (1..4).joinToString(" ") { quarter ->
            val size = quarter * settings.bootstrap / 4
            "$size:${real(Resampling.meanAndSe(summary.values.copyOf(size))[1])}"
        }
        val lines = mutableListOf("histogram $name $statistic min ${real(low)} max ${real(high)} width ${real((high - low) / bins)} top $top estimate_bin $estimateBin",
            "convergence $convergence")
        for (i in 0 until bins) {
            var line = "bin ${i + 1} ${real(low + (high - low) * i / bins)} ${counts[i]}"
            if (counts[i] > 0) line += " ${Report.bar(counts[i], top)}"
            if (marks[i].isNotEmpty()) line += " " + marks[i].joinToString(" ")
            lines += line
        }
        return lines
    }
    private fun bcaAlpha(z0: Double, acceleration: Double, z: Double): Double =
        Resampling.phi(z0 + (z0 + z) / (1 - acceleration * (z0 + z)))
    private fun bcaLine(statistic: String, summary: Summary, jackknife: Jackknife): String {
        val below = summary.values.count { it < summary.estimate }
        val z0 = Resampling.phiInverse(below.toDouble() / settings.bootstrap)
        var squares = 0.0
        var cubes = 0.0
        for (value in jackknife.values) {
            val difference = jackknife.average - value
            squares += difference * difference; cubes += difference * difference * difference
        }
        val acceleration = cubes / (6 * squares * sqrt(squares))
        val lower = floor((settings.bootstrap + 1) * bcaAlpha(z0, acceleration, zLow)).toInt().coerceIn(1, settings.bootstrap)
        val upper = (settings.bootstrap + 1 - floor((settings.bootstrap + 1) * (1 - bcaAlpha(z0, acceleration, -zLow))).toInt()).coerceIn(1, settings.bootstrap)
        return "bca $statistic below $below z0 ${real(z0)} acceleration ${real(acceleration)} ranks $lower $upper interval ${real(summary.ordered[lower - 1])} ${real(summary.ordered[upper - 1])}"
    }
    private fun groupJackknife(bootstrap: GroupBootstrap): List<String> {
        val values = bootstrap.group.values
        val count = values.size
        val jackknives = Array(4) { statistic -> Jackknife(bootstrap.summaries[statistic].estimate,
            DoubleArray(count) { Resampling.groupStatistic(statistic, Resampling.without(values, it)) }) }
        val lines = mutableListOf("group ${bootstrap.group.name} n $count")
        for (statistic in 0..3) {
            val jackknife = jackknives[statistic]
            lines += "jackknife ${GROUP_STATISTICS[statistic]} estimate ${real(bootstrap.summaries[statistic].estimate)} average ${real(jackknife.average)} bias ${real(jackknife.bias)} se ${real(jackknife.se)}"
        }
        for (statistic in 0..3) lines += bcaLine(GROUP_STATISTICS[statistic], bootstrap.summaries[statistic], jackknives[statistic])
        val omitted = List(count) { mutableListOf<Int>() }
        for (replicate in bootstrap.indices.indices) {
            val chosen = BooleanArray(count)
            for (index in bootstrap.indices[replicate]) chosen[index] = true
            for (i in values.indices) if (!chosen[i]) omitted[i] += replicate
        }
        val errors = Array(4) { DoubleArray(count) }
        for (statistic in 0..3) {
            val summary = bootstrap.summaries[statistic]
            for (i in values.indices) errors[statistic][i] = Resampling.meanAndSe(omitted[i].map { summary.values[it] }.toDoubleArray())[1]
            val spread = jackknifeSpread(errors[statistic])
            lines += "after_bootstrap ${GROUP_STATISTICS[statistic]} se ${real(summary.se)} average ${real(spread[0])} se_of_se ${real(sqrt(spread[1]))}"
        }
        lines += "without min ${omitted.minOf { it.size }} max ${omitted.maxOf { it.size }}"
        val total = Resampling.sum(values)
        val ranking = values.indices.sortedWith(compareByDescending<Int> { abs(count * values[it] - total) }.thenBy { it }).take(5)
        for ((rank, index) in ranking.withIndex()) {
            val size = omitted[index].size
            val influence = (count - 1) * (jackknives[0].average - jackknives[0].values[index])
            val summary = bootstrap.summaries[0]
            val shifted = omitted[index].map { summary.values[it] - summary.estimate }.sorted()
            lines += "influence ${rank + 1} obs ${index + 1} value ${real(values[index] / 100.0)} l ${real(influence)} without $size se ${real(errors[0][index])} q05 ${real(shifted[(5 * size + 99) / 100 - 1])} q50 ${real(shifted[(50 * size + 99) / 100 - 1])} q95 ${real(shifted[(95 * size + 99) / 100 - 1])}"
        }
        return lines
    }
    private fun pairJackknife(pair: PairBootstrap): List<String> = buildList {
        val x = pair.first.group.values
        val y = pair.second.group.values
        for (statistic in 0..3) {
            val first = DoubleArray(x.size) { Resampling.pairStatistic(statistic, Resampling.without(x, it), y) }
            val second = DoubleArray(y.size) { Resampling.pairStatistic(statistic, x, Resampling.without(y, it)) }
            val a = Jackknife(pair.summaries[statistic].estimate, first)
            val b = Jackknife(pair.summaries[statistic].estimate, second)
            var bias = 0.0; bias += a.bias; bias += b.bias
            var variance = 0.0; variance += a.variance; variance += b.variance
            add("pair ${pair.name} ${PAIR_STATISTICS[statistic]} estimate ${real(pair.summaries[statistic].estimate)} bias ${real(bias)} se ${real(sqrt(variance))}")
        }
    }
    private fun deviationTotal(values: LongArray, center: Long): Long {
        var total = 0L
        for (value in values) total += abs(2 * value - center)
        return total
    }
    private fun splitStatistics(values: LongArray, ranks: LongArray, order: IntArray, size: Int): LongArray {
        val x = Resampling.sample(values, order.copyOfRange(0, size))
        val y = Resampling.sample(values, order.copyOfRange(size, order.size))
        val firstCenter = Resampling.doubledMedian(x)
        val secondCenter = Resampling.doubledMedian(y)
        var rankTotal = 0L
        for (i in 0 until size) rankTotal += ranks[order[i]]
        return longArrayOf(Tests.contrast(Resampling.sum(x), x.size, Resampling.sum(y), y.size), firstCenter - secondCenter,
            rankTotal - size.toLong() * (order.size + 1), Tests.contrast(deviationTotal(x, firstCenter), x.size, deviationTotal(y, secondCenter), y.size))
    }
    private fun permutationLines(x: LongArray, y: LongArray): TestResult {
        val combined = x + y
        val ranks = Tests.doubledRanks(combined)
        val positions = IntArray(combined.size) { it }
        val observed = splitStatistics(combined, ranks, positions, x.size)
        val tallies = observed.map { Tally(it) }
        repeat(settings.permutations) {
            val order = positions.copyOf(); generator.shuffle(order)
            val trial = splitStatistics(combined, ranks, order, x.size)
            for (i in 0..3) tallies[i].count(trial[i])
        }
        val rankTotal = Resampling.sum(ranks.copyOf(x.size))
        val denominator = settings.permutations + 1
        val lines = listOf("permutation n ${x.size} ${y.size} perms ${settings.permutations}",
            "mean diff ${real(Resampling.meanDifference(x, y))} ${tallies[0].text(1, denominator)}",
            "median diff ${real(observed[1] / 200.0)} ${tallies[1].text(1, denominator)}",
            "ranksum w ${real(rankTotal / 2.0)} u ${real((rankTotal - x.size.toLong() * (x.size + 1)) / 2.0)} ${tallies[2].text(1, denominator)}",
            "absdev diff ${real(observed[3].toDouble() / (200L * x.size * y.size))} ${tallies[3].text(1, denominator)}")
        return TestResult(lines, tallies.map { it.extreme }.toIntArray())
    }
    private fun powerLine(x: LongArray, y: LongArray): String {
        var rejections = 0
        repeat(settings.powerSims) {
            val first = Resampling.sample(x, Resampling.resampleIndices(generator, x.size))
            val second = Resampling.sample(y, Resampling.resampleIndices(generator, y.size))
            val combined = first + second
            val total = Resampling.sum(combined)
            val observed = abs(Tests.contrast(Resampling.sum(first), x.size, Resampling.sum(second), y.size))
            var count = 0
            repeat(settings.powerPerms) {
                val shuffled = combined.copyOf(); generator.shuffle(shuffled)
                val head = Resampling.sum(shuffled.copyOf(x.size))
                if (abs(Tests.contrast(head, x.size, total - head, y.size)) >= observed) count++
            }
            if (100 * (count + 1) <= (100 - settings.confidence) * (settings.powerPerms + 1)) rejections++
        }
        val power = rejections.toDouble() / settings.powerSims
        return "power sims ${settings.powerSims} perms ${settings.powerPerms} rejections $rejections power ${real(power)} se ${real(sqrt(power * (1 - power) / settings.powerSims))}"
    }
    private fun exactLines(x: LongArray, y: LongArray): List<String> {
        val size = settings.pilot
        val first = x.copyOf(size)
        val second = y.copyOf(size)
        val combined = first + second
        val ranks = Tests.doubledRanks(combined)
        val total = Resampling.sum(combined)
        val choices = Tests.positionChoices(2 * size, size)
        val meanValues = LongArray(choices.size)
        val rankValues = LongArray(choices.size)
        for ((index, choice) in choices.withIndex()) {
            var chosen = 0L
            var rankSum = 0L
            for (position in choice) { chosen += combined[position]; rankSum += ranks[position] }
            meanValues[index] = Tests.contrast(chosen, size, total - chosen, size)
            rankValues[index] = rankSum - size.toLong() * (2 * size + 1)
        }
        val mean = Tally(meanValues[0])
        val rank = Tally(rankValues[0])
        for (i in choices.indices) { mean.count(meanValues[i]); rank.count(rankValues[i]) }
        val rankTotal = Resampling.sum(ranks.copyOf(size))
        var cumulative = 0
        var attained = 0
        var critical: Long? = null
        for ((value, count) in Tests.valueCounts(LongArray(meanValues.size) { abs(meanValues[it]) }).entries.reversed()) {
            cumulative += count
            if (100 * cumulative > (100 - settings.confidence) * choices.size) break
            critical = value; attained = cumulative
        }
        val criticalLine = if (critical == null) "critical diff none attained none" else
            "critical diff ${real(critical.toDouble() / (100L * size * size))} attained ${pValue(attained, choices.size)}"
        return listOf("exact size $size splits ${choices.size}", "mean diff ${real(Resampling.meanDifference(first, second))} ${mean.text(0, choices.size)}",
            "ranksum w ${real(rankTotal / 2.0)} u ${real((rankTotal - size.toLong() * (size + 1)) / 2.0)} ${rank.text(0, choices.size)}", criticalLine)
    }
    private fun studentizedLines(pair: PairBootstrap): List<String> {
        val x = pair.first.group.values
        val y = pair.second.group.values
        val k = x.size
        val m = y.size
        val estimate = Resampling.meanDifference(x, y)
        val firstSd = Resampling.sd(x)
        val secondSd = Resampling.sd(y)
        val firstVariance = firstSd * firstSd / k
        val secondVariance = secondSd * secondSd / m
        val se0 = sqrt(firstVariance + secondVariance)
        val t = estimate / se0
        val statistics = DoubleArray(settings.bootstrap)
        var extreme = 0
        for (i in statistics.indices) {
            val first = pair.first.summaries[3].values[i]
            val second = pair.second.summaries[3].values[i]
            statistics[i] = (pair.summaries[0].values[i] - estimate) / sqrt(first * first / k + second * second / m)
            if (abs(statistics[i]) >= abs(t)) extreme++
        }
        statistics.sort()
        val lower = estimate - statistics[highRank - 1] * se0
        val upper = estimate - statistics[lowRank - 1] * se0
        val degrees = (firstVariance + secondVariance) * (firstVariance + secondVariance) /
            (firstVariance * firstVariance / (k - 1) + secondVariance * secondVariance / (m - 1))
        var greater = 0L
        var equal = 0L
        for (a in x) for (b in y) { if (a > b) greater++; if (a == b) equal++ }
        val d = Resampling.cohenD(x, y)
        val hedges = d * (1 - 3.0 / (4 * (k + m - 2) - 1))
        val cles = (2 * greater + equal).toDouble() / (2L * k * m)
        return listOf("bootstrap_t t ${real(t)} df ${real(degrees)} extreme $extreme p ${pValue(extreme + 1, settings.bootstrap + 1)} interval ${real(lower)} ${real(upper)}",
            "effect pooled_sd ${real(Resampling.pooledSd(x, y))} cohen_d ${real(d)} hedges_g ${real(hedges)} cles ${real(cles)}")
    }
    private fun holmLines(extremes: List<IntArray>): List<String> = buildList {
        val count = data.pairs.size
        val denominator = settings.permutations + 1
        for (statistic in 0..3) {
            val order = data.pairs.indices.sortedWith(compareBy<Int> { extremes[it][statistic] }.thenBy { it })
            var adjusted = 0
            for ((index, number) in order.withIndex()) {
                val extreme = extremes[number][statistic]
                adjusted = maxOf(adjusted, minOf(denominator, (count - index) * (extreme + 1)))
                val pair = data.pairs[number]
                val verdict = if (100 * adjusted <= (100 - settings.confidence) * denominator) "reject" else "retain"
                add("holm ${TEST_STATISTICS[statistic]} rank ${index + 1} ${pair.first.name} ${pair.second.name} p ${pValue(extreme + 1, denominator)} adjusted ${pValue(adjusted, denominator)} $verdict")
            }
        }
    }
    private fun tanh(value: Double): Double { val growth = exp(2 * value); return (growth - 1) / (growth + 1) }
    private fun pairedLines(summaries: Array<Summary>): List<String> {
        val paired = data.paired
        val differences = paired.differences
        val count = differences.size
        val positive = differences.count { it > 0 }
        val negative = differences.count { it < 0 }
        val average = Resampling.mean(differences)
        val sd = Resampling.sd(differences)
        val correlation = Resampling.correlation(paired.before, paired.after)
        val z = 0.5 * ln((1 + correlation) / (1 - correlation))
        val halfWidth = -zLow / sqrt((count - 3).toDouble())
        return listOf("paired subjects $count positive $positive negative $negative zero ${count - positive - negative}",
            "paired before ${real(Resampling.mean(paired.before))} after ${real(Resampling.mean(paired.after))} diff ${real(average)} sd_diff ${real(sd)} t ${real(average / (sd / sqrt(count.toDouble())))} dz ${real(average / sd)}",
            "paired_bootstrap ${summaries[0].interval()}", "correlation r ${real(correlation)} ${summaries[1].interval()} fisher ${real(tanh(z - halfWidth))} ${real(tanh(z + halfWidth))}")
    }
    private fun signFlipLines(): List<String> {
        val differences = data.paired.differences
        val magnitudes = differences.filter { it != 0L }.map { abs(it) }.toLongArray()
        val ranks = Tests.doubledRanks(magnitudes)
        val rankOf = magnitudes.indices.associate { magnitudes[it] to ranks[it] }
        val signed = LongArray(differences.size) { i ->
            val value = differences[i]
            if (value == 0L) 0L else (if (value > 0) 1 else -1) * rankOf.getValue(abs(value))
        }
        val mean = Tally(Resampling.sum(differences))
        val rank = Tally(Resampling.sum(signed))
        repeat(settings.permutations) {
            var sum = 0L
            var rankSum = 0L
            for (i in differences.indices) {
                val sign = if (generator.draw() % 2 == 1L) -1 else 1
                sum += sign * differences[i]; rankSum += sign * signed[i]
            }
            mean.count(sum); rank.count(rankSum)
        }
        val positive = signed.filter { it > 0 }.sum()
        return listOf("signflip flips ${settings.permutations}", "mean diff ${real(Resampling.mean(differences))} ${mean.text(1, settings.permutations + 1)}",
            "signedrank w_plus ${real(positive / 2.0)} ${rank.text(1, settings.permutations + 1)}")
    }
    private fun deltas(samples: List<LongArray>, pairs: List<Pair<Int, Int>>): List<Delta> = pairs.map { (i, j) ->
        val x = samples[i]
        val y = samples[j]
        Delta(abs(Tests.contrast(Resampling.sum(x), x.size, Resampling.sum(y), y.size)), x.size.toLong() * y.size)
    }
    private fun welchLine(samples: List<LongArray>): String {
        val means = samples.map { Resampling.mean(it) }
        val weights = DoubleArray(samples.size) { val sd = Resampling.sd(samples[it]); samples[it].size / (sd * sd) }
        val total = Resampling.sequentialSum(weights)
        var center = 0.0
        for (i in weights.indices) center += weights[i] * means[i]
        center /= total
        var spread = 0.0
        for (i in weights.indices) { val difference = means[i] - center; spread += weights[i] * (difference * difference) }
        spread /= samples.size - 1
        var lambda = 0.0
        for (i in weights.indices) { val share = 1 - weights[i] / total; lambda += share * share / (samples[i].size - 1) }
        val groups = samples.size
        val f = spread / (1 + 2 * (groups - 2) * lambda / (groups * groups - 1))
        val degrees = (groups * groups - 1) / (3 * lambda)
        return "welch f ${real(f)} df ${groups - 1} ${real(degrees)}"
    }
    private fun anovaLines(ordinary: List<GroupBootstrap>): List<String> {
        val samples = data.groups.map { it.values }
        val sizes = samples.map { it.size }.toIntArray()
        val groups = samples.size
        val total = sizes.sum()
        val squares = Tests.sumsOfSquares(samples)
        val between = squares[0]
        val within = squares[1]
        val f = Tests.fStatistic(between, within, groups, total)
        val eta = between / (between + within)
        val msw = within / (total - groups)
        val omega = (between - (groups - 1) * msw) / (between + within + msw)
        val etaValues = DoubleArray(settings.bootstrap) { index ->
            val spread = Tests.sumsOfSquares(ordinary.map { it.samples[index] })
            spread[0] / (spread[0] + spread[1])
        }
        val etaSummary = Summary(eta, etaValues, lowRank, highRank)
        val combined = samples.flatMap { it.toList() }.toLongArray()
        val ranks = Tests.doubledRanks(combined)
        val rankSums = Tests.splitList(ranks, sizes).map { Resampling.sum(it) }.toLongArray()
        var tieTotal = 0L
        var tieGroups = 0
        for (count in Tests.valueCounts(combined).values)
            if (count >= 2) { tieGroups++; tieTotal += count.toLong() * count * count - count }
        val correction = 1 - tieTotal.toDouble() / (total.toLong() * total * total - total)
        val h = Tests.hStatistic(rankSums, sizes, correction)
        val lines = mutableListOf("anova groups $groups observations $total ssb ${real(between)} ssw ${real(within)} df ${groups - 1} ${total - groups} f ${real(f)} eta_squared ${real(eta)} omega_squared ${real(omega)}",
            "eta_bootstrap ${etaSummary.interval()}", welchLine(samples), "kruskal h ${real(h)} tie_groups $tieGroups")
        val pairs = buildList { for (i in 0 until groups) for (j in i + 1 until groups) add(i to j) }
        val observed = deltas(samples, pairs)
        var fExtreme = 0
        var hExtreme = 0
        val extremes = IntArray(pairs.size)
        val maxima = IntArray(pairs.size)
        val positions = IntArray(total) { it }
        repeat(settings.permutations) {
            val order = positions.copyOf(); generator.shuffle(order)
            val parts = Tests.splitList(order, sizes)
            val trial = parts.map { Resampling.sample(combined, it) }
            val trialRanks = LongArray(groups)
            for (i in 0 until groups) for (index in parts[i]) trialRanks[i] += ranks[index]
            val spread = Tests.sumsOfSquares(trial)
            if (Tests.fStatistic(spread[0], spread[1], groups, total) >= f - 0.000000001 * f) fExtreme++
            if (Tests.hStatistic(trialRanks, sizes, correction) >= h - 0.000000001 * h) hExtreme++
            val values = deltas(trial, pairs)
            val largest = values.max()
            for (i in pairs.indices) {
                if (values[i] >= observed[i]) extremes[i]++
                if (largest >= observed[i]) maxima[i]++
            }
        }
        val denominator = settings.permutations + 1
        lines += "anova_permutation perms ${settings.permutations} f_extreme $fExtreme f_p ${pValue(fExtreme + 1, denominator)} h_extreme $hExtreme h_p ${pValue(hExtreme + 1, denominator)}"
        for ((index, pair) in pairs.withIndex()) {
            val first = data.groups[pair.first]
            val second = data.groups[pair.second]
            lines += "pairwise ${first.name} ${second.name} diff ${real(Resampling.meanDifference(first.values, second.values))} extreme ${extremes[index]} p ${pValue(extremes[index] + 1, denominator)} maxt ${maxima[index]} adjusted ${pValue(maxima[index] + 1, denominator)}"
        }
        return lines
    }
    fun run(): Map<String, List<String>> {
        val ordinary = data.groups.map { GroupBootstrap(it, Resampling.ordinaryIndices(generator, it.values.size, settings.bootstrap), lowRank, highRank) }
        val balanced = data.groups.map { GroupBootstrap(it, Resampling.balancedIndices(generator, it.values.size, settings.bootstrap), lowRank, highRank) }
        val paired = pairedBootstrap()
        val pairs = data.pairs.map { PairBootstrap(ordinary[it.first.number - 1], ordinary[it.second.number - 1], lowRank, highRank) }
        val tests = mutableListOf<String>()
        val extremes = mutableListOf<IntArray>()
        for (pair in pairs) {
            val x = pair.first.group.values
            val y = pair.second.group.values
            tests += "compare ${pair.first.group.name} ${pair.second.group.name}"
            val result = permutationLines(x, y)
            tests += result.lines; extremes += result.extremes
            tests += powerLine(x, y); tests += exactLines(x, y); tests += studentizedLines(pair)
        }
        tests += holmLines(extremes); tests += pairedLines(paired); tests += signFlipLines(); tests += anovaLines(ordinary)
        val jackknife = mutableListOf<String>()
        val histograms = mutableListOf<String>()
        for (bootstrap in ordinary) {
            jackknife += groupJackknife(bootstrap)
            for (statistic in 0..3) histograms += histogramLines(bootstrap.group.name, GROUP_STATISTICS[statistic], bootstrap.summaries[statistic])
        }
        for (pair in pairs) {
            jackknife += pairJackknife(pair)
            for (statistic in 0..3) histograms += histogramLines(pair.name, PAIR_STATISTICS[statistic], pair.summaries[statistic])
        }
        return mapOf("descriptives.txt" to descriptiveLines(), "bootstrap.csv" to bootstrapLines(ordinary, balanced, pairs),
            "jackknife.txt" to jackknife, "tests.txt" to tests, "histograms.txt" to histograms)
    }
    companion object {
        private val GROUP_STATISTICS = listOf("mean", "median", "trimmed_mean", "sd")
        private val PAIR_STATISTICS = listOf("mean_diff", "median_ratio", "hodges_lehmann", "cohen_d")
        private val TEST_STATISTICS = listOf("mean", "median", "ranksum", "absdev")
    }
}

fun main() {
    Report.writeFiles(Study(Dataset.load("input")).run())
}
