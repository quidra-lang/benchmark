class Optics(points: List<Point>, neighborhoods: Array<IntArray>, minimum: Int) {
    val core = IntArray(points.size) {
        INF
    };
    val reach = IntArray(points.size) {
        INF
    };
    val predecessor = IntArray(points.size) {
        -1
    };
    val order = mutableListOf<Int>()
    init {
        val count = points.size;
        val processed = BooleanArray(count);
        val seeds = BooleanArray(count)
        for (i in 0 until count) if (neighborhoods[i].size >= minimum) {
            val distances = neighborhoods[i].map {
                GridIndex.distance(points[i], points[it])
            }.sorted();
            core[i] = distances[minimum - 1]
        }
        for (start in 0 until count) {
            if (processed[start]) continue
            seeds[start] = true
            while (true) {
                var current = -1
                for (i in 0 until count) if (seeds[i] && (current < 0 || reach[i] < reach[current])) current = i
                if (current < 0) break
                seeds[current] = false;
                processed[current] = true;
                order.add(current)
                if (core[current] == INF) continue
                for (other in neighborhoods[current]) if (!processed[other]) {
                    val distance = maxOf(core[current], GridIndex.distance(points[current], points[other]));
                    if (distance < reach[other]) {
                        reach[other] = distance;
                        predecessor[other] = current;
                        seeds[other] = true
                    }
                }
            }
        }
    }
    companion object {
        const val INF = Int.MAX_VALUE
    }
}
