import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    val text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door."
    val counts = Regex("[a-z]+").findAll(text.lowercase()).map { it.value }.groupingBy { it }.eachCount()
    val words = counts.keys.sortedWith(compareByDescending<String> { counts[it]!! }.thenBy { it })
    for (word in words.take(5)) println("$word: ${counts[word]}")
    println("distinct words: ${counts.size}")
}
