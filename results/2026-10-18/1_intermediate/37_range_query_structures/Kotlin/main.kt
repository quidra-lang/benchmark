import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

private enum class Kind {
    SEG,
    LAZY,
    FEN,
    RFEN,
    SPARSE,
    SQRT,
    PERSIST,
    GRID,
}

private enum class Operation {
    SUM,
    MIN,
    MAX,
    GCD;

    fun combine(a: Long, b: Long): Long =
        when (this) {
            SUM -> a + b
            MIN -> min(a, b)
            MAX -> max(a, b)
            GCD -> gcd(a, b)
        }

    fun leaf(value: Long) = if (this == GCD) abs(value) else value
}

private class CommandError(message: String) : RuntimeException(message)

private fun fail(message: String): Nothing = throw CommandError(message)

private fun gcd(a: Long, b: Long): Long {
    var x = abs(a)
    var y = abs(b)
    while (y != 0L) {
        val rest = x % y
        x = y
        y = rest
    }
    return x
}

private fun isqrt(n: Int): Int {
    var root = 1
    while ((root + 1) * (root + 1) <= n) root++
    return root
}

private data class Span(val l: Int, val r: Int) {
    val length
        get() = r - l + 1

    val middle
        get() = (l + r) / 2

    val leaf
        get() = l == r

    fun covers(other: Span) = l <= other.l && other.r <= r

    fun left() = Span(l, middle)

    fun right() = Span(middle + 1, r)
}

private fun whole(n: Int) = Span(0, n - 1)

private data class Report(val text: String, val values: LongArray)

private data class Answer(val value: Long, val visited: Int) {
    fun report() = Report("sum=$value visited=$visited", longArrayOf(value))
}

private data class Aggregate(val sum: Long, val min: Long, val max: Long) {
    fun merge(other: Aggregate) =
        Aggregate(sum + other.sum, minOf(min, other.min), maxOf(max, other.max))

    fun add(value: Long, length: Int) = Aggregate(sum + value * length, min + value, max + value)

    fun text() = "sum=$sum min=$min max=$max"

    companion object {
        fun single(value: Long) = Aggregate(value, value, value)
    }
}

private class Layout(n: Int) {
    val spans = arrayOfNulls<Span>(4 * n)
    val count = 2 * n - 1
    var maxNode = 0
        private set

    init {
        build(1, whole(n))
    }

    private fun build(node: Int, span: Span) {
        spans[node] = span
        maxNode = max(maxNode, node)
        if (!span.leaf) {
            build(2 * node, span.left())
            build(2 * node + 1, span.right())
        }
    }

    operator fun get(node: Int) = spans[node]!!
}

private class Segment(values: LongArray, val op: Operation) {
    val shape = Layout(values.size)
    val tree = LongArray(4 * values.size)

    init {
        build(1, values)
    }

    private fun build(node: Int, values: LongArray) {
        val span = shape[node]
        if (span.leaf) tree[node] = op.leaf(values[span.l])
        else {
            build(2 * node, values)
            build(2 * node + 1, values)
            pull(node)
        }
    }

    private fun pull(node: Int) {
        tree[node] = op.combine(tree[2 * node], tree[2 * node + 1])
    }

    private fun queryAt(node: Int, wanted: Span): Answer {
        val span = shape[node]
        if (wanted.covers(span)) return Answer(tree[node], 1)
        val answer =
            when {
                wanted.r <= span.middle -> queryAt(2 * node, wanted)
                wanted.l > span.middle -> queryAt(2 * node + 1, wanted)
                else -> {
                    val left = queryAt(2 * node, wanted)
                    val right = queryAt(2 * node + 1, wanted)
                    Answer(op.combine(left.value, right.value), left.visited + right.visited)
                }
            }
        return answer.copy(visited = answer.visited + 1)
    }

    fun query(wanted: Span): Report {
        val answer = queryAt(1, wanted)
        return Report(
            "${op.name.lowercase()}=${answer.value} visited=${answer.visited}",
            longArrayOf(answer.value),
        )
    }

    fun update(index: Int, value: Long, node: Int = 1): Int {
        val span = shape[node]
        if (span.leaf) {
            tree[node] = op.leaf(value)
            return 1
        }
        val visited = update(index, value, if (index <= span.middle) 2 * node else 2 * node + 1)
        pull(node)
        return visited + 1
    }

    fun dump(): List<String> = buildList {
        add("SEG DUMP $op nodes=${shape.count}")
        for (node in 1..shape.maxNode) {
            val span = shape.spans[node] ?: continue
            add("NODE $node ${span.l} ${span.r} ${tree[node]}")
        }
    }
}

private class Counts(var visited: Int = 0, var covered: Int = 0, var pushes: Int = 0) {
    override fun toString() = "visited=$visited covered=$covered pushes=$pushes"
}

private class LazyNode(
    var value: Aggregate = Aggregate.single(0),
    var assign: Long? = null,
    var add: Long = 0,
)

private data class LazyAnswer(val value: Aggregate, val visited: Int, val pushes: Int)

private class Lazy(values: LongArray) {
    val shape = Layout(values.size)
    val nodes = Array(4 * values.size) { LazyNode() }

    init {
        build(1, values)
    }

    private fun build(node: Int, values: LongArray) {
        val span = shape[node]
        if (span.leaf) nodes[node].value = Aggregate.single(values[span.l])
        else {
            build(2 * node, values)
            build(2 * node + 1, values)
            pull(node)
        }
    }

    private fun pull(node: Int) {
        nodes[node].value = nodes[2 * node].value.merge(nodes[2 * node + 1].value)
    }

    private fun apply(node: Int, value: Long, assignment: Boolean) {
        val span = shape[node]
        val target = nodes[node]
        target.value =
            if (assignment) Aggregate(value * span.length, value, value)
            else target.value.add(value, span.length)
        if (!span.leaf) {
            if (assignment) {
                target.assign = value
                target.add = 0
            } else target.add += value
        }
    }

    private fun push(node: Int): Int {
        val source = nodes[node]
        val assignment = source.assign
        if (assignment == null && source.add == 0L) return 0
        for (child in 2 * node..2 * node + 1) {
            if (assignment != null) apply(child, assignment, true)
            if (source.add != 0L) apply(child, source.add, false)
        }
        source.assign = null
        source.add = 0
        return 1
    }

    fun update(wanted: Span, value: Long, assignment: Boolean): Counts {
        val counts = Counts()
        fun visit(node: Int) {
            counts.visited++
            val span = shape[node]
            if (wanted.covers(span)) {
                counts.covered++
                apply(node, value, assignment)
                return
            }
            counts.pushes += push(node)
            if (wanted.l <= span.middle) visit(2 * node)
            if (wanted.r > span.middle) visit(2 * node + 1)
            pull(node)
        }
        visit(1)
        return counts
    }

    private fun queryAt(node: Int, wanted: Span): LazyAnswer {
        val span = shape[node]
        if (wanted.covers(span)) return LazyAnswer(nodes[node].value, 1, 0)
        val pushes = push(node)
        val answer =
            when {
                wanted.r <= span.middle -> queryAt(2 * node, wanted)
                wanted.l > span.middle -> queryAt(2 * node + 1, wanted)
                else -> {
                    val left = queryAt(2 * node, wanted)
                    val right = queryAt(2 * node + 1, wanted)
                    LazyAnswer(
                        left.value.merge(right.value),
                        left.visited + right.visited,
                        left.pushes + right.pushes,
                    )
                }
            }
        return answer.copy(visited = answer.visited + 1, pushes = answer.pushes + pushes)
    }

    fun query(wanted: Span): Report {
        val answer = queryAt(1, wanted)
        val value = answer.value
        return Report(
            "${value.text()} visited=${answer.visited} pushes=${answer.pushes}",
            longArrayOf(value.sum, value.min, value.max),
        )
    }

    fun dump(): List<String> = buildList {
        add("LAZY DUMP nodes=${shape.count}")
        for (node in 1..shape.maxNode) {
            val span = shape.spans[node] ?: continue
            val item = nodes[node]
            add(
                "NODE $node ${span.l} ${span.r} ${item.value.text()} assign=${item.assign ?: "-"} add=${item.add}",
            )
        }
    }
}

private class Bit(n: Int) {
    val tree = LongArray(n + 1)

    constructor(values: LongArray) : this(values.size) {
        values.forEachIndexed { i, value -> add(i + 1, value) }
    }

    fun add(position: Int, value: Long): Int {
        var p = position
        var visited = 0
        while (p < tree.size) {
            tree[p] += value
            visited++
            p += p and -p
        }
        return visited
    }

    fun prefix(position: Int): Answer {
        var p = position
        var sum = 0L
        var visited = 0
        while (p > 0) {
            sum += tree[p]
            visited++
            p -= p and -p
        }
        return Answer(sum, visited)
    }

    fun query(span: Span): Answer {
        val a = prefix(span.r + 1)
        val b = prefix(span.l)
        return Answer(a.value - b.value, a.visited + b.visited)
    }

    fun lower(target: Long): Answer {
        val n = tree.size - 1
        var position = 0
        var visited = 0
        var rest = target
        var step = Integer.highestOneBit(n)
        while (step > 0) {
            if (position + step <= n) {
                val value = tree[position + step]
                visited++
                if (value < rest) {
                    rest -= value
                    position += step
                }
            }
            step /= 2
        }
        return Answer(if (position < n) position.toLong() else -1, visited)
    }

    fun dump(name: String) = "$name ${tree.drop(1).joinToString(" ")}"
}

private class Fenwick(values: LongArray) {
    val values = values.copyOf()
    val bit = Bit(values)
}

private class RangeFenwick(values: LongArray) {
    val first = Bit(values.size)
    val second = Bit(values.size)

    init {
        for (i in values.indices) {
            val difference = values[i] - if (i == 0) 0 else values[i - 1]
            first.add(i + 1, difference)
            second.add(i + 1, difference * i)
        }
    }

    fun add(span: Span, value: Long): Int {
        var visited = first.add(span.l + 1, value)
        visited += first.add(span.r + 2, -value)
        visited += second.add(span.l + 1, value * span.l)
        visited += second.add(span.r + 2, -value * (span.r + 1))
        return visited
    }

    private fun prefix(position: Int): Answer {
        val a = first.prefix(position)
        val b = second.prefix(position)
        return Answer(position * a.value - b.value, a.visited + b.visited)
    }

    fun query(span: Span): Answer {
        val a = prefix(span.r + 1)
        val b = prefix(span.l)
        return Answer(a.value - b.value, a.visited + b.visited)
    }
}

private class Sparse(contents: LongArray) {
    val values = contents.copyOf()
    val minimum = mutableListOf(IntArray(values.size) { it })
    val maximum = mutableListOf(IntArray(values.size) { it })
    var entries = values.size
        private set

    init {
        var level = 1
        while ((1 shl level) <= values.size) {
            val length = values.size - (1 shl level) + 1
            val half = 1 shl (level - 1)
            val low =
                IntArray(length) {
                    select(minimum[level - 1][it], minimum[level - 1][it + half], true)
                }
            val high =
                IntArray(length) {
                    select(maximum[level - 1][it], maximum[level - 1][it + half], false)
                }
            minimum.add(low)
            maximum.add(high)
            entries += length
            level++
        }
    }

    private fun select(a: Int, b: Int, minimum: Boolean) =
        if (if (minimum) values[a] <= values[b] else values[a] >= values[b]) a else b

    fun query(span: Span): Report {
        val level = 31 - Integer.numberOfLeadingZeros(span.length)
        val end = span.r - (1 shl level) + 1
        val low = select(minimum[level][span.l], minimum[level][end], true)
        val high = select(maximum[level][span.l], maximum[level][end], false)
        return Report(
            "min=${values[low]} minpos=$low max=${values[high]} maxpos=$high level=$level",
            longArrayOf(values[low], values[high]),
        )
    }

    fun dump(): List<String> = buildList {
        add("SPARSE DUMP levels=${minimum.size}")
        for (level in minimum.indices) {
            add("MIN $level ${minimum[level].joinToString(" ")}")
            add("MAX $level ${maximum[level].joinToString(" ")}")
        }
    }
}

private data class Partition(val cells: List<Int>, val blocks: List<Int>) {
    fun text() = "whole=${blocks.size} cells=${cells.size}"
}

private class Sqrt(values: LongArray, val block: Int) {
    val raw = values.copyOf()
    val tags = LongArray((values.size + block - 1) / block)
    val sums = LongArray(tags.size)

    init {
        raw.forEachIndexed { i, value -> sums[i / block] += value }
    }

    private fun split(span: Span): Partition {
        val first = span.l / block
        val last = span.r / block
        val cells = (span.l..span.r).filter { it / block == first || it / block == last }
        return Partition(cells, (first + 1 until last).toList())
    }

    fun add(span: Span, value: Long): Partition {
        val part = split(span)
        for (i in part.cells) {
            raw[i] += value
            sums[i / block] += value
        }
        for (b in part.blocks) {
            tags[b] += value
            sums[b] += value * block
        }
        return part
    }

    fun query(span: Span): Report {
        val part = split(span)
        var sum = 0L
        for (i in part.cells) sum += raw[i] + tags[i / block]
        for (b in part.blocks) sum += sums[b]
        return Report("sum=$sum ${part.text()}", longArrayOf(sum))
    }

    fun dump(): List<String> = buildList {
        add("SQRT DUMP block=$block blocks=${tags.size}")
        for (b in tags.indices) {
            val first = b * block
            val end = min((b + 1) * block, raw.size)
            add(
                "BLOCK $b $first ${end - 1} add=${tags[b]} sum=${sums[b]} ${raw.sliceArray(first until end).joinToString(" ")}",
            )
        }
    }
}

private class PersistentNode(
    val value: Long,
    val left: PersistentNode? = null,
    val right: PersistentNode? = null,
)

private data class ChangedNode(val node: PersistentNode, val created: Int)

private fun buildNode(values: LongArray?, span: Span): PersistentNode {
    if (span.leaf) return PersistentNode(values?.get(span.l) ?: 0)
    val left = buildNode(values, span.left())
    val right = buildNode(values, span.right())
    return PersistentNode(left.value + right.value, left, right)
}

private fun changeNode(
    source: PersistentNode,
    span: Span,
    index: Int,
    value: Long,
    increment: Boolean,
): ChangedNode {
    if (span.leaf)
        return ChangedNode(PersistentNode(if (increment) source.value + value else value), 1)
    var left = source.left!!
    var right = source.right!!
    val changed =
        if (index <= span.middle) {
            changeNode(left, span.left(), index, value, increment).also { left = it.node }
        } else {
            changeNode(right, span.right(), index, value, increment).also { right = it.node }
        }
    return ChangedNode(PersistentNode(left.value + right.value, left, right), changed.created + 1)
}

private fun queryNode(node: PersistentNode, span: Span, wanted: Span): Answer {
    if (wanted.covers(span)) return Answer(node.value, 1)
    val answer =
        when {
            wanted.r <= span.middle -> queryNode(node.left!!, span.left(), wanted)
            wanted.l > span.middle -> queryNode(node.right!!, span.right(), wanted)
            else -> {
                val left = queryNode(node.left!!, span.left(), wanted)
                val right = queryNode(node.right!!, span.right(), wanted)
                Answer(left.value + right.value, left.visited + right.visited)
            }
        }
    return answer.copy(visited = answer.visited + 1)
}

private class Persistent(contents: LongArray) {
    val n = contents.size
    val values = contents.distinct().sorted().toLongArray()
    val roots = mutableListOf(buildNode(contents, whole(n)))
    val prefixes = mutableListOf(buildNode(null, whole(values.size)))
    var positionNodes = 2 * n - 1
        private set

    var valueNodes = 2 * values.size - 1
        private set

    init {
        for (value in contents) {
            val changed =
                changeNode(prefixes.last(), whole(values.size), values.binarySearch(value), 1, true)
            prefixes.add(changed.node)
            valueNodes += changed.created
        }
    }

    fun set(version: Int, index: Int, value: Long): Int {
        val changed = changeNode(roots[version], whole(n), index, value, false)
        roots.add(changed.node)
        positionNodes += changed.created
        return changed.created
    }

    fun query(version: Int, span: Span) = queryNode(roots[version], whole(n), span).report()

    fun kth(wanted: Span, target: Long): Answer {
        var u = prefixes[wanted.r + 1]
        var w = prefixes[wanted.l]
        var span = whole(values.size)
        var k = target
        var visited = 1
        while (!span.leaf) {
            val count = u.left!!.value - w.left!!.value
            if (k <= count) {
                u = u.left!!
                w = w.left!!
                span = span.left()
            } else {
                k -= count
                u = u.right!!
                w = w.right!!
                span = span.right()
            }
            visited++
        }
        return Answer(values[span.l], visited)
    }
}

private class Grid(val height: Int, val width: Int, values: LongArray) {
    val tree = Array(height + 1) { LongArray(width + 1) }

    init {
        values.forEachIndexed { i, value -> add(i / width, i % width, value) }
    }

    fun checkCell(row: Int, column: Int) {
        if (row < 0 || row >= height || column < 0 || column >= width) fail("BAD CELL $row $column")
    }

    fun add(row: Int, column: Int, value: Long): Int {
        var visited = 0
        var y = row + 1
        while (y <= height) {
            var x = column + 1
            while (x <= width) {
                tree[y][x] += value
                visited++
                x += x and -x
            }
            y += y and -y
        }
        return visited
    }

    private fun prefix(row: Int, column: Int): Answer {
        var sum = 0L
        var visited = 0
        var y = row
        while (y > 0) {
            var x = column
            while (x > 0) {
                sum += tree[y][x]
                visited++
                x -= x and -x
            }
            y -= y and -y
        }
        return Answer(sum, visited)
    }

    fun query(row: Int, column: Int, bottom: Int, right: Int): Answer {
        val a = prefix(bottom + 1, right + 1)
        val b = prefix(row, right + 1)
        val c = prefix(bottom + 1, column)
        val d = prefix(row, column)
        return Answer(
            a.value - b.value - c.value + d.value,
            a.visited + b.visited + c.visited + d.visited,
        )
    }

    fun dump(): List<String> = buildList {
        add("GRID DUMP rows=$height cols=$width")
        for (row in 1..height) add("ROW $row ${tree[row].drop(1).joinToString(" ")}")
    }
}

private class Lab(var values: LongArray) {
    var original = values.copyOf()
    var seg: Segment? = null
    var lazy: Lazy? = null
    var fen: Fenwick? = null
    var rfen: RangeFenwick? = null
    var sparse: Sparse? = null
    var sqrt: Sqrt? = null
    var persist: Persistent? = null
    var grid: Grid? = null

    fun has(kind: Kind) =
        when (kind) {
            Kind.SEG -> seg != null
            Kind.LAZY -> lazy != null
            Kind.FEN -> fen != null
            Kind.RFEN -> rfen != null
            Kind.SPARSE -> sparse != null
            Kind.SQRT -> sqrt != null
            Kind.PERSIST -> persist != null
            Kind.GRID -> grid != null
        }

    fun checkIndex(index: Int) {
        if (index < 0 || index >= values.size) fail("BAD INDEX $index")
    }

    fun checkRange(span: Span) {
        checkIndex(span.l)
        checkIndex(span.r)
        if (span.l > span.r) fail("BAD RANGE ${span.l} ${span.r}")
    }

    fun checkVersion(version: Int) {
        if (version < 0 || version >= persist!!.roots.size) fail("BAD VERSION $version")
    }

    fun build(kind: Kind, op: Operation, block: Int): String =
        when (kind) {
            Kind.SEG -> {
                val tree = Segment(values, op)
                seg = tree
                "SEG BUILD $op nodes=${tree.shape.count} maxnode=${tree.shape.maxNode} root=${tree.tree[1]}"
            }
            Kind.LAZY -> {
                val tree = Lazy(values)
                lazy = tree
                "LAZY BUILD nodes=${tree.shape.count} ${tree.nodes[1].value.text()}"
            }
            Kind.FEN -> {
                fen = Fenwick(values)
                "FEN BUILD n=${values.size} total=${values.sum()}"
            }
            Kind.RFEN -> {
                rfen = RangeFenwick(values)
                "RFEN BUILD n=${values.size} total=${values.sum()}"
            }
            Kind.SPARSE -> {
                val tree = Sparse(values)
                sparse = tree
                "SPARSE BUILD levels=${tree.minimum.size} entries=${tree.entries}"
            }
            Kind.SQRT -> {
                val tree = Sqrt(values, block)
                sqrt = tree
                "SQRT BUILD block=$block blocks=${tree.tags.size}"
            }
            Kind.PERSIST -> {
                val tree = Persistent(values)
                persist = tree
                "PERSIST BUILD nodes=${tree.positionNodes} distinct=${tree.values.size} valuenodes=${tree.valueNodes}"
            }
            Kind.GRID -> error("Not an array structure")
        }

    fun query(kind: Kind, version: Int, span: Span): Report =
        when (kind) {
            Kind.SEG -> seg!!.query(span)
            Kind.LAZY -> lazy!!.query(span)
            Kind.FEN -> fen!!.bit.query(span).report()
            Kind.RFEN -> rfen!!.query(span).report()
            Kind.SPARSE -> sparse!!.query(span)
            Kind.SQRT -> sqrt!!.query(span)
            Kind.PERSIST -> persist!!.query(version, span)
            Kind.GRID -> error("Not an array structure")
        }

    fun dump(kind: Kind): List<String> =
        when (kind) {
            Kind.SEG -> seg!!.dump()
            Kind.LAZY -> lazy!!.dump()
            Kind.FEN -> listOf("FEN DUMP n=${values.size}", fen!!.bit.dump("T"))
            Kind.RFEN ->
                listOf(
                    "RFEN DUMP n=${values.size}",
                    rfen!!.first.dump("B1"),
                    rfen!!.second.dump("B2"),
                )
            Kind.SPARSE -> sparse!!.dump()
            Kind.SQRT -> sqrt!!.dump()
            Kind.GRID -> grid!!.dump()
            Kind.PERSIST -> error("No persistent dump")
        }

    fun check(span: Span): List<String> {
        var expected = Aggregate(0, values[span.l], values[span.l])
        var common = 0L
        for (i in span.l..span.r) {
            expected = expected.merge(Aggregate.single(values[i]))
            common = gcd(common, values[i])
        }
        val rows = mutableListOf("CHECK ${span.l} ${span.r} ${expected.text()} gcd=$common")
        var ok = 0
        var diff = 0
        for (kind in Kind.entries) {
            if (kind == Kind.GRID || !has(kind)) continue
            val wanted =
                when (kind) {
                    Kind.SEG ->
                        longArrayOf(
                            when (seg!!.op) {
                                Operation.SUM -> expected.sum
                                Operation.MIN -> expected.min
                                Operation.MAX -> expected.max
                                Operation.GCD -> common
                            },
                        )
                    Kind.LAZY -> longArrayOf(expected.sum, expected.min, expected.max)
                    Kind.SPARSE -> longArrayOf(expected.min, expected.max)
                    else -> longArrayOf(expected.sum)
                }
            val version = if (kind == Kind.PERSIST) persist!!.roots.lastIndex else 0
            val answer = query(kind, version, span)
            val equal = answer.values.contentEquals(wanted)
            if (equal) ok++ else diff++
            val prefix = if (kind == Kind.PERSIST) "version=$version " else ""
            rows.add("$kind ${if (equal) "OK" else "DIFF"} $prefix${answer.text}")
        }
        rows.add("RESULT ok=$ok diff=$diff")
        return rows
    }

    fun mo(queries: List<Span>): List<String> {
        val block = isqrt(values.size)
        val order =
            queries.indices.sortedWith(
                compareBy<Int> { queries[it].l / block }
                    .thenBy { (if (queries[it].l / block % 2 == 0) 1 else -1) * queries[it].r }
                    .thenBy { it },
            )
        val unique = values.distinct().sorted().toLongArray()
        val ranks = IntArray(values.size) { unique.binarySearch(values[it]) }
        val frequencies = IntArray(unique.size)
        val answers = IntArray(queries.size)
        var left = 0
        var right = 0
        var moves = 0
        var distinct = 0
        for (index in order) {
            val span = queries[index]
            val end = span.r + 1
            moves += abs(span.l - left) + abs(end - right)
            while (left > span.l) {
                left--
                val rank = ranks[left]
                if (frequencies[rank] == 0) distinct++
                frequencies[rank]++
            }
            while (right < end) {
                val rank = ranks[right++]
                if (frequencies[rank] == 0) distinct++
                frequencies[rank]++
            }
            while (left < span.l) {
                val rank = ranks[left++]
                frequencies[rank]--
                if (frequencies[rank] == 0) distinct--
            }
            while (right > end) {
                right--
                val rank = ranks[right]
                frequencies[rank]--
                if (frequencies[rank] == 0) distinct--
            }
            answers[index] = distinct
        }
        return buildList {
            add("MO queries=${queries.size} block=$block moves=$moves")
            add("ORDER ${order.joinToString(" ") { (it + 1).toString() }}")
            queries.forEachIndexed { i, span ->
                add("ANSWER ${i + 1} ${span.l} ${span.r} distinct=${answers[i]}")
            }
        }
    }

    fun execute(line: String): List<String> {
        val words = line.split(' ')
        fun number(i: Int) = words[i].toLong()
        fun index(i: Int) = words[i].toInt()
        fun span(i: Int) = Span(index(i), index(i + 1))
        when (words[0]) {
            "LOAD" -> {
                val removed = Kind.entries.count { it != Kind.GRID && has(it) }
                values = words.drop(1).map(String::toLong).toLongArray()
                original = values.copyOf()
                seg = null
                lazy = null
                fen = null
                rfen = null
                sparse = null
                sqrt = null
                persist = null
                return listOf("LOAD n=${values.size} removed=$removed")
            }
            "RESET" -> {
                values = original.copyOf()
                val op = seg?.op ?: Operation.SUM
                val block = sqrt?.block ?: 0
                var rebuilt = 0
                for (kind in Kind.entries) if (kind != Kind.GRID && has(kind)) {
                    build(kind, op, block)
                    rebuilt++
                }
                return listOf("RESET rebuilt=$rebuilt")
            }
            "ARRAY",
            "CHECK" -> {
                val range = span(1)
                checkRange(range)
                return if (words[0] == "CHECK") check(range)
                else
                    listOf(
                        "ARRAY ${range.l} ${range.r} ${values.sliceArray(range.l..range.r).joinToString(" ")}",
                    )
            }
            "MO" -> {
                val queries = (1 until words.size step 2).map { span(it).also(::checkRange) }
                return mo(queries)
            }
        }
        val kind = Kind.valueOf(words[0])
        val action = words[1]
        if (action == "BUILD") {
            val op =
                if (kind == Kind.SEG)
                    Operation.entries.find { it.name == words[2] } ?: fail("BAD OP ${words[2]}")
                else Operation.SUM
            var block = 0
            if (kind == Kind.SQRT) {
                block = if (words.size == 3) index(2) else isqrt(values.size)
                if (block > values.size) fail("BAD BLOCK $block")
            }
            if (kind == Kind.GRID) {
                val height = index(2)
                val width = index(3)
                val count = words.size - 4
                if (count != height * width) fail("BAD COUNT $count ${height * width}")
                val contents = words.drop(4).map(String::toLong).toLongArray()
                grid = Grid(height, width, contents)
                return listOf("GRID BUILD rows=$height cols=$width total=${contents.sum()}")
            }
            return listOf(build(kind, op, block))
        }
        if (!has(kind)) fail("NOT BUILT $kind")
        if (action == "DUMP") return dump(kind)
        if (kind == Kind.GRID) {
            val tree = grid!!
            val row = index(2)
            val column = index(3)
            tree.checkCell(row, column)
            if (action == "ADD") {
                val value = number(4)
                return listOf(
                    "GRID ADD $row $column $value visited=${tree.add(row, column, value)}",
                )
            }
            val bottom = index(4)
            val right = index(5)
            tree.checkCell(bottom, right)
            if (row > bottom || column > right) fail("BAD RECT $row $column $bottom $right")
            return listOf(
                "GRID SUM $row $column $bottom $right ${tree.query(row, column, bottom, right).report().text}",
            )
        }
        if (kind == Kind.PERSIST) {
            val tree = persist!!
            if (action == "NODES")
                return listOf(
                    "PERSIST NODES versions=${tree.roots.size} position=${tree.positionNodes} value=${tree.valueNodes}",
                )
            if (action == "KTH") {
                val range = span(2)
                checkRange(range)
                val k = number(4)
                if (k < 1 || k > range.length) fail("BAD K $k")
                val answer = tree.kth(range, k)
                return listOf(
                    "PERSIST KTH ${range.l} ${range.r} $k value=${answer.value} visited=${answer.visited}",
                )
            }
            val version = index(2)
            checkVersion(version)
            val position = index(3)
            if (action == "SET") {
                checkIndex(position)
                val value = number(4)
                val next = tree.roots.size
                val created = tree.set(version, position, value)
                return listOf(
                    "PERSIST SET $version $position $value version=$next created=$created",
                )
            }
            val range = Span(position, index(4))
            checkRange(range)
            return listOf(
                "PERSIST QUERY $version ${range.l} ${range.r} ${tree.query(version, range).text}",
            )
        }
        if (kind == Kind.FEN && action == "LOWER") {
            val tree = fen!!
            for (i in tree.values.indices) if (tree.values[i] < 0) fail("NEGATIVE $i")
            val k = number(2)
            val answer = tree.bit.lower(k)
            val position = if (answer.value < 0) "none" else answer.value.toString()
            return listOf("FEN LOWER $k index=$position visited=${answer.visited}")
        }
        if (kind == Kind.SEG && action == "UPDATE") {
            val position = index(2)
            checkIndex(position)
            val value = number(3)
            val tree = seg!!
            val visited = tree.update(position, value)
            values[position] = value
            return listOf("SEG UPDATE $position $value root=${tree.tree[1]} visited=$visited")
        }
        if (kind == Kind.FEN && (action == "ADD" || action == "PREFIX")) {
            val position = index(2)
            checkIndex(position)
            val tree = fen!!
            if (action == "PREFIX")
                return listOf("FEN PREFIX $position ${tree.bit.prefix(position + 1).report().text}")
            val value = number(3)
            values[position] += value
            tree.values[position] += value
            return listOf("FEN ADD $position $value visited=${tree.bit.add(position + 1, value)}")
        }
        val range = span(2)
        checkRange(range)
        if (action == "ADD" || action == "ASSIGN") {
            val value = number(4)
            val assignment = action == "ASSIGN"
            val details =
                when (kind) {
                    Kind.LAZY -> lazy!!.update(range, value, assignment).toString()
                    Kind.RFEN -> "visited=${rfen!!.add(range, value)}"
                    Kind.SQRT -> sqrt!!.add(range, value).text()
                    else -> error("Not a range update")
                }
            for (i in range.l..range.r) values[i] = if (assignment) value else values[i] + value
            return listOf("$kind $action ${range.l} ${range.r} $value $details")
        }
        return listOf("$kind $action ${range.l} ${range.r} ${query(kind, 0, range).text}")
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    if (input.readLine() == null) return
    val lab = Lab(input.readLine().split(' ').map(String::toLong).toLongArray())
    val count = input.readLine().toInt()
    val output = System.out.bufferedWriter()
    repeat(count) {
        try {
            for (row in lab.execute(input.readLine())) output.append(row).append('\n')
        } catch (error: CommandError) {
            output.append("ERROR ").append(error.message!!).append('\n')
        }
        output.flush()
    }
}
