class Phase(text: String) {
    private val fields = text.split(':')
    val duration = fields[0].toInt()
    val token = fields[1]
    val greens = if (token == "-") emptySet() else token.split(',').toSet()
}
class Junction(val node: String, val offset: Int, tokens: List<String>) {
    val phases = tokens.map(::Phase)
    val cycle = phases.sumOf { it.duration }
    fun green(segment: String, step: Int): Boolean {
        if (phases.isEmpty()) return true
        var time = (step - 1 + offset) % cycle
        for (phase in phases) { if (time < phase.duration) return segment in phase.greens; time -= phase.duration }
        return false
    }
    fun planLines(): List<String> {
        if (phases.isEmpty()) return listOf("JUNCTION $node unsignalized")
        val lines = mutableListOf("JUNCTION $node signal cycle $cycle offset $offset")
        var start = 0
        for ((index, phase) in phases.withIndex()) { lines += "  PHASE ${index + 1} $start-${start + phase.duration - 1} ${phase.token}"; start += phase.duration }
        return lines
    }
}
