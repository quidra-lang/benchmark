class Minstd(seed: Long) {
    var state = seed
    fun draw(): Long { state = state * 48271L % 2147483647L; return state }
}
fun select(weights: List<Int>, random: Long): Int {
    val value = random % weights.sum()
    var total = 0
    for ((index, weight) in weights.withIndex()) { total += weight; if (value < total) return index }
    return weights.lastIndex
}
