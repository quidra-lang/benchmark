fun main() {
    var a = 1
    var b = 1
    val terms = mutableListOf<Int>()
    repeat(30) {
        terms.add(a)
        val next = a + b
        a = b
        b = next
    }
    println(terms.joinToString(" "))
    println("sum: ${terms.sum()}")
}
