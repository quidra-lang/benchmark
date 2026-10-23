private class Problem(val reason: String) : RuntimeException(reason)

private fun fail(reason: String): Nothing = throw Problem(reason)

private class Q(numerator: Long, denominator: Long = 1) : Comparable<Q> {
    val p: Long
    val q: Long
    init {
        var a = kotlin.math.abs(numerator)
        var b = kotlin.math.abs(denominator)
        while (b != 0L) {
            val r = a % b
            a = b
            b = r
        }
        val sign = if (denominator < 0) -1 else 1
        p = sign * numerator / a
        q = kotlin.math.abs(denominator) / a
    }
    operator fun plus(b: Q) = Q(p * b.q + b.p * q, q * b.q)
    operator fun minus(b: Q) = Q(p * b.q - b.p * q, q * b.q)
    operator fun times(b: Q) = Q(p * b.p, q * b.q)
    operator fun div(b: Q) = Q(p * b.q, q * b.p)
    operator fun unaryMinus() = Q(-p, q)
    override fun compareTo(other: Q) = (p * other.q).compareTo(other.p * q)
    override fun toString() = if (q == 1L) "$p" else "$p/$q"

    fun value(): String {
        val h = kotlin.math.abs(p) * 1000000 / q
        return "$this (${if (p < 0) "-" else ""}${h / 1000000}.${(h % 1000000).toString().padStart(6, '0')})"
    }
}
private val zero = Q(0)
private val one = Q(1)

private fun number(raw: String): Q {
    var s = raw
    var multiplier = one
    for ((suffix, factor) in listOf("meg" to Q(1000000), "k" to Q(1000), "m" to Q(1, 1000), "u" to Q(1, 1000000))) {
        if (s.endsWith(suffix)) {
            s = s.dropLast(suffix.length)
            multiplier = factor
            break
        }
    }
    var sign = 1L
    if (s.startsWith('-')) {
        sign = -1
        s = s.drop(1)
    }
    val value = when {
        s.matches(Regex("[0-9]+")) -> Q(s.toLong())
        s.matches(Regex("[0-9]+\\.[0-9]+")) -> {
            val parts = s.split('.')
            Q((parts[0] + parts[1]).toLong(), parts[1].fold(1L) {
                n, _ -> n * 10
            })
        }
        s.matches(Regex("[0-9]+/[0-9]+")) -> {
            val parts = s.split('/')
            if (parts[1].toLong() == 0L) fail("invalid value $raw")
            Q(parts[0].toLong(), parts[1].toLong())
        } else -> fail("invalid value $raw")
    }
    return Q(sign) * value * multiplier
}

private fun validNode(s: String) = s == "0" || s.matches(Regex("[a-z][a-z0-9]{0,7}"))

private data class Element(val name: String, val nodes: List<String>, val reference: String, var value: Q) {
    val kind get() = name[0]
    val a get() = nodes[0]
    val b get() = nodes[1]
    val voltage get() = kind in "VEH"
    val independent get() = kind in "VI"
}

private class Union(nodes: Collection<String>) {
    private val parent = nodes.associateWith {
        it
    }.toMutableMap()

    fun root(x: String): String {
        val p = parent.getValue(x)
        if (p == x) return x
        val r = root(p)
        parent[x] = r
        return r
    }

    fun join(a: String, b: String) {
        val x = root(a)
        val y = root(b)
        if (x < y) parent[y] = x else parent[x] = y
    }
}

private fun reach(start: String, edges: List<Pair<String, String>>): Set<String> {
    val found = mutableSetOf(start)
    val queue = ArrayDeque<String>()
    queue.add(start)
    while (queue.isNotEmpty()) {
        val a = queue.removeFirst()
        for ((u, v) in edges) {
            val b = if (a == u) v else if (a == v) u else continue
            if (found.add(b)) queue.add(b)
        }
    }
    return found
}

private fun solve(a: Array<Array<Q>>, b: Array<Q>): Array<Q>? {
    val n = b.size
    val m = Array(n) {
        i -> Array(n + 1) {
            j -> if (j == n) b[i] else a[i][j]
        }
    }
    for (k in 0 until n) {
        val r = (k until n).firstOrNull {
            m[it][k].p != 0L
        } ?: return null
        val temp = m[k]
        m[k] = m[r]
        m[r] = temp
        val pivot = m[k][k]
        for (j in 0..n) m[k][j] = m[k][j] / pivot
        for (i in 0 until n) if (i != k && m[i][k].p != 0L) {
            val f = m[i][k]
            for (j in 0..n) m[i][j] = m[i][j] - f * m[k][j]
        }
    }
    return Array(n) {
        m[it][n]
    }
}

private class Equations(val elements: List<Element>) {
    val nodes = elements.flatMap {
        it.nodes
    }.filter {
        it != "0"
    }.distinct().sorted()
    val sources = elements.filter {
        it.voltage
    }
    val labels = nodes + sources.map {
        it.name
    }
    val index = labels.withIndex().associate {
        it.value to it.index
    }
    val a = Array(labels.size) {
        Array(labels.size) {
            zero
        }
    }
    val b = Array(labels.size) {
        zero
    }
    init {
        for (e in elements) {
            val w = e.value
            when (e.kind) {
                'R' -> {
                    val g = one / w
                    add(e.a, e.a, g)
                    add(e.b, e.b, g)
                    add(e.a, e.b, -g)
                    add(e.b, e.a, -g)
                }
                'I' -> {
                    add(b, e.a, -w)
                    add(b, e.b, w)
                }
                'G' -> {
                    add(e.a, e.nodes[2], w)
                    add(e.b, e.nodes[3], w)
                    add(e.a, e.nodes[3], -w)
                    add(e.b, e.nodes[2], -w)
                }
                'F' -> {
                    add(e.a, e.reference, w)
                    add(e.b, e.reference, -w)
                } else -> {
                    add(e.a, e.name, one)
                    add(e.name, e.a, one)
                    add(e.b, e.name, -one)
                    add(e.name, e.b, -one)
                    when (e.kind) {
                        'V' -> add(b, e.name, w)
                        'E' -> {
                            add(e.name, e.nodes[2], -w)
                            add(e.name, e.nodes[3], w)
                        }
                        'H' -> add(e.name, e.reference, -w)
                    }
                }
            }
        }
    }

    fun add(row: String, column: String, value: Q) {
        if (row != "0" && column != "0") {
            val i = index.getValue(row)
            val j = index.getValue(column)
            a[i][j] = a[i][j] + value
        }
    }

    fun add(rhs: Array<Q>, row: String, value: Q) {
        if (row != "0") {
            val i = index.getValue(row)
            rhs[i] = rhs[i] + value
        }
    }

    fun v(y: Array<Q>, node: String) = if (node == "0") zero else y[index.getValue(node)]

    fun injection(x: String, y: String): Array<Q> {
        val rhs = Array(labels.size) {
            zero
        }
        add(rhs, x, one)
        add(rhs, y, -one)
        return solve(a, rhs)!!
    }

    fun alone(e: Element, unit: Boolean = false): Array<Q> {
        val rhs = Array(labels.size) {
            zero
        }
        val w = if (unit) one else e.value
        if (e.kind == 'V') add(rhs, e.name, w) else {
            add(rhs, e.a, -w)
            add(rhs, e.b, w)
        }
        return solve(a, rhs)!!
    }

    fun current(e: Element, y: Array<Q>): Q = when (e.kind) {
        'R' -> (v(y, e.a) - v(y, e.b)) / e.value
        'I' -> e.value
        'G' -> e.value * (v(y, e.nodes[2]) - v(y, e.nodes[3]))
        'F' -> e.value * y[index.getValue(e.reference)]
        else -> y[index.getValue(e.name)]
    }
}

private data class Resistor(val name: String, val a: String, val b: String, val value: Q)

private class Circuit {
    val elements = mutableListOf<Element>()

    fun nodes() = elements.flatMap {
        it.nodes
    }.filter {
        it != "0"
    }.distinct().sorted()

    fun get(name: String) = elements.firstOrNull {
        it.name == name
    } ?: fail("unknown element $name")

    fun node(name: String) {
        if (name != "0" && name !in nodes()) fail("unknown node $name")
    }

    fun floating() = nodes().filter {
        it !in reach("0", elements.filter {
            it.kind in "RVEH"
        }.map {
            it.a to it.b
        })
    }

    fun loops(): List<String> {
        val u = Union(nodes() + "0")
        val result = mutableListOf<String>()
        for (e in elements.filter {
            it.voltage
        }) {
            if (u.root(e.a) == u.root(e.b)) result.add(e.name)
            u.join(e.a, e.b)
        }
        return result
    }

    fun structure() {
        if (nodes().isEmpty()) fail("no nodes")
        floating().firstOrNull()?.let {
            fail("floating node $it")
        }
        loops().firstOrNull()?.let {
            fail("voltage source loop at $it")
        }
    }

    fun add(w: List<String>) {
        val name = w[0]
        val kind = name[0]
        if (kind !in "RVIEGFH") fail("unknown element type $name")
        val count = if (kind in "RVI") 4 else if (kind in "EG") 6 else 5
        if (w.size != count) fail("wrong field count for $name")
        if (elements.any {
            it.name == name
        }) fail("duplicate element $name")
        val ns = if (kind in "EG") w.subList(1, 5) else w.subList(1, 3)
        for (n in ns) if (!validNode(n)) fail("invalid node $n")
        val reference = if (kind in "FH") w[3] else ""
        if (kind in "FH" && elements.none {
            it.name == reference && it.kind == 'V'
        }) fail("unknown voltage source $reference")
        val value = number(w.last())
        if (kind == 'R' && value <= zero) fail("nonpositive resistance $name")
        elements.add(Element(name, ns.toList(), reference, value))
    }

    fun resistance(a: String, b: String): List<String> {
        val u = Union(nodes() + "0")
        for (e in elements) if (e.kind == 'V') u.join(e.a, e.b)
        val x = u.root(a)
        val y = u.root(b)
        if (x == y) return listOf("Req = ${zero.value()}")
        val edges = elements.filter {
            it.kind == 'R' && u.root(it.a) != u.root(it.b)
        }
        val connected = reach(x, edges.map {
            u.root(it.a) to u.root(it.b)
        })
        if (y !in connected) return listOf("Req = INFINITE")
        val groups = connected.filter {
            it != y
        }.sorted()
        val index = groups.withIndex().associate {
            it.value to it.index
        }
        val matrix = Array(groups.size) {
            Array(groups.size) {
                zero
            }
        }
        val rhs = Array(groups.size) {
            zero
        }

        fun stamp(p: String, q: String, v: Q) {
            if (p != y && q != y) {
                val i = index.getValue(p)
                val j = index.getValue(q)
                matrix[i][j] = matrix[i][j] + v
            }
        }
        for (e in edges) if (u.root(e.a) in connected) {
            val p = u.root(e.a)
            val q = u.root(e.b)
            val g = one / e.value
            stamp(p, p, g)
            stamp(q, q, g)
            stamp(p, q, -g)
            stamp(q, p, -g)
        }
        rhs[index.getValue(x)] = one
        return listOf("Req = ${solve(matrix, rhs)!![index.getValue(x)].value()}")
    }

    fun reduce(a: String, b: String): List<String> {
        if (a == b) return listOf("Req = ${zero.value()}")
        var list = elements.filter {
            it.kind == 'R'
        }.map {
            Resistor(it.name, it.a, it.b, it.value)
        }.toMutableList()
        val connected = reach(a, list.map {
            it.a to it.b
        })
        if (b !in connected) return listOf("Req = INFINITE")
        list = list.filter {
            it.a in connected
        }.toMutableList()
        val out = mutableListOf<String>()
        var created = 0
        while (true) {
            val self = list.indexOfFirst {
                it.a == it.b
            }
            if (self >= 0) {
                out.add("remove ${list.removeAt(self).name}")
                continue
            }
            val degree = sortedMapOf<String, Int>()
            for (r in list) {
                degree[r.a] = (degree[r.a] ?: 0) + 1
                degree[r.b] = (degree[r.b] ?: 0) + 1
            }
            val dangling = degree.keys.firstOrNull {
                it != a && it != b && degree[it] == 1
            }
            if (dangling != null) {
                val i = list.indexOfFirst {
                    it.a == dangling || it.b == dangling
                }
                out.add("remove ${list.removeAt(i).name}")
                continue
            }
            var pair: Pair<Int, Int>? = null
            outer@ for (i in list.indices) for (j in i + 1 until list.size) {
                val x = list[i]
                val y = list[j]
                if (x.a == y.a && x.b == y.b || x.a == y.b && x.b == y.a) {
                    pair = i to j
                    break@outer
                }
            }
            if (pair != null) {
                val (i, j) = pair
                val x = list[i]
                val y = list[j]
                val value = x.value * y.value / (x.value + y.value)
                val r = Resistor("#${++created}", x.a, x.b, value)
                list.removeAt(j)
                list.removeAt(i)
                list.add(r)
                out.add("${r.name} = ${x.name} || ${y.name} = ${value.value()}")
                continue
            }
            val p = degree.keys.firstOrNull {
                it != a && it != b && degree[it] == 2
            } ?: break
            val indices = list.indices.filter {
                list[it].a == p || list[it].b == p
            }
            val i = indices[0]
            val j = indices[1]
            val x = list[i]
            val y = list[j]
            val value = x.value + y.value
            val r = Resistor("#${++created}", if (x.a == p) x.b else x.a, if (y.a == p) y.b else y.a, value)
            list.removeAt(j)
            list.removeAt(i)
            list.add(r)
            out.add("${r.name} = ${x.name} + ${y.name} = ${value.value()}")
        }
        out.add(if (list.size == 1) "Req = ${list[0].value.value()}" else "not series-parallel: ${list.size} resistors remain")
        return out
    }

    fun command(w: List<String>): List<String> {
        val c = w[0]
        val counts = mapOf(".OP" to 0, ".CURRENT" to 1, ".VOLTAGE" to 2, ".POWER" to 0, ".KCL" to 1, ".THEVENIN" to 2, ".NORTON" to 2, ".MAXPOWER" to 2, ".TF" to 2, ".SENS" to 1, ".ZPARAM" to 4, ".SUPERPOSITION" to 1, ".SWEEP" to 5, ".MATRIX" to 0, ".REQ" to 2, ".REDUCE" to 2, ".CHECK" to 0, ".ALTER" to 2, ".DELETE" to 1, ".CLEAR" to 0, ".NODES" to 0, ".PRINT" to 0)
        val count = counts[c] ?: fail("unknown command $c")
        if (w.size != count + 1) fail("wrong argument count for $c")
        when (c) {
            ".CLEAR" -> {
                val n = elements.size
                elements.clear()
                return listOf("cleared $n elements")
            }
            ".PRINT" -> return if (elements.isEmpty()) listOf("empty netlist") else elements.map {
                e -> (listOf(e.name) + e.nodes + (if (e.reference.isEmpty()) emptyList() else listOf(e.reference)) + e.value.toString()).joinToString(" ")
            }
            ".NODES" -> {
                val ns = elements.flatMap {
                    it.nodes
                }.distinct().sorted()
                return if (ns.isEmpty()) listOf("no nodes") else ns.map {
                    n -> "$n: " + elements.filter {
                        n in it.nodes
                    }.joinToString(" ") {
                        it.name
                    }
                }
            }
            ".DELETE" -> {
                val e = get(w[1])
                elements.firstOrNull {
                    it.kind in "FH" && it.reference == e.name
                }?.let {
                    fail("${e.name} is referenced by ${it.name}")
                }
                elements.remove(e)
                return listOf("deleted ${e.name}")
            }
            ".ALTER" -> {
                val e = get(w[1])
                val v = number(w[2])
                if (e.kind == 'R' && v <= zero) fail("nonpositive resistance ${e.name}")
                val old = e.value
                e.value = v
                return listOf("altered ${e.name}: $old -> $v")
            }
            ".CHECK" -> {
                val ns = nodes()
                if (ns.isEmpty()) return listOf("no nodes")
                val out = mutableListOf<String>()
                for (n in ns) if (elements.sumOf {
                    (if (it.a == n) 1 else 0) + (if (it.b == n) 1 else 0)
                } < 2) out.add("dangling node $n")
                out.addAll(floating().map {
                    "floating node $it"
                })
                out.addAll(loops().map {
                    "voltage source loop at $it"
                })
                if (out.isEmpty()) {
                    val e = Equations(elements)
                    if (solve(e.a, e.b) == null) out.add("singular matrix")
                }
                return out.ifEmpty {
                    listOf("ok")
                }
            }
            ".REQ", ".REDUCE" -> {
                node(w[1])
                node(w[2])
                return if (c == ".REQ") resistance(w[1], w[2]) else reduce(w[1], w[2])
            }
            ".SWEEP" -> {
                val e = get(w[1])
                val from = number(w[2])
                val to = number(w[3])
                val step = number(w[4])
                node(w[5])
                if (step <= zero) fail("invalid sweep step")
                if (from > to) fail("invalid sweep range")
                val ratio = (to - from) / step
                val k = ratio.p / ratio.q + 1
                if (k > 20) fail("too many sweep points")
                if (e.kind == 'R' && from <= zero) fail("nonpositive resistance ${e.name}")
                structure()
                return (0 until k.toInt()).map {
                    i ->
                    val x = from + Q(i.toLong()) * step
                    val eq = Equations(elements.map {
                        if (it === e) it.copy(value = x) else it
                    })
                    val y = solve(eq.a, eq.b)
                    "${e.name} = $x: " + if (y == null) "singular matrix" else "V(${w[5]}) = ${eq.v(y, w[5]).value()}"
                }
            }
        }
        when (c) {
            ".CURRENT" -> get(w[1])
            ".VOLTAGE", ".THEVENIN", ".NORTON", ".MAXPOWER" -> {
                node(w[1])
                node(w[2])
            }
            ".KCL", ".SENS", ".SUPERPOSITION" -> node(w[1])
            ".ZPARAM" -> w.drop(1).forEach(::node)
            ".TF" -> {
                node(w[1])
                val e = get(w[2])
                if (!e.independent) fail("not an independent source ${e.name}")
            }
        }
        structure()
        val eq = Equations(elements)
        if (c == ".MATRIX") return listOf("unknowns: " + (eq.nodes.map {
            "V($it)"
        } + eq.sources.map {
            "I(${it.name})"
        }).joinToString(" ")) + eq.labels.indices.map {
            i -> "${eq.labels[i]}: " + eq.a[i].joinToString(" ") + " | ${eq.b[i]}"
        }
        val y = solve(eq.a, eq.b) ?: fail("singular matrix")

        fun v(n: String) = eq.v(y, n)
        val out = mutableListOf<String>()
        when (c) {
            ".OP" -> {
                for (n in eq.nodes) out.add("V($n) = ${v(n).value()}")
                for (e in eq.sources) out.add("I(${e.name}) = ${eq.current(e, y).value()}")
            }
            ".CURRENT" -> out.add("I(${w[1]}) = ${eq.current(get(w[1]), y).value()}")
            ".VOLTAGE" -> out.add("V(${w[1]},${w[2]}) = ${(v(w[1]) - v(w[2])).value()}")
            ".POWER" -> {
                var absorbed = zero
                var delivered = zero
                var total = zero
                for (e in elements) {
                    val p = (v(e.a) - v(e.b)) * eq.current(e, y)
                    out.add("P(${e.name}) = ${p.value()}")
                    if (p > zero) absorbed += p
                    if (p < zero) delivered -= p
                    total += p
                }
                out.add("absorbed = ${absorbed.value()}")
                out.add("delivered = ${delivered.value()}")
                out.add("total = ${total.value()}")
            }
            ".KCL" -> {
                var sum = zero
                val n = w[1]
                for (e in elements) if (e.a == n || e.b == n) {
                    val i = if (e.a == n && e.b == n) zero else if (e.a == n) eq.current(e, y) else -eq.current(e, y)
                    sum += i
                    out.add("I(${e.name}) leaving $n = ${i.value()}")
                }
                out.add("sum = ${sum.value()}")
            }
            ".THEVENIN", ".NORTON", ".MAXPOWER" -> {
                val z = eq.injection(w[1], w[2])
                val voltage = v(w[1]) - v(w[2])
                val resistance = eq.v(z, w[1]) - eq.v(z, w[2])
                if (c == ".NORTON" && resistance.p == 0L) fail("zero thevenin resistance")
                if (c == ".MAXPOWER" && resistance <= zero) fail("nonpositive thevenin resistance")
                when (c) {
                    ".THEVENIN" -> {
                        out.add("Vth = ${voltage.value()}")
                        out.add("Rth = ${resistance.value()}")
                    }
                    ".NORTON" -> {
                        out.add("In = ${(voltage / resistance).value()}")
                        out.add("Rn = ${resistance.value()}")
                    } else -> {
                        out.add("RL = ${resistance.value()}")
                        out.add("Pmax = ${(voltage * voltage / (Q(4) * resistance)).value()}")
                    }
                }
            }
            ".TF" -> {
                val e = get(w[2])
                val z = eq.alone(e, true)
                out.add("gain = ${eq.v(z, w[1]).value()}")
                if (e.kind == 'V') {
                    val i = z[eq.index.getValue(e.name)]
                    out.add("input resistance = " + if (i.p == 0L) "INFINITE" else (-one / i).value())
                } else out.add("input resistance = ${(eq.v(z, e.b) - eq.v(z, e.a)).value()}")
                out.add("output resistance = ${eq.v(eq.injection(w[1], "0"), w[1]).value()}")
            }
            ".SENS" -> for (e in elements) {
                val d = Array(eq.labels.size) {
                    zero
                }
                when (e.kind) {
                    'R' -> {
                        val t = eq.current(e, y) / e.value
                        eq.add(d, e.a, t)
                        eq.add(d, e.b, -t)
                    }
                    'I' -> {
                        eq.add(d, e.a, -one)
                        eq.add(d, e.b, one)
                    }
                    'G', 'F' -> {
                        val t = if (e.kind == 'G') v(e.nodes[2]) - v(e.nodes[3]) else y[eq.index.getValue(e.reference)]
                        eq.add(d, e.a, -t)
                        eq.add(d, e.b, t)
                    }
                    'V' -> eq.add(d, e.name, one)
                    'E' -> eq.add(d, e.name, v(e.nodes[2]) - v(e.nodes[3]))
                    'H' -> eq.add(d, e.name, y[eq.index.getValue(e.reference)])
                }
                out.add("dV(${w[1]})/d${e.name} = ${eq.v(solve(eq.a, d)!!, w[1]).value()}")
            }
            ".ZPARAM" -> {
                val z1 = eq.injection(w[1], w[2])
                val z2 = eq.injection(w[3], w[4])
                out.add("z11 = ${(eq.v(z1, w[1]) - eq.v(z1, w[2])).value()}")
                out.add("z12 = ${(eq.v(z2, w[1]) - eq.v(z2, w[2])).value()}")
                out.add("z21 = ${(eq.v(z1, w[3]) - eq.v(z1, w[4])).value()}")
                out.add("z22 = ${(eq.v(z2, w[3]) - eq.v(z2, w[4])).value()}")
            }
            ".SUPERPOSITION" -> {
                var total = zero
                for (e in elements.filter {
                    it.independent
                }) {
                    val value = eq.v(eq.alone(e), w[1])
                    total += value
                    out.add("${e.name}: V(${w[1]}) = ${value.value()}")
                }
                out.add("total: V(${w[1]}) = ${total.value()}")
            }
        }
        return out
    }
}

fun main() {
    val circuit = Circuit()
    var lineNumber = 0
    while (true) {
        val line = readLine() ?: break
        lineNumber++
        if (line == ".END") break
        if (line.startsWith('*')) continue
        val words = line.split(' ')
        try {
            if (line.startsWith('.')) circuit.command(words).forEach(::println) else circuit.add(words)
        } catch (e: Problem) {
            println("error: line $lineNumber: ${e.reason}")
        }
    }
}
