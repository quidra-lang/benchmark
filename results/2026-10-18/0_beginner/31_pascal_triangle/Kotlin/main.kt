fun main() {
    var row = listOf(1)
    repeat(12) {
        println(row.joinToString(" "))
        row = List(row.size + 1) { k -> if (k == 0 || k == row.size) 1 else row[k - 1] + row[k] }
    }
}
