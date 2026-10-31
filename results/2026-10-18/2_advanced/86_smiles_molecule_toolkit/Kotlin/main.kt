import java.io.File
import kotlin.math.abs
fun validName(text: String): Boolean = text.length in 1..32 && text.all {
    it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it in "_-"
}
fun number(text: String, low: Int, high: Int): Int? {
    if (text.isEmpty() || text.length > 1 && text[0] == '0' || !text.all {
        it in '0'..'9'
    }) return null
    return text.toIntOrNull()?.takeIf {
        it in low..high
    }
}
fun threshold(text: String): Ratio? {
    val a = text.split('/')
    if (a.size != 2) return null
    val p = number(a[0], 0, 99) ?: return null
    val q = number(a[1], 1, 99) ?: return null
    return if (p <= q) Ratio(p, q) else null
}
fun analyze(text: String, elements: Elements): Molecule {
    val m = SmilesParser.parse(text, elements).molecule
    RingsAromatic.detect(m)
    for (b in m.bonds) if (b.kind == 0) b.kind = if (m.atoms[b.a].aromatic && m.atoms[b.b].aromatic && b.ring) 4 else 1
    RingsAromatic.kekulize(m, elements)
    for ((i, a) in m.atoms.withIndex()) {
        if (a.bracket) {
            if (m.multiplicity(i) + a.hydrogens > elements.getValue(a.element).valences.last() + abs(a.charge)) throw MoleculeError("bad valence", a.column)
        } else a.hydrogens = m.organicHydrogens(i, elements) ?: throw MoleculeError("bad valence", a.column)
    }
    return m
}
fun scaffold(m: Molecule, elements: Elements): String? {
    if (m.rings.isEmpty()) return null
    val ringAtoms = m.rings.flatten().toSet()
    val remaining = m.atoms.indices.toMutableSet()
    while (true) {
        val removed = remaining.sorted().firstOrNull {
            i -> i !in ringAtoms && m.neighbors[i].count {
                it.first in remaining
            } == 1
        } ?: break
        remaining.remove(removed)
    }
    val core = remaining.toSet()
    for (b in m.bonds) if (b.kind == 2) {
        if (b.a in core) remaining.add(b.b); if (b.b in core) remaining.add(b.a)
    }
    val graph = Molecule()
    val index = mutableMapOf<Int, Int>()
    for (i in remaining.sorted()) {
        index[i] = graph.atoms.size
        val extra = m.neighbors[i].filter {
            it.first !in remaining
        }.sumOf {
            m.bonds[it.second].multiplicity
        }
        graph.atoms.add(m.atoms[i].copy(hydrogens = m.atoms[i].hydrogens + extra))
    }
    for (b in m.bonds) if (b.a in remaining && b.b in remaining) graph.bonds.add(b.copy(a = index.getValue(b.a), b = index.getValue(b.b)))
    graph.rebuild()
    return Canonical.smiles(graph, elements).first
}
data class Analysis(val name: String, val graph: Molecule, val smiles: String, val classes: Int, val formula: String, val weight: Int,
val heavy: Int, val rotatable: Int, val donors: Int, val acceptors: Int, val lipinski: String, val charge: Int,
val scaffold: String?, val fingerprint: Fingerprint)
fun properties(name: String, m: Molecule, elements: Elements): Analysis {
    val counts = mutableMapOf<String, Int>()
    var weight = 0
    var hydrogens = 0
    for (a in m.atoms) {
        counts[a.element] = counts.getOrDefault(a.element, 0) + 1
        hydrogens += a.hydrogens
        weight += if (a.mass == 0) elements.getValue(a.element).mass else a.mass * 1000
    }
    counts["H"] = counts.getOrDefault("H", 0) + hydrogens
    weight += hydrogens * elements.getValue("H").mass
    counts.entries.removeIf {
        it.value == 0
    }
    val order = mutableListOf<String>()
    if ("C" in counts) {
        order.add("C"); if ("H" in counts) order.add("H")
    }
    order.addAll(counts.keys.filter {
        it !in order
    }.sorted())
    val formula = order.joinToString("") {
        it + if (counts.getValue(it) > 1) counts.getValue(it).toString() else ""
    }
    val heavy = m.atoms.count {
        it.element != "H"
    }
    val heavyDegree = m.neighbors.map {
        ns -> ns.count {
            m.atoms[it.first].element != "H"
        }
    }
    val triple = m.neighbors.map {
        ns -> ns.any {
            m.bonds[it.second].multiplicity == 3
        }
    }
    val rotatable = m.bonds.count {
        it.multiplicity == 1 && !it.ring && heavyDegree[it.a] >= 2 && heavyDegree[it.b] >= 2 && !triple[it.a] && !triple[it.b]
    }
    val acceptors = m.atoms.count {
        it.element in listOf("N", "O")
    }
    val donors = m.atoms.indices.count {
        i -> val a = m.atoms[i]; a.element in listOf("N", "O") && (a.hydrogens > 0 || m.neighbors[i].any {
            m.atoms[it.first].element == "H"
        })
    }
    val violations = (if (weight > 500000) 1 else 0) + (if (donors > 5) 1 else 0) + (if (acceptors > 10) 1 else 0)
    val (smiles, classes) = Canonical.smiles(m, elements)
    return Analysis(name, m, smiles, classes, formula, weight, heavy, rotatable, donors, acceptors, if (violations <= 1) "pass" else "fail", m.atoms.sumOf {
        it.charge
    }, scaffold(m, elements), Search.fingerprint(m, elements))
}
data class RingSystem(val rings: List<Int>, val kind: String, val atoms: Int)
fun ringSystems(m: Molecule): List<RingSystem> {
    val remaining = m.rings.indices.toMutableSet()
    val result = mutableListOf<RingSystem>()
    while (remaining.isNotEmpty()) {
        val start = remaining.minOrNull()!!
        val group = mutableSetOf<Int>()
        val stack = mutableListOf(start)
        remaining.remove(start)
        while (stack.isNotEmpty()) {
            val i = stack.removeAt(stack.lastIndex)
            group.add(i)
            val neighbors = remaining.filter {
                j -> m.rings[i].any {
                    it in m.rings[j]
                }
            }.sorted()
            for (j in neighbors) {
                remaining.remove(j); stack.add(j)
            }
        }
        val rings = group.sorted()
        var kind = if (rings.size == 1) "isolated" else "spiro"
        for (x in rings.indices) for (y in x + 1 until rings.size) {
            val common = m.rings[rings[x]].intersect(m.rings[rings[y]].toSet()).toList()
            if (common.size >= 2) {
                if (common.size == 2 && m.bond(common[0], common[1]) != null) {
                    if (kind != "bridged") kind = "fused"
                }
                else kind = "bridged"
            }
        }
        result.add(RingSystem(rings, kind, rings.flatMap {
            m.rings[it]
        }.toSet().size))
    }
    return result
}
fun paragraph(output: MutableList<String>, lines: List<String>) {
    if (output.isNotEmpty()) output.add(""); output.addAll(lines)
}
fun canonicalReport(molecules: List<Analysis>): List<String> {
    val result = mutableListOf<String>()
    paragraph(result, listOf("CANONICAL molecules=${molecules.size} unique=${molecules.map { it.smiles }.toSet().size}") + molecules.map {
        "${it.name} ${it.smiles} classes=${it.classes} charge=${if (it.charge > 0) "+" else ""}${it.charge}"
    })
    fun names(ids: List<Int>): String = ids.joinToString(",") {
        molecules[it].name
    }
    val duplicates = molecules.indices.groupBy {
        molecules[it].smiles
    }.entries.filter {
        it.value.size >= 2
    }.sortedBy {
        it.value[0]
    }
    paragraph(result, listOf("DUPLICATES groups=${duplicates.size} molecules=${duplicates.sumOf { it.value.size }}") + duplicates.mapIndexed {
        i, g -> "group ${i + 1} ${g.key} members=${names(g.value)}"
    })
    val isomers = molecules.indices.groupBy {
        molecules[it].formula
    }.entries.filter {
        g -> g.value.map {
            molecules[it].smiles
        }.toSet().size >= 2
    }.sortedBy {
        it.value[0]
    }
    paragraph(result, listOf("ISOMERS groups=${isomers.size}") + isomers.mapIndexed {
        i, g -> "isomer ${i + 1} ${g.key} forms=${g.value.map { molecules[it].smiles }.toSet().size} members=${names(g.value)}"
    })
    val scaffolds = molecules.indices.filter {
        molecules[it].scaffold != null
    }.groupBy {
        molecules[it].scaffold!!
    }.entries.sortedWith(compareByDescending<Map.Entry<String, List<Int>>> {
        it.value.size
    }.thenBy {
        it.key
    })
    paragraph(result, listOf("SCAFFOLDS distinct=${scaffolds.size} acyclic=${molecules.count { it.scaffold == null }}") + scaffolds.mapIndexed {
        i, g -> "scaffold ${i + 1} ${g.key} count=${g.value.size} members=${names(g.value)}"
    })
    return result
}
fun ringsReport(molecules: List<Analysis>): List<String> {
    val result = mutableListOf<String>()
    var total = 0
    var aromatic = 0
    var cyclic = 0
    val sizes = sortedMapOf<Int, Int>()
    val kinds = listOf("isolated", "fused", "spiro", "bridged")
    val kindCounts = IntArray(4)
    for (m in molecules) if (m.graph.rings.isNotEmpty()) {
        val graph = m.graph
        val aromaticCount = graph.rings.count {
            r -> r.all {
                graph.atoms[it].aromatic
            }
        }
        val systems = ringSystems(graph)
        cyclic++; total += graph.rings.size; aromatic += aromaticCount
        val lines = mutableListOf("MOLECULE ${m.name} atoms=${graph.atoms.size} bonds=${graph.bonds.size} rings=${graph.rings.size} aromatic=$aromaticCount systems=${systems.size} ring_atoms=${graph.rings.flatten().toSet().size} ring_bonds=${graph.bonds.count { it.ring }}")
        for ((i, ring) in graph.rings.withIndex()) {
            sizes[ring.size] = sizes.getOrDefault(ring.size, 0) + 1
            lines.add("ring ${i + 1} size=${ring.size} aromatic=${if (ring.all { graph.atoms[it].aromatic }) "yes" else "no"} hetero=${ring.count { graph.atoms[it].element != "C" }} atoms=${ring.joinToString("-") { (it + 1).toString() }}")
        }
        for ((i, system) in systems.withIndex()) {
            kindCounts[kinds.indexOf(system.kind)]++
            lines.add("system ${i + 1} kind=${system.kind} rings=${system.rings.joinToString(",") { (it + 1).toString() }} atoms=${system.atoms}")
        }
        val doubles = graph.bonds.filter {
            it.kind == 4 && it.multiplicity == 2
        }.map {
            "${it.a + 1}=${it.b + 1}"
        }
        lines.add("kekule " + if (doubles.isEmpty()) "-" else doubles.joinToString(" "))
        paragraph(result, lines)
    }
    val sizeText = if (sizes.isEmpty()) "-" else sizes.entries.joinToString(" ") {
        "${it.key}=${it.value}"
    }
    paragraph(result, listOf("SUMMARY molecules=${molecules.size} cyclic=$cyclic rings=$total aromatic=$aromatic", "sizes $sizeText", "systems isolated=${kindCounts[0]} fused=${kindCounts[1]} spiro=${kindCounts[2]} bridged=${kindCounts[3]}"))
    return result
}
class QueryError(val reason: String) : Exception(reason)
data class Query(val kind: String, val id: String, val args: List<String>, val indices: MutableList<Int> = mutableListOf(),
var pattern: Pattern? = null, var count: Int = 0, var threshold: Ratio = Ratio(0, 1))
fun query(a: List<String>, names: Map<String, Int>, elements: Elements): Query {
    val kind = a[0]
    val args = a.drop(2)
    val valid = if (kind in listOf("MATCH", "CLUSTER")) args.size == 1 else if (kind == "MATRIX") args.size in 2..12 else args.size == 2
    if (!valid) throw QueryError("bad arguments")
    val q = Query(kind, a[1], args)
    fun index(name: String): Int = names[name] ?: throw QueryError("unknown molecule $name")
    when (kind) {
        "MATCH" -> try {
            q.pattern = Pattern.parse(args[0], elements)
        } catch (e: MoleculeError) {
            throw QueryError("bad pattern ${e.reason} at column ${e.column}")
        }
        "CLUSTER" -> q.threshold = threshold(args[0]) ?: throw QueryError("bad threshold")
        "NEAREST", "WITHIN" -> {
            q.indices.add(index(args[0]))
            if (kind == "NEAREST") q.count = number(args[1], 1, 99) ?: throw QueryError("bad count")
            else q.threshold = threshold(args[1]) ?: throw QueryError("bad threshold")
        }
        else -> {
            for (name in args) q.indices.add(index(name))
            if (q.indices.toSet().size != q.indices.size) throw QueryError("repeated molecule")
        }
    }
    return q
}
fun process(q: Query, molecules: List<Analysis>, sub: MutableList<String>, similarity: MutableList<String>, counts: IntArray) {
    fun sim(a: Int, b: Int): Ratio = Search.similarity(molecules[a].fingerprint, molecules[b].fingerprint)
    when (q.kind) {
        "MATCH" -> {
            counts[0]++
            val pattern = q.pattern!!
            val matches = molecules.mapIndexed {
                i, m -> Pair(i, Search.embeddings(pattern, m.graph))
            }.filter {
                it.second.count > 0
            }
            counts[1] += matches.size
            val lines = mutableListOf("MATCH ${q.id} ${q.args[0]} atoms=${pattern.graph.atoms.size} bonds=${pattern.graph.bonds.size} hits=${matches.size} embeddings=${matches.sumOf { it.second.count }}")
            for ((i, match) in matches) lines.add("${molecules[i].name} count=${match.count} unique=${match.unique} map=${match.first.joinToString(",")}")
            val top = matches.maxByOrNull {
                it.second.count
            }
            if (top != null) lines.add("top ${molecules[top.first].name} count=${top.second.count}")
            paragraph(sub, lines)
        }
        "CONTAINS" -> {
            counts[2]++
            val matches = Search.embeddings(Pattern.molecule(molecules[q.indices[0]].graph), molecules[q.indices[1]].graph)
            val result = if (matches.count == 0) "no" else {
                counts[3]++
                "yes count=${matches.count} unique=${matches.unique} map=${matches.first.joinToString(",")}"
            }
            paragraph(sub, listOf("CONTAINS ${q.id} ${q.args[0]} ${q.args[1]} result=$result"))
        }
        "MATRIX" -> {
            val lines = mutableListOf("MATRIX ${q.id} size=${q.indices.size}")
            for (a in q.indices) lines.add("row ${molecules[a].name} " + q.indices.joinToString(" ") {
                sim(a, it).toString()
            })
            var bestA = 0
            var bestB = 1
            var best = sim(q.indices[0], q.indices[1])
            for (a in q.indices.indices) for (b in a + 1 until q.indices.size) {
                val s = sim(q.indices[a], q.indices[b])
                if (s > best) {
                    bestA = a; bestB = b; best = s
                }
            }
            lines.add("best ${q.args[bestA]} ${q.args[bestB]} $best")
            paragraph(similarity, lines)
        }
        "NEAREST", "WITHIN" -> {
            val x = q.indices[0]
            var results = molecules.indices.filter {
                it != x
            }.map {
                Pair(it, sim(x, it))
            }.sortedWith(Comparator {
                a, b ->
                val order = b.second.compareTo(a.second)
                if (order == 0) a.first.compareTo(b.first) else order
            })
            results = if (q.kind == "NEAREST") results.take(q.count) else results.filter {
                it.second >= q.threshold
            }
            val first = if (q.kind == "NEAREST") "NEAREST ${q.id} ${q.args[0]} count=${results.size}" else "WITHIN ${q.id} ${q.args[0]} threshold=${q.threshold} count=${results.size}"
            paragraph(similarity, listOf(first) + results.mapIndexed {
                i, r -> "${i + 1} ${molecules[r.first].name} ${r.second} common=${r.second.p}"
            })
        }
        "COMPARE" -> {
            val a = molecules[q.indices[0]]
            val b = molecules[q.indices[1]]
            val s = Search.similarity(a.fingerprint, b.fingerprint)
            paragraph(similarity, listOf("COMPARE ${q.id} ${q.args[0]} ${q.args[1]} bits=${a.fingerprint.bits.size},${b.fingerprint.bits.size} common=${s.p} union=${s.q} tanimoto=$s identical=${if (a.smiles == b.smiles) "yes" else "no"}"))
        }
        "CLUSTER" -> {
            val neighbors = molecules.indices.map {
                i -> molecules.indices.filter {
                    it != i && sim(i, it) >= q.threshold
                }
            }
            val order = molecules.indices.sortedWith(compareByDescending<Int> {
                neighbors[it].size
            }.thenBy {
                it
            })
            val used = mutableSetOf<Int>()
            val clusters = mutableListOf<List<Int>>()
            for (i in order) if (used.add(i)) {
                val members = mutableListOf(i)
                for (j in neighbors[i]) if (used.add(j)) members.add(j)
                clusters.add(members)
            }
            val lines = mutableListOf("CLUSTER ${q.id} threshold=${q.threshold} clusters=${clusters.size} singletons=${clusters.count { it.size == 1 }}")
            for ((i, cluster) in clusters.filter {
                it.size > 1
            }.withIndex()) lines.add("cluster ${i + 1} centroid=${molecules[cluster[0]].name} size=${cluster.size} members=${cluster.joinToString(",") { molecules[it].name }}")
            paragraph(similarity, lines)
        }
    }
}
fun write(name: String, lines: List<String>) {
    File("output").mkdirs()
    File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n")
}
fun main() {
    val elements = readElements()
    val molecules = mutableListOf<Analysis>()
    val seen = mutableSetOf<String>()
    val moleculeErrors = mutableListOf<String>()
    val causes = mutableMapOf<String, Int>()
    var moleculeLines = 0
    fun cause(reason: String) {
        causes[reason] = causes.getOrDefault(reason, 0) + 1
    }
    for ((i, line) in File("input/molecules.smi").readLines().withIndex()) if (line.isNotEmpty() && !line.startsWith('#')) {
        moleculeLines++
        val a = line.split(' ')
        if (a.size != 2 || a[0].isEmpty() || !validName(a[1])) {
            moleculeErrors.add("line ${i + 1}: bad line"); cause("bad line")
        }
        else if (!seen.add(a[1])) {
            moleculeErrors.add("line ${i + 1} ${a[1]}: duplicate name"); cause("duplicate name")
        }
        else try {
            molecules.add(properties(a[1], analyze(a[0], elements), elements))
        }
        catch (e: MoleculeError) {
            moleculeErrors.add("line ${i + 1} ${a[1]}: ${e.reason} at column ${e.column}"); cause(e.reason)
        }
    }
    val names = molecules.withIndex().associate {
        it.value.name to it.index
    }
    val propertyLines = mutableListOf("name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski")
    for (m in molecules) {
        val weight = "${m.weight / 1000}.${(m.weight % 1000).toString().padStart(3, '0')}"
        propertyLines.add("${m.name},${m.formula},$weight,${m.heavy},${m.graph.rings.size},${m.rotatable},${m.donors},${m.acceptors},${m.lipinski}")
    }
    val substructure = mutableListOf<String>()
    val similarity = mutableListOf("FINGERPRINTS molecules=${molecules.size} size=1024 depth=5")
    similarity.addAll(molecules.map {
        "${it.name} bits=${it.fingerprint.bits.size} paths=${it.fingerprint.paths}"
    })
    val identifiers = mutableSetOf<String>()
    val queryErrors = mutableListOf<String>()
    var queryLines = 0
    var queryValid = 0
    val counts = IntArray(4)
    for ((i, line) in File("input/queries.txt").readLines().withIndex()) if (line.isNotEmpty() && !line.startsWith('#')) {
        queryLines++
        val a = line.split(' ')
        if (a[0] !in listOf("MATCH", "CONTAINS", "MATRIX", "NEAREST", "WITHIN", "COMPARE", "CLUSTER")) {
            queryErrors.add("line ${i + 1}: unknown query"); cause("unknown query")
        }
        else if (a.size == 1 || !validName(a[1])) {
            queryErrors.add("line ${i + 1} ${a[0]}: bad id"); cause("bad id")
        }
        else try {
            if (!identifiers.add(a[1])) throw QueryError("duplicate id")
            val q = query(a, names, elements)
            queryValid++
            process(q, molecules, substructure, similarity, counts)
        } catch (e: QueryError) {
            queryErrors.add("line ${i + 1} ${a[0]} ${a[1]}: ${e.reason}")
            cause(if (e.reason.startsWith("bad pattern ")) "bad pattern" else if (e.reason.startsWith("unknown molecule ")) "unknown molecule" else e.reason)
        }
    }
    paragraph(substructure, listOf("SUMMARY patterns=${counts[0]} hits=${counts[1]} contains=${counts[2]} found=${counts[3]}"))
    val errors = mutableListOf<String>()
    paragraph(errors, listOf("MOLECULES lines=$moleculeLines valid=${molecules.size} errors=${moleculeErrors.size}") + moleculeErrors)
    paragraph(errors, listOf("QUERIES lines=$queryLines valid=$queryValid errors=${queryErrors.size}") + queryErrors)
    val sortedCauses = causes.entries.sortedWith(compareByDescending<Map.Entry<String, Int>> {
        it.value
    }.thenBy {
        it.key
    })
    paragraph(errors, listOf("CAUSES kinds=${causes.size}") + sortedCauses.map {
        "${it.key}=${it.value}"
    })
    write("properties.csv", propertyLines)
    write("canonical.txt", canonicalReport(molecules))
    write("rings.txt", ringsReport(molecules))
    write("substructure.txt", substructure)
    write("similarity.txt", similarity)
    write("errors.txt", errors)
}
