class Minstd(seed: Int) {
    private var state = seed
    fun draw(): Int { state = (48271L * state % 2147483647).toInt(); return state }
    fun rnd(n: Int) = draw() % n
    fun roll(count: Int, sides: Int): Int {
        var total = 0
        repeat(count) { total += 1 + rnd(sides) }
        return total
    }
    fun select(weights: List<Int>): Int {
        val q = rnd(weights.sum())
        var total = 0
        for ((i, weight) in weights.withIndex()) { total += weight; if (q < total) return i }
        error("Invalid weights")
    }
}
