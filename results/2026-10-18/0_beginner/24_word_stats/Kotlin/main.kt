import java.math.BigDecimal
import java.math.RoundingMode

fun fixed(x: Double, places: Int): String = BigDecimal.valueOf(x).setScale(places, RoundingMode.HALF_UP).toPlainString()
fun main() {
    val words = "we planted beans and carrots in the garden behind our old house".split(' ')
    var longest = words[0]; var shortest = words[0]; var total = 0
    for (word in words) {
        if (word.length > longest.length) longest = word
        if (word.length < shortest.length) shortest = word
        total += word.length
    }
    println("words: ${words.size}")
    println("longest: $longest")
    println("shortest: $shortest")
    println("average length: ${fixed(total.toDouble() / words.size, 2)}")
}
