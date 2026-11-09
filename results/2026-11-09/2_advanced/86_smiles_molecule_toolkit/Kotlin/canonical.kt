fun lexCompare(a: List<Int>, b: List<Int>): Int {
    for (i in 0 until minOf(a.size, b.size)) if (a[i] != b[i]) return a[i].compareTo(b[i])
    return a.size.compareTo(b.size)
}
object Canonical {
    fun dense(values: List<List<Int>>): List<Int> {
        val ranks = values.distinct().sortedWith(Comparator(::lexCompare)).withIndex().associate {
            it.value to it.index + 1
        }
        return values.map {
            ranks.getValue(it)
        }
    }
    fun refine(m: Molecule, input: List<Int>): List<Int> {
        var ranks = input
        while (true) {
            val classes = ranks.toSet().size
            val values = m.atoms.indices.map {
                i ->
                val neighbors = m.neighbors[i].map {
                    Pair(ranks[it.first], m.bonds[it.second].kind)
                }.sortedWith(compareBy<Pair<Int, Int>> {
                    it.first
                }.thenBy {
                    it.second
                })
                listOf(ranks[i]) + neighbors.flatMap {
                    listOf(it.first, it.second)
                }
            }
            ranks = dense(values)
            if (ranks.toSet().size == classes) return ranks
        }
    }
    fun ranks(m: Molecule, elements: Elements): Pair<List<Int>, Int> {
        val values = m.atoms.mapIndexed {
            i, a -> listOf(m.neighbors[i].size, elements.getValue(a.element).number, a.mass, a.charge, a.hydrogens, if (a.aromatic) 1 else 0)
        }
        var ranks = refine(m, dense(values))
        val classes = ranks.toSet().size
        while (ranks.toSet().size < m.atoms.size) {
            val counts = ranks.groupingBy {
                it
            }.eachCount()
            val tied = counts.filterValues {
                it > 1
            }.keys.minOrNull()!!
            val atom = ranks.indexOf(tied)
            val split = ranks.mapIndexed {
                i, rank -> listOf(rank * 2 - if (i == atom) 1 else 0)
            }
            ranks = refine(m, dense(split))
        }
        return Pair(ranks, classes)
    }
    fun atom(m: Molecule, i: Int, elements: Elements): String {
        val a = m.atoms[i]
        val symbol = if (a.aromatic) a.element.lowercase() else a.element
        val allowed = a.element in listOf("B", "C", "N", "O", "P", "S", "F", "Cl", "Br", "I") && (!a.aromatic || a.element in listOf("B", "C", "N", "O", "P", "S"))
        if (allowed && a.mass == 0 && a.charge == 0 && (!a.aromatic || m.needsPi(i, elements, true) == m.needsPi(i, elements, false)) && m.organicHydrogens(i, elements) == a.hydrogens) return symbol
        return buildString {
            append('[')
            if (a.mass != 0) append(a.mass)
            append(symbol)
            if (a.hydrogens > 0) {
                append('H'); if (a.hydrogens > 1) append(a.hydrogens)
            }
            if (a.charge != 0) {
                append(if (a.charge > 0) '+' else '-'); if (kotlin.math.abs(a.charge) > 1) append(kotlin.math.abs(a.charge))
            }
            append(']')
        }
    }
    fun bond(m: Molecule, edge: Int): String {
        val b = m.bonds[edge]
        val aromatic = m.atoms[b.a].aromatic && m.atoms[b.b].aromatic && b.ring
        return when (b.kind) {
            1 -> if (aromatic) "-" else ""; 2 -> "="; 3 -> "#"; else -> if (aromatic) "" else ":"
        }
    }
    fun smiles(m: Molecule, elements: Elements): Pair<String, Int> {
        val (ranks, classes) = this.ranks(m, elements)
        val start = ranks.indexOf(1)
        val visited = IntArray(m.atoms.size)
        val kinds = IntArray(m.bonds.size)
        val children = List(m.atoms.size) {
            mutableListOf<Pair<Int, Int>>()
        }
        val assigned = mutableMapOf<Int, Int>()
        var serial = 0
        fun visit(a: Int, incoming: Int?) {
            visited[a] = ++serial
            for ((b, edge) in m.neighbors[a].sortedBy {
                ranks[it.first]
            }) {
                if (edge == incoming || kinds[edge] == 2) continue
                if (visited[b] == 0) {
                    kinds[edge] = 1; children[a].add(Pair(b, edge)); visit(b, edge)
                }
                else kinds[edge] = 2
            }
        }
        fun write(a: Int): String = buildString {
            append(atom(m, a, elements))
            for ((_, edge) in m.neighbors[a].filter {
                kinds[it.second] == 2
            }.sortedBy {
                visited[it.first]
            }) {
                val old = assigned.remove(edge)
                val number: Int
                if (old != null) number = old
                else {
                    var next = 1
                    while (next in assigned.values) next++
                    number = next; assigned[edge] = next; append(bond(m, edge))
                }
                append(if (number < 10) "$number" else "%${number.toString().padStart(2, '0')}")
            }
            for ((i, child) in children[a].withIndex()) {
                val branch = i + 1 < children[a].size
                if (branch) append('(')
                append(bond(m, child.second)); append(write(child.first))
                if (branch) append(')')
            }
        }
        visit(start, null)
        return Pair(write(start), classes)
    }
}
