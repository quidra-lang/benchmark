data class Clustering(val labels: IntArray, val core: BooleanArray)
object Dbscan {
    fun cluster(neighborhoods: Array<IntArray>, minimum: Int): Clustering {
        val labels = IntArray(neighborhoods.size) {
            -2
        };
        val core = BooleanArray(labels.size) {
            neighborhoods[it].size >= minimum
        };
        var cluster = 0
        for (p in labels.indices) {
            if (labels[p] != -2) continue
            if (!core[p]) {
                labels[p] = -1;
                continue
            }
            labels[p] = cluster;
            val queue = ArrayDeque<Int>();
            for (q in neighborhoods[p]) queue.addLast(q)
            while (queue.isNotEmpty()) {
                val q = queue.removeFirst();
                if (labels[q] == -1) labels[q] = cluster else if (labels[q] == -2) {
                    labels[q] = cluster;
                    if (core[q]) for (neighbor in neighborhoods[q]) queue.addLast(neighbor)
                }
            }
            cluster++
        }
        return Clustering(labels, core)
    }
}
