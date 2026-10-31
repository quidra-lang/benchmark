class Tableau(val t: MutableList<MutableList<F>>, val beta: MutableList<F>, val basis: MutableList<Int>) {
    fun pivot(row: Int, column: Int) {
        val divisor = t[row][column]; t[row] = t[row].map {
            it / divisor
        }.toMutableList(); beta[row] = beta[row] / divisor
        for (i in t.indices) if (i != row) {
            val factor = t[i][column]; t[i] = t[i].indices.map {
                k -> t[i][k] - factor * t[row][k]
            }.toMutableList(); beta[i] = beta[i] - factor * beta[row]
        }
        basis[row] = column
    }
    fun reduced(costs: List<F>): List<F> = costs.indices.map {
        k -> costs[k] - t.indices.map {
            i -> costs[basis[i]] * t[i][k]
        }.sumF()
    }
    fun value(costs: List<F>): F = t.indices.map {
        i -> costs[basis[i]] * beta[i]
    }.sumF()
    fun display(heading: String, columns: List<String>, rows: List<String>, costs: List<F>, constant: F, sign: F): List<String> = listOf("TABLEAU $heading", "COLUMNS " + columns.joinToString(" ")) + t.indices.map {
        i -> "ROW ${rows[i]} ${columns[basis[i]]} ${t[i].joinToString(" ")} | ${beta[i]}"
    } + "COST ${reduced(costs).joinToString(" ")} | ${constant + sign * value(costs)}"
}
