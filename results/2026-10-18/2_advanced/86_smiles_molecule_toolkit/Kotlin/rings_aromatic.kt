object RingsAromatic {
    fun edgeSet(m: Molecule, ring: List<Int>): Set<Int> = ring.indices.map {
        m.bond(ring[it], ring[(it + 1) % ring.size])!!
    }.toSet()
    fun detect(m: Molecule) {
        val n = m.atoms.size
        val candidates = mutableListOf<Pair<List<Int>, Set<Int>>>()
        val seen = mutableSetOf<Set<Int>>()
        for (root in 0 until n) {
            val parent = IntArray(n) {
                -1
            }
            val visited = BooleanArray(n)
            val queue = ArrayDeque<Int>()
            visited[root] = true
            queue.addLast(root)
            while (queue.isNotEmpty()) {
                val a = queue.removeFirst()
                for ((b, _) in m.neighbors[a]) if (!visited[b]) {
                    visited[b] = true; parent[b] = a; queue.addLast(b)
                }
            }
            fun path(atom: Int): List<Int> {
                val result = mutableListOf(atom)
                var x = atom
                while (parent[x] >= 0) {
                    x = parent[x]; result.add(x)
                }
                return result
            }
            for (bond in m.bonds) {
                if (parent[bond.a] == bond.b || parent[bond.b] == bond.a) continue
                val a = path(bond.a)
                val b = path(bond.b)
                if (a.any {
                    it != root && it in b
                }) continue
                val ring = a.reversed() + b.dropLast(1)
                val edges = edgeSet(m, ring)
                if (seen.add(edges)) candidates.add(Pair(ring, edges))
            }
        }
        val basis = mutableMapOf<Int, Set<Int>>()
        val selected = mutableListOf<List<Int>>()
        for ((ring, edges) in candidates.sortedBy {
            it.first.size
        }) {
            var vector = edges
            while (vector.isNotEmpty()) {
                val pivot = vector.maxOrNull()!!
                val b = basis[pivot]
                if (b == null) {
                    basis[pivot] = vector; selected.add(ring); break
                }
                vector = (vector - b) + (b - vector)
            }
        }
        m.rings = selected.map {
            r ->
            val k = r.indexOf(r.minOrNull()!!)
            val rotated = r.drop(k) + r.take(k)
            if (rotated[1] < rotated.last()) rotated else listOf(rotated[0]) + rotated.drop(1).reversed()
        }.sortedWith(Comparator {
            a, b -> if (a.size != b.size) a.size.compareTo(b.size) else lexCompare(a, b)
        })
        for (ring in m.rings) for (edge in edgeSet(m, ring)) m.bonds[edge].ring = true
    }
    fun kekulize(m: Molecule, elements: Elements) {
        val remaining = m.atoms.indices.filter {
            m.needsPi(it, elements, true)
        }.toMutableSet()
        val paired = mutableMapOf<Int, Int>()
        fun matching(system: Set<Int>): Boolean {
            val u = system.filter {
                it !in paired
            }.minOrNull() ?: return true
            for ((v, edge) in m.neighbors[u]) if (v in system && v !in paired && m.bonds[edge].kind == 4) {
                paired[u] = v; paired[v] = u
                if (matching(system)) return true
                paired.remove(u); paired.remove(v)
            }
            return false
        }
        while (remaining.isNotEmpty()) {
            val start = remaining.minOrNull()!!
            val system = mutableSetOf<Int>()
            val stack = mutableListOf(start)
            remaining.remove(start)
            while (stack.isNotEmpty()) {
                val a = stack.removeAt(stack.lastIndex)
                system.add(a)
                for ((b, edge) in m.neighbors[a]) if (m.bonds[edge].kind == 4 && remaining.remove(b)) stack.add(b)
            }
            if (!matching(system)) throw MoleculeError("kekulization failed", m.atoms[system.minOrNull()!!].column)
        }
        for (bond in m.bonds) bond.multiplicity = if (bond.kind == 4) (if (paired[bond.a] == bond.b) 2 else 1) else bond.kind
    }
}
