import kotlin.math.abs
import kotlin.math.sqrt

private const val MODULUS = 2147483647L
private const val FEATURES_HEADER = "customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure"
private const val SEGMENTS_HEADER = "customer,segment,name,distance,other,other_distance,silhouette,recommend"
private class Minstd(var state: Long) {
    fun draw(): Long { state = state * 48271 % MODULUS; return state }
}
private data class Improvement(val labels: IntArray, val passes: Int, val transfers: Int, val sse: Double)
private class Run(val method: String, val number: Int, val seeds: IntArray, points: List<DoubleArray>, limit: Int) {
    val lloyd = KMeans.lloyd(points, seeds.map { points[it] }, limit)
    val lloydSse = KMeans.sse(points, lloyd.labels, lloyd.centers)
    val improved = improve(points, lloyd.labels, seeds.size, limit)
}
private class Solution(points: List<DoubleArray>, original: IntArray, val k: Int) {
    val members: List<List<Int>>
    val sizes: IntArray
    val labels = IntArray(original.size)
    val centers: List<DoubleArray>
    val sse: Double
    init {
        val groups = List(k) { mutableListOf<Int>() }
        for (i in original.indices) groups[original[i]].add(i)
        members = groups.sortedWith(compareByDescending<List<Int>> { it.size }.thenBy { it[0] })
        sizes = IntArray(k) { members[it].size }
        for (j in 0 until k) for (i in members[j]) labels[i] = j
        centers = KMeans.centers(points, labels, k)
        sse = KMeans.sse(points, labels, centers)
    }
}
private class Candidate(val k: Int, val runs: List<Run>, val methodBests: List<Run>, val best: Run, val solution: Solution) {
    var silhouettes = doubleArrayOf()
    var silhouette = 0.0
    var calinskiHarabasz = 0.0
    var daviesBouldin = 0.0
    var elbow = 0.0
    var hartigan: Double? = null
    var ruleNumbers = intArrayOf()
    var names = listOf<String>()
}
private fun nearestGaps(points: List<DoubleArray>, chosen: List<Int>): DoubleArray {
    return DoubleArray(points.size) { i ->
        var nearest = Double.POSITIVE_INFINITY
        for (j in chosen) nearest = minOf(nearest, KMeans.squaredDistance(points[i], points[j]))
        nearest
    }
}
private fun seeds(method: String, points: List<DoubleArray>, k: Int, number: Int, random: Minstd): IntArray {
    val chosen = mutableListOf<Int>()
    when (method) {
        "forgy" -> while (chosen.size < k) {
            val index = (random.draw() % points.size).toInt()
            if (index !in chosen) chosen.add(index)
        }
        "maximin" -> {
            val center = KMeans.meanPoint(points)
            val order = points.indices.sortedWith(compareBy<Int> { KMeans.squaredDistance(points[it], center) }.thenBy { it })
            chosen.add(order[number - 1])
            while (chosen.size < k) {
                val gaps = nearestGaps(points, chosen)
                var best = 0
                for (i in 1 until gaps.size) if (gaps[i] > gaps[best]) best = i
                chosen.add(best)
            }
        }
        else -> {
            chosen.add((random.draw() % points.size).toInt())
            while (chosen.size < k) {
                val gaps = nearestGaps(points, chosen)
                val threshold = (random.draw().toDouble() / MODULUS) * Features.sum(gaps)
                var total = 0.0
                var selected = -1
                for (i in gaps.indices) {
                    total += gaps[i]
                    if (total > threshold) { selected = i; break }
                }
                if (selected < 0) for (i in gaps.indices) if (gaps[i] > 0) selected = i
                chosen.add(selected)
            }
        }
    }
    return chosen.toIntArray()
}
private fun improve(points: List<DoubleArray>, original: IntArray, k: Int, limit: Int): Improvement {
    val labels = original.copyOf()
    val sizes = KMeans.sizes(labels, k)
    val centers = KMeans.centers(points, labels, k).toMutableList()
    var passes = 0
    var transfers = 0
    var moved = true
    while (moved && passes < limit) {
        moved = false
        passes++
        for (i in points.indices) {
            val own = labels[i]
            if (sizes[own] == 1) continue
            val removal = (sizes[own].toDouble() / (sizes[own] - 1)) * KMeans.squaredDistance(points[i], centers[own])
            var target = -1
            var targetCost = 0.0
            for (q in 0 until k) if (q != own) {
                val cost = (sizes[q].toDouble() / (sizes[q] + 1)) * KMeans.squaredDistance(points[i], centers[q])
                if (target < 0 || cost < targetCost) { target = q; targetCost = cost }
            }
            if (targetCost < removal) {
                labels[i] = target
                sizes[own]--
                sizes[target]++
                centers[own] = KMeans.center(points, labels, own)
                centers[target] = KMeans.center(points, labels, target)
                transfers++
                moved = true
            }
        }
    }
    return Improvement(labels, passes, transfers, KMeans.sse(points, labels, KMeans.centers(points, labels, k)))
}
private fun bestRun(runs: List<Run>): Run {
    var best = runs[0]
    for (run in runs) if (Report.fourDecimal(run.improved.sse) < Report.fourDecimal(best.improved.sse)) best = run
    return best
}
private fun gini(customers: List<Customer>): Double {
    val spends = customers.map { it.spend.toLong() }.sorted()
    var total = 0L
    var weighted = 0L
    for (i in spends.indices) { total += spends[i]; weighted += (i + 1L) * spends[i] }
    return (2 * weighted - (spends.size + 1L) * total).toDouble() / (spends.size * total)
}
private fun categoryTotals(customers: List<Customer>): Map<String, Int> {
    val totals = sortedMapOf<String, Int>()
    for (customer in customers) for ((category, spend) in customer.categorySpend) totals[category] = totals.getOrDefault(category, 0) + spend
    return totals
}
private fun ranking(totals: Map<String, Int>) = totals.keys.filter { totals.getValue(it) > 0 }
    .sortedWith(compareByDescending<String> { totals.getValue(it) }.thenBy { it })
private fun yesNo(flag: Boolean) = if (flag) "yes" else "no"
private fun ints(values: IntArray) = values.joinToString(" ")
private fun blocks(groups: List<List<String>>): List<String> {
    val lines = mutableListOf<String>()
    for (group in groups) { if (lines.isNotEmpty()) lines.add(""); lines.addAll(group) }
    return lines
}
private class Analysis(val params: Params, val data: TransactionData, val rules: List<NamingRule>) {
    val random = Minstd(params.seed)
    val referenceOrders = Transactions.groupOrders(data.validRows, 1, params.referenceDay)
    val customerOrders = Transactions.byCustomer(referenceOrders)
    val customers = Features.eligible(referenceOrders, params.referenceDay)
    val n = customers.size
    val numbers = customers.indices.associateBy { customers[it].id }
    val transformed = customers.map { it.transformed() }
    val standard = Features.standardization(transformed)
    val means = standard.means
    val sds = standard.sds
    val points = transformed.map { Features.standardize(it, means, sds) }
    val candidates = mutableListOf<Candidate>()
    val votes = linkedMapOf<String, Int>()
    lateinit var chosen: Candidate
    var finalVotes = 0
    var k = 0
    lateinit var labels: IntArray
    lateinit var other: IntArray
    lateinit var scoresR: IntArray
    lateinit var scoresF: IntArray
    lateinit var scoresM: IntArray
    lateinit var codes: Array<String>
    lateinit var centers: List<DoubleArray>
    lateinit var names: List<String>
    lateinit var categoryNames: List<String>
    lateinit var silhouettes: DoubleArray
    lateinit var distances: DoubleArray
    lateinit var otherDistances: DoubleArray
    lateinit var segmentSse: DoubleArray
    var totalSpend = 0
    lateinit var overallCategories: Map<String, Int>
    val segmentCustomers = mutableListOf<List<Customer>>()
    val segmentCategories = mutableListOf<Map<String, Int>>()
    val rankings = mutableListOf<List<String>>()
    lateinit var segmentSpends: IntArray
    lateinit var jaccards: Array<DoubleArray>
    fun ids(indices: IntArray) = indices.joinToString(" ") { customers[it].id }
    fun candidate(count: Int) = candidates[count - params.kMin]
    fun analyze() {
        for (count in params.kMin..params.kMax) candidates.add(search(count))
        evaluate()
        chooseK()
        describeFinal()
        subsamples()
    }
    fun search(count: Int): Candidate {
        val runs = mutableListOf<Run>()
        val bests = mutableListOf<Run>()
        for (method in params.methods) {
            val methodRuns = mutableListOf<Run>()
            for (number in 1..params.restarts) methodRuns.add(Run(method, number, seeds(method, points, count, number, random), points, params.maxIterations))
            runs.addAll(methodRuns)
            bests.add(bestRun(methodRuns))
        }
        val best = bestRun(bests)
        return Candidate(count, runs, bests, best, Solution(points, best.improved.labels, count))
    }
    fun evaluate() {
        val table = Validation.distanceTable(points)
        val first = candidates.first().solution.sse
        val last = candidates.last().solution.sse
        for (position in candidates.indices) {
            val c = candidates[position]
            val solution = c.solution
            c.silhouettes = Validation.silhouettes(table, solution.labels, solution.sizes)
            c.silhouette = Features.sum(c.silhouettes) / n
            c.calinskiHarabasz = Validation.calinskiHarabasz(points, solution.centers, solution.sizes, solution.sse)
            c.daviesBouldin = Validation.daviesBouldin(points, solution.labels, solution.centers, solution.sizes)
            c.elbow = Validation.elbow(c.k, params.kMin, params.kMax, solution.sse, first, last)
            if (c.k < params.kMax) c.hartigan = Validation.hartigan(solution.sse, candidates[position + 1].solution.sse, n, c.k)
            c.ruleNumbers = IntArray(c.k)
            val names = mutableListOf<String>()
            val repeats = mutableMapOf<Int, Int>()
            for (j in 0 until c.k) {
                val rule = Profiles.ruleNumber(rules, solution.centers[j])
                c.ruleNumbers[j] = rule
                val repeat = repeats.getOrDefault(rule, 0) + 1
                repeats[rule] = repeat
                names.add(rules[rule - 1].name + if (repeat == 1) "" else "_$repeat")
            }
            c.names = names
        }
    }
    fun chooseK() {
        var elbow = candidates[1]
        var silhouette = candidates[0]
        var ch = candidates[0]
        var db = candidates[0]
        var hartigan = params.kMax
        var found = false
        for (i in candidates.indices) {
            val c = candidates[i]
            if (i > 0 && i < candidates.size - 1 && Report.fourDecimal(c.elbow) > Report.fourDecimal(elbow.elbow)) elbow = c
            if (Report.fourDecimal(c.silhouette) > Report.fourDecimal(silhouette.silhouette)) silhouette = c
            if (Report.fourDecimal(c.calinskiHarabasz) > Report.fourDecimal(ch.calinskiHarabasz)) ch = c
            if (Report.fourDecimal(c.daviesBouldin) < Report.fourDecimal(db.daviesBouldin)) db = c
            val value = c.hartigan
            if (!found && value != null && value <= 10) { hartigan = c.k; found = true }
        }
        votes["elbow"] = elbow.k
        votes["silhouette"] = silhouette.k
        votes["calinski_harabasz"] = ch.k
        votes["davies_bouldin"] = db.k
        votes["hartigan"] = hartigan
        chosen = candidates[0]
        finalVotes = -1
        for (c in candidates) {
            val count = votes.values.count { it == c.k }
            if (count > finalVotes || count == finalVotes && Report.fourDecimal(c.silhouette) > Report.fourDecimal(chosen.silhouette)) {
                chosen = c
                finalVotes = count
            }
        }
    }
    fun describeFinal() {
        val solution = chosen.solution
        k = solution.k
        labels = solution.labels
        centers = solution.centers
        names = chosen.names
        silhouettes = chosen.silhouettes
        distances = DoubleArray(n)
        otherDistances = DoubleArray(n)
        other = IntArray(n)
        scoresR = IntArray(n)
        scoresF = IntArray(n)
        scoresM = IntArray(n)
        codes = Array(n) { "" }
        for (i in 0 until n) {
            var nearest = -1
            for (j in 0 until k) if (j != labels[i] && (nearest < 0 || KMeans.squaredDistance(points[i], centers[j]) < KMeans.squaredDistance(points[i], centers[nearest]))) nearest = j
            distances[i] = sqrt(KMeans.squaredDistance(points[i], centers[labels[i]]))
            other[i] = nearest
            otherDistances[i] = sqrt(KMeans.squaredDistance(points[i], centers[nearest]))
            val customer = customers[i]
            val older = customers.count { it.recency > customer.recency }
            val fewer = customers.count { it.frequency < customer.frequency }
            val smaller = customers.count { it.spend < customer.spend }
            scoresR[i] = 1 + 5 * older / n
            scoresF[i] = 1 + 5 * fewer / n
            scoresM[i] = 1 + 5 * smaller / n
            codes[i] = "${scoresR[i]}${scoresF[i]}${scoresM[i]}"
            totalSpend += customer.spend
        }
        overallCategories = categoryTotals(customers)
        categoryNames = overallCategories.keys.sorted()
        segmentSpends = IntArray(k)
        segmentSse = DoubleArray(k)
        for (j in 0 until k) {
            val group = mutableListOf<Customer>()
            for (i in solution.members[j]) {
                group.add(customers[i])
                segmentSpends[j] += customers[i].spend
                segmentSse[j] += KMeans.squaredDistance(points[i], centers[j])
            }
            segmentCustomers.add(group)
            val totals = categoryTotals(group)
            segmentCategories.add(totals)
            rankings.add(ranking(totals))
        }
    }
    fun subsamples() {
        val size = n * params.subsamplePercent / 100
        jaccards = Array(k) { DoubleArray(params.subsamples) }
        for (b in 0 until params.subsamples) {
            val order = IntArray(n) { it }
            for (t in 0 until size) {
                val j = t + (random.draw() % (n - t)).toInt()
                val swap = order[t]
                order[t] = order[j]
                order[j] = swap
            }
            val sample = order.copyOf(size).sortedArray()
            val subset = sample.map { points[it] }
            val sampledLabels = KMeans.lloyd(subset, centers, params.maxIterations).labels
            for (segment in 0 until k) for (j in 0 until k) {
                var both = 0
                var either = 0
                for (t in 0 until size) {
                    val member = labels[sample[t]] == segment
                    val assigned = sampledLabels[t] == j
                    if (member && assigned) both++
                    if (member || assigned) either++
                }
                if (either > 0) jaccards[segment][b] = maxOf(jaccards[segment][b], both.toDouble() / either)
            }
        }
    }
    fun recommendation(i: Int): String {
        for (category in rankings[labels[i]]) if (customers[i].categorySpend.getOrDefault(category, 0) <= 0) return category
        return "-"
    }
    fun featuresLines(): List<String> {
        val lines = mutableListOf(FEATURES_HEADER)
        for (i in 0 until n) {
            val c = customers[i]
            val fields = mutableListOf(c.id, c.recency.toString(), c.frequency.toString(), Report.amount(c.spend), Report.real(c.basket), c.categories.toString(), c.tenure.toString())
            fields.addAll(points[i].map { Report.real(it) })
            lines.add(fields.joinToString(","))
        }
        return lines
    }
    fun runSummary(run: Run) = "${run.method} restart ${run.number} sse ${Report.real(run.improved.sse)}"
    fun runLine(run: Run) = "run ${run.method} ${run.number} seeds ${ids(run.seeds)} iterations ${run.lloyd.iterations}" +
        " converged ${yesNo(run.lloyd.converged)} reseeds ${run.lloyd.reseeds} sse ${Report.real(run.lloydSse)}" +
        " passes ${run.improved.passes} transfers ${run.improved.transfers} refined ${Report.real(run.improved.sse)}"
    fun runsLines(): List<String> {
        val groups = mutableListOf<List<String>>()
        for (c in candidates) {
            val lines = mutableListOf("k ${c.k}")
            for (run in c.runs) lines.add(runLine(run))
            for (run in c.methodBests) lines.add("best ${runSummary(run)}")
            lines.add("chosen ${runSummary(c.best)}")
            lines.add("sizes ${ints(c.solution.sizes)}")
            groups.add(lines)
        }
        return blocks(groups)
    }
    fun selectionLines(): List<String> {
        val indices = mutableListOf("indices")
        val voteLines = mutableListOf("votes")
        val segments = mutableListOf("segments")
        val stability = mutableListOf("stability")
        for (position in candidates.indices) {
            val c = candidates[position]
            val hartigan = c.hartigan?.let { Report.real(it) } ?: "-"
            indices.add("k=${c.k} sse ${Report.real(c.solution.sse)} elbow ${Report.real(c.elbow)} silhouette ${Report.real(c.silhouette)}" +
                " calinski_harabasz ${Report.real(c.calinskiHarabasz)} davies_bouldin ${Report.real(c.daviesBouldin)} hartigan $hartigan")
            segments.add("k=${c.k} " + (0 until c.k).joinToString(" ") { "${c.names[it]}:${c.solution.sizes[it]}" })
            val parts = mutableListOf("k=${c.k}")
            for (i in c.methodBests.indices) for (j in i + 1 until c.methodBests.size) {
                val a = c.methodBests[i]
                val b = c.methodBests[j]
                parts.add("${a.method}:${b.method} ${Report.real(Validation.ari(a.improved.labels, b.improved.labels))}")
            }
            parts.add("final")
            for (run in c.methodBests) parts.add("${run.method} ${Report.real(Validation.ari(run.improved.labels, c.solution.labels))}")
            parts.add(if (position + 1 < candidates.size) "next ${Report.real(Validation.ari(c.solution.labels, candidates[position + 1].solution.labels))}" else "next -")
            stability.add(parts.joinToString(" "))
        }
        for ((criterion, count) in votes) voteLines.add("$criterion k=$count")
        voteLines.add("chosen k=${chosen.k} votes $finalVotes")
        return blocks(listOf(indices, voteLines, segments, stability))
    }
    fun segmentsLines(): List<String> {
        val lines = mutableListOf(SEGMENTS_HEADER)
        for (i in 0 until n) lines.add(listOf(customers[i].id, (labels[i] + 1).toString(), names[labels[i]], Report.real(distances[i]),
            (other[i] + 1).toString(), Report.real(otherDistances[i]), Report.real(silhouettes[i]), recommendation(i)).joinToString(","))
        return lines
    }
    fun medianLine(group: List<Customer>): String {
        val index = (group.size - 1) / 2
        val recency = group.map { it.recency }.sorted()[index]
        val frequency = group.map { it.frequency }.sorted()[index]
        val spend = group.map { it.spend }.sorted()[index]
        val basket = group.map { it.basket }.sorted()[index]
        val categories = group.map { it.categories }.sorted()[index]
        val tenure = group.map { it.tenure }.sorted()[index]
        return "  median recency $recency frequency $frequency monetary ${Report.amount(spend)} basket ${Report.real(basket)} categories $categories tenure $tenure"
    }
    fun related(members: List<Int>, count: Int): String {
        if (count !in params.kMin..params.kMax) return "k=$count -"
        val counts = IntArray(count)
        val related = candidate(count).solution.labels
        for (i in members) counts[related[i]]++
        var best = 0
        for (i in 1 until count) if (counts[i] > counts[best]) best = i
        return "k=$count segment ${best + 1} shared ${counts[best]}"
    }
    fun cadenceLine(group: List<Customer>): String {
        val gaps = mutableListOf<Double>()
        var overdue = 0
        for (c in group) if (c.frequency >= 2) {
            val active = c.tenure - c.recency
            val intervals = c.frequency - 1
            gaps.add(active.toDouble() / intervals)
            if (c.recency * intervals > params.overdueFactor * active) overdue++
        }
        val meanGap = if (gaps.isEmpty()) "-" else Report.real(Features.mean(gaps.toDoubleArray()))
        return "  cadence customers ${gaps.size} mean_gap $meanGap overdue $overdue"
    }
    fun orderSizesLine(group: List<Customer>): String {
        val bins = IntArray(params.orderBins.size + 1)
        for (c in group) for (order in c.orders) bins[params.orderBins.count { order.net >= it * 100 }]++
        return "  order_sizes ${ints(bins)}"
    }
    fun returnsLine(group: List<Customer>): String {
        var gross = 0
        var returned = 0
        var cancelled = 0
        for (c in group) for (order in customerOrders.getValue(c.id)) {
            if (!order.valid()) cancelled++
            for (row in order.rows) if (row.amount > 0) gross += row.amount else if (row.amount < 0) returned -= row.amount
        }
        return "  returns rate ${Report.real(returned.toDouble() / gross)} returned ${Report.amount(returned)} cancelled $cancelled"
    }
    fun rfmLine(members: List<Int>): String {
        var r = 0
        var f = 0
        var m = 0
        val counts = sortedMapOf<String, Int>()
        for (i in members) {
            r += scoresR[i]; f += scoresF[i]; m += scoresM[i]
            counts[codes[i]] = counts.getOrDefault(codes[i], 0) + 1
        }
        var mode = counts.firstKey()
        for (code in counts.keys) if (counts.getValue(code) > counts.getValue(mode)) mode = code
        return "  rfm r ${Report.real(r.toDouble() / members.size)} f ${Report.real(f.toDouble() / members.size)} m ${Report.real(m.toDouble() / members.size)} mode $mode ${counts.getValue(mode)}"
    }
    fun categoriesLine(segment: Int): String {
        val parts = mutableListOf("  categories")
        for (category in rankings[segment].take(params.topCategories)) {
            val share = segmentCategories[segment].getValue(category).toDouble() / segmentSpends[segment]
            val lift = share / (overallCategories.getValue(category).toDouble() / totalSpend)
            parts.addAll(listOf(category, Report.real(share), Report.real(lift)))
        }
        return parts.joinToString(" ")
    }
    fun outliersLine(members: List<Int>): String {
        val outliers = mutableListOf<String>()
        if (members.size >= 2) {
            val values = members.map { distances[it] }.toDoubleArray()
            val limit = Features.mean(values) + params.outlierSd * Features.sampleSd(values)
            for (i in members) if (distances[i] > limit) outliers.add(customers[i].id)
        }
        return (listOf("  outliers", outliers.size.toString()) + outliers).joinToString(" ")
    }
    fun segmentProfile(segment: Int): List<String> {
        val members = chosen.solution.members[segment]
        val group = segmentCustomers[segment]
        val size = members.size
        val spend = segmentSpends[segment]
        val center = centers[segment]
        val lines = mutableListOf("segment ${segment + 1} ${names[segment]} rule ${chosen.ruleNumbers[segment]} size $size share ${Report.real(size.toDouble() / n)}" +
            " revenue ${Report.amount(spend)} revenue_share ${Report.real(spend.toDouble() / totalSpend)}")
        lines.add("  center ${Report.reals(center)}")
        val values = Profiles.originalScale(center, means, sds)
        lines.add("  value " + (0 until 6).joinToString(" ") { "${Features.NAMES[it]} ${Report.real(values[it])}" })
        val traits = (0 until 6).sortedWith(compareBy<Int> { -abs(center[it]) }.thenBy { it }).take(2)
            .map { (if (center[it] > 0) "high_" else "low_") + Features.NAMES[it] }
        lines.add("  traits ${traits.joinToString(" ")}")
        lines.add(medianLine(group))
        lines.add("  related ${related(members, k - 1)} ${related(members, k + 1)}")
        val top = members.sortedWith(compareByDescending<Int> { customers[it].spend }.thenBy { it }).take(params.topCustomers)
        val parts = mutableListOf("  top_customers")
        for (i in top) parts.addAll(listOf(customers[i].id, Report.amount(customers[i].spend)))
        lines.add(parts.joinToString(" "))
        lines.add(cadenceLine(group))
        lines.add(orderSizesLine(group))
        lines.add("  sse ${Report.real(segmentSse[segment])} share ${Report.real(segmentSse[segment] / chosen.solution.sse)}")
        lines.add("  gini ${Report.real(gini(group))}")
        lines.add(returnsLine(group))
        val sil = members.map { silhouettes[it] }.toDoubleArray()
        lines.add("  silhouette ${Report.real(Features.mean(sil))} negative ${sil.count { it < 0 }}")
        lines.add(rfmLine(members))
        lines.add(categoriesLine(segment))
        lines.add(outliersLine(members))
        return lines
    }
    fun segmentNumbers() = (1..k).joinToString(" ")
    fun profilesLines(): List<String> {
        val groups = mutableListOf<List<String>>()
        groups.add(listOf("segments k=$k customers $n revenue ${Report.amount(totalSpend)} gini ${Report.real(gini(customers))}"))
        for (j in 0 until k) groups.add(segmentProfile(j))
        val mix = mutableListOf("category_mix ${segmentNumbers()}")
        for (category in categoryNames) {
            val shares = DoubleArray(k) { segmentCategories[it].getOrDefault(category, 0).toDouble() / segmentSpends[it] }
            mix.add("$category ${Report.reals(shares)}")
        }
        groups.add(mix)
        val recency = mutableListOf("rfm_recency ${segmentNumbers()}")
        for (score in 5 downTo 1) {
            val counts = IntArray(k)
            for (i in 0 until n) if (scoresR[i] == score) counts[labels[i]]++
            recency.add("r=$score ${ints(counts)}")
        }
        val numericCodes = codes.map(String::toInt).toIntArray()
        recency.add("ari rfm_codes ${Report.real(Validation.ari(numericCodes, labels))}")
        groups.add(recency)
        val centerLines = mutableListOf("center_distances")
        for (j in 0 until k) centerLines.add("${j + 1} ${Report.reals(DoubleArray(k) { sqrt(KMeans.squaredDistance(centers[j], centers[it])) })}")
        groups.add(centerLines)
        return blocks(groups)
    }
    fun robustnessLines(): List<String> {
        val sample = mutableListOf("subsamples ${params.subsamples} size ${n * params.subsamplePercent / 100}")
        for (j in 0 until k) sample.add("segment ${j + 1} ${names[j]} mean_jaccard ${Report.real(Features.mean(jaccards[j]))} min_jaccard ${Report.real(jaccards[j].min())}")
        val ablation = mutableListOf("ablation")
        for (f in 0 until 6) {
            val subset = points.map { point -> point.indices.filter { it != f }.map { point[it] }.toDoubleArray() }
            val seed = seeds("maximin", subset, k, 1, random)
            val run = Run("maximin", 1, seed, subset, params.maxIterations)
            ablation.add("without ${Features.NAMES[f]} seeds ${ids(seed)} iterations ${run.lloyd.iterations} converged ${yesNo(run.lloyd.converged)}" +
                " transfers ${run.improved.transfers} sse ${Report.real(run.improved.sse)} ari ${Report.real(Validation.ari(run.improved.labels, labels))}")
        }
        val members = chosen.solution.members[0]
        val subset = members.map { points[it] }
        val seed = seeds("maximin", subset, 2, 1, random)
        val run = Run("maximin", 1, seed, subset, params.maxIterations)
        val parts = Solution(subset, run.improved.labels, 2)
        val originalSeeds = seed.map { members[it] }.toIntArray()
        val drilldown = mutableListOf("drilldown segment 1 ${names[0]} size ${members.size} seeds ${ids(originalSeeds)} iterations ${run.lloyd.iterations}" +
            " converged ${yesNo(run.lloyd.converged)} transfers ${run.improved.transfers}",
            "sse before ${Report.real(segmentSse[0])} after ${Report.real(run.improved.sse)} gain ${Report.real(segmentSse[0] - run.improved.sse)}")
        for (j in 0 until 2) drilldown.add("part ${j + 1} size ${parts.sizes[j]} center ${Report.reals(parts.centers[j])}")
        return blocks(listOf(sample, ablation, drilldown))
    }
    fun periodLines(): List<String> {
        val day = params.referenceDay
        val days = params.periodDays
        val lines = mutableListOf("periods ${params.periods} days $days")
        for (q in 1..params.periods) {
            val first = day - q * days + 1
            val last = day - (q - 1) * days
            val revenue = IntArray(k)
            val active = IntArray(k)
            val acquired = IntArray(k)
            for (i in 0 until n) {
                val c = customers[i]
                val label = labels[i]
                var bought = false
                for (order in c.orders) if (order.day in first..last) { revenue[label] += order.net; bought = true }
                if (bought) active[label]++
                if (day - c.tenure in first..last) acquired[label]++
            }
            lines.add("period $q days $first $last revenue " + revenue.joinToString(" ") { Report.amount(it) } + " active ${ints(active)} acquired ${ints(acquired)}")
        }
        return lines
    }
    fun migrationLines(): List<String> {
        val day = params.snapshotDay
        val snapshot = sortedMapOf<String, Int>()
        for (c in Features.eligible(Transactions.groupOrders(data.validRows, 1, day), day)) {
            val point = Features.standardize(c.transformed(), means, sds)
            var best = 0
            for (j in 1 until k) if (KMeans.squaredDistance(point, centers[j]) < KMeans.squaredDistance(point, centers[best])) best = j
            snapshot[c.id] = best
        }
        val table = Array(k + 1) { IntArray(k) }
        var stayed = 0
        var fresh = 0
        val moved = mutableListOf<String>()
        for (i in 0 until n) {
            val origin = snapshot[customers[i].id]
            val label = labels[i]
            if (origin == null) { table[k][label]++; fresh++ }
            else {
                table[origin][label]++
                if (origin == label) stayed++ else moved.add("${customers[i].id} ${origin + 1} ${label + 1}")
            }
        }
        val lost = snapshot.keys.count { it !in numbers }
        val lines = mutableListOf("migration day $day customers ${snapshot.size}", "from\\to ${segmentNumbers()}")
        for (j in 0..k) lines.add((if (j == k) "none" else (j + 1).toString()) + " ${ints(table[j])}")
        lines.add("moved_customers")
        lines.addAll(moved)
        lines.add("stayed $stayed moved ${moved.size} new $fresh lost $lost")
        return lines
    }
    fun outcomeLines(): List<String> {
        val first = params.referenceDay + 1
        val last = params.referenceDay + params.outcomeDays
        val purchases = Transactions.byCustomer(Transactions.groupOrders(data.validRows, first, last).filter { it.valid() })
        val lines = mutableListOf("outcome days $first $last")
        for (j in 0 until k) {
            var buyers = 0
            var spend = 0
            val size = segmentCustomers[j].size
            for (c in segmentCustomers[j]) {
                val orders = purchases[c.id]
                if (orders != null) { buyers++; for (order in orders) spend += order.net }
            }
            lines.add("segment ${j + 1} ${names[j]} size $size buyers $buyers rate ${Report.real(buyers.toDouble() / size)}" +
                " revenue ${Report.amount(spend)} per_customer ${Report.real((spend / 100.0) / size)}")
        }
        val outsiders = purchases.keys.filter { it !in numbers }
        var spend = 0
        for (id in outsiders) for (order in purchases.getValue(id)) spend += order.net
        lines.add("unsegmented buyers ${outsiders.size} revenue ${Report.amount(spend)}")
        return lines
    }
    fun summaryLines(): List<String> {
        var used = 0
        var returned = 0
        var later = 0
        for (row in data.validRows) {
            if (row.day <= params.referenceDay) { used++; if (row.amount < 0) returned++ } else later++
        }
        val valid = referenceOrders.count { it.valid() }
        val excluded = data.customers.filter { it !in numbers }
        val dataLines = listOf("rows ${data.rowCount} duplicates ${data.duplicates} zero ${data.free} used $used returns $returned later $later",
            "orders ${referenceOrders.size} valid $valid cancelled ${referenceOrders.size - valid}",
            "customers ${data.customers.size} clustered $n excluded ${excluded.size}", "excluded_ids " + if (excluded.isEmpty()) "-" else excluded.joinToString(" "))
        val categoryLines = mutableListOf<String>()
        for (category in categoryNames) {
            val buyers = customers.count { it.categorySpend.getOrDefault(category, 0) > 0 }
            val total = overallCategories.getValue(category)
            categoryLines.add("category $category revenue ${Report.amount(total)} share ${Report.real(total.toDouble() / totalSpend)} customers $buyers")
        }
        val features = mutableListOf<String>()
        val correlations = mutableListOf("correlation ${Features.NAMES.joinToString(" ")}")
        for (f in 0 until 6) {
            val column = DoubleArray(n) { customers[it].values()[f] }
            val transform = if (Features.SQRT[f]) "sqrt" else "none"
            features.add("feature ${Features.NAMES[f]} transform $transform raw_mean ${Report.real(Features.mean(column))}" +
                " raw_sd ${Report.real(Features.sampleSd(column))} mean ${Report.real(means[f])} sd ${Report.real(sds[f])}")
            correlations.add("${Features.NAMES[f]} ${Report.reals(DoubleArray(6) { Features.correlation(points, f, it) })}")
        }
        return blocks(listOf(dataLines, categoryLines, features, correlations))
    }
}
fun main() {
    val analysis = Analysis(Transactions.readParams("input/params.txt"), Transactions.read("input/transactions.csv"), Profiles.read("input/segment_rules.txt"))
    analysis.analyze()
    val files = linkedMapOf("features.csv" to analysis.featuresLines(), "runs.txt" to analysis.runsLines(), "selection.txt" to analysis.selectionLines(),
        "segments.csv" to analysis.segmentsLines(), "profiles.txt" to analysis.profilesLines(), "robustness.txt" to analysis.robustnessLines(),
        "tracking.txt" to blocks(listOf(analysis.periodLines(), analysis.migrationLines(), analysis.outcomeLines())), "summary.txt" to analysis.summaryLines())
    Report.writeFiles(files)
}
