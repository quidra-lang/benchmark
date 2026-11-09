import java.io.File

object Scoring {
    fun letter(c: Char): Boolean = c in 'A'..'Z' || c in 'a'..'z'

    fun value(c: Char): Int = if (c in 'a'..'z') c - 'a' else c - 'A'

    fun upper(value: Int): Char = ('A'.code + value).toChar()

    fun letters(text: String): String = buildString {
        for (c in text) if (letter(c)) append(upper(value(c)))
    }

    fun groups(text: String): List<String> {
        val pieces = text.chunked(5)
        return pieces.chunked(10).map { it.joinToString(" ") }
    }

    fun monogram(text: String, weights: IntArray): Int =
        text.sumOf { weights[it - 'A'] }

    fun bigram(text: String, weights: Array<IntArray>): Int {
        var score = 0
        for (i in 1 until text.length) score += weights[text[i - 1] - 'A'][text[i] - 'A']
        return score
    }

    fun read(path: String): Pair<IntArray, Array<IntArray>> {
        val lines = File(path).readLines(Charsets.US_ASCII)
        val mono = lines[1].split(" ").map(String::toInt).toIntArray()
        val bi = Array(26) { index -> lines[index + 3].split(" ").map(String::toInt).toIntArray() }
        return mono to bi
    }
}
