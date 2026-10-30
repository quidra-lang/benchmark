data class Params(val width: Int, val indent: Int, val rel: Int, val binary: Int, val punctuation: Int, val colGap: Int, val rowGap: Int)
data class Spacing(val types: List<Pair<Int, Int>>, val gaps: List<Int>)
object Layout {
    fun types(node: Node): Pair<Int, Int> = when (node) {
        is Node.Atom -> Boxes.atomType(node.kind, node.value).let {
            Pair(it, it)
        }
        is Node.Delimited -> Pair(4, 5)
        is Node.Script -> types(node.base)
        is Node.Binary -> if (node.name in listOf("overset", "underset")) types(node.second) else Pair(0, 0)
        else -> Pair(0, 0)
    }
    fun word(node: Node): Boolean = when (node) {
        is Node.Atom -> node.kind == "command" && (node.value.drop(1) in Lexer.greek || node.value == "\\infty")
        is Node.Script -> word(node.base)
        else -> false
    }
    fun alphanumeric(node: Node): Boolean {
        if (word(node)) return true
        return when (node) {
            is Node.Atom -> node.kind in listOf("identifier", "number")
            is Node.Script -> alphanumeric(node.base)
            is Node.Accent -> node.name in listOf("overline", "hat", "vec", "dot", "tilde") && alphanumeric(node.body)
            else -> false
        }
    }
    fun spacing(nodes: List<Node>, script: Boolean, params: Params): Spacing {
        val types = nodes.map(::types).toMutableList()
        for (i in types.indices) {
            if (types[i].first == 2 && (i == 0 || types[i - 1].second in listOf(1, 2, 3, 4, 6))) types[i] = Pair(0, 0)
            if (types[i].first in listOf(3, 5, 6) && i > 0 && types[i - 1].second == 2) types[i - 1] = Pair(0, 0)
        }
        if (types.lastOrNull()?.second == 2) types[types.lastIndex] = Pair(0, 0)
        val table = listOf(listOf(0,1,2,3,0,0,0),listOf(1,1,0,3,0,0,0),listOf(2,2,0,0,2,0,0),listOf(3,3,0,0,3,0,0),listOf(0,0,0,0,0,0,0),listOf(0,1,2,3,0,0,0),listOf(4,4,0,4,4,4,4))
        val gaps = (0 until nodes.size - 1).map {
            i ->
            if (alphanumeric(nodes[i]) && alphanumeric(nodes[i + 1]) && (word(nodes[i]) || word(nodes[i + 1]))) 1
            else when (table[types[i].second][types[i + 1].first]) {
                0 -> 0; 1 -> 1; 2 -> if (script) 0 else params.binary; 3 -> if (script) 0 else params.rel; else -> if (script) 0 else params.punctuation
            }
        }
        return Spacing(types, gaps)
    }
    fun row(elements: List<Box>, gaps: List<Int>, description: String, roles: List<String> = emptyList()): Box {
        val ascent = elements.maxOfOrNull {
            it.baseline
        } ?: 0
        val descent = elements.maxOfOrNull {
            it.height - 1 - it.baseline
        } ?: 0
        val result = Box(elements.sumOf {
            it.width
        } + gaps.sum(), ascent + descent + 1, ascent, description)
        var x = 0
        for ((i, box) in elements.withIndex()) {
            result.child(box, x, ascent - box.baseline, roles.getOrElse(i) {
                ""
            }); x += box.width + gaps.getOrElse(i) {
                0
            }
        }
        return result
    }
}
