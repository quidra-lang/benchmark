class Minstd(seed: Int) {
    private var state = seed.toLong()
    fun draw(): Int {
        state = state * 48271 % 2147483647;
        return state.toInt()
    }
    fun below(limit: Int): Int = draw() % limit
    fun chance(fraction: IntArray): Boolean = draw() % fraction[1] < fraction[0]
    fun shuffle(sequence: MutableList<Int>) {
        for (length in sequence.size downTo 2) {
            val index = below(length);
            val old = sequence[length - 1];
            sequence[length - 1] = sequence[index];
            sequence[index] = old
        }
    }
}
