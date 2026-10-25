fun runClue(cells: List<Int>): List<Int> {
    val result = mutableListOf<Int>(); var run = 0
    for (state in cells) { if (state == FILLED) run++ else if (run > 0) { result += run; run = 0 } }
    if (run > 0) result += run
    return result
}
fun clueText(clue: List<Int>, separator: String = " "): String = if (clue.isEmpty()) "0" else clue.joinToString(separator)
fun isClueLine(text: String): Boolean = text.isNotEmpty() && text.all { it == ' ' || it in '0'..'9' }
fun parseClue(text: String): List<Int>? {
    if (text == "0") return emptyList()
    val result = mutableListOf<Int>()
    for (token in text.split(' ')) { if (token.length !in 1..2 || token[0] == '0' || token.any { it !in '0'..'9' }) return null; result += token.toInt() }
    return result
}
fun clueFits(clue: List<Int>, length: Int): Boolean = clue.sum() + clue.size - 1 <= length
