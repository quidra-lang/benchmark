import java.util.Locale
import kotlin.math.abs

data class Step(val node: Node, val left: Boolean, val method: String)
data class Route(val path: List<Node>, val steps: List<Step>) {
    val leaf: Node get() = path.last()
}
class PrunedTree(val root: Node, cut: Set<Int> = emptySet()) {
    val cut = cut.toSet()
    fun isLeaf(node: Node): Boolean = node.split == null || node.number in cut
    fun preorder(start: Node = root): List<Node> {
        val nodes = mutableListOf<Node>()
        val pending = mutableListOf(start)
        while (pending.isNotEmpty()) {
            val node = pending.removeAt(pending.lastIndex)
            nodes += node
            if (!isLeaf(node)) { pending += node.right; pending += node.left }
        }
        return nodes
    }
    fun leaves(start: Node = root): List<Node> = preorder(start).filter { isLeaf(it) }
    fun internalNodes(): List<Node> = preorder().filter { !isLeaf(it) }
    fun depth(): Int = leaves().maxOf { it.depth }
    fun trainingErrors(): Int = leaves().sumOf { it.errors }
    fun route(row: Row): Route {
        var node = root
        val path = mutableListOf(node)
        val steps = mutableListOf<Step>()
        while (!isLeaf(node)) {
            val split = requireNotNull(node.split)
            var left = node.defaultLeft
            var method = "default"
            val value = row.value(split.attribute)
            if (value >= 0) { left = split.goesLeft(value); method = "primary" }
            else for (surrogate in node.surrogates)
                if (row.value(surrogate.split.attribute) >= 0) {
                    left = surrogate.goesLeft(row.value(surrogate.split.attribute))
                    method = "surrogate"
                    break
                }
            steps += Step(node, left, method)
            node = if (left) node.left else node.right
            path += node
        }
        return Route(path, steps)
    }
    fun leafOf(row: Row): Node = route(row).leaf
    fun predict(row: Row): Int = leafOf(row).prediction
    fun correct(rows: List<Row>): Int = rows.count { predict(it) == it.label }
}
object Evaluation {
    fun real(value: Double, places: Int = 4): String {
        val text = String.format(Locale.ROOT, "%.${places}f", value)
        return if (text == "-0." + "0".repeat(places)) text.drop(1) else text
    }
    fun ratio(numerator: Long, denominator: Long): String = if (denominator == 0L) "0/0 -"
        else "$numerator/$denominator ${real(numerator.toDouble() / denominator)}"
    fun ratio(numerator: Int, denominator: Int): String = ratio(numerator.toLong(), denominator.toLong())
    private fun gcd(first: Long, second: Long): Long {
        var a = abs(first)
        var b = second
        while (b != 0L) { val next = a % b; a = b; b = next }
        return a
    }
    fun fraction(numerator: Long, denominator: Long, places: Int = 4): String {
        if (denominator == 0L) return "- -"
        val divisor = gcd(numerator, denominator)
        return "${numerator / divisor}/${denominator / divisor} ${real(numerator.toDouble() / denominator, places)}"
    }
    fun fraction(numerator: Int, denominator: Int): String = fraction(numerator.toLong(), denominator.toLong())
    fun classification(title: String, classes: List<String>, rows: List<Row>, predictions: List<Int>): List<String> {
        val size = classes.size
        val matrix = Array(size) { IntArray(size) }
        for (i in rows.indices) matrix[rows[i].label][predictions[i]]++
        val correct = classes.indices.sumOf { matrix[it][it] }
        val lines = mutableListOf("confusion $title correct $correct/${rows.size} accuracy ${fraction(correct, rows.size)}",
            "actual\\predicted " + classes.joinToString(" "))
        for (i in classes.indices) lines += classes[i] + " " + matrix[i].joinToString(" ")
        var total = 0.0
        var available = 0
        for (i in classes.indices) {
            val hits = matrix[i][i]
            val predicted = matrix.sumOf { it[i] }
            val support = matrix[i].sum()
            if (predicted + support > 0) { total += (2 * hits).toDouble() / (predicted + support); available++ }
            lines += "class ${classes[i]} precision ${fraction(hits, predicted)} recall ${fraction(hits, support)} f1 ${fraction(2 * hits, predicted + support)} support $support"
        }
        lines += "macro_f1 ${real(total / available)}"
        return lines
    }
}
