data class Chosen(val course: String, val saturation: Int)

class Attempt(
    private val courses: List<String>, private val graph: ConflictGraph, private val limit: Int,
    private val candidateSlots: (String, Map<String, Int>) -> List<Int>
) {
    var deadEnds = 0
        private set
    var deadEndCourse: String? = null
        private set
    var aborted = false
        private set
    val chosen = mutableListOf<Chosen>()

    private fun saturation(id: String, assignment: Map<String, Int>): Int =
        graph.neighbours(id).keys.mapNotNull { assignment[it] }.toSet().size

    fun search(assignment: MutableMap<String, Int>): Boolean {
        val id = courses.filter { it !in assignment }.minWithOrNull(
            compareByDescending<String> { saturation(it, assignment) }
                .thenByDescending { graph.degree(it) }.thenBy { it }
        ) ?: return true
        chosen += Chosen(id, saturation(id, assignment))
        for (slot in candidateSlots(id, assignment)) {
            assignment[id] = slot
            if (search(assignment)) return true
            assignment.remove(id)
            if (aborted) return false
        }
        chosen.removeAt(chosen.lastIndex)
        deadEnds++
        deadEndCourse = id
        aborted = deadEnds > limit
        return false
    }
}

object Coloring {
    fun greedyNumbering(order: List<String>, graph: ConflictGraph): Int {
        val numbers = mutableMapOf<String, Int>()
        for (id in order) {
            val taken = graph.neighbours(id).keys.mapNotNull { numbers[it] }.toSet()
            var number = 1
            while (number in taken) number++
            numbers[id] = number
        }
        return numbers.values.maxOrNull() ?: 0
    }
}
