fun main() {
    val matrix = arrayOf(intArrayOf(125,340,78,912,456), intArrayOf(603,27,819,150,384), intArrayOf(0,765,231,498,62), intArrayOf(947,113,586,39,720))
    val columns = IntArray(5)
    for (row in matrix) {
        for (j in row.indices) columns[j] += row[j]
        val sum = row.sum()
        println((row.toList() + sum).joinToString("") { it.toString().padStart(6) })
    }
    println((columns.toList() + columns.sum()).joinToString("") { it.toString().padStart(6) })
}
