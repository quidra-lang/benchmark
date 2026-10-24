import java.util.Locale

fun main() {
    val words = "we planted beans and carrots in the garden behind our old house".split(' ')
    println("words: ${words.size}")
    println("longest: ${words.maxBy { it.length }}")
    println("shortest: ${words.minBy { it.length }}")
    println("average length: %.2f".format(Locale.ROOT, words.map { it.length }.average()))
}
