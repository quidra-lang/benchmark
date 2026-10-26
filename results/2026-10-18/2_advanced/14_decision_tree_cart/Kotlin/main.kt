import java.io.File
import Evaluation.real
import Evaluation.ratio
import Evaluation.fraction
import kotlin.math.abs
import kotlin.math.round

class Minstd(seed: Long) {
    private var state = seed
    fun draw(): Long { state = 48271L * state % 2147483647L; return state }
}

class Condition(val attribute: Attribute) {
    private var lower = -1
    private var upper = Int.MAX_VALUE
    private var equal = -1
    private val excluded = sortedSetOf<Int>()
    fun add(split: Split, left: Boolean) {
        if (attribute.integer) {
            if (left) upper = minOf(upper, split.point) else lower = maxOf(lower, split.point)
        } else if (left) equal = split.point else excluded += split.point
    }
    fun text(): String {
        val name = attribute.name
        if (attribute.integer) {
            if (lower >= 0 && upper < Int.MAX_VALUE) return "${Split.halfText(lower)} < $name <= ${Split.halfText(upper)}"
            return if (lower >= 0) "$name > ${Split.halfText(lower)}" else "$name <= ${Split.halfText(upper)}"
        }
        if (equal >= 0) return "$name = ${attribute.values[equal]}"
        val names = excluded.map { attribute.values[it] }
        return if (names.size == 1) "$name != ${names.first()}" else "$name not in {${names.joinToString(",")}}"
    }
    fun holds(row: Row): Boolean {
        val value = row.value(attribute)
        if (value < 0) return false
        if (attribute.integer) return (lower < 0 || 2 * value > lower) && 2 * value <= upper
        return if (equal >= 0) value == equal else value !in excluded
    }
}
class Rule(val number: Int, val leaf: Node, val conditions: List<Condition>) {
    val general = conditions.toMutableList()
    val removed = mutableListOf<String>()
}
data class DepthResult(val depth: Int, val tree: PrunedTree, val cvCorrect: Int)
data class Bag(val tree: PrunedTree, val distinct: Int, val outOfBag: Int, val correct: Int)
data class Permutation(val attribute: Attribute, val counts: IntArray, val drop: Int)

fun sections(vararg sections: List<String>): List<String> = buildList {
    for (section in sections) { if (isNotEmpty()) add(""); addAll(section) }
}

class Analysis(private val data: Dataset) {
    private val attributes = data.attributes
    private val classes = data.classes
    private val settings = data.settings
    private val train = data.train
    private val validation = data.validation
    private val test = data.test
    private val builder = TreeBuilder(attributes, classes.size, settings)
    val grown = PrunedTree(builder.grow(train))
    private val pruning = Pruning.reducedError(grown.root, validation)
    val pruned = pruning.tree
    private val decisions = pruning.decisions
    private val rules = mutableListOf<Rule>()
    private val bounds = (0..settings.folds).map { it * train.size / settings.folds }
    private val foldTrees: List<PrunedTree>
    private val depthResults: List<DepthResult>
    private val selectedDepth: DepthResult
    private val sequence = Pruning.costComplexity(grown.root)
    private val selectedIndex: Int
    private val bags = mutableListOf<Bag>()
    private val oobVotes = Array(train.size) { IntArray(classes.size) }
    private val testVotes = Array(test.size) { IntArray(classes.size) }
    private val predictions: Map<String, List<Int>>

    init {
        collectRules(pruned.root, emptyList())
        rules.forEach { generalize(it) }
        foldTrees = (1..settings.folds).map { fold ->
            PrunedTree(builder.grow(train.take(bounds[fold - 1]) + train.drop(bounds[fold])))
        }
        depthResults = (0..settings.maxDepth).map { depth ->
            val correct = (1..settings.folds).sumOf { fold -> limited(foldTrees[fold - 1], depth).correct(foldRows(fold)) }
            DepthResult(depth, limited(grown, depth), correct)
        }
        selectedDepth = depthResults.minWith(compareByDescending<DepthResult> { it.cvCorrect }.thenBy { it.depth })
        selectedIndex = sequence.indices.minWith(compareBy<Int> { validationErrors(sequence[it].tree) }.thenByDescending { it })
        bagging()
        val models = mapOf("grown" to grown, "pruned" to pruned, "depth" to selectedDepth.tree,
            "cost_complexity" to sequence[selectedIndex].tree)
        predictions = models.mapValues { (_, tree) -> test.map { tree.predict(it) } } +
            ("bagging" to testVotes.map { Impurity.majority(it) })
    }

    private fun accuracy(tree: PrunedTree, rows: List<Row>): String = ratio(tree.correct(rows), rows.size)
    private fun validationErrors(tree: PrunedTree): Int = validation.size - tree.correct(validation)
    private fun foldRows(fold: Int): List<Row> = train.subList(bounds[fold - 1], bounds[fold])
    private fun limited(tree: PrunedTree, depth: Int): PrunedTree =
        PrunedTree(tree.root, tree.internalNodes().filter { it.depth == depth }.map { it.number }.toSet())

    private fun bagging() {
        val generator = Minstd(settings.bagSeed)
        repeat(settings.bagTrees) {
            val indices = List(train.size) { (generator.draw() % train.size).toInt() }
            val tree = PrunedTree(builder.grow(indices.map { train[it] }))
            val sampled = indices.toSet()
            var outOfBag = 0
            var correct = 0
            for (i in train.indices)
                if (i !in sampled) {
                    outOfBag++
                    val prediction = tree.predict(train[i])
                    oobVotes[i][prediction]++
                    if (prediction == train[i].label) correct++
                }
            bags += Bag(tree, sampled.size, outOfBag, correct)
            for (i in test.indices) testVotes[i][tree.predict(test[i])]++
        }
    }

    private fun collectRules(node: Node, steps: List<Pair<Split, Boolean>>) {
        if (pruned.isLeaf(node)) {
            val conditions = attributes.mapNotNull { attribute ->
                val related = steps.filter { it.first.attribute.index == attribute.index }
                if (related.isEmpty()) null else Condition(attribute).also { condition ->
                    related.forEach { (split, left) -> condition.add(split, left) }
                }
            }
            rules += Rule(rules.size + 1, node, conditions)
            return
        }
        val split = requireNotNull(node.split)
        collectRules(node.left, steps + (split to true))
        collectRules(node.right, steps + (split to false))
    }
    private fun coverage(conditions: List<Condition>, rows: List<Row>, label: Int): Pair<Int, Int> {
        val covered = rows.filter { row -> conditions.all { it.holds(row) } }
        return covered.count { it.label == label } to covered.size
    }
    private fun laplace(conditions: List<Condition>, label: Int): Fraction {
        val (hits, covered) = coverage(conditions, validation, label)
        return Fraction((hits + 1).toLong(), (covered + classes.size).toLong())
    }
    private fun generalize(rule: Rule) {
        while (rule.general.isNotEmpty()) {
            val current = laplace(rule.general, rule.leaf.prediction)
            var best: Fraction? = null
            var bestIndex = -1
            for (i in rule.general.indices) {
                val trial = rule.general.toMutableList().also { it.removeAt(i) }
                val value = laplace(trial, rule.leaf.prediction)
                if (best == null || value > best) { best = value; bestIndex = i }
            }
            if (current > requireNotNull(best)) return
            rule.removed += rule.general.removeAt(bestIndex).attribute.name
        }
    }
    private fun conditionsText(conditions: List<Condition>): String =
        if (conditions.isEmpty()) "true" else conditions.joinToString(" and ") { it.text() }

    private fun nodeLines(tree: PrunedTree, node: Node, condition: String, lines: MutableList<String>) {
        val line = "  ".repeat(node.depth) + "${node.number} $condition n ${node.size} counts ${node.counts.joinToString(" ")}"
        lines += line + if (tree.isLeaf(node)) " leaf ${classes[node.prediction]}" else ""
        if (!tree.isLeaf(node)) {
            val split = requireNotNull(node.split)
            nodeLines(tree, node.left, split.condition(true), lines)
            nodeLines(tree, node.right, split.condition(false), lines)
        }
    }
    fun treeLines(tree: PrunedTree): List<String> {
        val lines = mutableListOf<String>()
        nodeLines(tree, tree.root, "root", lines)
        lines += ""
        val nodes = tree.preorder()
        val leaves = tree.leaves()
        lines += "nodes ${nodes.size} leaves ${leaves.size} depth ${tree.depth()} errors ${ratio(tree.trainingErrors(), train.size)}"
        for (level in 0..tree.depth()) {
            val levelLeaves = leaves.filter { it.depth == level }
            lines += "level $level nodes ${nodes.count { it.depth == level }} leaves ${levelLeaves.size} rows ${levelLeaves.sumOf { it.size }} errors ${levelLeaves.sumOf { it.errors }}"
        }
        return lines
    }
    fun rootCandidates(): List<String> {
        val candidates = attributes.mapNotNull { builder.bestSplit(train, listOf(it)) }.sortedWith { first, second ->
            val comparison = second.quality().compareTo(first.quality())
            if (comparison != 0) comparison else first.split.attribute.index.compareTo(second.split.attribute.index)
        }
        val lines = mutableListOf("root candidates n ${train.size} counts ${grown.root.counts.joinToString(" ")}")
        for ((index, candidate) in candidates.withIndex()) {
            val value = candidate.quality()
            val gain = value.numerator.toDouble() / value.denominator / train.size -
                Impurity.squareSum(grown.root.counts).toDouble() / (train.size.toLong() * train.size)
            lines += "${index + 1} ${candidate.split.condition(true)} left ${candidate.leftSize} right ${candidate.rightSize} gain ${real(gain, 6)}"
        }
        return lines
    }
    fun surrogateLines(): List<String> = buildList {
        add("surrogates")
        for (node in grown.internalNodes()) {
            val listed = node.surrogates.joinToString(" ; ") {
                "${it.split.condition(true)} ${if (it.left) "left" else "right"} ${it.score}/${node.size}"
            }.ifEmpty { "none" }
            add("node ${node.number} split ${requireNotNull(node.split).condition(true)} default ${if (node.defaultLeft) "left" else "right"} surrogates $listed")
        }
    }
    fun prunedTreeFile(): List<String> {
        val lines = mutableListOf("reduced_error_pruning validation ${validation.size}")
        for (decision in decisions)
            lines += "node ${decision.node.number} depth ${decision.node.depth} rows ${decision.rows} leaf ${decision.leafError} subtree ${decision.subtreeError} ${if (decision.pruned) "pruned" else "kept"}"
        val count = decisions.count { it.pruned }
        lines += "examined ${decisions.size} pruned $count kept ${decisions.size - count}"
        return sections(lines, treeLines(pruned))
    }
    fun predictionsFile(): List<String> = buildList {
        add("id,predicted,actual,grown,leaf,path,missing")
        for (row in test) {
            val route = pruned.route(row)
            val path = route.path.joinToString("-") { it.number.toString() }
            val missing = route.steps.count { it.method != "primary" }
            add("${row.id},${classes[route.leaf.prediction]},${classes[row.label]},${classes[grown.predict(row)]},${route.leaf.number},$path,$missing")
        }
    }
    fun rulesFile(): List<String> {
        val original = mutableListOf("rules ${rules.size}")
        val generalized = mutableListOf("generalized ${rules.size}")
        val ruleNumbers = rules.associate { it.leaf.number to it.number }
        for (rule in rules) {
            val reached = test.filter { pruned.leafOf(it) === rule.leaf }
            val hits = reached.count { it.label == rule.leaf.prediction }
            original += "rule ${rule.number} node ${rule.leaf.number} if ${conditionsText(rule.conditions)} then ${classes[rule.leaf.prediction]} train ${ratio(rule.leaf.counts[rule.leaf.prediction], rule.leaf.size)} test ${ratio(hits, reached.size)}"
            val (validHits, validCovered) = coverage(rule.general, validation, rule.leaf.prediction)
            val (testHits, testCovered) = coverage(rule.general, test, rule.leaf.prediction)
            val removed = rule.removed.joinToString(",").ifEmpty { "none" }
            generalized += "general ${rule.number} if ${conditionsText(rule.general)} then ${classes[rule.leaf.prediction]} removed $removed laplace ${fraction(validHits + 1, validCovered + classes.size)} validation $validHits/$validCovered test $testHits/$testCovered"
        }
        val wrong = test.filter { pruned.predict(it) != it.label }
        val errors = mutableListOf("misclassified ${wrong.size}")
        for (row in wrong) {
            val route = pruned.route(row)
            val path = route.steps.joinToString("; ") { step ->
                requireNotNull(step.node.split).condition(step.left) + if (step.method == "primary") "" else " [${step.method}]"
            }.ifEmpty { "root" }
            errors += "${row.id} actual ${classes[row.label]} predicted ${classes[route.leaf.prediction]} rule ${ruleNumbers.getValue(route.leaf.number)} path $path"
        }
        return sections(original, generalized, errors)
    }

    private fun dataLines(): List<String> = buildList {
        add("data train ${train.size} validation ${validation.size} test ${test.size} attributes ${attributes.size} classes ${classes.size} target ${data.target}")
        val training = Impurity.counts(train, classes.size)
        val valid = Impurity.counts(validation, classes.size)
        val testing = Impurity.counts(test, classes.size)
        for (k in classes.indices) add("class ${classes[k]} train ${training[k]} validation ${valid[k]} test ${testing[k]}")
        add("missing validation ${validation.sumOf { it.missingCount() }} test ${test.sumOf { it.missingCount() }}")
        for (attribute in attributes)
            add("missing ${attribute.name} validation ${validation.count { it.value(attribute) < 0 }} test ${test.count { it.value(attribute) < 0 }}")
    }
    private fun summary(name: String, tree: PrunedTree): String =
        "$name nodes ${tree.preorder().size} leaves ${tree.leaves().size} depth ${tree.depth()} train ${accuracy(tree, train)} validation ${accuracy(tree, validation)} test ${accuracy(tree, test)}"
    private fun modelEvaluation(model: String): List<String> =
        Evaluation.classification("$model test", classes, test, predictions.getValue(model))
    private fun routingLines(): List<String> = buildList {
        val tallies = grown.preorder().associate { it.number to IntArray(3) }
        val methods = listOf("primary", "surrogate", "default")
        for (row in test) for (step in pruned.route(row).steps) tallies.getValue(step.node.number)[methods.indexOf(step.method)]++
        add("routing pruned test")
        for (node in pruned.internalNodes()) {
            val counts = tallies.getValue(node.number)
            add("node ${node.number} rows ${counts.sum()} primary ${counts[0]} surrogate ${counts[1]} default ${counts[2]}")
        }
        for (complete in listOf(true, false)) {
            val rows = test.filter { (it.missingCount() == 0) == complete }
            add("${if (complete) "complete" else "incomplete"} rows ${rows.size} correct ${accuracy(pruned, rows)}")
        }
    }
    private fun crossValidationLines(): List<String> = buildList {
        add("cross_validation folds ${settings.folds}")
        var total = 0
        for (fold in 1..settings.folds) {
            val rows = foldRows(fold)
            val tree = foldTrees[fold - 1]
            val correct = tree.correct(rows)
            total += correct
            add("fold $fold rows ${bounds[fold - 1] + 1}-${bounds[fold]} leaves ${tree.leaves().size} correct ${ratio(correct, rows.size)}")
        }
        add("cv accuracy ${ratio(total, train.size)}")
    }
    private fun depthLines(): List<String> = buildList {
        add("depth_selection")
        for (result in depthResults)
            add("depth ${result.depth} leaves ${result.tree.leaves().size} cv ${ratio(result.cvCorrect, train.size)} train ${accuracy(result.tree, train)} validation ${accuracy(result.tree, validation)} test ${accuracy(result.tree, test)}")
        add("selected depth ${selectedDepth.depth} leaves ${selectedDepth.tree.leaves().size} test ${accuracy(selectedDepth.tree, test)}")
    }
    private fun complexityLines(): List<String> = buildList {
        add("cost_complexity")
        for ((index, step) in sequence.withIndex())
            add("subtree $index alpha ${fraction(step.alpha.numerator, step.alpha.denominator * train.size, 6)} leaves ${step.tree.leaves().size} train_errors ${step.tree.trainingErrors()} validation_errors ${validationErrors(step.tree)}")
        val tree = sequence[selectedIndex].tree
        add("selected subtree $selectedIndex leaves ${tree.leaves().size} test ${accuracy(tree, test)}")
    }
    private fun baggingLines(): List<String> = buildList {
        add("bagging trees ${settings.bagTrees} seed ${settings.bagSeed}")
        for ((index, bag) in bags.withIndex())
            add("bag ${index + 1} distinct ${bag.distinct} leaves ${bag.tree.leaves().size} oob ${ratio(bag.correct, bag.outOfBag)}")
        var voted = 0
        var hits = 0
        for (i in train.indices)
            if (oobVotes[i].sum() > 0) {
                voted++
                if (Impurity.majority(oobVotes[i]) == train[i].label) hits++
            }
        add("oob accuracy ${ratio(hits, voted)} unvoted ${train.size - voted}")
        addAll(modelEvaluation("bagging"))
    }
    private fun mcnemarLines(): List<String> = buildList {
        add("mcnemar pruned test")
        for (model in listOf("grown", "depth", "cost_complexity", "bagging")) {
            var b = 0
            var c = 0
            for (i in test.indices) {
                val first = predictions.getValue("pruned")[i] == test[i].label
                val second = predictions.getValue(model)[i] == test[i].label
                if (first && !second) b++
                if (second && !first) c++
            }
            val difference = maxOf(0, abs(b - c) - 1).toLong()
            val squared = difference * difference
            val statistic = if (b + c == 0) "0/1 0.0000" else fraction(squared, (b + c).toLong())
            add("versus $model b $b c $c statistic $statistic significant ${if (1000 * squared > 3841L * (b + c)) "yes" else "no"}")
        }
    }
    private fun scores(model: String): List<List<Fraction>> = test.indices.map { i ->
        val leaf = if (model == "bagging") null else (if (model == "grown") grown else pruned).leafOf(test[i])
        classes.indices.map { k -> if (leaf == null) Fraction(testVotes[i][k].toLong(), settings.bagTrees.toLong())
            else Fraction(leaf.counts[k].toLong(), leaf.size.toLong()) }
    }
    private fun aucLines(): List<String> = buildList {
        for (model in listOf("grown", "pruned", "bagging")) {
            val scores = scores(model)
            val parts = mutableListOf("auc", model)
            var total = 0.0
            var available = 0
            for (k in classes.indices) {
                var wins = 0L
                var positive = 0L
                for (i in test.indices)
                    if (test[i].label == k) {
                        positive++
                        for (j in test.indices)
                            if (test[j].label != k) {
                                val comparison = scores[i][k].compareTo(scores[j][k])
                                if (comparison > 0) wins += 2 else if (comparison == 0) wins++
                            }
                    }
                val denominator = 2 * positive * (test.size - positive)
                parts += classes[k]
                parts += fraction(wins, denominator)
                if (denominator > 0) { total += wins.toDouble() / denominator; available++ }
            }
            parts += "macro"
            parts += if (available == 0) "-" else real(total / available)
            add(parts.joinToString(" "))
        }
    }
    private fun learningLines(): List<String> = buildList {
        add("learning_curve")
        for (size in settings.curve) {
            val grown = PrunedTree(builder.grow(train.take(size)))
            val pruned = Pruning.reducedError(grown.root, validation).tree
            add("size $size grown leaves ${grown.leaves().size} test ${accuracy(grown, test)} pruned leaves ${pruned.leaves().size} test ${accuracy(pruned, test)}")
        }
    }
    fun evaluationFile(): List<String> = sections(dataLines(), listOf(summary("grown", grown), summary("pruned", pruned)),
        modelEvaluation("grown"), modelEvaluation("pruned"), routingLines(), crossValidationLines(), depthLines(),
        complexityLines(), baggingLines(), mcnemarLines(), aucLines(), learningLines())

    fun impurityLines(title: String, tree: PrunedTree): List<String> = buildList {
        val importance = DoubleArray(attributes.size)
        val splits = IntArray(attributes.size)
        for (node in tree.internalNodes()) {
            val index = requireNotNull(node.split).attribute.index
            importance[index] += Impurity.decrease(node.counts, node.left.counts, node.right.counts)
            splits[index]++
        }
        var total = 0.0
        for (value in importance) total += value
        val shares = importance.map { if (total == 0.0) 0.0 else it / total }
        val order = attributes.indices.sortedWith(compareByDescending<Int> { round(shares[it] * 10000) }.thenBy { it })
        add("impurity $title")
        for ((rank, index) in order.withIndex())
            add("${rank + 1} ${attributes[index].name} decrease ${real(importance[index] / train.size)} share ${real(shares[index])} splits ${splits[index]}")
    }
    fun permutationLines(): List<String> {
        val generator = Minstd(settings.permutationSeed)
        val repeats = settings.repeats
        val base = pruned.correct(test)
        val results = attributes.map { attribute ->
            val counts = IntArray(repeats)
            repeat(repeats) { repeat ->
                val values = test.map { it.value(attribute) }.toMutableList()
                for (position in test.size downTo 2) {
                    val other = (generator.draw() % position).toInt()
                    val temporary = values[position - 1]
                    values[position - 1] = values[other]
                    values[other] = temporary
                }
                counts[repeat] = pruned.correct(test.mapIndexed { index, row -> row.withValue(attribute, values[index]) })
            }
            Permutation(attribute, counts, repeats * base - counts.sum())
        }.sortedWith(compareByDescending<Permutation> { it.drop }.thenBy { it.attribute.index })
        val lines = mutableListOf("permutation pruned test repeats $repeats seed ${settings.permutationSeed} base ${ratio(base, test.size)}")
        for ((index, result) in results.withIndex())
            lines += "${index + 1} ${result.attribute.name} correct ${result.counts.joinToString(" ")} drop ${fraction(result.drop, repeats * test.size)}"
        return lines
    }
}

fun main() {
    val analysis = Analysis(Dataset.load("input"))
    File("output").mkdirs()
    val files = mapOf(
        "tree.txt" to sections(analysis.rootCandidates(), analysis.treeLines(analysis.grown), analysis.surrogateLines()),
        "pruned_tree.txt" to analysis.prunedTreeFile(), "predictions.csv" to analysis.predictionsFile(),
        "rules.txt" to analysis.rulesFile(), "evaluation.txt" to analysis.evaluationFile(),
        "importance.txt" to sections(analysis.impurityLines("grown", analysis.grown), analysis.impurityLines("pruned", analysis.pruned), analysis.permutationLines())
    )
    for ((name, lines) in files) File("output", name).writeText(lines.joinToString("\n") + "\n", Charsets.US_ASCII)
}
