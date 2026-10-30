import java.math.BigInteger
data class Allocation(val nodes: List<String>, val neighbors: Map<String, Set<String>>, val costs: Map<String, BigInteger>, val order: List<String>, val potential: List<Pair<String, Int>>, val registers: Map<String, Int>, val spills: Set<String>)
object Regalloc {
    fun allocate(function: Function, graph: Graph, analysis: Analysis, count: Int): Allocation {
        val nodes = function.parameters.toMutableSet()
        for ((i, instruction) in graph.instructions.withIndex()) {
            if (graph.owners[i] in graph.reachable) {
                instruction.destination?.let {
                    nodes.add(it)
                }
                nodes.addAll(instruction.used)
            }
        }
        val sorted = nodes.sorted()
        val neighbors = sorted.associateWith {
            mutableSetOf<String>()
        }.toMutableMap()
        val costs = sorted.associateWith {
            BigInteger.ZERO
        }.toMutableMap()
        val partners = mutableMapOf<String, MutableSet<String>>()
        fun edge(a: String, b: String) {
            if (a != b) {
                neighbors.getValue(a).add(b)
                neighbors.getValue(b).add(a)
            }
        }
        for (b in graph.reachable) {
            var live = analysis.live.output[b]
            for (i in graph.blocks[b].last downTo graph.blocks[b].first) {
                val instruction = graph.instructions[i]
                val x = instruction.destination
                if (x != null) {
                    for (v in live) {
                        if (v != x && !(instruction.kind == "copy" && instruction.a?.variable == v)) edge(x, v)
                    }
                }
                live = Transfer.live(live, instruction)
            }
            val weight = BigInteger.TEN.pow(graph.depths[b])
            for (i in graph.blocks[b].first..graph.blocks[b].last) {
                val instruction = graph.instructions[i]
                for (v in instruction.used + listOfNotNull(instruction.destination)) costs[v] = costs.getValue(v).add(weight)
            }
        }
        val initial = analysis.live.input[0] + function.parameters
        for (p in function.parameters) {
            costs[p] = costs.getValue(p).add(BigInteger.ONE)
            for (v in initial) if (v != p) edge(p, v)
        }
        for (instruction in graph.instructions) {
            val x = instruction.destination
            val y = instruction.a?.variable
            if (instruction.kind == "copy" && x != null && y != null && x != y) {
                partners.getOrPut(x) {
                    mutableSetOf()
                }.add(y)
                partners.getOrPut(y) {
                    mutableSetOf()
                }.add(x)
            }
        }
        val remaining = nodes.toMutableSet()
        val order = mutableListOf<String>()
        val potential = mutableListOf<Pair<String, Int>>()
        while (remaining.isNotEmpty()) {
            val degrees = remaining.associateWith {
                neighbors.getValue(it).count {
                    neighbor -> neighbor in remaining
                }
            }
            val low = remaining.filter {
                degrees.getValue(it) < count
            }
            val chosen: String
            if (low.isNotEmpty()) chosen = low.minWith(compareBy<String> {
                degrees.getValue(it)
            }.thenBy {
                it
            })
            else {
                chosen = remaining.minWith(Comparator {
                    a, b -> val x = costs.getValue(a).multiply(BigInteger.valueOf(degrees.getValue(b).toLong()))
                    val y = costs.getValue(b).multiply(BigInteger.valueOf(degrees.getValue(a).toLong()))
                    val comparison = x.compareTo(y)
                    if (comparison == 0) a.compareTo(b) else comparison
                })
                potential.add(chosen to degrees.getValue(chosen))
            }
            order.add(chosen)
            remaining.remove(chosen)
        }
        val registers = mutableMapOf<String, Int>()
        val spills = mutableSetOf<String>()
        for (node in order.asReversed()) {
            val occupied = neighbors.getValue(node).mapNotNull {
                registers[it]
            }.toSet()
            val free = (0 until count).filter {
                it !in occupied
            }
            if (free.isEmpty()) {
                spills.add(node)
                continue
            }
            val biased = (partners[node] ?: emptySet()).mapNotNull {
                registers[it]
            }.filter {
                it in free
            }
            registers[node] = biased.minOrNull() ?: free[0]
        }
        return Allocation(sorted, neighbors.mapValues {
            it.value.toSet()
        }, costs.toMap(), order, potential, registers, spills)
    }
}
