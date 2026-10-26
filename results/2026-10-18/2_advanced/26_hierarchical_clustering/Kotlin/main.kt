import java.math.BigInteger
import java.nio.file.Files
import java.nio.file.Path
import java.util.Locale
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

private fun real(value: Double?): String {
    if (value == null) return "-"
    val text = String.format(Locale.ROOT, "%.4f", value)
    return if (text == "-0.0000") "0.0000" else text
}
private fun fourDigit(value: Double): Double = real(value).toDouble()
private fun reals(values: DoubleArray): String = values.joinToString(" ") { real(it) }
private fun integers(values: IntArray): String = values.joinToString(" ")
private fun ariText(value: Fraction): String = "$value ${real(value.value)}"
private fun pairValues(matrix: Array<DoubleArray>): DoubleArray {
    val values = DoubleArray(matrix.size * (matrix.size - 1) / 2)
    var position = 0
    for (i in matrix.indices) for (j in i + 1 until matrix.size) values[position++] = matrix[i][j]
    return values
}
private fun histogramBin(value: Double, maximum: Double): Int = min(9, floor(10 * value / maximum).toInt())
private fun clusterMembers(partition: IntArray, groups: Int): List<MutableList<Int>> {
    val members = List(groups) { mutableListOf<Int>() }
    for (i in partition.indices) members[partition[i] - 1].add(i)
    return members
}
private fun centroid(vectors: Array<DoubleArray>): DoubleArray = DoubleArray(vectors[0].size) { f ->
    var total = 0.0
    for (vector in vectors) total += vector[f]
    total / vectors.size
}
private fun majorityClass(row: IntArray): Int {
    var best = 0
    for (t in 1 until row.size) if (row[t] > row[best]) best = t
    return best
}
private fun joinParts(parts: List<List<String>>): List<String> {
    val lines = mutableListOf<String>()
    for (part in parts) { if (lines.isNotEmpty()) lines.add(""); lines.addAll(part) }
    return lines
}
private fun connectedComponents(count: Int, edges: List<Agglomerative.Edge>): IntArray {
    val components = IntArray(count) { it }
    for (edge in edges) {
        val old = components[edge.child]
        val replacement = components[edge.parent]
        for (u in 0 until count) if (components[u] == old) components[u] = replacement
    }
    return components
}
private class Minstd(seed: Int) {
    private var state = seed.toLong()
    fun draw(): Long { state = 48271 * state % 2147483647; return state }
}
private class Settings(entries: Map<String, List<String>>) {
    val distance = entries.getValue("DISTANCE").first()
    val standardize = entries.getValue("STANDARDIZE").first()
    val linkages = entries.getValue("LINKAGES")
    val cutHeights = entries.getValue("CUT_HEIGHTS").map(String::toDouble).toDoubleArray()
    val cutCounts = entries.getValue("CUT_K").map(String::toInt).toIntArray()
    val inconsistencyDepth = BigInteger(entries.getValue("INCONSISTENCY")[0])
    val inconsistencyCount = entries.getValue("INCONSISTENCY")[1].toInt()
    val gapMaxK = entries.getValue("GAP_MAX_K").first().toInt()
    val listSize = entries.getValue("LIST_SIZE").first().toInt()
    val width = entries.getValue("DENDROGRAM_WIDTH").first().toInt()
    val compareLinkage = entries.getValue("COMPARE_LINKAGE").first()
    val replicates = entries.getValue("SUBSAMPLES")[0].toInt()
    val percent = entries.getValue("SUBSAMPLES")[1].toInt()
    val seed = entries.getValue("SUBSAMPLES")[2].toInt()
    val refineIterations = entries.getValue("REFINE_ITERATIONS").first().toInt()
}
private class Tree(val merges: List<Agglomerative.Merge>, val count: Int) {
    val heights = merges.map(Agglomerative.Merge::height).toDoubleArray()
    val children = Dendrogram.children(merges, count)
    val order = Dendrogram.leafOrder(children, count)
    val depths = IntArray(2 * count - 1)
    val subtreeHeights = DoubleArray(merges.size)
    val members = mutableListOf<IntArray>()
    init {
        for (u in 0 until count) members.add(intArrayOf(u))
        for (step in merges.indices) {
            val merge = merges[step]
            members.add(members[merge.a] + members[merge.b])
            depths[count + step] = 1 + max(depths[merge.a], depths[merge.b])
            subtreeHeights[step] = max(merge.height, max(subtreeHeight(merge.a), subtreeHeight(merge.b)))
        }
    }
    val root: Int get() = 2 * count - 2
    fun height(node: Int): Double = if (node < count) 0.0 else heights[node - count]
    fun subtreeHeight(node: Int): Double = if (node < count) 0.0 else subtreeHeights[node - count]
    private fun partition(selected: BooleanArray): IntArray {
        val owner = IntArray(count) { it }
        for (step in selected.indices) if (selected[step]) for (u in members[count + step]) owner[u] = count + step
        val numbers = IntArray(2 * count - 1)
        var groups = 0
        for (u in order) if (numbers[owner[u]] == 0) numbers[owner[u]] = ++groups
        return IntArray(count) { numbers[owner[it]] }
    }
    fun cutAtHeight(height: Double): IntArray = partition(BooleanArray(merges.size) { subtreeHeights[it] <= height })
    fun cutInto(groups: Int): IntArray = partition(BooleanArray(merges.size) { it < count - groups })
    fun cophenetic(): Array<DoubleArray> {
        val matrix = Array(count) { DoubleArray(count) }
        for (merge in merges) for (i in members[merge.a]) for (j in members[merge.b]) { matrix[i][j] = merge.height; matrix[j][i] = merge.height }
        return matrix
    }
    fun joiningHeights(): DoubleArray {
        val values = DoubleArray(count)
        for (merge in merges) { if (merge.a < count) values[merge.a] = merge.height; if (merge.b < count) values[merge.b] = merge.height }
        return values
    }
    fun heightSequence(step: Int, depth: Int): List<Double> {
        if (depth == 0) return emptyList()
        val merge = merges[step]
        val sequence = mutableListOf(merge.height)
        for (child in intArrayOf(merge.a, merge.b)) if (child >= count) sequence.addAll(heightSequence(child - count, depth - 1))
        return sequence
    }
    fun newick(node: Int, idents: List<String>): String {
        if (node < count) return idents[node]
        val upper = children[node - count][0]
        val lower = children[node - count][1]
        return "(${newick(upper, idents)}:${real(height(node) - height(upper))},${newick(lower, idents)}:${real(height(node) - height(lower))})"
    }
}
private data class PartitionEvaluation(val partition: IntArray, val sizes: IntArray, val silhouette: Double?, val dunn: Double?, val wss: Double, val ch: Double?, val ari: Fraction) {
    fun text(): String = "sizes ${integers(sizes)} silhouette ${real(silhouette)} dunn ${real(dunn)} wss ${real(wss)} ch ${real(ch)} ari ${ariText(ari)}"
}
private data class LinkageResult(val method: String, val tree: Tree, val cophenetic: DoubleArray, val correlation: Double, val heightCuts: List<PartitionEvaluation>, val countCuts: List<PartitionEvaluation>, val labelPartition: IntArray)

private class Study(input: InputData) {
    val featureNames = input.features
    val settings = Settings(input.settings)
    val count = input.observations.size
    val idents = input.observations.map(Observation::ident)
    val labels = input.observations.map(Observation::label)
    val classes = labels.distinct().sorted()
    val targets = labels.map { classes.binarySearch(it) }.toIntArray()
    val raw = input.observations.map(Observation::values).toTypedArray()
    val statistics = Distances.statistics(raw)
    val means = statistics.means
    val deviations = statistics.deviations
    val vectors = if (settings.standardize == "yes") Distances.standardize(raw, statistics) else raw
    val distances = Distances.matrix(vectors, settings.distance)
    val distancePairs = pairValues(distances)
    val distanceMax = distancePairs.max()
    val neighbors = IntArray(count) { nearestNeighbor(it) }
    val results = settings.linkages.map { analyseLinkage(it) }
    val chosen: LinkageResult
    val kappa: Int
    val selectedCut: PartitionEvaluation
    val selected: IntArray
    val members: List<List<Int>>
    val silhouettes: DoubleArray
    val table: Array<IntArray>
    val majority: IntArray
    init {
        var bestResult = 0
        var bestPosition = 0
        for (r in results.indices) for (position in settings.cutCounts.indices) {
            if (results[r].countCuts[position].ari > results[bestResult].countCuts[bestPosition].ari) { bestResult = r; bestPosition = position }
        }
        chosen = results[bestResult]
        kappa = settings.cutCounts[bestPosition]
        selectedCut = chosen.countCuts[bestPosition]
        selected = selectedCut.partition
        members = clusterMembers(selected, kappa)
        silhouettes = Validation.silhouettes(selected, kappa, distances)
        table = classTable(selected)
        majority = table.map(::majorityClass).toIntArray()
    }
    fun nearestNeighbor(i: Int): Int {
        var best = -1
        for (j in 0 until count) if (j != i && (best < 0 || distances[i][j] < distances[i][best])) best = j
        return best
    }
    fun classTable(partition: IntArray): Array<IntArray> = Validation.contingency(partition.map { it - 1 }.toIntArray(), targets, partition.max(), classes.size)
    fun labelAri(partition: IntArray): Fraction = Validation.adjustedRand(classTable(partition))
    fun partitionAri(first: IntArray, second: IntArray): Fraction = Validation.adjustedRand(Validation.contingency(first.map { it - 1 }.toIntArray(), second.map { it - 1 }.toIntArray(), first.max(), second.max()))
    fun matchCount(partition: IntArray): Int = classTable(partition).sumOf { it.max() }
    fun meanSilhouette(partition: IntArray, delta: Array<DoubleArray>): Double? {
        val groups = partition.max()
        return if (groups < 2) null else Distances.sum(Validation.silhouettes(partition, groups, delta)) / partition.size
    }
    fun centroids(partition: IntArray): Array<DoubleArray> = clusterMembers(partition, partition.max()).map { group -> centroid(group.map { vectors[it] }.toTypedArray()) }.toTypedArray()
    fun withinSum(partition: IntArray): Double {
        val centers = centroids(partition)
        var total = 0.0
        for (i in 0 until count) total += Distances.squared(vectors[i], centers[partition[i] - 1])
        return total
    }
    fun dunnIndex(partition: IntArray, groups: Int): Double? {
        var diameter = 0.0
        var separation = Double.POSITIVE_INFINITY
        for (i in 0 until count) for (j in i + 1 until count) {
            if (partition[i] == partition[j]) diameter = max(diameter, distances[i][j]) else separation = min(separation, distances[i][j])
        }
        return if (groups >= 2 && diameter > 0) separation / diameter else null
    }
    fun evaluate(partition: IntArray): PartitionEvaluation {
        val groups = partition.max()
        val sizes = clusterMembers(partition, groups).map { it.size }.toIntArray()
        val wss = withinSum(partition)
        var ch: Double? = null
        if (groups >= 2 && groups < count) {
            val overall = centroid(vectors)
            val centers = centroids(partition)
            var bss = 0.0
            for (g in 0 until groups) bss += sizes[g] * Distances.squared(centers[g], overall)
            ch = (bss / (groups - 1)) / (wss / (count - groups))
        }
        return PartitionEvaluation(partition, sizes, meanSilhouette(partition, distances), dunnIndex(partition, groups), wss, ch, labelAri(partition))
    }
    fun analyseLinkage(method: String): LinkageResult {
        val tree = Tree(Agglomerative.cluster(distances, method), count)
        val cophenetic = pairValues(tree.cophenetic())
        val heightCuts = settings.cutHeights.map { evaluate(tree.cutAtHeight(it)) }
        val countCuts = settings.cutCounts.map { evaluate(tree.cutInto(it)) }
        return LinkageResult(method, tree, cophenetic, Validation.correlation(distancePairs, cophenetic), heightCuts, countCuts, tree.cutInto(classes.size))
    }
    fun linkageTable(): List<String> {
        val lines = mutableListOf("method,step,a,b,height,size")
        for (result in results) for ((step, merge) in result.tree.merges.withIndex()) lines.add("${result.method},${step + 1},${merge.a},${merge.b},${real(merge.height)},${merge.size}")
        return lines
    }
    fun clustersTable(): List<String> {
        val header = mutableListOf("id", "label")
        for (result in results) {
            for (j in 1..settings.cutHeights.size) header.add("${result.method}_h$j")
            for (k in settings.cutCounts) header.add("${result.method}_k$k")
        }
        val lines = mutableListOf(header.joinToString(","))
        for (i in 0 until count) {
            val fields = mutableListOf(idents[i], labels[i])
            for (result in results) {
                for (cut in result.heightCuts) fields.add(cut.partition[i].toString())
                for (cut in result.countCuts) fields.add(cut.partition[i].toString())
            }
            lines.add(fields.joinToString(","))
        }
        return lines
    }
    fun dendrogramReport(): List<String> {
        val blocks = mutableListOf<List<String>>()
        for (result in results) {
            val tree = result.tree
            val maximum = tree.heights.max()
            val columns = settings.cutHeights.map { Dendrogram.column(it, maximum, settings.width) }.toIntArray()
            val lines = mutableListOf("dendrogram ${result.method} height_max ${real(maximum)} width ${settings.width}")
            lines.addAll(Dendrogram.rows(tree.merges, tree.children, tree.order, idents, labels, maximum, columns, settings.width))
            for (j in columns.indices) lines.add("cut ${real(settings.cutHeights[j])} column ${if (columns[j] <= settings.width) columns[j].toString() else "-"}")
            blocks.add(lines)
        }
        return joinParts(blocks)
    }
    fun treesReport(): List<String> = results.map { "${it.method} ${it.tree.newick(it.tree.root, idents)};" }
    fun pairText(first: Int, second: Int): String = "${real(distances[first][second])} ${idents[first]} ${idents[second]}"
    fun dataPart(): List<String> {
        val lines = mutableListOf("data n $count features ${featureNames.size} classes ${classes.size} distance ${settings.distance} standardize ${settings.standardize}")
        for (f in featureNames.indices) lines.add("feature ${featureNames[f]} mean ${real(means[f])} sd ${real(deviations[f])}")
        var minFirst = 0
        var minSecond = 1
        var maxFirst = 0
        var maxSecond = 1
        for (i in 0 until count) for (j in i + 1 until count) {
            if (distances[i][j] < distances[minFirst][minSecond]) { minFirst = i; minSecond = j }
            if (distances[i][j] > distances[maxFirst][maxSecond]) { maxFirst = i; maxSecond = j }
        }
        lines.add("distances pairs ${distancePairs.size} min ${pairText(minFirst, minSecond)} max ${pairText(maxFirst, maxSecond)} mean ${real(Distances.sum(distancePairs) / distancePairs.size)}")
        var nearestTotal = 0.0
        var reciprocal = 0
        for (i in 0 until count) { nearestTotal += distances[i][neighbors[i]]; if (i < neighbors[i] && neighbors[neighbors[i]] == i) reciprocal++ }
        lines.add("nearest_neighbors mean ${real(nearestTotal / count)} reciprocal_pairs $reciprocal")
        lines.add("labels ${evaluate(targets.map { it + 1 }.toIntArray()).text()}")
        return lines
    }
    fun correlationPart(): List<String> {
        val columns = Array(featureNames.size) { f -> DoubleArray(count) { i -> raw[i][f] } }
        val lines = mutableListOf("correlation ${featureNames.joinToString(" ")}")
        for (f in featureNames.indices) lines.add("${featureNames[f]} ${reals(DoubleArray(featureNames.size) { g -> Validation.correlation(columns[f], columns[g]) })}")
        return lines
    }
    fun histogramPart(): List<String> {
        val counts = IntArray(10)
        for (value in distancePairs) counts[histogramBin(value, distanceMax)]++
        val highest = counts.max()
        val lines = mutableListOf("histogram")
        for (bin in 0 until 10) {
            var line = "${real(bin * distanceMax / 10)} ${real((bin + 1) * distanceMax / 10)} ${counts[bin]}"
            val length = counts[bin] * 50 / highest
            if (length > 0) line += " " + "#".repeat(length)
            lines.add(line)
        }
        return lines
    }
    fun gaps(tree: Tree): DoubleArray {
        val ordered = tree.subtreeHeights.sortedArray()
        return DoubleArray(settings.gapMaxK - 1) { position -> val k = position + 2; ordered[count - k] - ordered[count - k - 1] }
    }
    fun inconsistencyLine(tree: Tree, step: Int): String {
        val depth = settings.inconsistencyDepth.min(BigInteger.valueOf(count.toLong())).intValueExact()
        val sequence = tree.heightSequence(step, depth).toDoubleArray()
        val size = sequence.size
        val mean = Distances.sum(sequence) / size
        var deviation = 0.0
        var coefficient = 0.0
        if (size >= 2) {
            var squares = 0.0
            for (value in sequence) { val difference = value - mean; squares += difference * difference }
            deviation = sqrt(squares / (size - 1))
            coefficient = (tree.heights[step] - mean) / deviation
        }
        return "step ${step + 1} height ${real(tree.heights[step])} mean ${real(mean)} sd ${real(deviation)} count $size coefficient ${real(coefficient)}"
    }
    fun linkagePart(result: LinkageResult): List<String> {
        val tree = result.tree
        var leafPath = 0.0
        for (r in 0 until count - 1) leafPath += distances[tree.order[r]][tree.order[r + 1]]
        val inversions = (1 until tree.heights.size).filter { tree.heights[it] < tree.heights[it - 1] }
        val lines = mutableListOf("linkage ${result.method}", "cophenetic ${real(result.correlation)} leaf_path ${real(leafPath)}", "heights min ${real(tree.heights.min())} max ${real(tree.heights.max())} inversions ${inversions.size}")
        for (step in inversions) lines.add("inversion step ${step + 1} height ${real(tree.heights[step])} previous ${real(tree.heights[step - 1])}")
        val gaps = gaps(tree)
        var suggested = 2
        for (k in 3..settings.gapMaxK) if (fourDigit(gaps[k - 2]) > fourDigit(gaps[suggested - 2])) suggested = k
        lines.add("gaps ${reals(gaps)}"); lines.add("suggested_k $suggested")
        val joining = tree.joiningHeights()
        val late = (0 until count).sortedWith(compareByDescending<Int> { joining[it] }.thenBy { it }).take(settings.listSize)
        lines.add("late_joiners " + late.joinToString(" ") { "${idents[it]}:${real(joining[it])}" })
        val kinds = IntArray(3)
        for (merge in tree.merges) { val leaves = (if (merge.a < count) 1 else 0) + (if (merge.b < count) 1 else 0); kinds[2 - leaves]++ }
        lines.add("merges leaf_leaf ${kinds[0]} leaf_cluster ${kinds[1]} cluster_cluster ${kinds[2]} depth ${tree.depths[tree.root]}")
        val matches = matchCount(result.labelPartition)
        lines.add("label_cut k ${classes.size} purity $matches/$count ${real(matches.toDouble() / count)}")
        lines.add("inconsistency depth ${settings.inconsistencyDepth}")
        for (step in count - settings.inconsistencyCount - 1 until count - 1) lines.add(inconsistencyLine(tree, step))
        for (j in settings.cutHeights.indices) { val cut = result.heightCuts[j]; lines.add("cut height ${real(settings.cutHeights[j])} clusters ${cut.sizes.size} ${cut.text()}") }
        for (j in settings.cutCounts.indices) lines.add("cut k ${settings.cutCounts[j]} ${result.countCuts[j].text()}")
        return lines
    }
    fun resultOf(method: String): LinkageResult? = results.firstOrNull { it.method == method }
    fun mstPart(): List<String> {
        val single = resultOf("single")!!
        val edges = Agglomerative.minimumSpanningTree(distances)
        var total = 0.0
        for (edge in edges) total += edge.weight
        val weights = edges.map(Agglomerative.Edge::weight).sorted()
        var heightsMatch = true
        for (step in weights.indices) if (abs(weights[step] - single.tree.heights[step]) > 0.000000001) heightsMatch = false
        val linked = Array(count) { BooleanArray(count) }
        for (edge in edges) { linked[edge.parent][edge.child] = true; linked[edge.child][edge.parent] = true }
        val nearestEdges = (0 until count).count { linked[it][neighbors[it]] }
        val lines = mutableListOf("mst total ${real(total)} heights ${if (heightsMatch) "match" else "mismatch"} nn_edges $nearestEdges/$count")
        val ordered = edges.withIndex().sortedWith(compareBy<IndexedValue<Agglomerative.Edge>> { it.value.weight }.thenBy { it.index }).map { it.value }
        for (position in settings.cutCounts.indices) {
            val k = settings.cutCounts[position]
            val component = connectedComponents(count, ordered.take(count - k))
            val partition = single.countCuts[position].partition
            var match = true
            for (i in 0 until count) for (j in i + 1 until count) if ((component[i] == component[j]) != (partition[i] == partition[j])) match = false
            lines.add("mst partition k $k ${if (match) "match" else "mismatch"}")
        }
        return lines
    }
    fun comparePart(): List<String> {
        val lines = mutableListOf("compare linkage ${settings.compareLinkage} k ${classes.size}")
        for (type in Distances.types) {
            val delta = Distances.matrix(vectors, type)
            val tree = Tree(Agglomerative.cluster(delta, settings.compareLinkage), count)
            val partition = tree.cutInto(classes.size)
            val coefficient = Validation.correlation(pairValues(delta), pairValues(tree.cophenetic()))
            lines.add("metric $type cophenetic ${real(coefficient)} silhouette ${real(meanSilhouette(partition, delta))} ari ${ariText(labelAri(partition))}")
        }
        return lines
    }
    fun copheneticPart(): List<String> {
        val lines = mutableListOf("cophenetic_matrix", "linkage ${settings.linkages.joinToString(" ")}")
        for (first in results) lines.add("${first.method} ${reals(results.map { Validation.correlation(first.cophenetic, it.cophenetic) }.toDoubleArray())}")
        return lines
    }
    fun agreementPart(): List<String> {
        val lines = mutableListOf("agreement k ${classes.size}", "linkage ${settings.linkages.joinToString(" ")}")
        for (first in results) lines.add("${first.method} ${reals(results.map { partitionAri(first.labelPartition, it.labelPartition).value }.toDoubleArray())}")
        return lines
    }
    fun summaryPart(): List<String> {
        val ranking = results.withIndex().sortedWith(compareByDescending<IndexedValue<LinkageResult>> { fourDigit(it.value.correlation) }.thenBy { it.index })
        val lines = mutableListOf("summary", "cophenetic_ranking " + ranking.joinToString(" ") { it.value.method })
        for (position in settings.cutCounts.indices) {
            var best = results.first()
            for (result in results) if (result.countCuts[position].ari > best.countCuts[position].ari) best = result
            lines.add("best_ari k ${settings.cutCounts[position]} ${best.method} ${ariText(best.countCuts[position].ari)}")
        }
        for (result in results) {
            var best = 0
            for (position in 1 until settings.cutCounts.size) if (fourDigit(result.countCuts[position].silhouette!!) > fourDigit(result.countCuts[best].silhouette!!)) best = position
            lines.add("best_silhouette ${result.method} k ${settings.cutCounts[best]} ${real(result.countCuts[best].silhouette)}")
        }
        lines.add("selected ${chosen.method} k $kappa")
        return lines
    }
    fun validationReport(): List<String> {
        val parts = mutableListOf(dataPart(), correlationPart(), histogramPart())
        for (result in results) parts.add(linkagePart(result))
        if (resultOf("single") != null) parts.add(mstPart())
        parts.addAll(listOf(comparePart(), copheneticPart(), agreementPart(), summaryPart()))
        return joinParts(parts)
    }
    fun separation(first: List<Int>, second: List<Int>): Double {
        var best = Double.POSITIVE_INFINITY
        for (i in first) for (j in second) best = min(best, distances[i][j])
        return best
    }
    fun clusterLines(g: Int): List<String> {
        val group = members[g]
        val size = group.size
        val majorityClass = majority[g]
        val majorityCount = table[g][majorityClass]
        var silhouette = 0.0
        for (i in group) silhouette += silhouettes[i]
        silhouette /= size
        val averages = DoubleArray(featureNames.size) { f -> var total = 0.0; for (i in group) total += raw[i][f]; total / size }
        var medoid = -1
        var medoidSum = 0.0
        for (i in group) {
            var total = 0.0
            for (j in group) total += distances[i][j]
            if (medoid < 0 || total < medoidSum) { medoid = i; medoidSum = total }
        }
        var widestFirst = -1
        var widestSecond = -1
        for (position in group.indices) for (later in position + 1 until group.size) {
            val i = group[position]
            val j = group[later]
            if (widestFirst < 0 || distances[i][j] > distances[widestFirst][widestSecond]) { widestFirst = i; widestSecond = j }
        }
        val diameter = if (widestFirst < 0) "0.0000 - -" else pairText(widestFirst, widestSecond)
        var nearest = -1
        var nearestSeparation = 0.0
        for (h in 0 until kappa) if (h != g) {
            val value = separation(group, members[h])
            if (nearest < 0 || value < nearestSeparation) { nearest = h; nearestSeparation = value }
        }
        return listOf("cluster ${g + 1} size $size silhouette ${real(silhouette)} majority ${classes[majorityClass]} purity $majorityCount/$size ${real(majorityCount.toDouble() / size)}",
            "  mean ${reals(averages)}", "  medoid ${idents[medoid]} diameter $diameter nearest ${nearest + 1} separation ${real(nearestSeparation)}")
    }
    fun selectionPart(): List<String> {
        val lines = mutableListOf("selected linkage ${chosen.method} k $kappa ari ${ariText(selectedCut.ari)} silhouette ${real(selectedCut.silhouette)}")
        for (g in 0 until kappa) lines.addAll(clusterLines(g))
        return lines
    }
    fun centroidPart(): List<String> {
        val centers = centroids(selected)
        val lines = mutableListOf("centroid_distances")
        for (g in centers.indices) lines.add("${g + 1} ${reals(DoubleArray(centers.size) { h -> sqrt(Distances.squared(centers[g], centers[h])) })}")
        return lines
    }
    fun profilePart(): List<String> {
        val nameWidth = featureNames.maxOf(String::length)
        val lines = mutableListOf("profile_bars")
        for (g in 0 until kappa) {
            val group = members[g]
            lines.add("cluster ${g + 1}")
            for (f in featureNames.indices) {
                var total = 0.0
                for (i in group) total += (raw[i][f] - means[f]) / deviations[f]
                val zeta = total / group.size
                val length = min(10, floor(abs(zeta) * 4).toInt())
                val bar = "#".repeat(length)
                val blank = " ".repeat(10)
                val left = if (zeta < 0) " ".repeat(10 - length) + bar else blank
                val right = if (zeta < 0) blank else bar + " ".repeat(10 - length)
                lines.add("${featureNames[f].padEnd(nameWidth)} $left|$right ${real(zeta)}")
            }
        }
        return lines
    }
    fun contingencyPart(): List<String> {
        val lines = mutableListOf("contingency", "cluster ${classes.joinToString(" ")} total")
        val totals = IntArray(classes.size)
        for (g in table.indices) {
            var total = 0
            for (t in table[g].indices) { total += table[g][t]; totals[t] += table[g][t] }
            lines.add("${g + 1} ${integers(table[g])} $total")
        }
        val matches = matchCount(selected)
        lines.add("total ${integers(totals)} $count"); lines.add("purity $matches/$count ${real(matches.toDouble() / count)}")
        return lines
    }
    fun misplacedPart(): List<String> {
        val lines = mutableListOf("misplaced")
        var misplaced = 0
        for (i in 0 until count) if (targets[i] != majority[selected[i] - 1]) {
            misplaced++
            lines.add("${idents[i]} label ${labels[i]} cluster ${selected[i]} majority ${classes[majority[selected[i] - 1]]}")
        }
        lines.add("count $misplaced")
        return lines
    }
    fun weakestPart(): List<String> {
        val order = (0 until count).sortedWith(compareBy<Int> { silhouettes[it] }.thenBy { it }).take(settings.listSize)
        val lines = mutableListOf("weakest")
        for (i in order) lines.add("${idents[i]} label ${labels[i]} cluster ${selected[i]} silhouette ${real(silhouettes[i])}")
        return lines
    }
    fun featurePart(): List<String> {
        val ratios = DoubleArray(featureNames.size)
        for (f in ratios.indices) {
            var overall = 0.0
            for (vector in vectors) overall += vector[f]
            overall /= count
            val averages = DoubleArray(kappa)
            for (g in 0 until kappa) { var total = 0.0; for (i in members[g]) total += vectors[i][f]; averages[g] = total / members[g].size }
            var between = 0.0
            for (g in 0 until kappa) { val difference = averages[g] - overall; between += members[g].size * difference * difference }
            var within = 0.0
            for (i in 0 until count) { val difference = vectors[i][f] - averages[selected[i] - 1]; within += difference * difference }
            ratios[f] = (between / (kappa - 1)) / (within / (count - kappa))
        }
        val ranking = ratios.indices.sortedWith(compareByDescending<Int> { fourDigit(ratios[it]) }.thenBy { it })
        val lines = mutableListOf("features")
        for ((rank, f) in ranking.withIndex()) lines.add("${rank + 1} ${featureNames[f]} f_ratio ${real(ratios[f])}")
        return lines
    }
    fun classCounts(tree: Tree, node: Int): String {
        val counts = IntArray(classes.size)
        for (i in tree.members[node]) counts[targets[i]]++
        return counts.joinToString("/")
    }
    fun topMergesPart(): List<String> {
        val tree = chosen.tree
        val lines = mutableListOf("top_merges")
        for (step in count - settings.inconsistencyCount - 1 until count - 1) {
            val merge = tree.merges[step]
            lines.add("step ${step + 1} height ${real(merge.height)} a ${merge.a} ${tree.members[merge.a].size} ${classCounts(tree, merge.a)} b ${merge.b} ${tree.members[merge.b].size} ${classCounts(tree, merge.b)}")
        }
        return lines
    }
    fun dropFeaturePart(): List<String> {
        val lines = mutableListOf("drop_feature")
        for (f in featureNames.indices) {
            val reduced = vectors.map { vector -> vector.filterIndexed { index, _ -> index != f }.toDoubleArray() }.toTypedArray()
            val partition = Tree(Agglomerative.cluster(Distances.matrix(reduced, settings.distance), chosen.method), count).cutInto(kappa)
            lines.add("${featureNames[f]} ari_selected ${ariText(partitionAri(partition, selected))} ari_labels ${ariText(labelAri(partition))}")
        }
        return lines
    }
    fun nearestCenter(vector: DoubleArray, centers: Array<DoubleArray>): Int {
        var best = 0
        var bestValue = Distances.squared(vector, centers[0])
        for (g in 1 until centers.size) { val value = Distances.squared(vector, centers[g]); if (value < bestValue) { best = g; bestValue = value } }
        return best + 1
    }
    fun refinementPart(): List<String> {
        val centers = centroids(selected)
        var previous = selected
        var iterations = settings.refineIterations
        for (t in 1..settings.refineIterations) {
            val assignment = vectors.map { nearestCenter(it, centers) }.toIntArray()
            if (assignment.contentEquals(previous)) { iterations = t; break }
            val groups = clusterMembers(assignment, kappa)
            for (g in 0 until kappa) if (groups[g].isNotEmpty()) centers[g] = centroid(groups[g].map { vectors[it] }.toTypedArray())
            previous = assignment
        }
        val refined = previous
        val changed = (0 until count).count { selected[it] != refined[it] }
        val sizes = clusterMembers(refined, kappa).map { it.size }.toIntArray()
        return listOf("refinement max_iterations ${settings.refineIterations}",
            "iterations $iterations changed $changed wss ${real(withinSum(selected))} -> ${real(withinSum(refined))}",
            "sizes ${integers(sizes)} silhouette ${real(meanSilhouette(refined, distances))}",
            "ari_selected ${ariText(partitionAri(refined, selected))} ari_labels ${ariText(labelAri(refined))}")
    }
    fun jaccard(samplePartition: IntArray, restricted: IntArray): DoubleArray {
        val counts = Validation.contingency(restricted.map { it - 1 }.toIntArray(), samplePartition.map { it - 1 }.toIntArray(), kappa, samplePartition.max())
        val columns = IntArray(counts[0].size)
        for (row in counts) for (h in row.indices) columns[h] += row[h]
        val values = DoubleArray(kappa)
        for (g in 0 until kappa) {
            val size = counts[g].sum()
            if (size == 0) continue
            var bestNumerator = 0L
            var bestDenominator = 1L
            for (h in columns.indices) {
                val numerator = counts[g][h].toLong()
                val denominator = size + columns[h] - numerator
                if (numerator * bestDenominator > bestNumerator * denominator) { bestNumerator = numerator; bestDenominator = denominator }
            }
            values[g] = bestNumerator.toDouble() / bestDenominator
        }
        return values
    }
    fun stabilityPart(): List<String> {
        val generator = Minstd(settings.seed)
        val size = count * settings.percent / 100
        var ariTotal = 0.0
        val jaccardTotals = DoubleArray(kappa)
        val lines = mutableListOf("stability replicates ${settings.replicates} percent ${settings.percent} seed ${settings.seed}")
        for (b in 1..settings.replicates) {
            val array = IntArray(count) { it }
            for (t in 0 until size) {
                val j = t + (generator.draw() % (count - t)).toInt()
                val old = array[t]; array[t] = array[j]; array[j] = old
            }
            val sample = array.copyOf(size).sortedArray()
            val delta = Array(size) { u -> DoubleArray(size) { w -> distances[sample[u]][sample[w]] } }
            val partition = Tree(Agglomerative.cluster(delta, chosen.method), size).cutInto(kappa)
            val restricted = sample.map { selected[it] }.toIntArray()
            val ari = partitionAri(partition, restricted)
            val jaccard = jaccard(partition, restricted)
            ariTotal += ari.value
            for (g in 0 until kappa) jaccardTotals[g] += jaccard[g]
            lines.add("replicate $b size $size ari ${ariText(ari)} jaccard ${reals(jaccard)}")
        }
        for (g in 0 until kappa) jaccardTotals[g] /= settings.replicates
        lines.add("mean_ari ${real(ariTotal / settings.replicates)}"); lines.add("mean_jaccard ${reals(jaccardTotals)}")
        return lines
    }
    fun distanceMapPart(): List<String> {
        val frame = "+" + "-".repeat(count) + "+"
        val lines = mutableListOf("distance_map ${chosen.method}", frame)
        for (u in chosen.tree.order) lines.add(buildString {
            append('|')
            for (w in chosen.tree.order) append("@%#*+=-:. "[histogramBin(distances[u][w], distanceMax)])
            append('|')
        })
        lines.add(frame)
        return lines
    }
    fun profilesReport(): List<String> = joinParts(listOf(selectionPart(), centroidPart(), profilePart(), contingencyPart(), misplacedPart(), weakestPart(), featurePart(), topMergesPart(), dropFeaturePart(), refinementPart(), stabilityPart(), distanceMapPart()))
    fun writeOutputs() {
        Files.createDirectories(Path.of("output"))
        Dataset.write("linkage.csv", linkageTable()); Dataset.write("clusters.csv", clustersTable()); Dataset.write("dendrogram.txt", dendrogramReport())
        Dataset.write("trees.txt", treesReport()); Dataset.write("validation.txt", validationReport()); Dataset.write("profiles.txt", profilesReport())
    }
}

fun main() {
    Study(Dataset.read()).writeOutputs()
}
