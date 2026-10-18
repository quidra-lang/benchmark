import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    val deck = mutableListOf<String>()
    for (suit in "SHDC") {
        for (rank in "A23456789TJQK") deck.add("$rank$suit")
    }
    var state = 2026L
    for (i in 51 downTo 1) {
        state = state * 48271 % 2147483647
        val j = (state % (i + 1)).toInt()
        val card = deck[i]
        deck[i] = deck[j]
        deck[j] = card
    }
    for (row in deck.chunked(13)) println(row.joinToString(" "))
}
