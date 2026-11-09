fun main() {
    val sentence = "every program starts with a single line"
    println(sentence.reversed())
    println(sentence.split(' ').reversed().joinToString(" "))
}
