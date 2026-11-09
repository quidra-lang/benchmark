import java.io.File
data class Element(val number: Int, val mass: Int, val valences: List<Int>)
typealias Elements = Map<String, Element>
fun readElements(): Elements = File("input/elements.txt").readLines().filter {
    it.isNotEmpty() && !it.startsWith('#')
}.associate {
    val a = it.split(' ')
    a[0] to Element(a[1].toInt(), a[2].toInt(), a[3].split(',').map(String::toInt))
}
data class Atom(val element: String, val aromatic: Boolean = false, val mass: Int = 0, val charge: Int = 0,
var hydrogens: Int = 0, val bracket: Boolean = false, val column: Int = 1)
data class Bond(var a: Int, var b: Int, var kind: Int, var multiplicity: Int = 0, var ring: Boolean = false)
class Molecule {
    val atoms = mutableListOf<Atom>()
    val bonds = mutableListOf<Bond>()
    var neighbors: List<List<Pair<Int, Int>>> = emptyList()
    var rings: List<List<Int>> = emptyList()
    fun rebuild() {
        bonds.sortWith(compareBy<Bond> {
            it.a
        }.thenBy {
            it.b
        })
        val adjacency = List(atoms.size) {
            mutableListOf<Pair<Int, Int>>()
        }
        for ((i, bond) in bonds.withIndex()) {
            adjacency[bond.a].add(Pair(bond.b, i))
            adjacency[bond.b].add(Pair(bond.a, i))
        }
        neighbors = adjacency.map {
            it.sortedBy {
                edge -> edge.first
            }
        }
    }
    fun bond(a: Int, b: Int): Int? = neighbors[a].firstOrNull {
        it.first == b
    }?.second
    fun base(i: Int): Int = neighbors[i].sumOf {
        val kind = bonds[it.second].kind; if (kind == 4) 1 else kind
    }
    fun multiplicity(i: Int): Int = neighbors[i].sumOf {
        bonds[it.second].multiplicity
    }
    fun needsPi(i: Int, elements: Elements, hydrogens: Boolean): Boolean {
        val atom = atoms[i]
        return atom.aromatic && elements.getValue(atom.element).valences[0] + atom.charge >= base(i) + (if (hydrogens) atom.hydrogens else 0) + 1
    }
    fun organicHydrogens(i: Int, elements: Elements): Int? {
        val total = multiplicity(i)
        return elements.getValue(atoms[i].element).valences.firstOrNull {
            it >= total
        }?.minus(total)
    }
}
class MoleculeError(val reason: String, val column: Int) : Exception(reason)
