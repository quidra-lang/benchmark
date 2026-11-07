fun main() {
    val values = intArrayOf(7, 98000, 4096, 50301, 2718281, 123456789)
    for (value in values) {
        val digits = value.toString()
        val count = digits.length
        val sum = digits.sumOf { it.digitToInt() }
        val reversed = digits.reversed().toInt()
        println("$value: digits=$count sum=$sum reversed=$reversed")
    }
}
