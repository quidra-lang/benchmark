class GridState(val letters: CharArray, val words: Array<String?>) {
    val used = words.filterNotNull().toMutableSet()
    fun copy() = GridState(letters.copyOf(), words.copyOf())
    fun pattern(slot: Slot) = slot.cells.map { letters[it] }.joinToString("")
    fun assign(slot: Slot, word: String): List<Int> {
        val filled = mutableListOf<Int>()
        for (i in 0 until slot.length) if (letters[slot.cells[i]] == '.') { letters[slot.cells[i]] = word[i]; filled.add(slot.cells[i]) }
        words[slot.index] = word
        used.add(word)
        return filled
    }
    fun unassign(slot: Slot, filled: List<Int>) {
        for (cell in filled) letters[cell] = '.'
        used.remove(words[slot.index]!!)
        words[slot.index] = null
    }
}
class Attempt(val layout: Layout, val index: WordIndex, initial: GridState, val minimum: Int, val budget: Int) {
    val state = initial.copy()
    var nodes = 0
    var backtracks = 0
    var prunes = 0
    var deadEnds = 0
    var maxDepth = 0
    val sequence = mutableListOf<Slot>()
    var best = initial.copy()
    val failures = IntArray(layout.slots.size)
    val trace = mutableListOf<String>()
    lateinit var outcome: String
    fun run() { outcome = when (search()) { "complete" -> "filled"; "fail" -> "unfillable"; else -> "budget" } }
    fun finalState() = if (outcome == "filled") state else best
    private fun candidates(slot: Slot) = index.candidates(state.pattern(slot), minimum, state.used)
    private fun search(): String {
        var chosen: Slot? = null
        var choices = emptyList<String>()
        for (slot in layout.slots) if (state.words[slot.index] == null) {
            val words = candidates(slot)
            if (chosen == null || words.size < choices.size) { chosen = slot; choices = words }
        }
        val slot = chosen ?: return "complete"
        if (choices.isEmpty()) { deadEnds++; failures[slot.index]++; return "fail" }
        for (word in choices) {
            if (nodes == budget) return "abort"
            nodes++
            val filled = state.assign(slot, word)
            sequence.add(slot)
            val wiped = slot.crossings.firstOrNull { state.words[it] == null && candidates(layout.slots[it]).isEmpty() }
            if (nodes <= 10) trace.add(slot.label + "=" + word + if (wiped == null) "" else "!")
            val result = if (wiped != null) {
                prunes++; failures[wiped]++; "fail"
            } else {
                if (sequence.size > maxDepth) { maxDepth = sequence.size; best = state.copy() }
                search()
            }
            if (result != "fail") return result
            state.unassign(slot, filled)
            sequence.removeAt(sequence.lastIndex)
            backtracks++
        }
        return "fail"
    }
}
