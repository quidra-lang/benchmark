object Simplex {
    fun phase(t: Tableau, costs: List<F>, candidates: List<Int>, columns: List<String>, rows: List<String>, constant: F, sign: F, level: Int, log: MutableList<String>): Pair<Int, Int?> {
        var count = 0
        while (true) {
            val reduced = t.reduced(costs)
            val q = candidates.firstOrNull {
                reduced[it] < F(0)
            } ?: return Pair(count, null)
            val p = t.t.indices.filter {
                t.t[it][q] > F(0)
            }.minWithOrNull(compareBy<Int> {
                t.beta[it] / t.t[it][q]
            }.thenBy {
                t.basis[it]
            }) ?: return Pair(count, q)
            val ratio = t.beta[p] / t.t[p][q]; val before = reduced[q]; val leaving = t.basis[p]
            t.pivot(p, q); count++
            if (level >= 1) log.add("PIVOT $count enter ${columns[q]} reduced $before leave ${columns[leaving]} row ${rows[p]} ratio $ratio objective ${constant + sign * t.value(costs)}")
        }
    }
}
