object Morphology {
    val NEIGHBORS = listOf(Pixel(0, -1), Pixel(1, -1), Pixel(1, 0), Pixel(1, 1), Pixel(0, 1), Pixel(-1, 1), Pixel(-1, 0), Pixel(-1, -1))
    fun occupied(mask: Array<BooleanArray>, x: Int, y: Int) = y in mask.indices && x in mask[0].indices && mask[y][x]
    fun erode(mask: Array<BooleanArray>, offsets: List<Pixel>): Array<BooleanArray> =
        Array(mask.size) { y -> BooleanArray(mask[0].size) { x -> offsets.all { occupied(mask, x + it.x, y + it.y) } } }
    fun dilate(mask: Array<BooleanArray>, offsets: List<Pixel>): Array<BooleanArray> =
        Array(mask.size) { y -> BooleanArray(mask[0].size) { x -> offsets.any { occupied(mask, x - it.x, y - it.y) } } }
    fun opening(mask: Array<BooleanArray>, offsets: List<Pixel>) = dilate(erode(mask, offsets), offsets)
    fun closing(mask: Array<BooleanArray>, offsets: List<Pixel>) = erode(dilate(mask, offsets), offsets)
    fun bits(pixels: Set<Pixel>, point: Pixel) = BooleanArray(8) { Pixel(point.x + NEIGHBORS[it].x, point.y + NEIGHBORS[it].y) in pixels }
    fun transitions(bits: BooleanArray) = bits.indices.count { !bits[it] && bits[(it + 1) % 8] }
    fun crossing(pixels: Set<Pixel>, point: Pixel) = transitions(bits(pixels, point))
    fun removable(bits: BooleanArray, first: Boolean): Boolean {
        val count = bits.count { it }
        if (count !in 2..6 || transitions(bits) != 1) return false
        val p2 = bits[0]
        val p4 = bits[2]
        val p6 = bits[4]
        val p8 = bits[6]
        return if (first) !(p2 && p4 && p6) && !(p4 && p6 && p8) else !(p2 && p4 && p8) && !(p2 && p6 && p8)
    }
    private fun thinningStep(skeleton: MutableSet<Pixel>, first: Boolean): Boolean {
        val removed = skeleton.filter { removable(bits(skeleton, it), first) }
        skeleton.removeAll(removed.toSet())
        return removed.isNotEmpty()
    }
    fun thin(pixels: List<Pixel>): Set<Pixel> {
        val skeleton = pixels.toMutableSet()
        while (true) {
            val first = thinningStep(skeleton, true)
            val second = thinningStep(skeleton, false)
            if (!first && !second) return skeleton
        }
    }
}
