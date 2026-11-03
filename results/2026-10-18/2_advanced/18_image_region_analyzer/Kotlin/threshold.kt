data class Split(val below: Int, val sumBelow: Long, val above: Int, val sumAbove: Long)
data class Candidate(val cutoff: Int, val split: Split, val numerator: Long, val denominator: Long) {
    constructor(cutoff: Int, split: Split) : this(cutoff, split,
        split.sumBelow * split.sumBelow * split.above + split.sumAbove * split.sumAbove * split.below, split.below.toLong() * split.above)
}
data class OtsuResult(val cutoff: Int, val upper: Int, val candidates: List<Candidate>)
data class IsodataResult(val cutoff: Int, val iterations: Int)
class Histogram(image: Image) {
    val maxval = image.maxval
    val pixels = image.width * image.height
    val counts = IntArray(maxval + 1)
    val belowCounts = IntArray(counts.size)
    val belowSums = LongArray(counts.size)
    val bins: IntArray
    val total: Long
    val minimum: Int
    val maximum: Int
    val levels: Int
    val median: Int
    val mode: Int
    val binWidth = (maxval + 8) / 8
    init {
        for (row in image.pixels) for (value in row) counts[value]++
        var count = 0
        var sum = 0L
        var first = -1
        var last = -1
        var distinct = 0
        var middle = -1
        var most = 0
        for (value in counts.indices) {
            count += counts[value]
            sum += value.toLong() * counts[value]
            belowCounts[value] = count
            belowSums[value] = sum
            if (counts[value] > 0) { if (first < 0) first = value; last = value; distinct++ }
            if (middle < 0 && 2 * count >= pixels) middle = value
            if (counts[value] > counts[most]) most = value
        }
        total = sum
        minimum = first
        maximum = last
        levels = distinct
        median = middle
        mode = most
        bins = IntArray(maxval / binWidth + 1)
        for (value in 0..maxval) bins[value / binWidth] += counts[value]
    }
    fun split(cutoff: Int) = Split(belowCounts[cutoff], belowSums[cutoff], pixels - belowCounts[cutoff], total - belowSums[cutoff])
}
object Threshold {
    fun compareScores(first: Candidate, second: Candidate): Int {
        val firstQ = first.numerator / first.denominator
        val secondQ = second.numerator / second.denominator
        if (firstQ != secondQ) return firstQ.compareTo(secondQ)
        val left = (first.numerator % first.denominator) * second.denominator
        val right = (second.numerator % second.denominator) * first.denominator
        return left.compareTo(right)
    }
    fun otsu(histogram: Histogram): OtsuResult {
        val candidates = mutableListOf<Candidate>()
        for (cutoff in 0 until histogram.maxval) {
            val split = histogram.split(cutoff)
            if (histogram.counts[cutoff] > 0 && split.above > 0) candidates.add(Candidate(cutoff, split))
        }
        candidates.sortWith { first, second ->
            val comparison = compareScores(second, first)
            if (comparison != 0) comparison else first.cutoff.compareTo(second.cutoff)
        }
        if (candidates.isEmpty()) return OtsuResult(histogram.minimum, histogram.minimum, candidates)
        val best = candidates[0].cutoff
        var following = best + 1
        while (histogram.counts[following] == 0) following++
        return OtsuResult(best, following - 1, candidates)
    }
    fun isodata(histogram: Histogram): IsodataResult {
        var cutoff = (histogram.total / histogram.pixels).toInt()
        var iterations = 0
        while (true) {
            val split = histogram.split(cutoff)
            if (split.below == 0 || split.above == 0) break
            val following = ((split.sumBelow * split.above + split.sumAbove * split.below) / (2L * split.below * split.above)).toInt()
            iterations++
            if (following == cutoff) break
            cutoff = following
            if (iterations == 100) break
        }
        return IsodataResult(cutoff, iterations)
    }
}
