import java.io.File
class Settings(val values: MutableList<String> = mutableListOf("longest", "4", "off", "barycenter", "12", "2", "1", "3", "TB", "off", "off", "0", "1")) {
    companion object {
        val names = listOf("layering", "width", "promotion", "heuristic", "sweeps", "node_sep", "dummy_sep", "layer_gap", "direction", "sifting", "reduce", "restarts", "seed")
    }
    fun copy(): Settings = Settings(values.toMutableList())
    fun text(name: String): String = values[names.indexOf(name)]
    fun integer(name: String): Int = text(name).toInt()
    fun on(name: String): Boolean = text(name) == "on"
    fun set(name: String, value: String): Boolean {
        val index = names.indexOf(name)
        if (index < 0) return false
        val words = when (name) {
            "layering" -> listOf("longest", "coffman"); "promotion", "sifting", "reduce" -> listOf("on", "off"); "heuristic" -> listOf("barycenter", "median"); "direction" -> listOf("TB", "BT", "LR", "RL"); else -> emptyList()
        }
        if (words.isNotEmpty()) {
            if (value !in words) return false; values[index] = value; return true
        }
        val range = when (name) {
            "width" -> 1L..40L; "sweeps" -> 0L..50L; "node_sep", "dummy_sep" -> 1L..9L; "layer_gap" -> 2L..9L; "restarts" -> 0L..9L; else -> 1L..2147483646L
        }
        if (value.length !in 1..10 || !value.all {
            it in '0'..'9'
        }) return false
        val number = value.toLongOrNull() ?: return false
        if (number !in range) return false
        values[index] = number.toString()
        return true
    }
}
data class Node(val id: Int, val label: String)
data class Edge(val a: Int, val b: Int)
class Graph(val name: String, val settings: Settings) {
    var nodes: List<Node> = emptyList()
    var edges = mutableListOf<Edge>()
    var path: Edge? = null
    var loops = 0
    var duplicates = 0
    var error: Pair<String, Int>? = null
}
object GraphIO {
    fun read(): List<Graph> {
        val defaults = Settings()
        for (line in File("input/params.txt").readLines()) if (line.isNotEmpty() && !line.startsWith('#')) {
            val a = line.split(' '); defaults.set(a[0], a[1])
        }
        val result = mutableListOf<Graph>()
        var current: Graph? = null
        var nodes = mutableMapOf<Int, String>()
        for ((i, line) in File("input/graphs.txt").readLines().withIndex()) if (line.isNotEmpty() && !line.startsWith('#')) {
            val a = line.split(' ')
            if (a[0] == "GRAPH") {
                current = Graph(a[1], defaults.copy()); nodes = mutableMapOf(); continue
            }
            val graph = current!!
            if (a[0] == "END") {
                if (graph.error == null && nodes.isEmpty()) graph.error = Pair("no_nodes", i + 1)
                graph.nodes = nodes.keys.sorted().map {
                    Node(it, nodes.getValue(it))
                }
                if (graph.error == null) {
                    val numbering = graph.nodes.withIndex().associate {
                        it.value.id to it.index
                    }
                    graph.edges = graph.edges.map {
                        Edge(numbering.getValue(it.a), numbering.getValue(it.b))
                    }.toMutableList()
                    graph.path = graph.path?.let {
                        Edge(numbering.getValue(it.a), numbering.getValue(it.b))
                    }
                }
                result.add(graph); current = null; continue
            }
            if (graph.error != null) continue
            var error: String? = null
            when (a[0]) {
                "OPTION" -> if (!graph.settings.set(a[1], a[2])) error = "bad_option"
                "NODE" -> {
                    val id = a[1].toInt()
                    if (id in nodes) error = "duplicate_node" else if (nodes.size == 40) error = "too_many_nodes" else nodes[id] = a[2]
                }
                "EDGE" -> {
                    val edge = Edge(a[1].toInt(), a[2].toInt())
                    if (edge.a !in nodes || edge.b !in nodes) error = "unknown_node"
                    else if (edge.a == edge.b) graph.loops++ else if (edge in graph.edges) graph.duplicates++ else graph.edges.add(edge)
                }
                else -> {
                    val edge = Edge(a[1].toInt(), a[2].toInt())
                    if (edge.a !in nodes || edge.b !in nodes) error = "unknown_node" else graph.path = edge
                }
            }
            if (error != null) graph.error = Pair(error, i + 1)
        }
        return result
    }
}
