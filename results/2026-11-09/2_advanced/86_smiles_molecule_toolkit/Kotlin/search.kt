sealed interface Matcher {
    data object AnyAtom : Matcher
    data object Aliphatic : Matcher
    data object Aromatic : Matcher
    data class AtomList(val atoms: List<Pair<String, Boolean>>) : Matcher
}
data class Pattern(val graph: Molecule, val atoms: List<Matcher>) {
    companion object {
        fun parse(text: String, elements: Elements): Pattern {
            val parsed = SmilesParser.parse(text, elements, true)
            return Pattern(parsed.molecule, parsed.matchers)
        }
        fun molecule(m: Molecule): Pattern = Pattern(m, m.atoms.map {
            Matcher.AtomList(listOf(Pair(it.element, it.aromatic)))
        })
    }
}
data class Matches(val count: Int, val unique: Int, val first: List<Int>)
data class Fingerprint(val bits: MutableSet<Int> = mutableSetOf(), var paths: Int = 0)
data class Ratio(val p: Int, val q: Int) : Comparable<Ratio> {
    override fun compareTo(other: Ratio): Int = (p * other.q).compareTo(other.p * q)
    override fun toString(): String {
        var a = p
        var b = q
        while (b != 0) {
            val r = a % b; a = b; b = r
        }
        return "${p / a}/${q / a}"
    }
}
object Search {
    fun patternAtom(s: String, column: Int): Pair<Matcher, Int> = when (s[0]) {
        '*' -> Pair(Matcher.AnyAtom, 1)
        'A' -> Pair(Matcher.Aliphatic, 1)
        'a' -> Pair(Matcher.Aromatic, 1)
        '[' -> {
            val end = s.indexOf(']')
            if (end < 0) throw MoleculeError("unclosed bracket", column)
            val atoms = s.substring(1, end).split(',').map {
                val (element, aromatic, n) = SmilesParser.organic(it) ?: throw MoleculeError("bad bracket atom", column)
                if (n != it.length) throw MoleculeError("bad bracket atom", column)
                Pair(element, aromatic)
            }
            Pair(Matcher.AtomList(atoms), end + 1)
        }
        else -> {
            val (element, aromatic, n) = SmilesParser.organic(s) ?: throw MoleculeError("unexpected character", column)
            Pair(Matcher.AtomList(listOf(Pair(element, aromatic))), n)
        }
    }
    fun embeddings(pattern: Pattern, m: Molecule): Matches {
        val map = mutableListOf<Int>()
        val used = BooleanArray(m.atoms.size)
        val sets = mutableSetOf<List<Int>>()
        var count = 0
        var first = emptyList<Int>()
        fun visit() {
            val a = map.size
            if (a == pattern.atoms.size) {
                count++
                if (first.isEmpty()) first = map.map {
                    it + 1
                }
                sets.add(map.sorted())
                return
            }
            for (b in m.atoms.indices) if (!used[b]) {
                val atom = m.atoms[b]
                val matches = when (val matcher = pattern.atoms[a]) {
                    Matcher.AnyAtom -> true
                    Matcher.Aliphatic -> !atom.aromatic
                    Matcher.Aromatic -> atom.aromatic
                    is Matcher.AtomList -> Pair(atom.element, atom.aromatic) in matcher.atoms
                }
                if (!matches) continue
                val bonds = pattern.graph.neighbors[a].filter {
                    it.first < a
                }.all {
                    (v, edge) ->
                    val f = m.bond(b, map[v])
                    if (f == null) false else when (val kind = pattern.graph.bonds[edge].kind) {
                        0 -> m.bonds[f].kind in listOf(1, 4); 5 -> true; else -> m.bonds[f].kind == kind
                    }
                }
                if (bonds) {
                    used[b] = true; map.add(b); visit(); map.removeAt(map.lastIndex); used[b] = false
                }
            }
        }
        visit()
        return Matches(count, sets.size, first)
    }
    fun fingerprint(m: Molecule, elements: Elements): Fingerprint {
        val codes = m.atoms.mapIndexed {
            i, a -> 16 * elements.getValue(a.element).number + (if (a.aromatic) 8 else 0) + m.neighbors[i].size
        }
        val result = Fingerprint()
        val path = mutableListOf<Int>()
        fun walk(hash: Int) {
            result.paths++
            result.bits.add(hash % 1024)
            if (path.size == 6) return
            for ((b, edge) in m.neighbors[path.last()]) if (b !in path) {
                val h = ((hash * 31 + m.bonds[edge].kind) % 1000003 * 31 + codes[b]) % 1000003
                path.add(b); walk(h); path.removeAt(path.lastIndex)
            }
        }
        for (i in m.atoms.indices) {
            path.clear(); path.add(i); walk(codes[i])
        }
        return result
    }
    fun similarity(a: Fingerprint, b: Fingerprint): Ratio {
        val common = a.bits.intersect(b.bits).size
        return Ratio(common, a.bits.size + b.bits.size - common)
    }
}
