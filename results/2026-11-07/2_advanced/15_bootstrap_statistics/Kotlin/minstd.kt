class Minstd(seed: Long) {
    private var state = seed
    fun draw(): Long { state = 48271L * state % 2147483647L; return state }
    fun below(limit: Int): Int = (draw() % limit).toInt()
    fun shuffle(items: IntArray) {
        for (i in items.lastIndex downTo 1) {
            val j = below(i + 1)
            val value = items[i]; items[i] = items[j]; items[j] = value
        }
    }
    fun shuffle(items: LongArray) {
        for (i in items.lastIndex downTo 1) {
            val j = below(i + 1)
            val value = items[i]; items[i] = items[j]; items[j] = value
        }
    }
}
