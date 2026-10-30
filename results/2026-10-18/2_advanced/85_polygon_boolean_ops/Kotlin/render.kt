object Render {
    fun draw(region: Region, operands: Pair<Rings, Rings>?, v: List<Long>): Pair<List<String>, IntArray> {
        val (x, y, cw, ch) = v
        val cols = v[4].toInt()
        val rows = v[5].toInt()
        val all = region.flatten()
        val lines = mutableListOf<String>()
        val counts = IntArray(4)
        for (j in 0 until rows) {
            val line = StringBuilder()
            for (i in 0 until cols) {
                val point = Point(bi(2 * x + (2 * i + 1) * cw), bi(2 * y + (2 * (rows - 1 - j) + 1) * ch), bi(2))
                val a = operands?.let {
                    RingOps.interior(point, it.first)
                } ?: false
                val b = operands?.let {
                    RingOps.interior(point, it.second)
                } ?: false
                val c = if (RingOps.interior(point, all)) {
                    counts[0]++; '#'
                }
                else if (a && b) {
                    counts[3]++; '+'
                }
                else if (a) {
                    counts[1]++; 'a'
                }
                else if (b) {
                    counts[2]++; 'b'
                }
                else '.'
                line.append(c)
            }
            lines.add(line.toString())
        }
        return Pair(lines, counts)
    }
}
