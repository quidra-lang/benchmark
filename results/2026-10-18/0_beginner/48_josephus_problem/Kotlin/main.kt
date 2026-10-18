import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    for ((n,k) in listOf(7 to 3,10 to 2,41 to 3)) {
        var index = 0; val people = (1..n).toMutableList(); val removed = mutableListOf<Int>()
        while (people.isNotEmpty()) { index = (index + k - 1) % people.size; removed.add(people.removeAt(index)) }
        println("n=$n k=$k: ${removed.joinToString(" ")}")
        println("survivor: ${removed.last()}")
    }
}
