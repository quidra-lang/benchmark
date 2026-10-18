fun main() {
    for (i in 1..9) {
        val row = buildString {
            for (j in 1..9) append((i * j).toString().padStart(3, ' '))
        }
        println(row)
    }
}
