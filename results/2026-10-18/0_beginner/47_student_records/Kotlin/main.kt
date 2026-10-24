import java.util.Locale

fun main() {
    val names = listOf("Tanaka","Suzuki","Yamada","Ito","Kato","Mori")
    val scores = listOf(listOf(78,85,94),listOf(88,74,82),listOf(65,90,71),listOf(80,79,85),listOf(92,88,95),listOf(70,62,78))
    val totals = scores.map { it.sum() }
    val order = names.indices.sortedWith(compareByDescending<Int> { totals[it] }.thenBy { names[it] })
    var rank = 0
    var previous = -1
    for ((position,i) in order.withIndex()) {
        if (totals[i] != previous) rank = position + 1
        previous = totals[i]
        println("%d. %s total=%d average=%.2f".format(Locale.ROOT, rank, names[i], totals[i], totals[i] / 3.0))
    }
}
